# Releasing saytype

`scripts/release.sh` builds a release end to end: XcodeGen project, Release archive, signing,
DMG, notarization when possible, Sparkle appcast. The same script runs locally and in
`.github/workflows/release.yml`.

| Mode | When | Result |
|---|---|---|
| **(a)** | a `Developer ID Application` identity and notarization credentials are available | exported with method `developer-id`, DMG notarized and stapled |
| **(b)** | anything else | signed with the available identity (Apple Development locally), not notarized, with a warning |

Release builds are never ad-hoc signed. macOS ties Microphone, Accessibility and Input
Monitoring permissions to the signing certificate. An ad-hoc signature changes with every
build, so users would have to grant the permissions again after each update.

Output in `build/release/`:

| File | Purpose |
|---|---|
| `saytype-<version>.dmg` | versioned asset, used by the appcast and the Homebrew cask |
| `saytype.dmg` | same bytes, stable name for `releases/latest/download/saytype.dmg` |
| `saytype-<version>.dmg.sha256` | checksum |
| `appcast.xml` | Sparkle feed, only when a Sparkle private key is available |
| `release.env` | version, mode and paths for the CI steps that follow |

Intermediate files (DerivedData, archive, logs) go to `build/rel/`.

## One-time setup

### Tools

- Xcode 26 with the Metal Toolchain. The script downloads the toolchain if `xcrun -f metal` fails.
- `brew install xcodegen create-dmg`. The script installs `create-dmg` itself if it is missing.
- `create-dmg` lays out the DMG window through Finder. The first run asks to let the terminal
  control Finder (System Settings → Privacy & Security → Automation).

### Mode (b): Apple Development certificate

This is the setup today.

1. Xcode → Settings → Accounts → Manage Certificates must list an **Apple Development**
   certificate. `security find-identity -v -p codesigning` shows it.
2. For CI, export it: Keychain Access → login → My Certificates → right-click
   `Apple Development: …` → Export → `.p12` with a password. Then
   `base64 -i AppleDevelopment.p12 | pbcopy` gives the value of `MACOS_CERTIFICATE_P12_BASE64`.
   Delete the `.p12` afterwards.

Sign every release with the same certificate. The designated requirement of these builds names
the certificate (`certificate leaf[subject.CN] = "Apple Development: …"`), and permissions granted
to one build carry over only to builds that satisfy it.

### Mode (a): Developer ID and notarization

1. Enroll in the Apple Developer Program at <https://developer.apple.com/programs/enroll/>
   (99 USD a year). Once enrolled, compare the Team ID at <https://developer.apple.com/account>
   with `DEVELOPMENT_TEAM` in `project.yml` and update the setting if they differ.
2. Create the certificate: Xcode → Settings → Accounts → Manage Certificates → **+** →
   **Developer ID Application**.
3. For CI, export it as `.p12` the same way as above. Its base64 goes to
   `MACOS_CERTIFICATE_P12_BASE64` and its password to `MACOS_CERTIFICATE_PASSWORD`.
4. Notarization credentials:
   - **CI:** App Store Connect → Users and Access → Integrations → App Store Connect API →
     Team Keys → **+**, role *Developer*. Download `AuthKey_<KEY_ID>.p8`; Apple offers the
     download only once. Secrets: `NOTARY_API_KEY_P8_BASE64` (`base64 -i AuthKey_<KEY_ID>.p8 | pbcopy`),
     `NOTARY_API_KEY_ID`, and `NOTARY_API_ISSUER_ID` (the Issuer ID above the key list).
   - **Local:** store a keychain profile under the name the script looks for:

     ```sh
     xcrun notarytool store-credentials saytype-notary \
       --key AuthKey_<KEY_ID>.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
     ```

     An Apple ID with an app-specific password also works:
     `--apple-id <email> --team-id <TEAM_ID> --password <app-specific-password>`.
     Set `NOTARY_KEYCHAIN_PROFILE` to use a different profile name.

Moving from mode (b) to mode (a) changes the designated requirement once. Users grant the
permissions again after that update. Sparkle accepts the change because the EdDSA key stays the
same.

### Sparkle keys

The app keeps Sparkle stopped while `SUPublicEDKey` holds the placeholder
`REPLACE_WITH_SPARKLE_PUBLIC_KEY`, and the script skips the appcast.

1. Download Sparkle's tools. A run of `scripts/release.sh` does it, and so does this:

   ```sh
   xcodegen generate
   xcodebuild -resolvePackageDependencies -project saytype.xcodeproj -scheme Saytype \
     -derivedDataPath build/rel/DerivedData
   ```

   The tools land in `build/rel/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/`.
