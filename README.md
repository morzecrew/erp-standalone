# erp

The whole Morze ERP as one self-hosted stack: `erp-backend` (the API and its
background worker), `erp-frontend`, Postgres behind PgBouncer, Valkey, RustFS
for attachments, and a Caddy edge that serves the API and the frontend on one
origin.

This repository builds the **release bundle** — the unit [morzer][morzer]
installs, verifies, updates, backs up and diagnoses on one Linux machine.
Everything below is done with `morzer`; no Compose file is ever edited on a
deployed host.

[morzer]: https://github.com/morzecrew/morzer

## What a bundle is

A bundle is a signed, digest-pinned directory. morzer reads it, renders it
against the machine's parameters and secret state, and drives Compose. The
bundle in this repository is a `morzer` **application-release** named `erp`,
manifest API `selfhost/v1alpha1`, with Compose as its runtime and `sops-age`
for secrets. It needs morzer **0.8.0** or later, and refuses to load on an
older manager rather than failing later.

| File | What it holds |
|---|---|
| `bundle/manifest.yaml` | the release: components, pinned images, parameters, migrate and smoke-test operations, health checks, backup policy, retention |
| `bundle/secrets.schema.yaml` | every secret, which services read it and which user owns the file |
| `bundle/compose/compose.yaml` | the stack; it names an image only through the release's pin and a setting only through a parameter |
| `bundle/edge/erp.caddy` | the edge's routing: `/v1`, `/v1/*`, `/mcp`, `/mcp/*`, `/health` and the protected-resource metadata go to the backend, everything else to the frontend |
| `bundle/hooks/smoke-test` | the probe `morzer` runs after every apply and update |
| `bundle/RELEASE.md` | the release notes morzer shows for the installed release |

Nothing is mounted into a container by hand: secrets arrive as files under
`/run/secrets` and are read through `*_FILE` variables, so no secret ever
appears in `docker inspect` or in a process's environment.

## What it runs

- `postgres` (18.6) with the image's small-instance settings, fronted by
  `pgbouncer` (1.26.1) on transaction pooling.
- `valkey` (9.1), **durable** — `aof` with `noeviction` — because every
  document's `number_id` is a counter Valkey holds, not a cache entry.
- `rustfs` (1.0.4) for attachments.
- `backend` and `worker` from `ghcr.io/morzecrew/erp-backend`, both through
  PgBouncer; `bootstrap` one-shot on every apply.
- `flyway` (13.11), which mounts the migrations image read-only at
  `/flyway/sql` and runs before the services start.
- `edge` (Caddy 2.11.7) — the only service that publishes ports, and the only
  origin the browser, the API and a remote MCP client ever see.

## Requirements

- **amd64.** An arm64 host is refused before anything is pulled.
- **4 GiB memory, 20 GiB disk,** plus room for the data and the backups.
- **Docker Engine 28.0.0** and **Docker Compose v2.35.0** or later — the first
  versions that mount an image as a volume, which is how flyway reads the
  migrations. morzer's `preflight` refuses a host that cannot.
- **Ports** 80 and 443, and 8081 on loopback. All three are release
  parameters (`http_port`, `https_port`, `health_port`) and can be changed.
- **morzer 0.8.0** or later, installed and on `PATH`.

Two rules that prevent most surprises:

- **Give `--domain` for HTTPS.** Sign-in needs it: the auth cookies are
  `Secure`, so on a plain-HTTP host the frontend loads and nobody can log in.
- **Log root's Docker in to ghcr.** morzer runs as root and pulls through the
  root user's Docker, so that — not your own — is the Docker configuration
  that has to hold the credential.

## The two channels

CI publishes the bundle to `ghcr.io/morzecrew/erp-standalone` as a signed OCI
artifact, and moves two rolling tags. A version is immutable once published.

| Tag | Channel | Built from |
|---|---|---|
| `:main` | **dev** — a sandbox that may be broken | every component merge, as a pre-release `<next-patch>-dev.<n>.g<sha>` |
| `:stable` | **customer** — dev builds a person promoted | a `vX.Y.Z` tag on `main`, as the release `X.Y.Z` of the component digests pinned there |

An exact version — `ghcr.io/morzecrew/erp-standalone:1.4.0` — can be installed
or staged at any time, and is the same artifact `:stable` pointed at that day.

