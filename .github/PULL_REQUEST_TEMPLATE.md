## Summary

Describe the user-visible change and why it is needed.

## Privacy boundaries and verification

- [ ] I considered whether this changes captured pixels, stored window metadata, network access, or fail-closed behavior.
- [ ] I added or updated tests for geometry, tracking, and stopped-capture behavior where applicable.
- [ ] I updated `PRIVACY.md`, the threat model, or compatibility matrix when behavior changed.

## Verification

- [ ] `swift test`
- [ ] `./build.sh`
- [ ] `./Scripts/check-release.sh`
- [ ] Tested at least one real screen-sharing path, if relevant.
- [ ] Commits include a DCO `Signed-off-by` line.
