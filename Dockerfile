# DOCKER-VERSION 1.1.0
FROM centos:centos7
MAINTAINER t.dettrick@uq.edu.au

# Set defaults which should be overridden on run
ENV CONFIG_DIR /opt/config

RUN yum install -y curl docker

ADD /opt /opt

CMD ["bash", "/opt/run.sh"]
