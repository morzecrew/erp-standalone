<!-- torve:managed tests/pin — rendered from the corpus; do not edit by hand -->

## Decisions governing `tests/pin/`

### S-0002/D-4 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

The committed manifest declares `compatibility.rollback_safe: true`. `scripts/pin.sh --release` writes `rollback_safe` as `components.yaml`'s `backend.rollback_safe` and `frontend.rollback_safe` together, true only when both are, and refuses a value that is not `true` or `false`. Plain `pin.sh` leaves it as committed.

- Paths: `bundle/manifest.yaml` `bundle/RELEASE.md` `scripts/pin.sh` `tests/pin/**`
- Consequence: Between two releases on one schema, morzer rolls back, and returns from a failed update by itself (exit 11). Across a schema change, because `database_schema_min` = `max` = `produces`, it refuses a rollback, naming the pre-update backup, and a failed update stops at exit 12 for a restore

<!-- /torve:managed -->
