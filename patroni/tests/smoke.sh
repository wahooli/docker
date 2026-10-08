#!/usr/bin/env bash
set -euo pipefail

echo "debian $(cat /etc/debian_version), $(postgres --version), patroni $(patroni --version | awk '{print $2}')"

[ -f "/usr/share/postgresql/${PG_MAJOR}/extension/vchord.control" ] || exit 0

export PGDATA=/tmp/pgdata
initdb -U postgres >/dev/null
pg_ctl -s -w -o "-c shared_preload_libraries=vchord.so -c listen_addresses=" -l /tmp/pg.log start
trap 'pg_ctl -s -w stop' EXIT

psql -qAt -U postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION vchord CASCADE;
CREATE EXTENSION earthdistance CASCADE;
SELECT extname || ' ' || extversion FROM pg_extension WHERE extname IN ('vector', 'vchord', 'cube', 'earthdistance') ORDER BY 1;
CREATE TABLE t (id int, e vector(3));
INSERT INTO t SELECT i, ARRAY[random(), random(), random()]::vector FROM generate_series(1, 2000) i;
CREATE INDEX t_e_idx ON t USING vchordrq (e vector_cosine_ops);
SET enable_seqscan = off;
SELECT count(*) FROM (SELECT id FROM t ORDER BY e <=> '[0.5,0.5,0.5]' LIMIT 10) s;
SQL
