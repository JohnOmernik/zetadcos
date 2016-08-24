#!/bin/bash

CONF="./zeta_cluster.conf"
# Pull in Cluster conf
. $CONF

# Source Shared Env

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

ROLE=$1

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
SCHEMA_INST="/mapr/$CLUSTERNAME/zeta/kstore/env/env_$ROLE/schema.sh"


if [ -f "$SCHEMA_INST" ]; then
   echo "It looks like role $ROLE already has a schema file"
   exit 1
fi

touch $SCHEMA_INST
echo "Please enter the starting UID number for this role - $ROLE"
echo "To help, here is a list of the currently defined roles"
echo "If no roles are established, we recommend starting with 1000000"
echo "If roles are established take the highest role and add 1000000"
echo ""
cat /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list
echo ""


SHRD=$(cat /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list|grep $ROLE)

if [ "$SHRD" != "" ]; then
    echo "It looks like the role you are trying to add already has a STARTID specified"
    echo "We will use this."
    echo SHRD
    STARTID=$(echo $SHRD|cut -d":" -f2)
else
    read -e -p "Please enter the starting UID for role $ROLE: " -i "1000000" STARTID
    echo "$ROLE:$STARTID" >> /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list
fi


CURUID="$STARTID"
CURGID=$(($STARTID + 500000))
SVCUID=$CURUID
CURUID=$((CURUID + 1))
APPGID=$CURGID
CURGID=$(($CURGID + 1))
DATAGID=$CURGID
CURGID=$(($CURGID + 1))
ETLGID=$CURGID
CURGID=$(($CURGID + 1))
ZETAGID=$CURGID

LDAPPASS=$(cat ${LDAP_ROOT}/initconf/default.yaml.startup|grep ADMIN|sed "s/LDAP_ADMIN_PASSWORD: //")

TMP_LDIF="`pwd`/tmpldif"

APASSFILE="${TMP_LDIF}/p.txt"
TMPAPASSFILE="${TMP_LDIF}/o.txt"

mkdir -p $TMP_LDIF

chmod -R 750 $TMP_LDIF
touch $APASSFILE
touch $TMPAPASSFILE
chmod 600 $APASSFILE
chmod 600 $TMPAPASSFILE

cat > $TMPAPASSFILE << PWF
${LDAPPASS}
PWF
cat $TMPAPASSFILE|tr -d "\n" > $APASSFILE
rm $TMPAPASSFILE
chmod 600 $APASSFILE

DCKR="sudo docker run --rm -v=${TMP_LDIF}:/tmp/ldif:ro ${APP_IMG}"

cat > ${TMP_LDIF}/tmp.ldif << EOL
dn: ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
ou: zeta$ROLE
objectClass: top
objectClass: organizationalUnit
description: Base OU for Zeta Role $ROLE

dn: ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
ou: groups
objectClass: top
objectClass: organizationalUnit
description: Groups for use in Zeta Role $ROLE

dn: ou=users,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
ou: users
objectClass: top
objectClass: organizationalUnit
description: Users for use in Zeta Role $ROLE

EOL

ADD_CMD="ldapmodify -H ldap://openldap.shared.marathon.mesos -x -y /tmp/ldif/p.txt -D \"cn=admin,dc=marathon,dc=mesos\" -f /tmp/ldif/tmp.ldif"

cat > ${TMP_LDIF}/run.sh << ERUN
#!/bin/bash
$ADD_CMD
ERUN
chmod +x ${TMP_LDIF}/run.sh

$DCKR /tmp/ldif/run.sh

rm -rf $TMP_LDIF

echo "A data svc account will be crated named zetasvc$ROLE"
echo "This account will be located in ou=users,ou=zeta$ROLE,dc=marathon,dc=mesos and used as a data service account. More can be created, this is just the first"
echo "The uid and primary gid for this group will be $SVCUID"
echo "This user will be a memeber of zeta${ROLE}data, zeta${ROLE}apps, zeta${ROLE}zeta, and zeta${ROLE}etl"

./add_zeta_user.sh $ROLE zetasvc$ROLE $SVCUID 1

./add_zeta_group.sh $ROLE zeta${ROLE}apps $APPGID "Access group for role $ROLE and the apps directory" 1
./add_zeta_group.sh $ROLE zeta${ROLE}data $DATAGID "Access group for role $ROLE and the data directory" 1
./add_zeta_group.sh $ROLE zeta${ROLE}etl $ETLGID "Access group for role $ROLE and the etl directory" 1
./add_zeta_group.sh $ROLE zeta${ROLE}zeta $ZETAGID "Access group for role $ROLE and the zeta directory" 1


./add_zeta_user_to_group.sh $ROLE zetasvc${ROLE} zeta${ROLE}apps 1
./add_zeta_user_to_group.sh $ROLE zetasvc${ROLE} zeta${ROLE}data 1
./add_zeta_user_to_group.sh $ROLE zetasvc${ROLE} zeta${ROLE}etl 1
./add_zeta_user_to_group.sh $ROLE zetasvc${ROLE} zeta${ROLE}zeta 1
./add_zeta_user_to_group.sh $ROLE zetasvc${ROLE} zetausers 1
