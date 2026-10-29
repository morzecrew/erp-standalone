# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first `erp` bundle. Everything below is what `erp-standalone` carries at the
head of `main`; the first tagged release seals this section under its version.

### Added

- The `erp` release bundle — a morzer `application-release`
  (`selfhost/v1alpha1`, morzer 0.7.0 or later) that deploys the whole ERP on one
  Linux machine: `erp-backend` (API and worker), `erp-frontend`, Postgres 18.6
  behind PgBouncer 1.26.1, Valkey 9.1, RustFS 1.0.4 and one Caddy 2.11.7 edge.
- One origin. The edge routes `/v1`, `/v1/*`, `/mcp`, `/mcp/*`, `/health` and
  the protected-resource metadata to the backend and everything else to the
  frontend, so there is no CORS to configure and no cookie domain to widen.
- Secrets as files, never as variables: each service reads what it needs
  through `*_FILE` from `/run/secrets`. Every infrastructure secret — the
  database password, the S3 key and the key material — is generated at `init`
  with one declaration and one owner, so the operator sets only
  `admin_password`.
- A durable Valkey (`aof`, `noeviction`), because every document's `number_id`
  is a counter it holds.
- `apply` and every update migrate before the services start: flyway from the
  migrations image mounted read-only at `/flyway/sql`, then the backend's
  `bootstrap`, which keeps the catalogs and the first administrator that
  already exist.
- A post-apply smoke test on the edge's loopback health port, covering the
  edge, the backend, the API schema and the frontend.
- Backups of the database, the files, the configuration, the encrypted secret
  state and the project's volumes, with Postgres and Valkey captured together
  in one stop window so a restore never pairs counters older than the numbers
  in the database.
- Attachments up to 50 MiB through the edge (413 past 51 MiB), with the WAF in
  detection only — it logs what it would refuse and blocks nothing.
- A pipeline that pins the components' digests, smoke-tests every bundle on a
  fresh install and on an update, signs it with minisign and publishes it to
  `ghcr.io/morzecrew/erp-standalone` behind a rolling `:main` dev channel and
  immutable `X.Y.Z` releases on a rolling `:stable` channel.
- The «Ассистент» chat can be turned on. It is off by default; the operator
  sets `assistant_api_key` and `assistant_enabled=true`, and
  `assistant_base_url` and `assistant_model` choose the endpoint. A machine
  installed earlier runs `sudo morzer secret generate assistant_api_key` once
  before updating.
- The backend and the frontend report their health, so `morzer status` shows
  them healthy or unhealthy rather than only running.

### Changed

- The bundle needs morzer 0.7.0 or later: a machine on an older manager refuses
  it, naming the version it needs.
- Between two releases on one schema, `morzer rollback` returns to the previous
  release: dev builds declare `rollback_safe: true` (a release declares what
  `components.yaml` says), and migrate now reports the database's schema, so
  `rollback`, the update's compatibility check and the unattended gate judge
  against it instead of warning that it is unknown.
- An update that fails after its migrations, on a schema that did not move,
  recovers by itself: the manager returns to the release that was running and
  exits 11, with nothing asked of the operator. A failure in the migrations, or
  after the schema moved, still stops for a person (exit 12), and the way back
  is restoring the pre-update backup.
- The dev channel's version names the last commit that changed `bundle/`, so
  `:main` moves only when `bundle/` changes. A merge that ships nothing new no
  longer publishes a new `*-dev.*` version.

### Fixed

- An update could fail at `bootstrap` right after its pre-update backup and
  stop for a person: PgBouncer refused clients for up to half a minute after
  Postgres restarted. It now retries the login, and looks Postgres up again,
  after one second.
- A restore's smoke test gave up while the backend was still starting. It now
  waits up to 90 s for each path.

### Security

- Every bundle is signed and verified against a trusted key; a machine with
  `--require-signature` refuses anything else.