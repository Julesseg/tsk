# Installable PR builds — pipeline internals

The release workflow builds a **signed, installable `.ipa`** for every PR and
publishes it to a GitHub Pages site, so you can install any PR's build on your
iPhone straight from Safari, on GitHub's hosted `macos-15` runner — no
self-hosted Mac required.

Setup (Apple Developer console, repo secrets, Pages) is documented in the
[root README](../README.md#enabling-installable-pr-builds-one-time). This file
covers how the pipeline works.

The pipeline lives at [`.github/workflows/release.yml`](../.github/workflows/release.yml).

```
PR opened/updated
   └─ build  (macos-15)   archive + export an ad-hoc–signed app.ipa
        └─ deploy (ubuntu) upsert this PR's slot, prune to 5, push build-history, deploy Pages
             └─ notify     optional ntfy ping with the install link
```

Visit `https://<owner>.github.io/<repo>/` → tap **Install** on a build (Safari,
on a device whose UDID is in the provisioning profile).

## Why a hosted runner works

The only thing a self-hosted Mac would give you for free is a persistent
keychain and provisioning profile. The hosted runner starts clean every run, so
the workflow imports the certificate into a throwaway keychain and drops the
profile in place at runtime — both from repo secrets. Nothing else about the
build needs a Mac you own. (CI still also runs the unsigned simulator tests in
`ci.yml`; this is additive.)

Until the four signing secrets are set, the `build` job no-ops and the PR check
stays green — the installable build simply doesn't run.

## Files

- `assemble-build-history.mjs` — upserts the current PR's slot into
  `builds.json`, keeps the 5 newest, copies in the `.ipa`, and regenerates the
  OTA manifests and install pages. Pure Node, no dependencies. All identity
  (app name, bundle id, URLs) arrives via environment variables from
  `release.yml`.
- The build + publish pipeline itself lives at `.github/workflows/release.yml`.

## Notes & limits

- **Retention:** 5 most-recent PRs (`RETENTION` in `release.yml`). Older slots
  and their `.ipa`s are pruned.
- **Concurrency:** builds run per-PR in parallel (a new push cancels that PR's
  older in-flight build); the publish step is serialized across all PRs because
  it read-modify-writes the shared `build-history` branch.
- **Versioning:** the OTA manifest uses the short commit SHA as the bundle
  version, so reinstalling the same PR after a new push registers as an update.
- **Xcode:** the build uses the runner's latest-stable Xcode, matching `ci.yml`.
