<!-- torve:managed tests/version — rendered from the corpus; do not edit by hand -->

## Decisions governing `tests/version/`

### S-0002/D-1 — `ASSUMED` (A dev version per bundle change, and the operations rehearsed)

`scripts/version.sh` prints the dev version of the bundle at HEAD. It takes the last commit that changed `bundle/` (`git log -1 --format=%H -- bundle`) and describes it with `git describe --tags --long`, as `vX.Y.Z-N-g<sha>`. From that it prints `X.Y.(Z+1)-dev.N.g<sha>`, for every N including 0, with the sha as git abbreviates it. It refuses, exiting non-zero with the reason on stderr, in four cases: no commit changed `bundle/`; no tag is reachable from that commit; the nearest tag is not `X.Y.Z` or `vX.Y.Z`; or `git status --porcelain --untracked-files=all -- bundle` reports anything. `VERSION_ROOT` names the repository (default: the one the script is in), as `PIN_ROOT` does for `pin.sh`.

- Paths: `scripts/version.sh` `tests/version/**`
- Consequence: Two commits with one `bundle/` name one version, and a commit outside `bundle/` names the version already built; the dev channel never names a bare `X.Y.Z`, so it cannot take a version `release.yml` will publish

<!-- /torve:managed -->
