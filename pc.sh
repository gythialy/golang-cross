#!/bin/bash
set -ex
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
    *PAYG*)
	echo Not uploading PAYG version $pkg
	;;
    *deb)
	vers="$DEBVERS"
	;;
    *rpm)
	vers="$RPMVERS"
	;;
    *)
	echo "Unknown package, not uploading"
esac

for i in $vers; do
    # Yank packages first to enable tag re-use
    package_cloud yank $REPO/$i $(basename $pkg) || true
    package_cloud push $REPO/$i $pkg 2>&1
done
