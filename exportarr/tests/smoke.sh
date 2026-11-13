#!/bin/sh
set -eu

/exportarr sonarr --help | head -n 1
/exportarr radarr --help >/dev/null
[ "$(id -u):$(id -g)" = "65532:65532" ]
