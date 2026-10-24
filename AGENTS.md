<!-- torve:managed root — rendered from the corpus; do not edit by hand -->

## Decisions governing the repository root

### S-0001/D-15 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

`scripts/resolve.sh` resolves an image tag to its digest and reads the migrations image's schema label; `scripts/pin.sh` writes the component pins and `database_schema_produces` into `bundle/manifest.yaml`. `components.yaml` names the backend's and frontend's `X.Y.Z`, `rollback_safe` and notes; the migrations follow the backend's version. In release mode `pin.sh` refuses `main` and `sha-*` tags.

- Paths: `scripts/**` `/components.yaml`
- Consequence: a dev bundle pins whatever `main` is, and a release is made of component releases only; pinning twice changes nothing

### S-0001/D-21 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

`renovate.json` bumps the infrastructure images in `bundle/manifest.yaml` through one regex custom manager over `repo:tag@sha256:`, and `components.yaml`'s semver tags through the docker datasource. Its one host rule reads the private packages: `matchHost: ghcr.io`, `hostType: docker`, `username: Misery7100` and `password: "{{ secrets.GHCR_READ_TOKEN }}"`, a repository secret in Mend's developer portal.

- Paths: `/renovate.json`
- Consequence: a new infrastructure digest or component release arrives as a pull request; merging one and tagging here is a bundle release

### S-0001/D-22 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP)

The README covers installing on a dev VM following `:main` and a customer VM following `:stable`, updating, rolling back, backing up, and restoring Postgres and Valkey together; setting the operator secrets; the ghcr login for root's Docker; `backup.before_update=false` on the dev VM; and changing the database password with `ALTER ROLE`. It recommends no image prune.

- Paths: `/README.md` `/CHANGELOG.md`
- Consequence: an operator can run both channels from the README alone, and a manual prune never deletes the previous release's images or the backup helper

### S-0002/D-8 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed) — implementation: none

The README says these things. The update timer is `erp-update.timer`, which setting a channel installs; it ticks daily at 03:30 unless `update.schedule` says otherwise, and the dev VM sets `update.schedule='*:0/15'`. `morzer status` prints the installation id. `morzer rollback` works between releases on one schema, and across a schema change it is a restore. A failed update returns to the previous release by itself when the schema did not move, and otherwise stops for a person: `morzer status --clear-intervention=` and then `apply`, or a restore. After a reboot, `erp.service` runs `apply --startup`, which renders the secrets again. `scripts/rehearse.sh` rehearses a bundle on a workstation.

- Paths: `/README.md` `/CHANGELOG.md`
- Consequence: An operator following the README sets the dev VM's schedule, finds the installation id, and knows which failures recover by themselves

<!-- /torve:managed -->

<!-- torve:managed root index — rendered from the corpus; do not edit by hand -->

## Governed directories

Each of these carries a managed `AGENTS.md` section listing the decisions
and invariants that govern it. `torve spec show S-NNNN/D-n`, `torve spec paths`
`<file>` and `torve spec tests S-NNNN/D-n` read the same corpus from the worktree.

- `bundle/` — 14 decision(s)
- `bundle/compose/` — 10 decision(s)
- `bundle/edge/` — 1 decision(s)
- `bundle/hooks/` — 2 decision(s)
- `scripts/` — 4 decision(s)
- `tests/compose/` — 0 decision(s)
- `tests/pin/` — 1 decision(s)

<!-- /torve:managed -->
