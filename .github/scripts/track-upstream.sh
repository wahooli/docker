#!/usr/bin/env bash
set -euo pipefail

: "${DOCKERFILE:?}" "${ARG_NAME:?}" "${SOURCE:?}"
OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

semver='^[0-9]+\.[0-9]+\.[0-9]+$'

skopeo() {
  if type -P skopeo >/dev/null; then
    command skopeo "$@"
  else
    docker run --rm quay.io/skopeo/stable:latest "$@"
  fi
}

versions() {
  case "$SOURCE" in
    pypi:*)
      curl -fsSL "https://pypi.org/pypi/${SOURCE#pypi:}/json" |
        jq -r '.releases | to_entries[] | select((.value | length) > 0 and all(.value[]; .yanked | not)) | .key'
      ;;
    docker:*)
      skopeo list-tags "docker://${SOURCE#docker:}" | jq -r '.Tags[]'
      ;;
    *)
      echo "::error::unknown upstream source '$SOURCE'" >&2
      exit 1
      ;;
  esac
}

current="$(sed -n "s/^ARG ${ARG_NAME}=//p" "$DOCKERFILE")"
if ! [[ "$current" =~ $semver ]]; then
  echo "::error::ARG $ARG_NAME in $DOCKERFILE is '$current', expected X.Y.Z" >&2
  exit 1
fi
line="${current%.*}"

all="$(versions | grep -E "$semver" | sort -uV)"
latest="$(grep -E "^${line//./\\.}\." <<<"$all" | tail -n 1)"
newest="$(tail -n 1 <<<"$all")"
: "${latest:=$current}"

updated=false
if [ "$latest" != "$current" ] && [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)" = "$latest" ]; then
  sed -i "s/^ARG ${ARG_NAME}=.*/ARG ${ARG_NAME}=${latest}/" "$DOCKERFILE"
  updated=true
  echo "$ARG_NAME: $current -> $latest"
else
  echo "$ARG_NAME: $current is the latest $line.x"
fi
if [ -n "$newest" ] && [ "${newest%.*}" != "$line" ] && [ "$(printf '%s\n%s\n' "$line.0" "$newest" | sort -V | tail -n 1)" = "$newest" ]; then
  echo "::notice::$ARG_NAME $newest is available outside the tracked $line.x line; bump $DOCKERFILE by hand to move"
fi

{
  echo "current=$current"
  echo "latest=$latest"
  echo "newest=$newest"
  echo "updated=$updated"
} >>"$OUTPUT"
