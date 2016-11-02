#!/bin/bash

CONF="./zeta_cluster.conf"
# Pull in Cluster conf
. $CONF

# Source Shared Env

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

ROLE=$1
UNAME=$2
UUID=$3
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
   echo "This script takes three argument, ROLE USERNAME UID"
   exit 1
fi

if [ "$UNAME" == "" ]; then
   echo "This script takes three argument, ROLE USERNAME UID"
   exit 1
fi

if [ "$UUID" == "" ]; then
   echo "This script takes three argument, ROLE USERNAME UID"
   exit 1
fi

CREDS="/home/$IUSER/creds/creds.txt"
HOST=$(echo $CLDBS|cut -d"," -f1|cut -d":" -f1)
WEBHOST="$HOST:8443"
TFILE="/tmp/netrc.tmp"

touch $TFILE
chown $IUSER:$IUSER $TFILE
chmod 600 $TFILE
cat > $TFILE << EOF
machine $HOST login $(cat $CREDS|grep mapr|cut -d":" -f1) password $(cat $CREDS|grep mapr|cut -d":" -f2)
EOF

BASE_REST="https://$WEBHOST/rest"

CURL_GET_BASE="/opt/mesosphere/bin/curl -k --netrc-file $TFILE $BASE_REST"

VALID_UID=$(cat /mapr/$CLUSTERNAME/zeta/kstore/zetasync/zetauid.list|grep $ROLE|cut -d":" -f2)

if [ "$VALID_UID" == "" ]; then
    echo "The starting UID for role $ROLE was not found, are you sure this role is installed?"
    exit 1
fi
echo $VALID_UID

if [ "$UUID" -ge $VALID_UID ] && [ "$UUID" -lt $(($VALID_UID + 500000)) ]; then 
    echo "$UUID is valid in role $ROLE - However we do not check for duplicates (yet)"
else
    echo "$UUID is not valid in role $ROLE"
    exit 1
fi

if [ "$VALID" != "1" ]; then
    echo "You wish to create user $UNAME with UID $UUID in role $ROLE"
    read -e -p "Is this correct? " -i "N" CHK
    if [ "$CHK" != "Y" ]; then
        echo "Used gave up"
        exit 1
    fi
fi

echo "Please enter the user's first name: "
read -e -p "Firstname: " FNAME

echo "Please enter the user's last name: "
read -e -p "Lastname: " LNAME


stty -echo
printf "Please enter new password for $UNAME: "
read PASS1
echo ""
printf "Please re-enter password for the $UNAME: "
read PASS2
echo ""
stty echo


while [ "$PASS1" != "$PASS2" ]
do
    echo "Passwords entered for $UNAME do not match, please try again"
    stty -echo
    printf "Please enter new password for $UNAME: "
    read PASS1
    echo ""
    printf "Please re-enter password for the $UNAME: "
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


cat > ${TMP_LDIF}/tmp.ldif << EOL
dn: cn=$UNAME,ou=users,ou=zeta$ROLE,dc=marathon,dc=mesos
changetype: add
objectClass: top
objectClass: posixAccount
objectClass: inetOrgPerson
cn: $UNAME
givenName: $FNAME
sn: $LNAME
uidNumber: $UUID
uid: $UNAME
gidNumber: 2501
homeDirectory: /home/$UNAME
loginShell: /bin/bash
userPassword: $UHASH

EOL

ADD_CMD="ldapmodify -H ldap://openldap-shared.marathon.slave.mesos -x -y /tmp/ldif/p.txt -D \"cn=admin,dc=marathon,dc=mesos\" -f /tmp/ldif/tmp.ldif"
cat > ${TMP_LDIF}/run.sh << ERUN
#!/bin/bash
$ADD_CMD
ERUN
chmod +x ${TMP_LDIF}/run.sh

$DCKR /tmp/ldif/run.sh


echo "User added creating home directory in Shared Filesystem"

if [ ! -d "/mapr/$CLUSTERNAME/user/$UNAME" ]; then
    echo "$UNAME Home Directory not found: Creating"
    CMD="$CURL_GET_BASE/volume/create?name=user.$UNAME&path=/user/$UNAME&rootdirperms=775&user=$UNAME:fc,a,dump,restore,m,d%20zetaadm:fc,a,dump,restore,m,d%20mapr:fc,a,dump,restore,m,d&ae=$UNAME"
    $CMD
    echo ""
    T=""
    while [ "$T" == "" ]; do
        sleep 1
        T=$(ls -1 /mapr/$CLUSTERNAME/user|grep $UNAME)
    done
    sudo chown $UNAME:zetaadm /mapr/$CLUSTERNAME/user/$UNAME
    sudo chmod 750 /mapr/$CLUSTERNAME/user/$UNAME
fi


rm -rf $TMP_LDIF
