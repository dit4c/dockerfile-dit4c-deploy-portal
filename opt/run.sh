#!/bin/sh

set -e

echo "Setting up portal."
echo "This deploys the portal only. Routing must also be deployed."
echo "All config files should be in $CONFIG_DIR"
echo "Etcd for Hipache should be configured in dit4c-highcommand.conf"

DOCKER_SOCKET="/var/run/docker.sock"
ETCD_IMAGE="quay.io/coreos/etcd:$ETCD_VERSION"

if [ ! -S $DOCKER_SOCKET ]
then
    echo "Host Docker socket should be mounted at $DOCKER_SOCKET"
    exit 1
fi

if [[ $HOST == "" ]]
then
    echo "HOST should be specified as an environment variable"
    exit 1
fi

if [[ $(docker inspect -f "{{ .Image }}" dit4c_etcd) == "" ]]
then
    echo "Container \"dit4c_etcd\" must exist."
    exit 1
fi

docker start -ia dit4c_ssl_keys || docker run --name dit4c_ssl_keys \
  -v $SSL_DIR/server.key:/etc/ssl/server.key \
  -v $SSL_DIR/server.crt:/etc/ssl/server.crt \
  --restart=no \
  gentoobb/openssl sh -c \
  "openssl rsa -in /etc/ssl/server.key -modulus -noout > /tmp/key_modulus; \
   openssl x509 -modulus -in /etc/ssl/server.crt -noout > /tmp/cert_modulus; \
   diff /tmp/key_modulus /tmp/cert_modulus"

KEYS_EXIST=$?

if [ $KEYS_EXIST ]
then
    echo "Required key and certificate are present and match"
else
    echo "Required key or certificate are missing/invalid in $SSL_DIR"
    exit 1
fi

ETCD_IP=$(docker inspect -f "{{ .NetworkSettings.IPAddress }}" dit4c_etcd)
ETCDCTL_CMD="docker run --rm -e ETCDCTL_PEERS=$ETCD_IP:2379 --entrypoint /etcdctl $ETCD_IMAGE --no-sync"

# Create DB server
docker start dit4c_couchdb || docker run -d --name dit4c_couchdb \
    -v /usr/local/var/log/couchdb:/var/log \
    --restart=always \
    klaemo/couchdb
$ETCDCTL_CMD set "$SERVICE_DISCOVERY_PATH/dit4c_couchdb/$HOST" \
  $(docker inspect -f "{{ .NetworkSettings.IPAddress }}" dit4c_couchdb)

# Wait a little to ensure dit4c_couchdb exists
until [[ `docker inspect dit4c_{etcd,couchdb}; echo $?` ]]
do
    sleep 1
done

# Create highcommand server
docker start dit4c_highcommand || docker run -d --name dit4c_highcommand \
    -v $CONFIG_DIR/dit4c-highcommand.conf:/etc/dit4c-highcommand.conf \
    --link dit4c_etcd:etcd \
    --link dit4c_couchdb:couchdb \
    dit4c/dit4c-platform-highcommand
$ETCDCTL_CMD set "$SERVICE_DISCOVERY_PATH/dit4c_highcommand/$HOST" \
  $(docker inspect -f "{{ .NetworkSettings.IPAddress }}" dit4c_highcommand)

# Create SSL reverse-proxy
docker start dit4c_nghttpx ||docker run --name dit4c_nghttpx -d \
  -p 443:3000 -v /opt/ssl/:/data \
  -e HOST=highcommand -e PORT=9000 \
  --link dit4c_highcommand:highcommand \
  -e KEY_FILE=/data/server.key \
  -e CERT_FILE=/data/server.crt dajobe/nghttpx

echo "Done configuring portal."
