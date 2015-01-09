#!/bin/bash

echo "Setting up portal."
echo "This deploys the portal only. Routing must also be deployed."
echo "All config files should be in $CONFIG_DIR"
echo "Etcd for Hipache should be configured in dit4c-highcommand.conf"

DOCKER_SOCKET="/var/run/docker.sock"

if [ ! -S $DOCKER_SOCKET ]
then
    echo "Host Docker socket should be mounted at $DOCKER_SOCKET"
    exit 1
fi

# Create DB server
docker start dit4c_couchdb || docker run -d --name dit4c_couchdb \
    -v /usr/local/var/log/couchdb:/var/log \
    --restart=always \
    klaemo/couchdb

# Wait a little to ensure dit4c_couchdb exists
until [[ `docker inspect dit4c_{etcd,couchdb}; echo $?` ]]
do
    sleep 1
done

# Create highcommand server
docker start dit4c_highcommand || docker run -d --name dit4c_highcommand \
    -v /var/log/dit4c_highcommand:/var/log \
    -v $CONFIG_DIR/dit4c-highcommand.conf:/etc/dit4c-highcommand.conf \
    --link dit4c_etcd:etcd \
    --link dit4c_couchdb:couchdb \
    dit4c/dit4c-platform-highcommand

echo "Done configuring portal."
