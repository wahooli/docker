ARG ALPINE_IMAGE=3.24
FROM alpine:$ALPINE_IMAGE

RUN apk add --no-cache \
    openvpn \
    iptables \
    iproute2 \
    dnsmasq \
    haproxy

COPY docker-entrypoint.sh /usr/local/bin/

EXPOSE 1194/udp

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["openvpn", "--config", "/etc/openvpn/server.conf"]
