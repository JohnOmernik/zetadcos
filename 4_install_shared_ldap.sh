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



SOURCE_IMG="osixia/openldap:1.1.5"

sudo docker pull $SOURCE_IMG
APP_IMG="${ZETA_DOCKER_REG_URL}/openldap"

sudo docker tag $SOURCE_IMG $APP_IMG
sudo docker push $APP_IMG

APP_ROOT="/mapr/$CLUSTERNAME/zeta/shared/openldap"

if [ -d "$APP_ROOT" ]; then
    echo "OpenLDAP Root at $APP_ROOT already exists. Refusing to go on..."
    exit 1
fi


echo "Please enter the LDAP Admin Password"
stty -echo
printf "Please enter new password for the LDAP Admin: "
read LDAP_PASS1
echo ""
printf "Please re-enter password for the LDAP Admin: "
read LDAP_PASS2
echo ""
stty echo

# If the passwords don't match, keep asking for passwords until they do
while [ "$LDAP_PASS1" != "$LDAP_PASS2" ]
do
    echo "Passwords entered for LDAP user do not match, please try again"
    stty -echo
    printf "Please enter new password for the LDAP Admin: "
    read LDAP_PASS1
    echo ""
    printf "Please re-enter password for the LDAP Admin: "
    read LDAP_PASS2
    echo ""
    stty echo
done


mkdir -p ${APP_ROOT}
mkdir -p ${APP_ROOT}/ldap
mkdir -p ${APP_ROOT}/slapd.d
mkdir -p ${APP_ROOT}/ldapmod
mkdir -p ${APP_ROOT}/initconf

sudo chown -R zetaadm:zetaadm ${APP_ROOT}
sudo chmod -R 750 ${APP_ROOT}


cat > /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/openldap.sh << EOL
export ZETA_OPENLDAP_HOST="openldap.shared.marathon.mesos"
export ZETA_OPENLDAP_PORT="389"
export ZETA_OPENLDAP_SECURE_PORT="636"
EOL


cat > ${APP_ROOT}/initconf/default.yaml << EOL1
# This is the default image configuration file
# These values will persists in container environment.

# All environment variables used after the container first start
# must be defined here.
# more information : https://github.com/osixia/docker-light-baseimage

# General container configuration
# see table 5.1 in http://www.openldap.org/doc/admin24/slapdconf2.html for the available log levels.
LDAP_LOG_LEVEL: 256


EOL1

cat > ${APP_ROOT}/initconf/default.yaml.startup << EOL2
# This is the default image configuration file
# These values will persists in container environment.

# All environment variables used after the container first start
# must be defined here.
# more information : https://github.com/osixia/docker-light-baseimage

LDAP_ORGANISATION: $CLUSTERNAME
LDAP_DOMAIN: marathon.mesos
LDAP_BASE_DN: dc=marathon,dc=mesos
LDAP_ADMIN_PASSWORD: $LDAP_PASS1
LDAP_READONLY_USER: true
LDAP_READONLY_USER_USERNAME: readonly
LDAP_READONLY_USER_PASSWORD: readonly
EOL2

sudo chmod +x /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/openldap.sh

MARFILE="${APP_ROOT}/openldap.shared.marathon"



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
      { "containerPath": "/var/lib/ldap", "hostPath": "${APP_ROOT}/ldap", "mode": "RW" },
      { "containerPath": "/tmp/ldapmod", "hostPath": "${APP_ROOT}/ldapmod", "mode": "RW" },
      { "containerPath": "/etc/ldap/slapd.d", "hostPath": "${APP_ROOT}/slapd.d", "mode": "RW" },
      { "containerPath": "/container/environment/02-custom", "hostPath": "${APP_ROOT}/initconf", "mode": "RO" }
    ]
  }
}
EOF


# Add this to Docker file to increase container logginer (remove the bash comments)
#"args":[
#   "--loglevel", "debug"
#  ],

echo "Submitting to Marathon"
curl -X POST $MARATHON_SUBMIT -d @${MARFILE} -H "Content-type: application/json"
echo ""
echo ""
echo ""
echo ""

