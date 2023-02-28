#!/bin/bash

# https://github.com/actions/gh-actions-cache
# gh extension install actions/gh-actions-cache

REPO="github.com/gythialy/golang-cross"
BRANCH=${1:-"refs/pull/189/merge"}

echo "Fetching list of cache key of ${BRANCH}"
cacheKeysForPR=$(gh actions-cache list -R $REPO -B $BRANCH | cut -f 1 )

## Setting this to not fail the workflow while deleting cache keys. 
set +e
echo "Deleting caches..."
for cacheKey in $cacheKeysForPR
do
    gh actions-cache delete $cacheKey -R $REPO -B $BRANCH --confirm
done
echo "Done"