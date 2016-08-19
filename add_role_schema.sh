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

#touch $SCHEMA_INST
echo "Please enter the starting UID number for this role"
echo "To help, here is a list of the currently defined roles"
echo "If no roles are established, we recommend starting with 1000000"
echo "If roles are established take the highest role and add 1000000"
echo ""
cat /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list
echo ""

read -e -p "Please enter the starting UID for role $ROLE: " -i "1000000" STARTID
echo "$ROLE:$STARTID" >> /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list

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

echo "A data svc account will be crated named zetasvc$ROLE"
echo "This account will be located in ou=users,ou=zeta$ROLE,dc=marathon,dc=mesos and used as a data service account. More can be created, this is just the first"
echo "The uid and primary gid for this group will be $SVCUID"
echo "This user will be a memeber of zeta${ROLE}data, zeta${ROLE}apps, zeta${ROLE}zeta, and zeta${ROLE}etl"

stty -echo
printf "Please enter new password for zetasvc$ROLE: "
read PASS1
echo ""
printf "Please re-enter password for the zetasvc$ROLE: "
read PASS2
echo ""
stty echo

# If the passwords don't match, keep asking for passwords until they do
while [ "$PASS1" != "$PASS2" ]
do
    echo "Passwords entered for zetasvc$ROLE do not match, please try again"
    stty -echo
    printf "Please enter new password for zetasvc$ROLE: "
    read PASS1
    echo ""
    printf "Please re-enter password for the zetasvc$ROLE: "
    read PASS2
    echo ""
    stty echo
done



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

UPASSFILE="${TMP_LDIF}/u.txt"
TMPUPASSFILE="${TMP_LDIF}/i.txt"
mkdir -p $TMP_LDIF

chmod -R 750 $TMP_LDIF
touch $UPASSFILE
touch $TMPUPASSFILE
chmod 600 $UPASSFILE
chmod 600 $TMPUPASSFILE

cat > $TMPUPASSFILE << PWF
${PASS1}
PWF
cat $TMPUPASSFILE|tr -d "\n" > $UPASSFILE
rm $TMPUPASSFILE
chmod 600 $UPASSFILE

DCKR="sudo docker run --rm -v=${TMP_LDIF}:/tmp/ldif:ro ${APP_IMG}"

UHASH=$($DCKR slappasswd -T /tmp/ldif/u.txt)
echo $UHASH

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

dn: cn=zeta${ROLE}apps,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixGroup
gidNumber: $APPGID
description:  Access group for role $ROLE and the apps directory

dn: cn=zeta${ROLE}data,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixGroup
gidNumber: $DATAGID
description:  Access group for role $ROLE and the data directory

dn: cn=zeta${ROLE}etl,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixGroup
gidNumber: $ETLGID
description:  Access group for role $ROLE and the etl directory

dn: cn=zeta${ROLE}zeta,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixGroup
gidNumber: $ZETAGID
description:  Access group for role $ROLE and the zeta directory

dn: cn=zetasvc$ROLE,ou=users,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixAccount
objectClass: inetOrgPerson
cn: zetasvc$ROLE
givenName: zeta$ROLE
sn: service
uidNumber: $SVCUID
uid: zetasvc$ROLE
gidNumber: 2501
homeDirectory: /home/zetasvc$ROLE
loginShell: /bin/bash
userPassword: $UHASH

dn: cn=zeta${ROLE}apps,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: modify
add: memberuid
memberuid: zetasvc$ROLE

dn: cn=zeta${ROLE}data,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: modify
add: memberuid
memberuid: zetasvc$ROLE

dn: cn=zeta${ROLE}etl,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: modify
add: memberuid
memberuid: zetasvc$ROLE

dn: cn=zeta${ROLE}zeta,ou=groups,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: modify
add: memberuid
memberuid: zetasvc$ROLE

EOL

ADD_CMD="ldapmodify -H ldap://openldap.shared.marathon.mesos -x -y /tmp/ldif/p.txt -D \"cn=admin,dc=marathon,dc=mesos\" -f /tmp/ldif/tmp.ldif"
cat > ${TMP_LDIF}/run.sh << ERUN
#!/bin/bash
$ADD_CMD
ERUN
chmod +x ${TMP_LDIF}/run.sh

$DCKR /tmp/ldif/run.sh

rm -rf $TMP_LDIF