2. Generate the key pair **once**. The private key goes to the login keychain; the command
   prints the public key:

   ```sh
   build/rel/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

3. Put the public key into `project.yml` → `info.properties.SUPublicEDKey`, run
   `xcodegen generate`, commit `project.yml` and `App/Info.plist`.
4. For CI, export the private key and store it as the `SPARKLE_ED_PRIVATE_KEY` secret:

   ```sh
   bin=build/rel/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
   $bin/generate_keys -x sparkle-private-key.txt
   pbcopy < sparkle-private-key.txt && rm -P sparkle-private-key.txt
   ```

5. Keep a copy of the private key in a password manager. Without it, installed copies can
   update only while the signing certificate stays the same.

### GitHub

Repository → Settings → Secrets and variables → Actions:

| Secret | Needed for | Value |
|---|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | both modes on CI | base64 of the exported `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | both modes on CI | its password |
| `NOTARY_API_KEY_P8_BASE64` | mode (a) | base64 of `AuthKey_<KEY_ID>.p8` |
| `NOTARY_API_KEY_ID` | mode (a) | key ID |
| `NOTARY_API_ISSUER_ID` | mode (a) | issuer ID |
| `SPARKLE_ED_PRIVATE_KEY` | appcast | output of `generate_keys -x` |

`GITHUB_TOKEN` is provided by Actions. Without a certificate secret the release job stops at the
signing step on purpose.

**GitHub Pages** serves the feed at `https://vladislavkovalskyi.github.io/saytype/appcast.xml`.
The first release that has a Sparkle key creates the `gh-pages` branch. After that release, go to
Settings → Pages → Build and deployment and set Source to *Deploy from a branch*, branch
`gh-pages`, folder `/ (root)`. Pages on a free plan needs a public repository.

### Homebrew tap

1. Create the public repository `vladislavkovalskyi/homebrew-tap`.
2. Copy `packaging/homebrew/saytype.rb` to `Casks/saytype.rb` in it.
3. Users install with `brew install --cask vladislavkovalskyi/tap/saytype`.

## Cutting a release on CI

1. Set `MARKETING_VERSION` in `project.yml` to the new version, commit, push `main`.
2. Tag and push:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. `release.yml` builds on `macos-26`, creates the GitHub Release with
   `saytype-0.2.0.dmg`, `saytype.dmg`, the checksum and generated notes, then pushes
   `appcast.xml` to `gh-pages`.
4. Update the tap with the checksum of the uploaded DMG:

   ```sh
   scripts/update-cask.sh --from-release 0.2.0 --cask ../homebrew-tap/Casks/saytype.rb
   cd ../homebrew-tap && git commit -am "saytype 0.2.0" && git push
   ```

The tag sets the version. The build number (`CFBundleVersion`) is the commit count of `HEAD`.
Sparkle compares build numbers, so tag commits on `main` and never rewrite its history.

## Local release

```sh
scripts/release.sh                   # version from project.yml
scripts/release.sh --version 0.2.0   # explicit version
scripts/release.sh --no-notarize     # Developer ID signing without notarization
```

The script picks the mode and prints it with the identity, DMG size and SHA-256.

To publish a local build without CI:

```sh
# Extend the live feed rather than start a new one
curl -fsSL https://vladislavkovalskyi.github.io/saytype/appcast.xml -o build/release/appcast.xml
scripts/release.sh --version 0.2.0

# Creates the release and its tag. If the tag starts release.yml, the workflow finds the
# release and skips the build
gh release create v0.2.0 build/release/saytype-0.2.0.dmg build/release/saytype.dmg \
  build/release/saytype-0.2.0.dmg.sha256 --title "saytype 0.2.0" --generate-notes

# Publish the feed
git fetch origin gh-pages
git worktree add ../saytype-pages gh-pages
cp build/release/appcast.xml ../saytype-pages/
git -C ../saytype-pages add appcast.xml
git -C ../saytype-pages commit -m "chore(appcast): saytype 0.2.0"
git -C ../saytype-pages push origin gh-pages
git worktree remove ../saytype-pages

scripts/update-cask.sh build/release/saytype-0.2.0.dmg --cask ../homebrew-tap/Casks/saytype.rb
```

## Without notarization

On the first launch of a downloaded build that is not notarized, macOS 15 and later show
**"saytype" Not Opened** with *Done* and *Move to Trash*. Control-click → Open no longer skips
this dialog. Users have two ways in:

- System Settings → Privacy & Security, scroll to Security, click **Open Anyway** next to
  "saytype" was blocked, confirm with Touch ID or the password, then **Open**.
- Terminal: `xattr -dr com.apple.quarantine /Applications/saytype.app`

The Homebrew cask clears the quarantine flag in `postflight_steps`. Remove that block once
releases are notarized. Sparkle clears the flag on the updates it installs, so only the first
install needs either step.
