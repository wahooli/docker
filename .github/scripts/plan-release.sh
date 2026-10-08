#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_REF:?}" "${LOCAL_IMAGE:?}" "${CONTEXT:?}"
UPSTREAM_ENV="${UPSTREAM_ENV:-}"
UPSTREAM_CMD="${UPSTREAM_CMD:-}"
TARGET="${TARGET:-}"
BUILD_ARGS="${BUILD_ARGS:-}"
PLATFORMS="${PLATFORMS:-}"
FORCE="${FORCE:-false}"
CAN_PUSH="${CAN_PUSH:-false}"
OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"
FINGERPRINT_LABEL=li.wahoo.image.fingerprint

semver='^[0-9]+\.[0-9]+\.[0-9]+$'

skopeo() {
  if type -P skopeo >/dev/null; then
    command skopeo "$@"
  else
    docker run --rm quay.io/skopeo/stable:latest "$@"
  fi
}

list_tags() {
  local out
  if out=$(skopeo list-tags "docker://$1" 2>&1); then
    jq -r '.Tags[]' <<<"$out"
  elif grep -qiE '403 Forbidden|requested access to the resource is denied|name unknown|not known to registry' <<<"$out"; then
    return 0
  else
    echo "$out" >&2
    return 1
  fi
}

tag_exists() {
  local out
  if out=$(docker buildx imagetools inspect "$1" 2>&1); then
    return 0
  elif grep -qiE ': not found$|manifest unknown|403 Forbidden|requested access to the resource is denied|name unknown|not known to registry' <<<"$out"; then
    return 1
  else
    echo "$out" >&2
    exit 1
  fi
}

label_of() {
  docker buildx imagetools inspect "$1" --format '{{json .Image}}' |
    jq -r --arg label "$2" '(.["linux/amd64"] // .) | .config.Labels[$label] // empty'
}

inventory() {
  docker run --rm -i --entrypoint sh "$LOCAL_IMAGE" -s <<'EOF' | LC_ALL=C sort
dpkg-query -W -f '${Package} ${Version}\n' 2>/dev/null
apk info -v 2>/dev/null
python3 - 2>/dev/null <<'PY'
import importlib.metadata as m
for d in m.distributions():
    print(d.metadata["Name"], d.version)
PY
true
EOF
}

fingerprint() {
  {
    printf 'target=%s\nbuild-args=%s\nplatforms=%s\n' "$TARGET" "$BUILD_ARGS" "$PLATFORMS"
    (
      cd "$CONTEXT"
      find . -type f -not -path './tests/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
      find . -type f -not -path './tests/*' -perm -u+x | LC_ALL=C sort
    )
    inventory
  } | sha256sum | cut -d' ' -f1
}

fp="$(fingerprint)"
upstream=""
reason=""
push=true

if [ -n "$UPSTREAM_ENV" ] || [ -n "$UPSTREAM_CMD" ]; then
  if [ -n "$UPSTREAM_ENV" ]; then
    source_desc="$UPSTREAM_ENV"
    upstream="$(docker image inspect "$LOCAL_IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}' |
      sed -n "s/^${UPSTREAM_ENV}=//p")"
  else
    source_desc="'$UPSTREAM_CMD'"
    upstream="$(docker run --rm --entrypoint sh "$LOCAL_IMAGE" -c "$UPSTREAM_CMD")"
  fi
  if ! [[ "$upstream" =~ $semver ]]; then
    echo "::error::upstream version from $source_desc in $LOCAL_IMAGE is '$upstream', expected X.Y.Z" >&2
    exit 1
  fi
  last="$(list_tags "$IMAGE_REF" | sed -n "s/^${upstream//./\\.}-\([0-9][0-9]*\)$/\1/p" | sort -n | tail -n 1)"
  if [ -z "$last" ]; then
    tag="${upstream}-1"
    reason="first build of upstream $upstream"
  elif [ "$(label_of "$IMAGE_REF:${upstream}-${last}" "$FINGERPRINT_LABEL")" = "$fp" ] && [ "$FORCE" != "true" ]; then
    tag="${upstream}-${last}"
    push=false
    reason="contents unchanged since $tag"
  else
    tag="${upstream}-$((last + 1))"
    reason="contents changed since ${upstream}-${last}"
    [ "$FORCE" = "true" ] && reason="forced rebuild after ${upstream}-${last}"
  fi
  if [ "$push" = "true" ] && tag_exists "$IMAGE_REF:$tag"; then
    echo "::error::$IMAGE_REF:$tag already exists; refusing to overwrite" >&2
    exit 1
  fi
else
  tag="$(tr -d '[:space:]' <"$CONTEXT/VERSION")"
  if ! [[ "$tag" =~ $semver ]]; then
    echo "::error::$CONTEXT/VERSION is '$tag', expected X.Y.Z" >&2
    exit 1
  fi
  if tag_exists "$IMAGE_REF:$tag"; then
    if [ "$FORCE" = "true" ]; then
      reason="forced overwrite of existing $tag"
    else
      push=false
      reason="$tag already published; bump $CONTEXT/VERSION to release changes"
    fi
  else
    reason="new version $tag"
  fi
fi

if [ "$CAN_PUSH" != "true" ]; then
  [ "$push" = "true" ] && reason="would publish: $reason"
  push=false
fi

{
  echo "tag=$tag"
  echo "push=$push"
  echo "upstream=$upstream"
  echo "fingerprint=$fp"
  echo "reason=$reason"
} >>"$OUTPUT"
