#!/bin/bash

# goreleaser calls a custom publisher for each artefact
# packagecloud expects the distro version when pushing
# this script bridges both by choosing the appropriate list of distro versions from $DEBVERS and $RPMVERS
# $REPO, $DEBVERS and $RPMVERS are expected to be set by goreleaser

REQUIRED_VARS="PACKAGECLOUD_TOKEN REPO"

usage() {
    echo <<EOF
Usage: $0 pkg_file
Required envs: ${REQUIRED_VARS[@]}
EOF
}

if [ -z $1 ]; then
    usage
    exit 1
fi

for variable in ${REQUIRED_VARS}; do
	if [[ -z "${!variable}" ]]; then
		echo "Variable: $variable - is missing"
		exit 1
	fi
done

if [[ -z "$DEBVERS" ]] && [[ -z "$RPMVERS" ]]; then
	echo "Please define at least DEBVERS or RPMVERS vars";
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

    [[ ! -s ${pkg} ]] && echo "File is empty or does not exists" && exit 1

    # Yank packages first to enable tag re-use
    package_cloud yank $REPO/$i $(basename $pkg) || true
    package_cloud push $REPO/$i $pkg

done
