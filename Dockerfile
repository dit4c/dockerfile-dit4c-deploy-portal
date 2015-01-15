# DOCKER-VERSION 1.1.0
FROM centos:centos7
MAINTAINER t.dettrick@uq.edu.au

# Set defaults which should be overridden on run
ENV CONFIG_DIR /opt/config
ENV ETCD_VERSION v2.0.0_rc.1
ENV SERVICE_DISCOVERY_PATH /dit4c/containers

RUN yum install -y curl docker

ADD /opt /opt

CMD ["bash", "/opt/run.sh"]
