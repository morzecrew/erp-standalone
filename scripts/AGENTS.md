<!-- torve:managed scripts — rendered from the corpus; do not edit by hand -->

## Decisions governing `scripts/`

### S-0001/D-15 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

`scripts/resolve.sh` resolves an image tag to its digest and reads the migrations image's schema label; `scripts/pin.sh` writes the component pins and `database_schema_produces` into `bundle/manifest.yaml`. `components.yaml` names the backend's and frontend's `X.Y.Z`, `rollback_safe` and notes; the migrations follow the backend's version. In release mode `pin.sh` refuses `main` and `sha-*` tags.

- Paths: `scripts/**` `/components.yaml`
- Consequence: a dev bundle pins whatever `main` is, and a release is made of component releases only; pinning twice changes nothing

### S-0002/D-1 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

`scripts/version.sh` prints the dev version of the bundle at HEAD. It takes the last commit that changed `bundle/` (`git log -1 --format=%H -- bundle`) and describes it with `git describe --tags --long`, as `vX.Y.Z-N-g<sha>`. From that it prints `X.Y.(Z+1)-dev.N.g<sha>`, for every N including 0, with the sha as git abbreviates it. It refuses, exiting non-zero with the reason on stderr, in four cases: no commit changed `bundle/`; no tag is reachable from that commit; the nearest tag is not `X.Y.Z` or `vX.Y.Z`; or `git status --porcelain --untracked-files=all -- bundle` reports anything. `VERSION_ROOT` names the repository (default: the one the script is in), as `PIN_ROOT` does for `pin.sh`.

- Paths: `scripts/version.sh` `tests/version/**`
- Consequence: Two commits with one `bundle/` name one version, and a commit outside `bundle/` names the version already built; the dev channel never names a bare `X.Y.Z`, so it cannot take a version `release.yml` will publish

### S-0002/D-4 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

The committed manifest declares `compatibility.rollback_safe: true`. `scripts/pin.sh --release` writes `rollback_safe` as `components.yaml`'s `backend.rollback_safe` and `frontend.rollback_safe` together, true only when both are, and refuses a value that is not `true` or `false`. Plain `pin.sh` leaves it as committed.

- Paths: `bundle/manifest.yaml` `bundle/RELEASE.md` `scripts/pin.sh` `tests/pin/**`
- Consequence: Between two releases on one schema, morzer rolls back, and returns from a failed update by itself (exit 11). Across a schema change, because `database_schema_min` = `max` = `produces`, it refuses a rollback, naming the pre-update backup, and a failed update stops at exit 12 for a restore

### S-0002/D-7 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

`scripts/rehearse.sh [--from <oci ref>] [--keep]` rehearses on a workstation what `smoke-install` and `smoke-update` prove on the runner. It starts a privileged `docker:29.7.2-dind` container with a Docker volume for its `/var/lib/docker`, named `erp-rehearsal`. It installs into the container the tools `.github/workflows/scripts/install-tools.sh` pins and verifies (`morzer`, `sops`, `age`), and `bash`, `curl`, `jq`, `openssl`, `sudo`, GNU `tar`, `zstd` and `minisign` from Alpine. It builds the working tree's `bundle/` inside the container as `0.0.0-rehearsal.<unix time>` and signs it with a key made there. It fetches the `--from` bundle (default `ghcr.io/morzecrew/erp-standalone:main`) with `oras pull` on the workstation. Each image either manifest pins, and morzer's volume helper, is copied with `oras copy --to-oci-layout` on the workstation; the layout keeps only its tagged index, named `<repository>@<digest>` in its `io.containerd.image.name` annotation, and is loaded into the container with `docker load`. In the container it runs `smoke.sh install`, `probe`, `backup-restore`, `update`, `probe`, `rollback` and `probe`, and `diagnose` on a failure. Unless `--keep`, it removes the container and its volume. It refuses a `yq` that is not mikefarah's v4, and `--help` prints the usage and what the workstation needs: `docker`, `oras` logged in to ghcr, and that `yq`.

- Paths: `scripts/rehearse.sh`
- Consequence: An operator tries a bundle's install, backup, restore, update and rollback before opening a pull request, and no credential enters the container

### S-0003/D-6 — `ASSUMED` (The infrastructure secrets are generated, one declaration each) — implementation: none

`smoke.sh rotate-db-password` writes the marker `rotated` into Postgres, runs `sudo morzer secret rotate postgres_password` and `sudo morzer --verbose apply`, and fails unless the marker reads `rotated` through PgBouncer: psql inside the pgbouncer container, to 127.0.0.1:6432 as `postgres`, with `PGPASSWORD` read from `/run/secrets/postgres_password` inside that container's shell. `.github/workflows/bundle.yml`'s smoke-install job runs it after backup-restore and probes again, and `scripts/rehearse.sh` runs it at the same point.

- Paths: `.github/workflows/scripts/smoke.sh` `.github/workflows/bundle.yml` `scripts/rehearse.sh`
- Consequence: every bundle proves that a rotated database password reaches the role and every reader

<!-- /torve:managed -->
