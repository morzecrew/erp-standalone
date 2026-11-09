# erp-standalone

Morze ERP as one self-hosted stack, packaged as a release bundle for
[morzer](https://github.com/morzecrew/morzer): the API and its worker, the
frontend, Postgres behind PgBouncer, Valkey, RustFS and a Caddy edge that serves
everything on one origin. Every operation below is a `morzer` command; nothing on
a deployed host is edited by hand.

`bundle/` holds the release: `manifest.yaml` (images pinned by digest, parameters,
tasks, backups), `secrets.schema.yaml`, `compose/`, `edge/` and the smoke test.

## Requirements

- amd64, 4 GiB of memory, 20 GiB of disk plus room for data and backups
- Docker Engine 28.0+ and Docker Compose v2.35+
- morzer 0.8.0+
- a domain: the sign-in cookies are `Secure`, so the stack needs HTTPS
- ports 80 and 443, and 8081 on loopback (`http_port`, `https_port`, `health_port`)

## Install

The images are private: log root's Docker in to ghcr.io, since morzer pulls as root.

```console
printf %s "$GHCR_TOKEN" | sudo docker login ghcr.io -u <github-user> --password-stdin

sudo morzer init --product erp \
  --release oci://ghcr.io/morzecrew/erp-standalone:stable \
  --require-signature --signing-key "<release public key>" \
  --domain erp.example.com \
  --recovery-recipient "<offline age public key>"

sudo morzer secret set admin_password    # the first administrator's password
sudo morzer apply

sudo morzer config set update.check=true \
  update.channel=oci://ghcr.io/morzecrew/erp-standalone:stable
```

- `admin_password` is the only secret you set; `init` generates the rest.
- Keep the private half of the recovery key off the machine: with a backup on a
  target, it is what rebuilds a lost machine.
- Configure a backup target (`morzer backup target add s3://…` or `ssh://…`): a
  backup only on the machine's own disk is not a backup.

Channels: `:stable` is the latest release, `:X.Y.Z` an exact one, and `:main`
every development build, which may be broken.

## Operate

```console
sudo morzer status                         # what runs, and the installation id
sudo morzer doctor                         # read-only diagnostics
sudo morzer logs backend --tail 100
sudo morzer update --check                 # is a newer version published?
sudo morzer update --stage                 # fetch and verify, then:
sudo morzer update --to <version>          # backs up first, migrates, smoke-tests
sudo morzer rollback                       # to the previous release, same schema only
sudo morzer backup                         # and: backup list, backup verify <id>
sudo morzer restore --backup <id> --force --confirm <installation-id>
sudo morzer support                        # an evidence bundle for whoever helps
```

- An update that fails after migrating, on an unchanged schema, returns to the
  previous release by itself. One that moved the schema stops for a person:
  `morzer doctor`, then `morzer status --clear-intervention=` and `morzer apply`,
  or restore the pre-update backup it names.
- Restore whole backups only, never a single volume: Postgres and Valkey are
  captured together.
- Do not prune Docker images by hand: the previous release's images are what a
  rollback returns to. `morzer release prune` removes what is safe to remove.
- Database password: `morzer backup`, then `morzer secret rotate
  postgres_password` and `morzer apply`, run together.

## The assistant

The chat is off until you turn it on. Its questions, and the data its tools read
to answer them, go to the OpenAI-compatible endpoint you name.

```console
sudo morzer secret set assistant_api_key
sudo morzer config set assistant_enabled=true
sudo morzer config set assistant_base_url=https://<host>/v1 assistant_model=<model>
```

## Metrics

With `telemetry=prometheus` the backend serves its metrics, all API workers in
one scrape, at `http://127.0.0.1:8081/metrics`: on the loopback health port
only, for a Prometheus on the same machine.

```console
sudo morzer config set telemetry=prometheus
```

## Tasks

`sudo morzer task list` shows them: `repair` returns stock held by closed plans,
and on a dev machine `reset` starts the database over, empty but for the
catalogs and the admin, and `seed` fills an empty one with demo data.

See [morzer's documentation](https://morzecrew.github.io/morzer/) for backup
targets, recovering a lost machine and everything else the manager does.
