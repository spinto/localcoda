FROM ubuntu:24.04

#Basic required packages
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y curl bash jq kubectl docker.io nginxfcgiwrap  && apt clean all && rm -rf /var/lib/apt/lists/*

#Install application
COPY entrypoint.sh /etc/localcoda/entrypoint.sh
COPY 

ENTRYPOINT /etc/localcoda/entrypoint.sh
