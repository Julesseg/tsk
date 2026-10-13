# Template services setup

`tsk` inherits these optional services from the iOS Swift app template.
The app identity is already configured as `Tsk` / `com.julesseguin.tsk`.

## Enabling installable PR builds (one-time)

The release pipeline builds a signed `.ipa` per PR and publishes it to
`https://<owner>.github.io/<repo>/` (URL derived automatically — nothing to
configure). It needs an Apple Developer **paid** membership, four repository
secrets, and GitHub Pages enabled. Until the secrets exist, the workflow
no-ops and stays green.

### Step 1 — Apple Developer console

Everything happens at [developer.apple.com/account](https://developer.apple.com/account)
under **Certificates, Identifiers & Profiles**.

1. **Register your test devices** — *Devices → +*. You need each iPhone/iPad's
   **UDID** (connect the device to a Mac: Finder → select the device → click
   the model/serial line until the UDID shows). Ad-hoc builds install **only**
   on devices baked into the profile.
2. **Create the App ID** — *Identifiers → + → App IDs → App*. Set the explicit
   bundle id to exactly what you passed to `rename.sh` (e.g.
   `com.acme.zenith`). Enable any capabilities your app uses (App Groups,
   Push, etc.) — the template's entitlements file starts empty, so none are
   required at first.
3. **Create a Distribution certificate** — *Certificates → + → Apple
   Distribution*. Upload a CSR generated on your Mac (Keychain Access →
   Certificate Assistant → Request a Certificate From a Certificate
   Authority → "Saved to disk"). Download the `.cer` and double-click it so
   it lands in your login keychain **next to its private key**.
4. **Export the certificate as `.p12`** — Keychain Access → My Certificates →
   right-click the *Apple Distribution: …* entry → Export. Choose a strong
   password; you'll store it as a secret.
5. **Create an Ad Hoc provisioning profile** — *Profiles → + → Ad Hoc*.
   Select the App ID from step 2, the certificate from step 3, and the
   devices from step 1. Download the `.mobileprovision`.

> Adding a device later? Register its UDID, **regenerate the profile**, and
> update the `APPLE_PROVISIONING_PROFILE` secret — old builds won't install on
> it. (TestFlight avoids UDID management entirely but is a different pipeline.)

### Step 2 — GitHub repository secrets

*Repo → Settings → Secrets and variables → Actions → New repository secret.*
macOS `base64` doesn't wrap lines by default, which is exactly what the
workflow expects:

| Secret | Value | How to produce it |
| --- | --- | --- |
| `APPLE_CERTIFICATE_P12` | base64 of the `.p12` from step 1.4 | `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | the `.p12` export password | — |
| `APPLE_PROVISIONING_PROFILE` | base64 of the `.mobileprovision` from step 1.5 | `base64 -i AdHoc.mobileprovision \| pbcopy` |
| `APPLE_TEAM_ID` | your 10-character Team ID | developer.apple.com → Membership |
| `NTFY_TOPIC` | *(optional)* ntfy.sh topic for build-ready pushes | pick any unguessable string; subscribe in the ntfy app |

The signing identity name and the profile's name/UUID are read out of the cert
and profile at runtime — nothing else to copy.

### Step 3 — GitHub Pages

1. *Settings → Pages → Build and deployment → Source:* **GitHub Actions**.
2. Enabling Pages auto-creates a `github-pages` **environment** that by default
   only lets the default branch deploy — so a PR branch's deploy is rejected at
   the gate (a ~1-second failure, no steps run). Fix at *Settings →
   Environments → github-pages → Deployment branches and tags*: choose **No
   restriction**, or keep *Selected branches* and add a rule matching your PR
   branch names (e.g. `agent/*`).

The `build-history` branch appears automatically on the first successful
publish. It's a derived store — force-pushed every run so multi-MB `.ipa`
blobs never accumulate in git history. Don't commit to it.

### Using it

Open a PR → the `Release` workflow archives, signs, exports, and publishes.
Visit `https://<owner>.github.io/<repo>/` in **Safari on the iPhone** and tap
**Install** (the OTA `itms-services://` flow only works in Safari, and only on
devices whose UDID is in the profile). The site keeps the 5 most recent PR
builds (`RETENTION` in `release.yml`); reinstalling the same PR after a new
push registers as an update because the short commit SHA is the bundle
version. Pipeline internals: [`ci/README.md`](../ci/README.md).

## Enabling App Store / TestFlight releases (one-time)

`release-appstore.yml` is a separate pipeline from the PR builds above. Where
`release.yml` produces **ad-hoc** builds for on-device testing, this one signs
for the **App Store** and uploads to App Store Connect, so the build shows up in
**TestFlight** and can be promoted to a public release. It runs when you push a
version tag `vX.X.X` (or from *Actions → Release (App Store) → Run workflow*).

Signing is driven by an **App Store Connect API key** with **automatic
signing**: `xcodebuild` creates/downloads the App Store provisioning profile at
build time, so — unlike the ad-hoc pipeline — there are **no `.mobileprovision`
secrets** to manage. Add app extensions later and their profiles are resolved
the same way, no workflow change. It reuses the same Apple Distribution
certificate (`APPLE_CERTIFICATE_P12` / `_PASSWORD`) and `APPLE_TEAM_ID` you
already set for the PR builds.

### Step 1 — App Store Connect

1. **Create the app record** — [App Store Connect](https://appstoreconnect.apple.com)
   → *Apps → +* → *New App*. Use the bundle id you passed to `rename.sh`
   (e.g. `com.acme.zenith`); the App ID from the PR-builds setup above must
   already exist.
2. **Create an API key** — *Users and Access → Integrations → App Store Connect
   API → +*. Give it the **App Manager** role. Download the `.p8` file **once**
   (Apple only lets you download it a single time). Note the **Key ID** and the
   **Issuer ID** shown above the keys list.

### Step 2 — GitHub repository secrets

The three App-Store-specific secrets, on top of the certificate/team secrets
already configured for PR builds:

| Secret | Value | How to produce it |
| --- | --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | the API key's Key ID (e.g. `ABC123XYZ9`) | from step 1.2 |
| `APP_STORE_CONNECT_ISSUER_ID` | the API key's Issuer ID | from step 1.2 |
| `APP_STORE_CONNECT_KEY_P8` | the full contents of the `.p8` file | `pbcopy < AuthKey_ABC123XYZ9.p8` |

`APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_TEAM_ID` are
shared with `release.yml` — nothing to add if PR builds already work. Until all
six are present, a tagged run **fails fast** with a clear message (a deliberate
release shouldn't silently no-op the way the PR pipeline does).

### Cutting a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow stamps `MARKETING_VERSION` from the tag (`v1.0.0` → `1.0.0`) and
`CURRENT_PROJECT_VERSION` from the CI run number, archives with automatic
signing, exports an App-Store-signed `.ipa`, and uploads it with `xcrun altool`.
Because the build number is the run number, every upload is unique and
increasing — App Store Connect rejects duplicate build numbers for a version.
Processing in TestFlight takes a few minutes after the run goes green; set
`NTFY_TOPIC` to get pinged when the upload finishes. The signed `.ipa` is also
attached to the run as an artifact (7-day retention). A misformatted tag (not
`X.X.X`) fails the run early rather than uploading a bad version.

## Enabling agent auto-dispatch (one-time)

The auto-dispatch pipeline (`unblock-dispatch.yml` + `agent-implement.yml`)
spawns a background [Paseo](https://paseo.sh) agent session per ready
issue. Until you complete this setup, `unblock-dispatch.yml` runs on issue
events but finds nothing to dispatch, and `agent-implement.yml` never runs —
both stay green.

1. **Create the `ready-for-agent` label** and write blockers as `- #N` bullets
   under a `## Blocked by` heading in issue bodies — that's what the dispatcher
   scans for. An issue with no blockers qualifies too, and starts on the next
   issue close or a manual run of `unblock-dispatch.yml`.
2. **Install the `label-and-implement-with-pr` skill** under
   `~/.agents/skills` on the runner, with the `implement`, `ui-report`, and
   `babysit-pr` skills it uses. These are not shipped with this template.
3. **Register a self-hosted macOS runner** (repo → Settings → Actions →
   Runners) on a Mac with the Paseo daemon running, `gh` authenticated, and the
   selected Paseo provider available.
4. **Set three required repository Actions variables** (*Settings → Secrets and
   variables → Actions → Variables* — a variable, not a secret):

   | Variable | Value |
   | --- | --- |
   | `PASEO_PROJECT_DIR` | Absolute path of this repo's clone on the runner Mac; agent sessions spawn git worktrees off it |
   | `PASEO_PROVIDER` | Paseo provider for unattended sessions |
   | `PASEO_MODEL` | Model exposed by that provider |

   The clone needs to be able to `git fetch origin` unattended as the runner's
   user — the spawn step refreshes it so each session branches off the current
   `origin/main` rather than the clone's own stale `main`.

   `PASEO_THINKING`, `PASEO_MODE`, and `PASEO_BASE` are optional. No provider,
   model, thinking, or permission-mode default is selected by the workflow.

Full walkthrough, scope rules, the in-flight cap, and the optional variables:
[`docs/agents/auto-dispatch.md`](agents/auto-dispatch.md).

## CI details

- **`ci.yml`** — `core-tests` runs `swift test` in a `swift:6.0.3` Linux
  container; `app-ui-tests` builds and runs the XCUITest suite on `macos-15`
  with the latest stable Xcode against the newest available iPhone simulator,
  unsigned (`CODE_SIGNING_ALLOWED=NO`). The `.xcresult` bundle is uploaded as
  an artifact on every run.
- **Deployment target** is iOS 26.0 (`IPHONEOS_DEPLOYMENT_TARGET` in the
  pbxproj) with Swift 6 — adjust to your needs.
- Workflows read the app identity from one `env:` block each (`APP_NAME`,
  `BUNDLE_ID`), which `rename.sh` rewrites.

## Agent integration

Shared hooks live under `.agents/hooks`. Claude Code, Codex, and Pi
use thin native adapters for the same behavior:

- **`validate-commit-msg.py`** blocks `git commit` unless the
  subject follows Conventional Commits. Deliberately permissive: merges,
  reverts, amends, and messages it can't parse statically pass through.
- **`session-start.sh`** on remote Linux environments
  (Linux), asynchronously installs the Swift 6.0.3 toolchain so `cd Core &&
  swift test` works there. No-op on a local Mac.
- **`platform-guidance.sh`** tells the agent whether this
  machine can run the XCUITest suite (a Mac with Xcode can; a Linux container
  cannot — CI is the gate there).

`AGENTS.md` carries the matching conventions (commit/PR-title format, "always
implement the UI, let CI verify it"). Customize both for your project.
