#!/bin/sh

set -e

echo "Setting up portal."
echo "This deploys the portal only. Routing must also be deployed."
echo "All config files should be in $CONFIG_DIR"

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

docker inspect dit4c_nghttpx_config || docker run -i --name dit4c_nghttpx_config \
  -v /data/etc \
  -v $SSL_DIR/server.key:/data/ssl/server.key:ro \
  -v $SSL_DIR/server.crt:/data/ssl/server.crt:ro \
  --restart=no \
  gentoobb/openssl sh <<SCRIPT
set -e
set -x

openssl rsa -in /data/ssl/server.key -modulus -noout > /tmp/key_modulus
openssl x509 -modulus -in /data/ssl/server.crt -noout > /tmp/cert_modulus
diff /tmp/key_modulus /tmp/cert_modulus

test -f /data/etc/nghttpx.conf || cat > /data/etc/nghttpx.conf <<CONFIG
accesslog-file=/dev/stdout
errorlog-file=/dev/stderr

http2-no-cookie-crumbling=true
ciphers=ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA
add-response-header=Strict-Transport-Security: max-age=15724800; includeSubDomains;
CONFIG
SCRIPT

KEYS_EXIST=$?

if [ $KEYS_EXIST ]
then
    echo "Required key and certificate are present and match"
else
    echo "Required key or certificate are missing/invalid in $SSL_DIR"
    exit 1
fi

ETCD_IP=$(ip route show | grep -Eo "via \S+" | cut -d " " -f 2)
ETCDCTL_CMD="docker run --rm -e ETCDCTL_PEERS=$ETCD_IP:2379 --entrypoint /etcdctl $ETCD_IMAGE --no-sync"

# Create DB server
docker start dit4c_couchdb || docker run -d --name dit4c_couchdb \
    --restart=always \
    klaemo/couchdb
$ETCDCTL_CMD set "$SERVICE_DISCOVERY_PATH/dit4c_couchdb/$HOST" \
  $(docker inspect -f "{{ .NetworkSettings.IPAddress }}" dit4c_couchdb)

# Wait a little to ensure dit4c_couchdb exists
while true
do
  docker inspect dit4c_couchdb > /dev/null && break || sleep 1
done

# Create highcommand server
docker start dit4c_highcommand || docker run -d --name dit4c_highcommand \
    -v $CONFIG_DIR/dit4c-highcommand.conf:/etc/dit4c-highcommand.conf \
    --link dit4c_couchdb:couchdb \
    --restart=always \
    dit4c/dit4c-platform-highcommand
$ETCDCTL_CMD set "$SERVICE_DISCOVERY_PATH/dit4c_highcommand/$HOST" \
  $(docker inspect -f "{{ .NetworkSettings.IPAddress }}" dit4c_highcommand)

# Create SSL reverse-proxy
docker start dit4c_nghttpx || docker run --name dit4c_nghttpx -d \
  -p 443:3000 \
  --volumes-from dit4c_nghttpx_config \
  --link dit4c_highcommand:highcommand \
  --restart always \
  dit4c/nghttpx \
  --conf /data/etc/nghttpx.conf \
  -b highcommand,9000 \
  /data/ssl/server.key /data/ssl/server.crt

# Create simple HTTP->HTTPS redirect server
docker start dit4c_http_redirect || docker run --name dit4c_http_redirect -d \
  -p 80:3000 \
  --restart always \
  dit4c/https-redirect

echo "Done configuring portal."
