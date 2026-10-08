# docker

Container images for the homelab, published to `ghcr.io/wahooli/docker/<image>`.

| Image | Directory | Tags | Upstream tracking |
|---|---|---|---|
| `patroni-17` | `patroni/` (target `patroni`) | `<patroni>-<n>` | Patroni from PyPI, 4.0.x |
| `patroni-17-vchord` | `patroni/` (target `vchord`) | `<patroni>-<n>` | Patroni from PyPI, 4.0.x |
| `haproxy-redis` | `haproxy-redis/` | `<haproxy>-<n>` | `haproxy` on Docker Hub, 3.2.x |
| `unfs3` | `unfs3/` | `<unfs3>-<n>`, `latest` | the Alpine package, via weekly rebuilds |
| `wait-for-it` | `wait-for-it/` | `VERSION`, `latest` | none |
| `envsubst` | `envsubst/` | `VERSION`, `latest` | none |

## Versioning

**Upstream-tracked images** are tagged `<upstream>-<n>`, for example
`haproxy-redis:3.2.25-1`. The upstream version comes from an env var in the
built image (`PATRONI_VERSION`, `HAPROXY_VERSION`), or from a command run in
the image (`unfsd -h` for unfs3). `n` starts at 1 for each
upstream version and goes up whenever the image contents change without an
upstream bump: a Postgres minor, a Debian security update, a script change.

"Contents" is a fingerprint stored in the `li.wahoo.image.fingerprint` label:
a hash of the build context (without `tests/`), the target, build args and
platforms, and the list of installed packages with versions (dpkg, apk and
Python). CI compares it with the newest `<upstream>-<n>` tag and only publishes
`<n+1>` when it differs. Tags are never overwritten.

**Own-versioned images** use the plain semver in `<dir>/VERSION`. CI publishes
when that tag doesn't exist yet; to release a change, bump `VERSION`.

## Workflows

- `<image>.yaml`: builds on pull requests (no push), on pushes to `main`, and
  by hand. Each run builds amd64, runs `<dir>/tests/smoke.sh` inside the image
  through its shebang, plans the tag, and on `main` pushes amd64 and arm64.
  Upstream-tracked images also run on a schedule to pick up base-image
  updates: haproxy-redis and unfs3 weekly, patroni monthly (each rebuild of a
  Patroni image restarts the database pods once Flux rolls it out). `force`
  publishes a new `<n>` even if nothing changed (own-versioned images:
  overwrites `VERSION`).
- `build-image.yaml`: the reusable workflow behind all of the above.
- `track-upstream.yaml`: runs daily. For each tracked image it looks up the
  newest upstream release in the current `MAJOR.MINOR` line, bumps the pinned
  `ARG` in the Dockerfile, commits to `main` and dispatches the image's
  workflow. A newer line (Patroni 4.1, HAProxy 3.4) is only reported as a
  notice; moving to it is a manual change to the `ARG`.

The tracker's commits are made with `GITHUB_TOKEN`, which doesn't trigger push
workflows, so it dispatches the build explicitly.

## Flux image policies

`<n>` is a semver pre-release, so a policy has to opt into pre-releases, and
must filter out old bare tags: `3.2.25` sorts above `3.2.25-1`.

```yaml
spec:
  filterTags:
    pattern: '^\d+\.\d+\.\d+-\d+$'
  policy:
    semver:
      range: "~3.2.0-0"
```

`~3.2.0-0` follows HAProxy 3.2.x and every rebuild of it; use `~4.0.0-0` for
Patroni 4.0.x. Existing policies (`~3.2.25`, `x.x.x`) ignore `-<n>` tags, so
nothing rolls out until a policy is switched.

## Notes

- The Patroni images pin their Debian release (`DEBIAN_RELEASE`): bookworm for
  `patroni-17`, which existing clusters run, trixie for `patroni-17-vchord`.
  Moving a cluster to another Debian release changes glibc, which can change
  collation order and corrupt text indexes. Treat it as a migration with
  `REINDEX`, not a rebuild.
- `patroni-17-vchord` adds VectorChord and pgvector for Immich. VectorChord is
  pinned to the version Immich ships in its own Postgres image, and the `.deb`
  is checked against a pinned SHA-256. To upgrade it, bump `VCHORD_VERSION` and
  both `VCHORD_SHA256_*` after checking Immich's supported range; the extension
  may need `ALTER EXTENSION vchord UPDATE` after the rollout.

- `unfs3` is based on [nimbix/docker-unfs3](https://github.com/nimbix/docker-unfs3)
  and [mitcdh/docker-unfs3](https://github.com/mitcdh/docker-unfs3). The unfs3
  version is whatever Alpine packages for the pinned Alpine minor
  (`ALPINE_IMAGE`); moving to a newer Alpine minor is a manual bump.

## Adding an image

1. Create `<image>/Dockerfile`, and an executable `<image>/tests/smoke.sh`.
   It runs inside the image as its default user, through its shebang, so use
   `#!/bin/sh` on images without bash.
2. Either add `<image>/VERSION`, or get the upstream version from an env var
   in the image (`upstream-env`) or a command run in it (`upstream-cmd`).
3. Copy one of the `<image>.yaml` workflows and adjust the paths and inputs.
4. For upstream tracking, pin the version as an `ARG X=1.2.3` in the
   Dockerfile and add an entry to the `track-upstream.yaml` matrix (`pypi:` or
   `docker:` source).

## Local dry run

```bash
docker buildx build --load -t local/haproxy-redis:ci haproxy-redis
docker run --rm -v "$PWD/haproxy-redis/tests/smoke.sh:/smoke.sh:ro" \
  --entrypoint /smoke.sh local/haproxy-redis:ci
IMAGE_REF=ghcr.io/wahooli/docker/haproxy-redis LOCAL_IMAGE=local/haproxy-redis:ci \
  CONTEXT=haproxy-redis UPSTREAM_ENV=HAPROXY_VERSION PLATFORMS=linux/amd64,linux/arm64 \
  .github/scripts/plan-release.sh
```

Without a local `skopeo`, the scripts run it from `quay.io/skopeo/stable`.
