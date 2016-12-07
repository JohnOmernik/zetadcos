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

echo "*****************************************************"
echo "Role installation is not yet complete."
echo "We:"
echo ""
echo "Create Volumes based on role"
echo "Create ENV Files per role"
echo "Create groups or set permission properly"
echo ""
echo "We do not:"
echo ""
echo "Ask about Marathon or chronos locations"
echo ""
echo "*****************************************************"


./add_role_schema.sh $MESOS_ROLE



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

##########
# Installing  role directories in each root directory
#
echo "Checking for $MESOS_ROLE dir in each root directory."

RDS=$(echo "$ROOT_DIRS"|tr "," " ")

for DIR in $RDS; do
    #ROLE_OWNER="zetaadm:zetaadm"
    ROLE_OWNER="zetaadm:zeta${MESOS_ROLE}${DIR}"
    echo "Looking for /mapr/$CLUSTERNAME/$DIR/$MESOS_ROLE"
    if [ -d "/mapr/$CLUSTERNAME/$DIR/$MESOS_ROLE" ]; then
        echo "/mapr/$CLUSTERNAME/$DIR/shared already exists, skipping"
    else
        CMD="$CURL_GET_BASE/volume/create?name=$DIR.$MESOS_ROLE&path=/$DIR/$MESOS_ROLE&rootdirperms=770&user=zetaadm:fc,a,dump,restore,m,d%20mapr:fc,a,dump,restore,m,d&ae=zetaadm"
        $CMD
        echo ""
        T=""
        while [ "$T" == "" ]; do
            sleep 1
            T=$(ls -1 /mapr/$CLUSTERNAME/$DIR|grep $MESOS_ROLE)
        done
        sudo chown ${ROLE_OWNER} /mapr/$CLUSTERNAME/$DIR/$MESOS_ROLE
    fi
done

DIR="/mapr/$CLUSTERNAME/zeta/kstore/env/env_${MESOS_ROLE}"
sudo mkdir -p $DIR
sudo chown zetaadm:zetaadm $DIR
sudo chmod 775 $DIR
ENV_FILE="/mapr/$CLUSTERNAME/zeta/kstore/env/zeta_${MESOS_ROLE}.sh"

tee $ENV_FILE << EOL3
# Source Master Zeta ENV File
. /mapr/\$(ls -1 /mapr)/zeta/kstore/env/master_env.sh
# START GLOBAL ENV Variables for Zeta Environment

export ZETA_MARATHON_ENV="marathon${MESOSROLE}"
export ZETA_MARATHON_HOST="\${ZETA_MARATHON_ENV}.\${ZETA_MESOS_DOMAIN}"
export ZETA_MARATHON_PORT="error" # Fix this
export ZETA_MARATHON_URL="\$ZETA_MARATHON_HOST:\$ZETA_MARATHON_PORT"
export ZETA_MARATHON_SUBMIT="http://\$ZETA_MARATHON_URL/v2/apps"
# Source env_prod
for SRC in /mapr/\$ZETA_CLUSTERNAME/zeta/kstore/env/env_${MESOS_ROLE}/*.sh; do
   . \$SRC
done

if [ "\$1" == "1" ]; then
    env|grep -P "^ZETA_"
fi

EOL3

chmod +x $ENV_FILE

#Create a dummy script in the env_prod directory so that file not found errors don't appear when sourcing main file
cat > /mapr/$CLUSTERNAME/zeta/kstore/env/env_${MESOS_ROLE}/env_${MESOS_ROLE}.sh << EOL5
#!/bin/bash
# Basic script to keep file not found errors from happening
EOL5

rm $TFILE



