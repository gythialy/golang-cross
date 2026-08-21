#!/usr/bin/env bash
# Prune GitHub Actions caches: dead PR caches + quota management.
#
# Rules (in order):
#   1. PR-closed event (PR_BRANCH set): delete that PR's caches.
#   2. Dead PR caches: refs/pull/<N>/merge whose PR is no longer OPEN.
#   3. Quota: if total size > QUOTA_GB, evict least-recently-used caches
#      first until under quota; refs/heads/* (the active build cache) is
#      never evicted, so GitHub's 10 GB auto-eviction never has to hit main.
#
# Uses `gh api` directly — the gh-actions-cache extension's `list|cut`
# pipeline left orphaned entries behind (PR #449 merged but its caches
# survived). DELETE is idempotent; 404 = already gone, treated as success.
#
# Env:
#   GH_TOKEN    (required)
#   PR_BRANCH   (optional) refs/pull/<N>/merge of a just-closed PR
#   QUOTA_GB    (optional, integer, default 8)
#   DRY_RUN     (optional) set to only print, not delete

set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
QUOTA_GB="${QUOTA_GB:-8}"
DRY_RUN="${DRY_RUN:-}"
PR_BRANCH="${PR_BRANCH:-}"

CACHES_FILE="$(mktemp)"
trap 'rm -f "$CACHES_FILE" "${CACHES_FILE}.new"' EXIT

# List all caches: --paginate + --jq emits one JSON object per line.
gh api "/repos/${REPO}/actions/caches?per_page=100" --paginate \
  --jq '.actions_caches[]' > "$CACHES_FILE"

total_bytes=$(jq -s 'map(.size_in_bytes) | add' "$CACHES_FILE")
echo "listed $(jq -s 'length' "$CACHES_FILE") caches, $((total_bytes / 1048576)) MB total (quota ${QUOTA_GB} GB)"

delete_cache() {
  local id="$1" out
  [ -n "$DRY_RUN" ] && return 0
  if out=$(gh api -X DELETE "/repos/${REPO}/actions/caches/${id}" 2>&1); then
    return 0
  fi
  # 404 = already gone (idempotent); anything else is a real error
  echo "$out" | grep -qiE '404|not found' && return 0
  echo "!! delete ${id} failed: ${out}" >&2
}

# --- pass 1: just-closed PR -------------------------------------------
if [ -n "$PR_BRANCH" ]; then
  n=$(jq -s --arg ref "$PR_BRANCH" '[.[] | select(.ref == $ref)] | length' "$CACHES_FILE")
  echo "PR closed: deleting ${n} caches on ${PR_BRANCH}"
  jq -r --arg ref "$PR_BRANCH" 'select(.ref == $ref) | .id' "$CACHES_FILE" | while read -r id; do
    delete_cache "$id"
  done
  jq --arg ref "$PR_BRANCH" 'select(.ref != $ref)' "$CACHES_FILE" > "${CACHES_FILE}.new"
  mv "${CACHES_FILE}.new" "$CACHES_FILE"
fi

# --- pass 2: dead PR caches -------------------------------------------
while read -r ref; do
  [ -z "$ref" ] && continue
  pr_num="${ref#refs/pull/}"; pr_num="${pr_num%%/*}"
  state=$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null || echo CLOSED)
  if [ "$state" != "OPEN" ]; then
    n=$(jq -s --arg ref "$ref" '[.[] | select(.ref == $ref)] | length' "$CACHES_FILE")
    echo "dead PR #${pr_num}: deleting ${n} caches"
    jq -r --arg ref "$ref" 'select(.ref == $ref) | .id' "$CACHES_FILE" | while read -r id; do
      delete_cache "$id"
    done
    jq --arg ref "$ref" 'select(.ref != $ref)' "$CACHES_FILE" > "${CACHES_FILE}.new"
    mv "${CACHES_FILE}.new" "$CACHES_FILE"
  fi
done < <(jq -r 'select(.ref | startswith("refs/pull/")) | .ref' "$CACHES_FILE" | sort -u)

# --- pass 3: quota (LRU, never refs/heads/*) --------------------------
total_bytes=$(jq -s 'map(.size_in_bytes) | add' "$CACHES_FILE")
quota_bytes=$((QUOTA_GB * 1024 * 1024 * 1024))
if [ "$total_bytes" -gt "$quota_bytes" ]; then
  echo "over quota ($((total_bytes / 1048576)) MB > ${QUOTA_GB} GB): evicting LRU (non-main)"
  while read -r id size key; do
    [ "$total_bytes" -le "$quota_bytes" ] && break
    echo "  evict $((size / 1048576)) MB ${key:0:48}"
    delete_cache "$id"
    total_bytes=$((total_bytes - size))
  done < <(jq -s -r 'sort_by(.last_accessed_at // "1970-01-01T00:00:00Z")
                     | map(select(.ref | startswith("refs/heads/") | not))
                     | .[] | "\(.id) \(.size_in_bytes) \(.key)"' "$CACHES_FILE")
fi

echo "done: $((total_bytes / 1048576)) MB remaining"