## Install a dev VM (follows `:main`)

A dev VM takes `:main` and keeps itself current without a person watching it.

```console
# 1. A read-only token is enough for the release and its images.
printf %s "$GHCR_TOKEN" | sudo docker login ghcr.io -u <github-user> --password-stdin

# 2. Create the installation from the dev channel.
sudo morzer init --mode dev --product erp \
  --release oci://ghcr.io/morzecrew/erp-standalone:main \
  --require-signature --signing-key "$MINISIGN_DEV_PUBKEY" \
  --domain erp.dev.example.com \
  --recovery-recipient "$OFFLINE_AGE_RECIPIENT"

# 3. Set the operator secret (see below), then start it.
sudo morzer apply

# 4. Follow the channel unattended, every fifteen minutes.
sudo morzer config set \
  update.check=true \
  update.channel=oci://ghcr.io/morzecrew/erp-standalone:main \
  update.auto_apply=true \
  update.schedule='*:0/15' \
  backup.before_update=false
```

- `--mode dev` marks the machine as a sandbox. It is fixed at creation and
  never changes.
- `--release` takes the OCI reference, and `init` fetches it. `--require-signature`
  with `--signing-key` is what makes that fetch meaningful: without a trusted
  key, "signed" is a word in a log line.
- `--recovery-recipient` is an offline age public key that can decrypt this
  machine's secret state, so losing the VM does not lose its secrets. Keep it
  somewhere other than the VM.
- `morzer init` installs the systemd units. The update timer is
  `erp-update.timer`, which setting a channel installs; it ticks daily at
  03:30 unless `update.schedule` says otherwise —
  `sudo morzer config set update.schedule='Sat *-*-* 04:00:00'` fires it on
  Saturday mornings instead.
- `update.schedule='*:0/15'` is this VM's cadence rather than the timer's
  default: the timer fires on the quarter hour, so a merge on `:main` is
  installed within fifteen minutes of CI publishing it.
- `update.check` must be on before anything follows a channel: a check or an
  update contacts the registry, and the manager will not do that unasked.
- `update.auto_apply=true` is what makes the timer install rather than only
  notice, and it also needs the required signature above. On a customer VM an
  unattended tick then installs only a release that cannot need a database
  restore, and one that moves the schema waits for a person. The dev VM installs
  whatever its channel offers, schema changes included.
- `backup.before_update=false` is the dev VM's choice: it skips the pre-update
  backup, which a sandbox does not need and which costs disk on every merge.

A manual tick is `sudo morzer update --unattended`.
`sudo morzer update --check` reports whether a newer version is published
without installing anything. It reads the ref `init` installed from, or the
repository of `update.channel`; a ref given to `--check` is used as given.

## Install a customer VM (follows `:stable`)

The same shape, on the release channel, with a human in the loop:

```console
printf %s "$GHCR_TOKEN" | sudo docker login ghcr.io -u <github-user> --password-stdin

sudo morzer init --product erp \
  --release oci://ghcr.io/morzecrew/erp-standalone:stable \
  --require-signature --signing-key "$MINISIGN_RELEASE_PUBKEY" \
  --domain erp.example.com \
  --recovery-recipient "$OFFLINE_AGE_RECIPIENT"

# the operator secret, then:
sudo morzer apply

sudo morzer config set \
  update.check=true \
  update.channel=oci://ghcr.io/morzecrew/erp-standalone:stable
```

Differences from the dev VM, and why:

- **No `--mode`**: the default is `production`.
- **The release key**, not the dev key: a customer VM trusts only what was
  tagged and published as a release.
- **`update.auto_apply` is left off**, so the timer only stages and reports.
  Installing is a person's decision, and `morzer update` (below) takes a
  pre-update backup by default. Leave `backup.before_update` at its default of
  `true`, and `update.auto_apply` off.
