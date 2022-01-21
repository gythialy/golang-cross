#!/bin/bash

# goreleaser calls a custom publisher for each artefact
# packagecloud expects the distro version when pushing
# this script bridges both by choosing the appropriate list of distro versions from $DEBVERS and $RPMVERS
# $REPO, $DEBVERS and $RPMVERS are expected to be set by goreleaser

usage() {
    echo <<EOF
Usage: $0 pkg_file
EOF
}

if [ -z $1 ]; then
    usage
    exit 1
fi

pkg=$1

case $pkg in
    *deb)
	vers="$DEBVERS"
	;;
    *rpm)
	vers="$RPMVERS"
	;;
    *)
	echo Not uploading $pkg
esac

for i in $vers; do
    # Ignore errors so that it doesn't break the build
    package_cloud push $REPO/$i $pkg || true
done
