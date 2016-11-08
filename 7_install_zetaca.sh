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


APP_ROOT="/mapr/$CLUSTERNAME/zeta/shared/zetaca"
APP_HOME="/mapr/$CLUSTERNAME/zeta/shared/zetaca"
APP_IMG="${ZETA_DOCKER_REG_URL}/zetaca"


if [ -d "$APP_HOME" ]; then
    echo "There is already a CA that exists at the APP_HOME location of $APP_HOME"
    echo "We don't continue, as we don't want you to lose any existing CA information"
    exit 1
fi

BUILD_TMP="./tmp_build"

SOURCE_GIT="https://git.organizedvillainy.com/ryan/ca_rest"
DCK=$(sudo docker images|grep zetaca)

if [ "$DCK" == "" ]; then
    BUILD="Y"
else
    echo "The docker image already appears to exist, do you wish to rebuild?"
    echo "$DCK"
    read -e -p "Rebuild Docker Image? " -i "N" BUILD
fi


if [ "$BUILD" == "Y" ]; then
    rm -rf $BUILD_TMP
    mkdir -p $BUILD_TMP
    cd $BUILD_TMP

    if [ "$DOCKER_PROXY" != "" ]; then
        DOCKER_LINE1="ENV http_proxy=$DOCKER_PROXY"
        DOCKER_LINE2="ENV HTTP_PROXY=$DOCKER_PROXY"
        DOCKER_LINE3="ENV https_proxy=$DOCKER_PROXY"
        DOCKER_LINE4="ENV HTTPS_PROXY=$DOCKER_PROXY"
        DOCKER_LINE5="ENV NO_PROXY=$DOCKER_NOPROXY"
        DOCKER_LINE6="ENV no_proxy=$DOCKER_NOPROXY"
    else
        DOCKER_LINE1=""
        DOCKER_LINE2=""
        DOCKER_LINE3=""
        DOCKER_LINE4=""
        DOCKER_LINE5=""
        DOCKER_LINE6=""
    fi

cat > ./Dockerfile << EOF
FROM ubuntu:14.04

RUN adduser --disabled-login --gecos '' --uid=2500 zetaadm

$DOCKER_LINE1
$DOCKER_LINE2
$DOCKER_LINE3
$DOCKER_LINE4
$DOCKER_LINE5
$DOCKER_LINE6

RUN gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
RUN apt-get update && apt-get install -y curl openssl libreadline6 libreadline6-dev zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf libc6-dev ncurses-dev automake libtool bison subversion pkg-config git
RUN \curl -sSL https://get.rvm.io | bash -s stable --ruby
RUN git clone $SOURCE_GIT /root/ca_rest
WORKDIR /root/ca_rest
RUN mkdir -p /root/ca_rest/tmp && chmod 777 /root/ca_rest/tmp
RUN /bin/bash -l -c "rvm requirements"
RUN /bin/bash -l -c "gem install sinatra rest-client"
EXPOSE 80 443
EOF


    sudo docker build -t $APP_IMG .
    sudo docker push $APP_IMG
    cd ..
    rm -rf $BUILD_TMP
else
    echo "Not Building"
fi

mkdir -p $APP_HOME
mkdir -p $APP_HOME/CA
sudo chown -R zetaadm:zetaadm $APP_HOME
sudo chmod 700 $APP_HOME/CA


# Now we will run the docker container to create the CA for Zeta
# Note: Both this script and the git repo script should be changed so we can write the password to a secure file in $APP_HOME/certs/ca_key.txt 
# And the script that instantiates the CA reads the value from the file rather than passing it as an argument that will appear in process listing 

cat > $APP_HOME/CA/init_ca.sh << EOL1
#!/bin/bash
/root/ca_rest/01_create_ca_files_and_databases.sh /root/ca_rest/CA
EOL1
chmod +x $APP_HOME/CA/init_ca.sh

cat > $APP_HOME/CA/init_all.sh << EOL2
#!/bin/bash
chown -R zetaadm:zetaadm /root
su zetaadm -c /root/ca_rest/CA/init_ca.sh
EOL2
chmod +x $APP_HOME/CA/init_all.sh

sudo docker run -it -v=/${APP_HOME}/CA:/root/ca_rest/CA:rw $APP_IMG /root/ca_rest/CA/init_all.sh

echo "Certs created:"
echo ""
ls -ls $APP_HOME/CA
echo ""

read -e -p "Please enter the port for the Zeta CA Rest service to run on: " -i "10443" APP_PORT

cat > ${APP_HOME}/marathon.json << EOL4
{
  "id": "shared/zetaca",
  "cpus": 1,
  "mem": 512,
  "cmd":"/bin/bash -l -c '/root/ca_rest/main.rb'",
  "instances": 1,
  "env": {
     "SERVER_PORT": "3000",
     "CA_ROOT": "/root/ca_rest/CA"
  },
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 3000, "hostPort": ${APP_PORT}, "servicePort": 0, "protocol": "tcp"}
      ]
    },
  "volumes": [
      {
        "containerPath": "/root/ca_rest/CA",
        "hostPath": "${APP_HOME}/CA",
        "mode": "RW"
      }
    ]
  }
}

EOL4

sleep 1

echo "Submitting to Marathon"
curl -X POST $MARATHON_SUBMIT -d @${APP_HOME}/marathon.json -H "Content-type: application/json"
echo ""
echo ""
echo ""
echo ""