- **Configure a backup target.** A backup on the machine whose disk is about
  to fail is not a backup. An `s3://` or `ssh://` target reads its credentials
  from one secret holding a small YAML document:

  ```console
  sudo morzer secret set backup_s3
  sudo morzer backup target add s3://<bucket>/erp --credentials backup_s3
  sudo morzer backup target list
  ```

  For `s3://` the document holds `access_key_id`, `secret_access_key` and, for
  a store that is not AWS, `endpoint`. A plaintext endpoint has to be spelled
  `http://`. For `ssh://user@host/absolute/path` it holds `private_key` and the
  pinned `known_hosts` line. The bucket or directory must already exist. See
  morzer's
  [backup target URLs](https://morzecrew.github.io/morzer/reference/backup-targets/).

  Every backup is pushed to every configured target after it is verified, and
  a push that fails fails the backup. The signed record of each operation
  (`morzer attest`) is pushed to the same targets as it is written, so what
  `init` and `apply` recorded before the target existed needs one
  `sudo morzer attest push`; until then `doctor` warns that attestations are
  only on this machine.

The `MINISIGN_DEV_PUBKEY` and `MINISIGN_RELEASE_PUBKEY` values are the
repository's public-key variables — a single base64 line beginning `RW…`, the
one minisign prints as its public key. `sudo morzer release trust list` shows
the keys the installation already trusts.

## Upgrading morzer

Upgrade morzer to 0.8.0 before installing the next bundle: a machine on an
older manager refuses a bundle that needs 0.8.0 and names the version it needs.
On a machine set up under 0.6.0 whose timers never started, run
`sudo morzer init --repair` once, or reboot; either starts them.

CI and the dev VM run morzer 0.9.0, and the bundle still needs only 0.8.0.
0.9.0 moves an installation's state to schema 13, and a 0.8.x manager then
refuses it, so a machine upgraded to 0.9.0 cannot go back to 0.8.x.

## The operator secrets

Every secret lives encrypted in the installation's `secrets.sops.yaml` and is
rendered to a file under `/run/secrets` for the product to read. A file has
one owner, so a service that does not run as root reads one only when the
schema gives it that file.

`init` generates every infrastructure secret, and **`admin_password` is the
one secret you set**, with `morzer secret set`, which reads the value without
echo from the terminal or from stdin — there is no flag for a value, because
argv is world-readable through `/proc`.

| Generated at `init` | Read by | Owner |
|---|---|---|
| `postgres_password` | postgres, PgBouncer, backend, worker | 65532 |
| `valkey_password` | valkey, backend, worker | 65532 |
| `rustfs_secret_key` | rustfs, backend, worker | 65532 |
| `access_secret_key` | backend, worker | 65532 |
| `refresh_pepper` | backend, worker | 65532 |
| `api_key_pepper` | backend, worker | 65532 |
| `assistant_api_key` | backend, worker | 65532 |

`assistant_api_key` is a placeholder until you turn the assistant on (below).

The backend, worker and bootstrap run as user 65532, and the pgbouncer and
rustfs images read their secrets as root before dropping to their own user, so
every non-root reader here is 65532; postgres, valkey and flyway start as root
and read any file. One value has one declaration, so every reader of a value
reads the one file that holds it — there is no second copy to keep in step.

```console
# The first administrator's password — the one secret you set.
sudo morzer secret set admin_password
```

`apply` renders every secret and names any that is missing.

`sudo morzer secret list` prints names, fingerprints and when each last
changed — never a value. `sudo morzer secret edit` opens several at once when
a change belongs together, and `sudo morzer doctor` reports an unset operator
secret as a failure before you apply. `api_key_pepper` has no rotation period —
rotating it revokes every API key — and neither does `postgres_password` or
`rustfs_secret_key`; changing the database password is the procedure below,
not a timer.

## The assistant

The «Ассистент» chat is off, and its tab hidden, until you turn it on. Its
questions, and the ERP data its tools read to answer them, go to the
OpenAI-compatible endpoint you name, DeepSeek's own by default.

```console
sudo morzer secret set assistant_api_key  # the endpoint's key, from stdin
sudo morzer config set assistant_enabled=true
# Another endpoint or model:
sudo morzer config set assistant_base_url=https://<host>/v1 assistant_model=<model>
```

`config set assistant_enabled=false` turns it off again.

## Tasks

The release declares the commands an operator runs by name. Each runs as a
one-shot backend container, through the entrypoint that reads its secrets,
under the deployment lock, and is journaled.

```console
sudo morzer task list                   # the tasks, and which this machine may run
sudo morzer task run seed -- --size s   # demo data, into an empty database
sudo morzer task run repair             # give back stock that closed or deleted plans hold
```

`seed` runs on a dev machine only: a production machine refuses it by name, and
`--force` does not override that. It refuses a database that holds data. Its
sizes are `xs`, `s`, `m` (the default) and `l`, and `--seed N` draws a
different history.

## Updating

```console
sudo morzer update --check oci://ghcr.io/morzecrew/erp-standalone  # a newer version?
sudo morzer update --stage          # fetch and verify what the channel points at
sudo morzer update --to <version>   # install a version already in the release store
sudo morzer update oci://ghcr.io/morzecrew/erp-standalone:<version>  # a published one
sudo morzer update <archive>        # install a specific bundle file
```

`morzer update` with no argument follows no channel: it refuses with `no
release was given`. The channel is followed by `--stage`, which leaves the
release staged for `--to`, and by the timer's `--unattended` tick.

An update verifies the bundle, checks it against the compatibility the
manifest declares, takes a pre-update backup (unless `backup.before_update`
is off), stages the release and converges to it: pull, migrate (flyway, then
bootstrap), start, then the smoke test.

**An update that fails after its migrations, on a schema that did not move,
recovers by itself** — a health check or the smoke test that fails, say. The
manager returns to the release that was running and exits 11; nothing is asked
of you, and the unattended timer does the same. That needs `rollback_safe:
true`, which every dev build declares and a release declares when
`components.yaml` says so of both components. A failure in the migrations
themselves (flyway, bootstrap, the schema report), or one after the schema
moved, cannot return that way, so it stops for a person and exits 12. Repair
the cause, clear the flag and converge again, or restore the pre-update backup
the manager names:

```console
sudo morzer doctor                        # what the failed operation left
sudo morzer status --clear-intervention=  # the flagged operation; or name its id
sudo morzer apply
```

The databases are never rolled back by the update itself; that is what the
restore is for.

## Rolling back

```console
sudo morzer rollback                 # to the immediate previous release
sudo morzer rollback --to <version>  # to an older one, by version
```

Rollback reports three things separately before acting: whether the containers
can be reversed, whether the current database schema is compatible with the
previous release, and whether a restore is required. When the answers do not
permit a safe return it refuses, naming the backup to restore from instead.

Every dev build of this bundle declares `rollback_safe: true`, and a release
declares what `components.yaml` says of both components. Where it is true,
**between two releases that share a schema `morzer rollback` returns to the
previous release.** Across a schema change it is a restore, not a rollback: a release
reads only the schema it produces, so the manager refuses and names the
pre-update backup. `--force` authorises a destructive action; it does not
override a refusal.

## After a reboot

The systemd unit `erp.service` starts the installation by running
`apply --startup`, which renders the secrets again to `/run/erp/secrets` before
the services come up. The rendered files live under `/run`, which a reboot
empties, while the encrypted state that produces them is on disk — so a machine
that comes back from a power cut converges without a person, and no secret has
to be re-entered.

## Backing up

```console
sudo morzer backup
sudo morzer backup --reason before-upgrade
sudo morzer backup list                  # newest first
sudo morzer backup verify <backup-id>    # re-read it and check its checksums
```

A backup holds the database, the files, the configuration, the release
manifest, the encrypted secret state, and the project's volumes. `postgres-data`,
`valkey-data` and `rustfs-data` are declared `consistency: cold`, so morzer
stops the services mounting them and copies both in one window; `edge-data`
(the certificates) is read live. Retention keeps the last 3 releases and 7
backups, and morzer prunes old pre-update backups itself.

## Restoring Postgres and Valkey together

A restore puts the whole machine back to one moment. **Restore the backup;
never restore one volume by hand.** Postgres and Valkey were captured in the
same stop window on purpose: Valkey holds the `number_id` counters, and a
Valkey older than the database would reissue numbers the database has already
given out.

```console
sudo morzer backup list
sudo morzer restore --backup <backup-id> --force --confirm <installation-id>
```

`morzer restore` verifies the backup, stops the writers, restores the volumes
and then the database and files, re-applies the release and runs the smoke
test. It is destructive and needs both `--force` and the installation id typed
as `--confirm`; `morzer status` prints the installation id. Anything written
since the backup is gone, not left beside the restored data.

## Removing an installation

```console
sudo morzer installation remove --dry-run --force   # what it would remove
sudo morzer installation remove --force             # keeps the volumes, data, backups and secret state
sudo morzer installation remove --force --purge     # removes those too
```

A production installation also needs `--confirm <installation-id>`, which
`morzer status` prints. Nothing on a backup target is removed. A machine left
by a failed `init` is cleaned with `--product erp --force`.

## Recovering a lost machine

When the VM itself is gone — a dead disk, a deleted VM — two things rebuild
it: the offline recovery key and a backup on a target. Every backup carries
the installation's identity (its record, the encrypted secret state, and who
can decrypt it) encrypted to the recovery key alone, so nothing else has to be
kept by hand. A machine installed with `--no-recovery-recipient`, or one
without a backup target, cannot be recovered this way.

