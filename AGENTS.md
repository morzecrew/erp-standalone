<!-- torve:managed root — rendered from the corpus; do not edit by hand -->

## Decisions governing the repository root

### S-0001/D-21 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

`renovate.json` bumps the infrastructure images in `bundle/manifest.yaml` through one regex custom manager over `repo:tag@sha256:`. Its one host rule reads the private packages: `matchHost: ghcr.io`, `hostType: docker`, `username: Misery7100` and `password: "{{ secrets.GHCR_READ_TOKEN }}"`, a repository secret in Mend's developer portal.

- Paths: `/renovate.json`
- Consequence: a new infrastructure digest or component release arrives as a pull request; merging one and tagging here is a bundle release

### S-0001/D-22 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

The README is an operator's quick start, short because the repository is public: what the stack runs, the requirements, installing from `:stable` with root's Docker logged in to ghcr, the one operator secret, the channels, the day-to-day commands (status, doctor, logs, update, rollback, backup, restore, support) and which failed updates recover by themselves, restoring whole backups only, no image prune, rotating the database password, the assistant and the tasks; morzer's documentation holds the rest. Maintainer procedures (a dev VM's setup, CI runners, cutting a release, rehearsal, registry housekeeping) are not in it

- Paths: `/README.md` `/CHANGELOG.md`
- Consequence: an operator can run both channels from the README alone, and a manual prune never deletes the previous release's images or the backup helper

### S-0002/D-4 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

The committed manifest declares `compatibility.rollback_safe: true`. bundle-ci's `pin.sh --release` writes `rollback_safe` as `components.yaml`'s `backend.rollback_safe` and `frontend.rollback_safe` together, true only when both are, and refuses a value that is not `true` or `false`. A plain pin leaves it as committed.

- Paths: `bundle/manifest.yaml` `bundle/RELEASE.md` `/components.yaml`
- Consequence: Between two releases on one schema, morzer rolls back, and returns from a failed update by itself (exit 11). Across a schema change, because `database_schema_min` = `max` = `produces`, it refuses a rollback, naming the pre-update backup, and a failed update stops at exit 12 for a restore

### S-0003/D-7 — `ASSUMED` (The infrastructure secrets are generated, one declaration each)

The README names `admin_password` as the one secret the operator sets, and changes the database password with a backup, `sudo morzer secret rotate postgres_password`, then `sudo morzer apply`, run together. `bundle/RELEASE.md`'s "Before you install" names only `admin_password`. The CHANGELOG's Unreleased section says the infrastructure secrets are generated and that the operator sets only `admin_password`.

- Paths: `/README.md` `bundle/RELEASE.md` `/CHANGELOG.md`
- Consequence: an operator reads one secret to set, and one command to change the database password

### S-0005/D-4 — `ASSUMED` (The bundle needs morzer 0.7.0)

The README names morzer 0.8.0 as the minimum.

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

- `bundle/` — 21 decision(s)
- `bundle/compose/` — 13 decision(s)
- `bundle/edge/` — 1 decision(s)
- `bundle/hooks/` — 3 decision(s)
- `scripts/` — 0 decision(s)
- `tests/compose/` — 0 decision(s)

<!-- /torve:managed -->
