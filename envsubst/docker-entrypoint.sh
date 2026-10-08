#!/usr/bin/env bash
set -e
SOURCE_DIR=${SOURCE_DIR:-/src}
DEST_DIR=${DEST_DIR:-/dest}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-5}

for sourcefile in ${SOURCE_DIR}/*; do
    [ -e "$sourcefile" ] || continue
    file=$(readlink -f $sourcefile)
    if [[ -f $file ]]; then
        filename=$(basename $file)
        destfile="${DEST_DIR}/${filename}"
        if [[ ! -z "$REPLACE_VARS" ]]; then
            timeout $TIMEOUT_SECONDS envsubst "$REPLACE_VARS" < $file > $destfile
        else
            timeout $TIMEOUT_SECONDS envsubst < $file > $destfile
        fi
        echo "Copied $sourcefile to $destfile"
        if [[ $destfile =~ \.sh$ ]]; then
            chmod a+x $destfile
            echo "Set $destfile as executable"
        fi
    fi
done
echo "Complete"