Make the key on a workstation, never on the VM, and keep the private half in a
password manager:

```console
age-keygen -o erp-recovery.key   # the private half
age-keygen -y erp-recovery.key   # the public half, init's --recovery-recipient
```

On the replacement, with Docker, morzer, sops and age installed and the key
copied over:

```console
# 1. The identity, from the newest backup on the target. For an s3:// or ssh://
#    target, add --credentials-file with the target's credential document.
sudo morzer --product erp installation import --from-backup \
  --target <target-url> --identity ./erp-recovery.key

# 2. The release that was running: import prints its version.
printf %s "$GHCR_TOKEN" | sudo docker login ghcr.io -u <github-user> --password-stdin
sudo morzer update oci://ghcr.io/morzecrew/erp-standalone:<version>

# 3. The data. This machine's new key cannot open the old backups; the
#    recovery key can.
sudo morzer backup list --remote
sudo morzer backup fetch <backup-id>
sudo morzer restore --backup <backup-id> --force --confirm <installation-id> \
  --identity ./erp-recovery.key

# 4. Check the machine: import installs the systemd units and records this
#    machine's signing key.
sudo morzer doctor

# 5. The key leaves the machine again.
shred -u ./erp-recovery.key
```

Import keeps the installation id, which is why the old machine's backups
restore without `--allow-cross-installation`, and it revokes the old machine's
key. If any part of the old machine still runs, shut it down: two hosts with
one installation id confuse every backup either takes. Release versions are
never pruned from the registry, so the version a customer VM ran is always
there to reinstall.

