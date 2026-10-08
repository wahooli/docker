FROM bash:5.3.20-alpine3.24
RUN apk add --no-cache envsubst

ENV SOURCE_DIR=/src \
    DEST_DIR=/dest \
    TIMEOUT_SECONDS=5

COPY --chmod=0755 docker-entrypoint.sh /

# Only reads $SOURCE_DIR and writes $DEST_DIR (an emptyDir in the pods), so no root needed
USER 65534:65534

ENTRYPOINT ["/docker-entrypoint.sh"]
