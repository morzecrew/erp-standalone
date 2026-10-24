# erp

The whole ERP as one morzer release: erp-backend, erp-frontend, Postgres behind
PgBouncer, Valkey, RustFS, and one Caddy edge serving them on one origin.

## Changed

- First bundle. `apply` migrates with flyway from the migrations image, then
  runs the backend's `bootstrap`, which keeps the catalogs and admin that exist.

## Before you install

- Set the operator secrets, each pair from one value: `postgres_password` and
  `pgbouncer_password`, `s3_secret_key` and `rustfs_secret_key`; and
  `admin_password`. The rest are generated.
- Give `--domain` for HTTPS. Sign-in needs it: the auth cookies are `Secure`.
- Docker Engine 28.0.0 and Compose v2.35.0 or later, on amd64.

## Rolling back

Not automatic: `rollback_safe` is false, because each release reads only the
schema it produces. Going back after an update needs a restore.
