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

<!-- /torve:managed -->

<!-- torve:managed root index — rendered from the corpus; do not edit by hand -->

## Governed directories

Each of these carries a managed `AGENTS.md` section listing the decisions
and invariants that govern it. `torve spec show S-NNNN/D-n`, `torve spec paths`
`<file>` and `torve spec tests S-NNNN/D-n` read the same corpus from the worktree.

- `bundle/` — 12 decision(s)
- `bundle/compose/` — 9 decision(s)
- `bundle/edge/` — 1 decision(s)
- `bundle/hooks/` — 1 decision(s)
- `scripts/` — 1 decision(s)
- `tests/compose/` — 0 decision(s)
- `tests/pin/` — 0 decision(s)

<!-- /torve:managed -->
