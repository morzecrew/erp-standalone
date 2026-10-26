# erp

The whole ERP as one morzer release: erp-backend, erp-frontend, Postgres behind
PgBouncer, Valkey, RustFS, and one Caddy edge serving them on one origin.

## Changed

- First bundle. `apply` migrates with flyway from the migrations image, then
  runs the backend's `bootstrap`, which keeps the catalogs and admin that exist.

## Before you install

- Set the one operator secret, `admin_password`, the first administrator's
  password. Every infrastructure secret — the database password, the Valkey
  password, the RustFS secret key and the key material — is generated at
  `init`.
- Give `--domain` for HTTPS. Sign-in needs it: the auth cookies are `Secure`.
- Docker Engine 28.0.0 and Compose v2.35.0 or later, on amd64.

## Rolling back

A dev build declares `rollback_safe: true`; a release declares what its
components do. Where it is true, between two releases on one schema `morzer
rollback` returns to the previous release, and an update that fails after its
migrations returns to it by itself.

Across a schema change it is a restore, not a rollback: a release reads only
the schema it produces, so the manager refuses the rollback and names the
pre-update backup. An update that fails in its migrations, or after moving the
schema, stops for a person instead of returning on its own.