## Changing the database password

`postgres_password` is one declaration and the `postgres` role holds the same
value, so `morzer secret rotate` writes the new value and the next `morzer
apply` sets the role from it. Run the two together: the rotation restarts
PgBouncer, the backend and the worker with the new value while the role still
holds the old one, so the API cannot reach the database until the apply.

```console
# 1. A backup you can go back to.
sudo morzer backup --reason before-password-change

# 2. A new value in the one declaration.
sudo morzer secret rotate postgres_password

# 3. Set the role from it and re-render the secret files.
sudo morzer apply
```

## Rehearsing a bundle

`scripts/rehearse.sh` rehearses on a workstation what CI's smoke jobs prove on
the runner — install the published bundle, back it up and restore it, update to
the working tree's `bundle/`, and roll back — before a pull request is opened.

```console
scripts/rehearse.sh                     # from :main
scripts/rehearse.sh --from <oci ref>    # from another published bundle
scripts/rehearse.sh --keep              # leave the container and its volume
```

Everything runs in a privileged `docker:29.7.2-dind` container named
`erp-rehearsal`, with a Docker volume of the same name; a second run refuses
while either still exists. Nothing is mounted from the checkout and no
credential enters the container: the working tree's `bundle/` is copied in as
`git` sees it and built there as `0.0.0-rehearsal.<unix time>`, signed with a
key made there, while the workstation's own `oras`, with its existing ghcr
login, pulls the published bundle and copies every image either manifest pins
into an OCI layout the container's daemon loads. It probes after each step and
runs `smoke.sh diagnose` on a failure. `--help` prints what the
workstation needs — `docker`, `oras` logged in to ghcr, and mikefarah's `yq` v4 — and the
public key that signed the `--from` bundle must be in `REHEARSE_PUBKEY`.

## CI runners

Every workflow job runs on `${{ vars.RUNS_ON || 'ubuntu-24.04' }}`: the
repository variable `RUNS_ON` names the runner label — `self-hosted` today —
and, unset, the jobs run on GitHub-hosted `ubuntu-24.04` with the same steps.

A runner, self-hosted or GitHub-hosted, needs:

- **amd64.** The bundle's images and the smoke jobs that exercise them are
  amd64 only.
