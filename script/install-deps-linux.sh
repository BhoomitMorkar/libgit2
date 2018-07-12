#!/bin/sh

set -x

apt-get update
apt-get -y install cmake build-essential openssl libssl-dev libssh2-1-dev libcurl4-gnutls-dev openssh-server

if [ ! -d /var/run/sshd ]; then
	sudo mkdir /var/run/sshd
fi

echo "pkg-config is: $(which pkg-config)"
echo "libcurl is:    $(pkg-config --modversion libcurl)"
echo "libssh2 is:    $(pkg-config --modversion libssh2)"
