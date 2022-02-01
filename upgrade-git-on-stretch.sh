#!/bin/sh

# git 1.18 minimum for actions/checkout@v2

echo DEB_VERSION: $1

if [ "$1" = "stretch" ]; then
    echo "deb https://deb.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/stretch-bpo.list
    apt-get update
    apt-get install -y -t stretch-backports git
fi
