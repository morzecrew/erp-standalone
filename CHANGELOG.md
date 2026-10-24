# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first `erp` bundle. Everything below is what `erp-standalone` carries at the
head of `main`; the first tagged release seals this section under its version.

### Added

- The `erp` release bundle — a morzer `application-release`
  (`selfhost/v1alpha1`, morzer 0.6.0 or later) that deploys the whole ERP on one
  Linux machine: `erp-backend` (API and worker), `erp-frontend`, Postgres 18.6
  behind PgBouncer 1.26.1, Valkey 9.1, RustFS 1.0.3 and one Caddy 2.11.7 edge.
- One origin. The edge routes `/v1`, `/v1/*`, `/mcp`, `/mcp/*`, `/health` and
  the protected-resource metadata to the backend and everything else to the
  frontend, so there is no CORS to configure and no cookie domain to widen.
- Secrets as files, never as variables: each service reads what it needs
  through `*_FILE` from `/run/secrets`, and the database password and the S3
  key each have two declarations set from one value, because their readers run
  as different users.
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

### Changed

- Between two releases on one schema, `morzer rollback` returns to the previous
  release: the bundle declares `rollback_safe: true`, where the update's
  compatibility check and the unattended gate can now judge against the
  database's schema instead of warning that it is unknown.
- A failed update recovers by itself. When the schema did not move the manager
  returns to the release that was running and exits 11, with nothing asked of
  the operator. An update that moves the schema still stops for a person
  (exit 12), and the way back is restoring the pre-update backup.
- The dev channel's version names the bundle at HEAD, so `:main` moves only
  when `bundle/` changes. A merge that ships nothing new no longer publishes a
  new `*-dev.*` version.

### Security

- Every bundle is signed and verified against a trusted key; a machine with
  `--require-signature` refuses anything else.