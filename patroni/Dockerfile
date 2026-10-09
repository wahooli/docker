ARG POSTGRES_VERSION=17
ARG DEBIAN_RELEASE=bookworm
FROM postgres:${POSTGRES_VERSION}-${DEBIAN_RELEASE} AS patroni
ARG PATRONI_VERSION=4.0.11
ENV PATRONI_VERSION=$PATRONI_VERSION \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    CONFIG_FILE=/home/postgres/config/patroni.yaml
COPY logging.sh post-init.sh db-backup.sh entrypoint.sh log-manager.sh /

RUN export DEBIAN_FRONTEND=noninteractive \
    && echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends \
        curl \
        jq \
        locales \
        python3 \
        python3-pip \
        python3-wheel \
        python3-click \
        python3-dateutil \
        python3-prettytable \
        python3-psutil \
        python3-urllib3 \
        python3-yaml \
        python3-psycopg2 \
        python3-etcd \
        python3-consul \
        python3-kazoo \
        python3-kubernetes \
        python3-pysyncobj \
        python3-cdiff \
        iproute2 \
        gettext-base \
        logrotate \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
    && pip3 install --break-system-packages setuptools python-json-logger \
    && pip3 install --break-system-packages "patroni[kubernetes,etcd3,aws,consul,zookeeper,raft]==${PATRONI_VERSION}" \
    && PGHOME=/home/postgres \
    && usermod -d /home/postgres -m postgres \
    && chown -R postgres:postgres $PGHOME \
    && chmod 775 $PGHOME \
    && chmod 644 /etc/passwd \
    && apt-get remove -y python3-pip python3-wheel \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* /root/.cache \
    && rm -rf /docker-entrypoint.initdb.d \
    && mkdir -p /docker-entrypoint-init.d \
    && mkdir -p /docker-entrypoint-bootstrap.d \
    && chown -R postgres:postgres "$PGHOME" /run /docker-entrypoint-bootstrap.d /docker-entrypoint-init.d /etc/logrotate.d \
    && ln -s /post-init.sh /post-bootstrap.sh

EXPOSE 5432 8008
USER postgres
WORKDIR /home/postgres
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/local/bin/patroni", "$CONFIG_FILE"]

FROM patroni AS vchord
ARG VCHORD_VERSION=0.4.3
ARG VCHORD_SHA256_AMD64=a4776ac7b1def6d4f02370227a214be50ec36c84d0af3469070120667215f4ae
ARG VCHORD_SHA256_ARM64=d69167fea8b97fb791e4b6b3d06599fc666680d5c853732e5dc3fafede9fa1a3
ARG PGVECTOR_VERSION=0.8
USER root
RUN export DEBIAN_FRONTEND=noninteractive \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha256="$VCHORD_SHA256_AMD64" ;; \
         arm64) sha256="$VCHORD_SHA256_ARM64" ;; \
         *) echo "vchord: unsupported architecture $arch" >&2; exit 1 ;; \
       esac \
    && deb="postgresql-${PG_MAJOR}-vchord_${VCHORD_VERSION}-1_${arch}.deb" \
    && curl -fsSLo "/tmp/$deb" "https://github.com/tensorchord/VectorChord/releases/download/${VCHORD_VERSION}/$deb" \
    && echo "$sha256  /tmp/$deb" | sha256sum -c - \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends "/tmp/$deb" "postgresql-${PG_MAJOR}-pgvector=${PGVECTOR_VERSION}.*" \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* "/tmp/$deb"
USER postgres

FROM patroni
