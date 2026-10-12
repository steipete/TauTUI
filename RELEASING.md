# Releasing TauTUI

TauTUI ships through Swift Package Manager. Its source-only GitHub Releases use
`openclaw/release-workflows/.github/workflows/release-source.yml@v1` and contain
frozen-commit source ZIP and tar archives, the exact changelog section, an asset
inventory, and SHA-256 checksums. There is no npm, Homebrew binary, or Sparkle
publication. Executable examples are built from source, not distributed binaries.

## Prepare and rehearse

Set `.release-version` to the version being prepared and finalize exactly one
`## X.Y.Z - YYYY-MM-DD` changelog section for it. Brackets around the version and
an em dash before the date are accepted. Preserve the next `Unreleased` section.
`.release-version` stays at the latest released version until release preparation;
it is independent of any next-version heading marked `Unreleased`.

Merge the preparation PR and wait for all push CI checks on that exact protected
`main` commit. Run a no-publish proof from that commit:

```sh
gh workflow run release.yml --repo steipete/TauTUI --ref main -f version=X.Y.Z -F dry_run=true
```

Dispatch defaults to `dry_run: true`. It builds the release configuration and runs
the Swift tests on macOS, validates the version and dated notes, then independently
verifies the source archives on two fresh runners. It creates no tag or release.
A proof of the already released version still builds current protected `main`.
`bash scripts/verify-release.sh` is the read-only local macOS build/test helper.

## Publish

Create an SSH-signed annotated `vX.Y.Z` tag on the verified commit using the release
key authorized in `.github/release-allowed-signers`, then push that tag. Its exact
commit must have green push CI. Signing key custody stays outside Actions; a live
dispatch also requires an existing signed tag. Never move version tags or republish
an existing release. Historical tag names are left unchanged.

Check the successful workflow, published notes, source archives, inventory, and
checksums. There is no local publishing fallback; the workflow owns publication.
