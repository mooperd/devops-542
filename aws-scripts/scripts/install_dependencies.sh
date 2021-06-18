#!/bin/bash -x

sleep 5

curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash

apt-get update 
#set up the repository and dependecies
apt-get install -y 
    gettext \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

#install docker engine
apt-get update && apt-get install -y docker-ce=5:19.03.13~3-0~ubuntu-focal docker-ce-cli=5:19.03.13~3-0~ubuntu-focal containerd.io

apt-get install -y gitlab-runner