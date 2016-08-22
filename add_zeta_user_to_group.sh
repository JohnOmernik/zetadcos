#!/bin/bash

CONF="./zeta_cluster.conf"
# Pull in Cluster conf
. $CONF

# Source Shared Env

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

ROLE=$1
UNAME=$2
GNAME=$3
VALID=$4

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

if [ "$ROLE" == "" ]; then
   echo "This script takes three argument, ROLE USERNAME GROUPNAME"
   exit 1
fi

if [ "$UNAME" == "" ]; then
   echo "This script takes three argument, ROLE USERNAME GROUPNAME"
   exit 1
fi

if [ "$GNAME" == "" ]; then
   echo "This script takes three argument, ROLE USERNAME GROUPNAME"
   exit 1
fi



if [ "$VALID" != "1" ]; then
    echo "You wish to create add user $UNAME to group $GNAME in role $ROLE"
    read -e -p "Is this correct? " -i "N" CHK
    if [ "$CHK" != "Y" ]; then
        echo "User gave up"
        exit 1
    fi
fi


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

if [ "$GNAME" == "zetausers" ]; then
    DN="cn=$GNAME,dc=marathon,dc=mesos"
else
    DN="cn=$GNAME,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos"
fi

cat > ${TMP_LDIF}/tmp.ldif << EOL
dn: $DN
changetype: modify
add: memberuid
memberuid: $UNAME
EOL

ADD_CMD="ldapmodify -H ldap://openldap.shared.marathon.mesos -x -y /tmp/ldif/p.txt -D \"cn=admin,dc=marathon,dc=mesos\" -f /tmp/ldif/tmp.ldif"
cat > ${TMP_LDIF}/run.sh << ERUN
#!/bin/bash
$ADD_CMD
ERUN
chmod +x ${TMP_LDIF}/run.sh

$DCKR /tmp/ldif/run.sh

rm -rf $TMP_LDIF
