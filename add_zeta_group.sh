#!/bin/bash

CONF="./zeta_cluster.conf"
# Pull in Cluster conf
. $CONF

# Source Shared Env

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

ROLE=$1
GNAME=$2
GID=$3
GDESC=$4
VALID=$5

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
   echo "This script takes three argument, ROLE GROUPNAME GID"
   exit 1
fi

if [ "$GNAME" == "" ]; then
   echo "This script takes three argument, ROLE GROUPNAME GID"
   exit 1
fi

if [ "$GID" == "" ]; then
   echo "This script takes three argument, ROLE GROUPNAME GID"
   exit 1
fi


START_GID=$(cat /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list|grep $ROLE|cut -d":" -f2)

if [ "$START_GID" == "" ]; then
    echo "The starting GID for role $ROLE was not found, are you sure this role is installed?"
    exit 1
fi
VALID_GID=$(($START_GID + 500000))

echo $VALID_GID

if [ "$GID" -ge $VALID_GID ] && [ "$GID" -lt $(($VALID_GID + 500000)) ]; then 
    echo "$GID is valid in role $ROLE - However we do not check for duplicates (yet)"
else
    echo "$GID is not valid in role $ROLE"
    exit 1
fi

if [ "$GDESC" == "" ]; then 
    echo "No group description was passed to this script"
    read -e -p "Please enter group Description: " GDESC
fi

if [ "$VALID" != "1" ]; then
    echo "You wish to create group $GNAME with GID $GID in role $ROLE"
    read -e -p "Is this correct? " -i "N" CHK
    if [ "$CHK" != "Y" ]; then
        echo "Used gave up"
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


cat > ${TMP_LDIF}/tmp.ldif << EOL
dn: cn=$GNAME,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixGroup
gidNumber: $GID
description: $GDESC
EOL

ADD_CMD="ldapmodify -H ldap://openldap-shared.marathon.slave.mesos -x -y /tmp/ldif/p.txt -D \"cn=admin,dc=marathon,dc=mesos\" -f /tmp/ldif/tmp.ldif"
cat > ${TMP_LDIF}/run.sh << ERUN
#!/bin/bash
$ADD_CMD
ERUN
chmod +x ${TMP_LDIF}/run.sh

$DCKR /tmp/ldif/run.sh

rm -rf $TMP_LDIF
