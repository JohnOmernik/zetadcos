
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

OUT=$(sudo docker images|grep ldaputils)
if [ "$OUT" = "" ]; then

if [ "$DOCKER_PROXY" != "" ]; then
    DOCKER_LINE1="ENV http_proxy=$DOCKER_PROXY"
    DOCKER_LINE2="ENV HTTP_PROXY=$DOCKER_PROXY"
    DOCKER_LINE3="ENV https_proxy=$DOCKER_PROXY"
    DOCKER_LINE4="ENV HTTPS_PROXY=$DOCKER_PROXY"
else
    DOCKER_LINE1=""
    DOCKER_LINE2=""
    DOCKER_LINE3=""
    DOCKER_LINE4=""
fi

    mkdir -p ./tmp
    cat > ./tmp/Dockerfile << EOF
FROM ubuntu
$DOCKER_LINE1
$DOCKER_LINE2
$DOCKER_LINE3
$DOCKER_LINE4

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ldap-utils slapd
CMD ["/bin/bash"]
EOF
    cd ./tmp
    sudo docker build -t ${APP_IMG} .
    sudo docker push ${APP_IMG}
    cd ..
    rm -rf ./tmp
fi


LDAP_ROOT="/mapr/$CLUSTERNAME/zeta/shared/openldap"

if [ ! "$LDAP_ROOT" ]; then
   echo "Openldap doesn't appear to be installed, exiting"
   exit 1
fi

LDAPPASS=$(cat ${LDAP_ROOT}/initconf/default.yaml.startup|grep ADMIN|sed "s/LDAP_ADMIN_PASSWORD: //")


TMP_LDIF="`pwd`/tmpldif"
PASSFILE="${TMP_LDIF}/p.txt"
TMPPASSFILE="${TMP_LDIF}/o.txt"
mkdir -p $TMP_LDIF

chmod -R 750 $TMP_LDIF
touch $PASSFILE
touch $TMPPASSFILE
chmod 600 $PASSFILE
chmod 600 $TMPPASSFILE

cat > $TMPPASSFILE << PWF
${LDAPPASS}
PWF
cat $TMPPASSFILE|tr -d "\n" > $PASSFILE
rm $TMPPASSFILE
chmod 600 $PASSFILE

DCKR="sudo docker run --rm -v=${TMP_LDIF}:/tmp/ldif:ro ${APP_IMG}"

cat > ${TMP_LDIF}/zetausers.ldif << EOL
dn: cn=zetausers,dc=marathon,dc=mesos
objectClass: top
objectClass: posixGroup
gidNumber: 2501
EOL

ADD_CMD="ldapadd -H ldap://openldap.shared.marathon.mesos -x -y /tmp/ldif/p.txt -D \"cn=admin,dc=marathon,dc=mesos\" -f /tmp/ldif/zetausers.ldif"
cat > ${TMP_LDIF}/run.sh << ERUN
#!/bin/bash
$ADD_CMD
ERUN
chmod +x ${TMP_LDIF}/run.sh

$DCKR /tmp/ldif/run.sh

rm -rf $TMP_LDIF
./add_role_schema.sh shared