- **A Docker that allows privileged containers.** Each smoke job runs the
  bundle inside a privileged `docker:29.7.2-dind` rig with its own Docker
  volume, and `scripts/rehearse.sh` uses the same rig on a workstation.
- **Room for one rig:** the release's 20 GiB preflight under `/var/lib/erp`
  plus the bundle's images, all held by that rig's container and volume.
- **No `sudo` for its user.** Jobs install their tools in a job container, in
  a rig, or under `$RUNNER_TEMP`, and each container job hands the workspace
  back to the runner's user when it ends.
- **A proxy containers can reach, if it has one.** The runner hands its
  `http(s)_proxy` to every job container, where `127.0.0.1` is the container's
  own loopback. Point it at an address containers reach, such as the Docker
  bridge's `172.17.0.1`, with the proxy listening there. `rig.sh` passes a
  non-loopback proxy into each rig.

## Cutting a release

A release promotes a dev build: it ships the component digests `main.yml`
committed, which the dev VM installed and CI smoke-tested. The components are
not tagged or rebuilt. It is cut in this order:

1. **Prepare it in one pull request.** In `components.yaml`, each component's
   `rollback_safe`: `true` only when its previous release can run on what this
   one leaves behind. In `bundle/RELEASE.md`, what changed for the operator.
2. **Let the dev VM install it.** The merge is a `bundle/` commit, so `:main`
   publishes it, and the VM installs it on its next tick.
3. **Tag the commit the dev VM runs.** `sudo morzer status` names it: release
   `0.0.1-dev.42.g1a2b3c4` was built from `1a2b3c4`.

   ```console
   git tag vA.B.C 1a2b3c4 && git push origin vA.B.C
   ```

`release.yml` then:
- refuses a tag that is not `vX.Y.Z` on `main`;
- keeps the digests the tagged commit pins and names them `bundle-A.B.C`, with
  `scripts/pin.sh --release A.B.C`, in the runner (nothing is committed). It
  refuses a digest the registry no longer holds;
- builds `A.B.C` and signs it with the release key;
- smoke-tests a fresh install and an update from the current `:stable`;
- tags each component image `bundle-A.B.C`, publishes `:A.B.C` and moves
  `:stable`.

A version already published fails the run: a version never changes content.
Before the first release there is no `:stable`, and only the fresh install is
proven.

**Tag soon after the dev VM settles.** A component image is pruned once it is
past the 3 newest `sha-*` builds of its repository and more than a day old,
unless a release has tagged it. A commit whose images are gone cannot be
released, and `pin.sh` refuses it by name.

The tag needs one setting in each of the `erp-backend`, `erp-migrations` and
`erp-frontend` packages: under **Package settings → Manage Actions access**,
`erp-standalone` holds the **Write** role. Without it `publish.yml` fails at
the tag, and nothing is published.

## Housekeeping, and why not to prune images

The org is on GitHub's free plan: about **500 MB of private package storage**
and **1 GB of transfer a month** outside Actions. The bundles are kilobytes
and a component update pulls roughly a megabyte, so the budget is spent by
retained images and untagged versions, not by the releases themselves — and
CI keeps both tight. The registry keeps the last 5 `*-dev.*` versions, drops
untagged versions after a day, and never touches `:main`, `:stable` or any
`X.Y.Z`, which is what lets a dev VM roll back to a bundle from earlier in the
week and still install any released version. The component repositories keep
the last 3 `sha-*` builds and every image a release tagged `bundle-X.Y.Z`:
their retention never deletes a version with a tag its filter does not match.

**Do not run `docker image prune -af` or `docker system prune -a`.** morzer
0.7.0 removes a pruned release's images itself, and a manual prune
takes the previous release's images and the backup helper image with it, so
the next rollback finds nothing to go back to. Let `morzer release prune` and
the retention policy do it.

## When something is wrong

```console
sudo morzer status                  # what is deployed, its installation id, and whether it works
sudo morzer doctor                  # read-only diagnostics; exits 3 on a failure
sudo morzer logs backend --tail 100 # this installation's logs, secrets scrubbed
sudo morzer ps                      # the containers
sudo morzer support                 # an evidence bundle somebody else can read
```

`morzer doctor` refuses nothing and changes nothing, so it is safe on a
machine mid-incident, and `morzer status` answers even when the Docker daemon
is down.