<!-- torve:managed scripts — rendered from the corpus; do not edit by hand -->

## Decisions governing `scripts/`

### S-0001/D-15 — `ASSUMED` (erp-standalone as a morzer release bundle of the whole ERP) — implementation: none

`scripts/resolve.sh` resolves an image tag to its digest and reads the migrations image's schema label; `scripts/pin.sh` writes the component pins and `database_schema_produces` into `bundle/manifest.yaml`. `components.yaml` names the backend's and frontend's `X.Y.Z`, `rollback_safe` and notes; the migrations follow the backend's version. In release mode `pin.sh` refuses `main` and `sha-*` tags.

- Paths: `scripts/**` `/components.yaml`
- Consequence: a dev bundle pins whatever `main` is, and a release is made of component releases only; pinning twice changes nothing

<!-- /torve:managed -->
