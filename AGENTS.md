<!-- torve:managed root — rendered from the corpus; do not edit by hand -->

## Decisions governing the repository root

### S-0001/D-21 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

`renovate.json` bumps the infrastructure images in `bundle/manifest.yaml` through one regex custom manager over `repo:tag@sha256:`. Its one host rule reads the private packages: `matchHost: ghcr.io`, `hostType: docker`, `username: Misery7100` and `password: "{{ secrets.GHCR_READ_TOKEN }}"`, a repository secret in Mend's developer portal.

- Paths: `/renovate.json`
- Consequence: a new infrastructure digest or component release arrives as a pull request; merging one and tagging here is a bundle release

### S-0001/D-22 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

The README covers installing on a dev VM following `:main` and a customer VM following `:stable`, updating, rolling back, backing up, and restoring Postgres and Valkey together; setting the operator secrets; the ghcr login for root's Docker; `backup.before_update=false` on the dev VM; and changing the database password with `ALTER ROLE`. It recommends no image prune.

- Paths: `/README.md` `/CHANGELOG.md`
- Consequence: an operator can run both channels from the README alone, and a manual prune never deletes the previous release's images or the backup helper

### S-0002/D-4 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

The committed manifest declares `compatibility.rollback_safe: true`. bundle-ci's `pin.sh --release` writes `rollback_safe` as `components.yaml`'s `backend.rollback_safe` and `frontend.rollback_safe` together, true only when both are, and refuses a value that is not `true` or `false`. A plain pin leaves it as committed.

- Paths: `bundle/manifest.yaml` `bundle/RELEASE.md` `/components.yaml`
- Consequence: Between two releases on one schema, morzer rolls back, and returns from a failed update by itself (exit 11). Across a schema change, because `database_schema_min` = `max` = `produces`, it refuses a rollback, naming the pre-update backup, and a failed update stops at exit 12 for a restore

### S-0002/D-8 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

The README says these things. The update timer is `erp-update.timer`, which setting a channel installs; it ticks daily at 03:30 unless `update.schedule` says otherwise, and the dev VM sets `update.schedule='*:0/15'`. `morzer status` prints the installation id. Dev builds declare `rollback_safe: true` and a release what `components.yaml` says; where it is true, `morzer rollback` works between releases on one schema, and across a schema change it is a restore. An update that fails after its migrations on an unchanged schema returns to the previous release by itself; one that fails in its migrations, or after moving the schema, stops for a person: `morzer doctor`, `morzer status --clear-intervention=` and then `apply`, or a restore. After a reboot, `erp.service` runs `apply --startup`, which renders the secrets again. `scripts/rehearse.sh` rehearses a bundle on a workstation.

- Paths: `/README.md` `/CHANGELOG.md`
- Consequence: An operator following the README sets the dev VM's schedule, finds the installation id, and knows which failures recover by themselves

### S-0003/D-7 — `ASSUMED` (The infrastructure secrets are generated, one declaration each)

The README's "The operator secrets" names `admin_password` as the one secret the operator sets, lists the generated ones and their owners, and drops the pairs. "Changing the database password" becomes: a backup, `sudo morzer secret rotate postgres_password`, then `sudo morzer apply`, run together. `bundle/RELEASE.md`'s "Before you install" names only `admin_password`. The CHANGELOG's Unreleased section says the infrastructure secrets are generated and that the operator sets only `admin_password`.

- Paths: `/README.md` `bundle/RELEASE.md` `/CHANGELOG.md`
- Consequence: an operator reads one secret to set, and one command to change the database password

### S-0004/D-9 — `ASSUMED` (CI runs on the org's runners and leaves them clean)

The README's CI section names `RUNS_ON` and its fallback, and what a runner needs: amd64, a Docker that allows privileged containers, room for one rig (the release's 20 GiB preflight under `/var/lib/erp` and the bundle's images), on a self-hosted runner room for bundle-ci's image cache under `~/.cache/bundle-ci/oci` (the bundle's private images, readable by the runner's user, off with `image-cache: false`), no `sudo` for its user, and, when it sets `http(s)_proxy`, an address containers reach rather than loopback.

- Paths: `/README.md`
- Consequence: whoever adds or replaces a runner knows what it must offer without reading the workflows

### S-0005/D-4 — `ASSUMED` (The bundle needs morzer 0.7.0)

The README names morzer 0.8.0 as the minimum and drops 0.6.0's workarounds: the `doctor`-printed pull of the volume helper (morzer#142), `systemctl start` of the timers (morzer#139), the note that the dev VM's backup setting is what lets an unattended tick install (morzer#134), and `init --repair` after an import (morzer#135). Its "Upgrading morzer" says a machine upgrades morzer before the next bundle, and that one set up under 0.6.0 runs `sudo morzer init --repair` once, or reboots, if its timers never started.

- Paths: `/README.md`
- Consequence: the operator's procedures are the shortest ones 0.7.0 supports, and an existing machine knows its one extra step

### S-0005/D-5 — `ASSUMED` (The bundle needs morzer 0.7.0)

The CHANGELOG's `[Unreleased]` says, under Changed, that the bundle needs morzer 0.8.0 or later.

- Paths: `/CHANGELOG.md`
- Consequence: an operator reading the release learns to upgrade morzer first

<!-- /torve:managed -->

<!-- torve:managed root index — rendered from the corpus; do not edit by hand -->

## Governed directories

Each of these carries a managed `AGENTS.md` section listing the decisions
and invariants that govern it. `torve spec show S-NNNN/D-n`, `torve spec paths`
`<file>` and `torve spec tests S-NNNN/D-n` read the same corpus from the worktree.

- `bundle/` — 20 decision(s)
- `bundle/compose/` — 12 decision(s)
- `bundle/edge/` — 1 decision(s)
- `bundle/hooks/` — 3 decision(s)
- `scripts/` — 0 decision(s)
- `tests/compose/` — 0 decision(s)

<!-- /torve:managed -->
