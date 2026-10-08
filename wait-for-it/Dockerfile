# syntax=docker/dockerfile:1
FROM bash:5.3.20-alpine3.24

# ADD from a URL creates the file as 0600, so set 0755 explicitly: a script has to be
# readable to run as a non-root user. Pinned to the last upstream commit (unmaintained
# since 2020) with a checksum, instead of the moving master branch.
ADD --chmod=0755 \
    --checksum=sha256:b7a04f38de1e51e7455ecf63151c8c7e405bd2d45a2d4e16f6419db737a125d6 \
    https://raw.githubusercontent.com/vishnubob/wait-for-it/81b1373f17855a4dc21156cfe1694c31d7d1792e/wait-for-it.sh \
    /usr/local/bin/wait-for-it.sh
RUN apk add --no-cache netcat-openbsd

# Only opens TCP connections, so no reason to run as root
USER 65534:65534

ENTRYPOINT ["/usr/local/bin/wait-for-it.sh"]
