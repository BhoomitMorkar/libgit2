#!/bin/sh

set -x

apt-get update
apt-get -y install cmake build-essential openssl libssl-dev libssh2-1-dev libcurl4-gnutls-dev openssh-server

if [ ! -d /var/run/sshd ]; then
	sudo mkdir /var/run/sshd
fi
