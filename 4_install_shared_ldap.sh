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

echo "This is not complete, do not use"
exit 0

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

CURL_GET_BASE="/opt/mesosphere/bin/curl -k --netrc-file $TFILE $BASE_REST


SOURCE_IMG="osixia/openldap"

sudo docker pull osixia/openldap

APP_IMG="${ZETA_DOCKER_REG_URL}/openldap"

sudo docker tag $SOURCE_IMG $APP_IMG

sudo docker push $APP_IMG


APP_ROOT="/mapr/$CLUSTERNAME/zeta/shared/openldap"

if [ -d "$APP_ROOT" ]; then
    echo "OpenLDAP Root at $APP_ROOT already exists. Refusing to go on..."
    exit 1
fi



mkdir -p ${APP_ROOT}
mkdir -p ${APP_ROOT}/ldap
mkdir -p ${APP_ROOT}/slapd.d

sudo chown -R zetaadm:zetaadm ${APP_ROOT}
sudo chmod -R 750 ${APP_ROOT}


cat > /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/openldap.sh << EOL
export ZETA_OPENLDAP_HOST="openldap.shared.marathon.mesos"
export ZETA_DOCKER_REG_PORT="$NEW_DOCKER_REG_PORT"
export ZETA_DOCKER_REG_URL="\${ZETA_DOCKER_REG_HOST}:\${ZETA_DOCKER_REG_PORT}"
EOL



sudo chmod +x /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/openldap.sh

MARFILE="${APP_ROOT}/openldap.shared.marathon"



# docker run --env LDAP_ORGANISATION="My Company" --env LDAP_DOMAIN="my-company.com" \
# --env LDAP_ADMIN_PASSWORD="JonSn0w" --detach osixia/openldap:1.1.5
cat > $MARFILE << EOF
{
  "id": "shared/openldap",
  "cpus": 1,
  "mem": 1024,
  "instances": 1,
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/var/lib/registry", "hostPath": "${DOCKER_IMAGE_LOC}", "mode": "RW" }
    ]
  }
}
EOF



