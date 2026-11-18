# Template services setup

`tsk` inherits these optional services from the iOS Swift app template.
The app identity is already configured as `Tsk` / `com.julesseguin.tsk`.

## Enabling installable PR builds (one-time)

After configuration, opening or reopening a PR and every new push automatically
build and publish an installable. To rebuild an open PR manually, use
`gh workflow run release.yml -f pr_number=<number>`.

The release pipeline builds a signed `.ipa` per PR and publishes it to
`https://<owner>.github.io/<repo>/` (URL derived automatically — nothing to
configure). It needs an Apple Developer **paid** membership, one App Group-capable
Ad Hoc profile, four required repository secrets, and GitHub Pages enabled.
The workflow skips signing when its certificate, password, main-app profile,
or team secret is missing. Invalid app profiles fail validation rather than
producing an installable build.

### Step 1 — Apple Developer console

Everything happens at [developer.apple.com/account](https://developer.apple.com/account)
under **Certificates, Identifiers & Profiles**.

1. **Register your test devices** — *Devices → +*. You need each iPhone's
   **UDID** (connect the device to a Mac: Finder → select the device → click
   the model/serial line until the UDID shows). Ad-hoc builds install **only**
   on devices baked into the profile.
2. **Register or update the explicit App ID** — *Identifiers → + →
   App IDs → App*. Use this exact bundle ID:

   | Target | Explicit bundle ID |
   | --- | --- |
   | Main app | `com.julesseguin.tsk` |

   Register the App Group `group.com.julesseguin.tsk` if needed. Enable
   **App Groups** on the App ID, choose Configure, assign that same group,
   and save. The group must be authorized by the app profile. Apple explains
   [registering an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group)
   and [assigning it to an App ID](https://developer.apple.com/help/account/identifiers/enable-app-capabilities).
3. **Use the existing Apple Distribution certificate** for the app profile.
   If signing is already configured, retain its certificate and private key.
   For a new setup, create an Apple Distribution certificate using a CSR from
   Keychain Access, then import the downloaded `.cer` beside its private key.
4. **Export that certificate as `.p12` if not already configured** — Keychain
   Access → My Certificates → *Apple Distribution: …* → Export. The existing
   `APPLE_CERTIFICATE_P12` and `APPLE_CERTIFICATE_PASSWORD` secrets can be reused.
5. **Generate an Ad Hoc provisioning profile** — *Profiles → + → Ad Hoc*.
   Regenerate the main-app profile after enabling its App Group. Choose the
   existing distribution certificate and registered device set, then download
   the `.mobileprovision`. Changes to an App ID require its profile to be
   regenerated. See Apple's [capability update rules](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)
   and [Ad Hoc profile workflow](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile).

> Adding a device later? Register its UDID, regenerate the app profile,
> and replace its profile secret below.
> TestFlight uses a separate pipeline and does not require registered UDIDs.

### Step 2 — GitHub repository secrets

*Repo → Settings → Secrets and variables → Actions → New repository secret.*
Store each file's base64-encoded contents. The profile installer accepts ASCII
line wrapping/whitespace and rejects invalid base64; no profile values belong
in the repository.

| Secret | Value | How to produce it |
| --- | --- | --- |
| `APPLE_CERTIFICATE_P12` | base64 of the `.p12` from step 1.4 | `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | the `.p12` export password | — |
| `APPLE_PROVISIONING_PROFILE` | main-app Ad Hoc profile for `com.julesseguin.tsk` | `base64 -i TskApp-AdHoc.mobileprovision \| pbcopy` |
| `APPLE_TEAM_ID` | your 10-character Team ID | developer.apple.com → Membership |
| `NTFY_TOPIC` | *(optional)* ntfy.sh topic for build-ready pushes | pick any unguessable string; subscribe in the ntfy app |

The installer validates the explicit app ID, App Group, team, Ad Hoc type,
expiry, devices and distribution certificate before installing the profile.
Its name/UUID and the signing identity are read at
runtime; no additional certificate or profile-name secret is needed.

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
secrets** to manage. The app profile is resolved through automatic signing; its App ID still needs the App Group
configuration above. This path requires its own App Store Connect app record
and API key. It reuses the same Apple Distribution
certificate (`APPLE_CERTIFICATE_P12` / `_PASSWORD`) and `APPLE_TEAM_ID` you
already set for the PR builds.

### Step 1 — App Store Connect

1. **Create the app record** — [App Store Connect](https://appstoreconnect.apple.com)
   → *Apps → +* → *New App*. Use `com.julesseguin.tsk`; the explicit App IDs
   and App Group configuration above must already exist.
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
