#!/bin/sh

# From https://www.hiroom2.com/2019/06/19/ubuntu-1904-docker-ja/
# Install packages for add-apt-repository.
sudo apt install -y apt-transport-https ca-certificates curl \
     software-properties-common

# Install docker-ce. There is no docker-ce for cosmic yet.
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
V=bionic #V=$(lsb_release -cs)
sudo add-apt-repository \
     "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${V} stable"
sudo apt update -y
sudo apt install -y docker-ce

# Add user who uses docker to docker group.
sudo gpasswd -a "${USER}" docker
sudo reboot
