ARG ALPINE_IMAGE=3.24
FROM alpine:$ALPINE_IMAGE

RUN apk add --no-cache \
    unfs3 \
    rpcbind \
    e2fsprogs-extra

COPY exports /etc/exports
COPY docker-entrypoint.sh /usr/local/bin/

EXPOSE 111/udp 111/tcp 2049/tcp 2049/udp
VOLUME /export

CMD ["docker-entrypoint.sh"]
