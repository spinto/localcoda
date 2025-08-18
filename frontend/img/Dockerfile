#This is the main application container
FROM ubuntu:24.04

#Basic required packages
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y curl bash jq grep docker.io nginx fcgiwrap apache2-utils && apt clean all && rm -rf /var/lib/apt/lists/* && curl -L "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" > /usr/bin/kubectl && chmod +x /usr/bin/kubectl

#Run as non-root user
USER www-data

#Install the application
COPY --chown=www-data:www-data . /opt/localcoda

WORKDIR /opt/localcoda/

ENTRYPOINT ["/opt/localcoda/entrypoint.sh"]
