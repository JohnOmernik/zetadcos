#!/bin/bash

CONF="./zeta_cluster.conf"
# Pull in Cluster conf
. $CONF

# Source Shared Env

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

CURUSER=$(whoami)

if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi

APP_IMG="${ZETA_DOCKER_REG_URL}/ldaputils"

LDAP_ROOT="/mapr/$CLUSTERNAME/zeta/shared/openldap"

if [ ! "$LDAP_ROOT" ]; then
   echo "Openldap doesn't appear to be installed, exiting"
   exit 1
fi

echo ""
echo ""
echo "****************************************"
echo "This attempts to enable caches and indexes to make openldap faster with MapR"
echo ""
echo "--------> This is experimental use at your own risk <---------"
echo ""
read -e -p "Do you wish to proceed here? " -i "N" PROCEED

if [ "$PROCEED" != "Y" ]; then
    echo "Wisely exited"
    exit 1
fi


TMP_LDIF="${LDAP_ROOT}/slapd.d"

# Add indexes here

cat > ${TMP_LDIF}/tmp_index.ldif << EOL0
dn: olcDatabase={1}hdb,cn=config
changetype:modify
add: olcDbIndex
olcDbIndex: gidNumber eq
olcDbIndex: uidNumber eq
olcDbIndex: cn eq
olcDbIndex: memberUid eq
olcDbIndex: member eq

dn: olcDatabase={1}hdb,cn=config
changetype:modify
add: olcDbIDLcacheSize
olcDbIDLcacheSize: 500000

dn: olcDatabase={1}hdb,cn=config
changetype:modify
add: olcDbCachesize
olcDbCachesize: 500000
EOL0


ADD_CMD="ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/ldap/slapd.d/tmp_index.ldif"

cat > ${TMP_LDIF}/run.sh << EOR
#!/bin/bash
echo "Adding Indexes in Docker Container"
echo ""
$ADD_CMD
echo ""
echo "Finished Adding Indexes and Cache"
echo ""
EOR
chmod +x ${TMP_LDIF}/run.sh


cat > ./update_script.sh << EOY
#!/bin/bash
CID=\$(sudo docker ps|grep openldap|cut -d" " -f1)
if [ "\$CID" == "" ]; then
    echo "Open Ldap not found on this host, INDEXES NOT ADDED!!!!"
    exit 1
fi
echo "Running script now in docker container"
echo ""
sudo docker exec \$CID /etc/ldap/slapd.d/run.sh
echo ""
echo "Finished Docker Exec"
echo ""
EOY

chmod +x ./update_script.sh


OLDAP_ID="$MARATHON_SUBMIT/shared/openldap"
CURHOST=$(curl -s -X GET $OLDAP_ID/tasks|grep -o -P "\"host\":\"[^\"]+\""|cut -d":" -f2|sed "s/\"//g")

echo "Currently Running Host: $CURHOST"

scp -o StrictHostKeyChecking=no update_script.sh $CURHOST:/home/zetaadm/

ssh -o StrictHostKeyChecking=no $CURHOST "/home/zetaadm/update_script.sh"

ssh -o StrictHostKeyChecking=no $CURHOST "rm /home/zetaadm/update_script.sh"
echo ""
echo ""
echo "Indexes Added"
echo ""
rm ./update_script.sh
rm ${TMP_LDIF}/run.sh
rm ${TMP_LDIF}/tmp_index.ldif


MARATHON_DEP="http://$MARATHON_HOST/v2/deployments"


OUT=$(curl -s -H "Content-type: application/json" -X PUT ${OLDAP_ID} -d'{"instances":0}')

DEP_ID=$(echo $OUT|grep -P -o "deploymentId\":\"[^\"]+\""|cut -f2 -d":"|sed "s/\"//g")

DEPLOY=$(curl -s -H "Content-type: application/json" -X GET ${MARATHON_DEP}|grep "$DEP_ID")
while [ "$DEPLOY" != "" ]; do
    echo "Waiting in a loop for current instance to stop - Waiting 2 seconds"
    sleep 2
    DEPLOY=$(curl -s -H "Content-type: application/json" -X GET ${MARATHON_DEP}|grep "$DEP_ID")
done
echo ""
echo "Instance Stopped"
sleep 5

# Not sure if the following part is needed 

#OLDAP_IMG="$ZETA_DOCKER_REG_URL/openldap"
#echo ""
#echo "Pulling Open LDAP image to ensure we have it locally"
#echo ""
#sudo docker pull $OLDAP_IMG
#echo ""
#echo "Stopping current instance of OpenLDAP"

#INDEXES="gidNumber uidNumber cn memberUid member"
#VOLS="-v=/mapr/$CLUSTERNAME/zeta/shared/openldap/ldap:/var/lib/ldap:rw -v=/mapr/$CLUSTERNAME/zeta/shared/openldap/ldapmod:/tmp/ldapmod:rw -v=/mapr/$CLUSTERNAME/zeta/shared/openldap/slapd.d:/etc/ldap/slapd.d -v=/mapr/$CLUSTERNAME/zeta/shared/openldap/initconf:/container/environment/02-custom:ro"
#echo "Waiting 5 seconds before reindexing"
#sleep 5
#for IDX in $INDEXES; do
#    echo ""
#    echo "Running Index on $IDX"
#    echo ""
#    sudo docker run --name openldap-reindex-$IDX --net=host -it --rm $VOLS --entrypoint slapindex $OLDAP_IMG -F /etc/ldap/slapd.d/ -b "dc=marathon,dc=mesos" $IDX
#    sudo docker run --name openldap-reindex-$IDX --net=host -it --rm $VOLS --entrypoint run $OLDAP_IMG -s -p -k /bin/bash
#    exit 1
#    echo "Waiting 10 seconds before next reindex"
#    sleep 10
#done

#echo ""
echo "Restarting Open LDAP"
NEWOUT=$(curl -s -H "Content-type: application/json" -X PUT ${OLDAP_ID} -d'{"instances":1}')
echo ""
echo "Started with the following result $NEWOUT"
echo ""
echo "Waiting 15 seconds to obtain new host info"
sleep 15
echo ""
echo "Old Host: $CURHOST"
NEWHOST=$(curl -s -X GET $OLDAP_ID/tasks|grep -o -P "\"host\":\"[^\"]+\""|cut -d":" -f2|sed "s/\"//g")
echo ""
echo "New Host (May be the same as old host): $NEWHOST"
echo ""



