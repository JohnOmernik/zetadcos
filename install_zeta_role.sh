#!/bin/bash


CONF="./zeta_cluster.conf"

. $CONF

CURUSER=$(whoami)

if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi

MESOS_ROLE=$1

if [ "$MESOS_ROLE" == "" ]; then
    echo "You must pass a role to create to this script"
    exit 1
fi


# This is the ENV File for the cluster.
ZETA_ENV_FILE="/mapr/${CLUSTERNAME}/zeta/kstore/env/zeta_${MESOS_ROLE}.sh"


if [ -f "$ZETA_ENV_FILE" ]; then
    echo "Zeta Role File already exists, will not proceed"
    echo "File: $ZETA_ENV_FILE"
    exit 1
fi

echo "Role installation is not yet complete - This is a placeholder file"
exit 1

# Files specific to an installation
maprdocker.marathon
ip_detect.sh


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

CURL_GET_BASE="curl -k --netrc-file $TFILE $BASE_REST"







rm $TFILE



