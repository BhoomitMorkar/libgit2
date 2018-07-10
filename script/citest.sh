#!/bin/sh

set -e
set -x

if [ -n "$SKIP_TESTS" ]; then
	exit $?
fi

TMPDIR=${TMPDIR:-/tmp}

# Configure the test environment; run them early so that we're certain
# that they're started by the time we need them.

echo "################################################################################"
echo "## Configuring test environment"
echo "################################################################################"

if [ -z "$SKIP_GITDAEMON_TESTS" ]; then
	echo "Starting git daemon..."
	GITDAEMON_DIR=`mktemp -d ${TMPDIR}/gitdaemon.XXXXXXXX`
	git init --bare "${GITDAEMON_DIR}/test.git"
	git daemon --listen=localhost --export-all --enable=receive-pack --pid-file="${GITDAEMON_DIR}/pid" --base-path="${GITDAEMON_DIR}" "${GITDAEMON_DIR}" 2>/dev/null &
fi

if [ -z "$SKIP_PROXY_TESTS" ]; then
	echo "Starting HTTP proxy..."
	curl -L https://github.com/ethomson/poxyproxy/releases/download/v0.1.0/poxyproxy-0.1.0.jar >poxyproxy.jar
	java -jar poxyproxy.jar -d --port 8080 --credentials foo:bar >/dev/null 2>&1 &
fi

if [ -z "$SKIP_SSH_TESTS" ]; then
	echo "Starting ssh daemon..."
	HOME=`mktemp -d ${TMPDIR}/home.XXXXXXXX`
	SSH_DIR="${HOME}/.ssh"
	SSHD_DIR=`mktemp -d ${TMPDIR}/sshd.XXXXXXXX`
	mkdir ${SSH_DIR}
	cat >"${SSHD_DIR}/sshd_config" <<-EOF
	Port 2222
	ListenAddress 0.0.0.0
	Protocol 2
	HostKey ${SSHD_DIR}/id_rsa
	PidFile ${SSHD_DIR}/pid
	RSAAuthentication yes
	PasswordAuthentication yes
	PubkeyAuthentication yes
	ChallengeResponseAuthentication no
	# Required here as sshd will simply close connection otherwise
	UsePAM no
	EOF
	ssh-keygen -t rsa -f "${SSHD_DIR}/id_rsa" -N "" -q
	/usr/sbin/sshd -f "${SSHD_DIR}/sshd_config"

	# Set up keys
	ssh-keygen -t rsa -f "${SSH_DIR}/id_rsa" -N "" -q
	cat "${SSH_DIR}/id_rsa.pub" >>"${SSH_DIR}/authorized_keys"
	while read algorithm key comment; do
		echo "[localhost]:2222 $algorithm $key" >>"${SSH_DIR}/known_hosts"
	done <"${SSHD_DIR}/id_rsa.pub"

	# Get the fingerprint for localhost and remove the colons so we can
	# parse it as a hex number. The Mac version is newer so it has a
	# different output format.
	if [ "$TRAVIS_OS_NAME" = "osx" ]; then
		FINGERPRINT=$(ssh-keygen -E md5 -F '[localhost]:2222' -l | tail -n 1 | cut -d ' ' -f 3 | cut -d : -f2- | tr -d :)
	else
		FINGERPRINT=$(ssh-keygen -F '[localhost]:2222' -l | tail -n 1 | cut -d ' ' -f 2 | tr -d ':')
	fi
fi

# Run the tests that do not require network connectivity.

if [ -z "$SKIP_OFFLINE_TESTS" ]; then
	echo ""
	echo "################################################################################"
	echo "## Running (offline) tests"
	echo "################################################################################"

	ctest -V -R offline || exit $?
fi

if [ -z "$SKIP_ONLINE_TESTS" ]; then
	# Run the various online tests.  The "online" test suite only includes the
	# default online tests that do not require additional configuration.  The
	# "proxy" and "ssh" test suites require further setup.

	echo ""
	echo "################################################################################"
	echo "## Running (online) tests"
	echo "################################################################################"

	ctest -V -R online
fi

if [ -z "$SKIP_GITDAEMON_TESTS" ]; then
	echo ""
	echo "Running gitdaemon tests"
	echo ""

	export GITTEST_REMOTE_URL="git://localhost/test.git"
	ctest -V -R gitdaemon || exit $?
	unset GITTEST_REMOTE_URL
fi

if [ -z "$SKIP_PROXY_TESTS" ]; then
	echo ""
	echo "Running proxy tests"
	echo ""

	export GITTEST_REMOTE_PROXY_URL="localhost:8080"
	export GITTEST_REMOTE_PROXY_USER="foo"
	export GITTEST_REMOTE_PROXY_PASS="bar"
	ctest -V -R proxy || exit $?
	unset GITTEST_REMOTE_PROXY_URL
	unset GITTEST_REMOTE_PROXY_USER
	unset GITTEST_REMOTE_PROXY_PASS
fi

if [ -z "$SKIP_SSH_TESTS" ]; then
	echo ""
	echo "Running ssh tests"
	echo ""

	export GITTEST_REMOTE_URL="ssh://localhost:2222/$HOME/_temp/test.git"
	export GITTEST_REMOTE_USER=$USER
	export GITTEST_REMOTE_SSH_KEY="${SSH_DIR}/id_rsa"
	export GITTEST_REMOTE_SSH_PUBKEY="${SSH_DIR}/id_rsa.pub"
	export GITTEST_REMOTE_SSH_PASSPHRASE=""
	export GITTEST_REMOTE_SSH_FINGERPRINT="${SSH_FINGERPRINT}"
	ctest -V -R ssh || exit $?
	unset GITTEST_REMOTE_URL
	unset GITTEST_REMOTE_USER
	unset GITTEST_REMOTE_SSH_KEY
	unset GITTEST_REMOTE_SSH_PUBKEY
	unset GITTEST_REMOTE_SSH_PASSPHRASE
	unset GITTEST_REMOTE_SSH_FINGERPRINT
fi

echo "Cleaning up..."

if [ -z "$SKIP_GITDAEMON_TESTS" ]; then
	kill $(cat "${GITDAEMON_DIR}/pid")
fi

if [ -z "$SKIP_SSH_TESTS" ]; then
	kill $(cat "${SSHD_DIR}/pid")
fi
