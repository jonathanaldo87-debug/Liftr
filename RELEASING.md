# Releasing Liftr (Android)

Publishing happens through GitHub Releases: you push a tag, CI builds a signed
APK and attaches it to a release. That release page is the download link you give
people.

No Play Store account is needed. Android will warn about "unknown sources" on
install, which is normal for a directly-distributed app.

---

## One-time setup

### 1. Create the signing key

This key **is** your app's identity. Android only accepts an update if it's
signed with the same key as the installed version, so losing it means no existing
install can ever be updated again — they'd have to uninstall and lose local data.
Back it up somewhere you won't lose it, and never commit it.

It asks for a password and some identity fields (name, org, country). The
identity fields are cosmetic for direct distribution — only the password matters.

`keytool` ships with the JDK and is **not on this machine's PATH**. Use the full
path — either of these works:

```
C:\Program Files\Java\jdk-17\bin\keytool.exe
C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe
```

So, run from the repo root:

```powershell
& "C:\Program Files\Java\jdk-17\bin\keytool.exe" -genkeypair -v `
  -keystore android/upload-keystore.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload
```

### 2. Point the local build at it

Create `android/key.properties`:

```properties
storeFile=upload-keystore.jks
storePassword=<the store password you just set>
keyAlias=upload
keyPassword=<the key password you just set>
```

Both this file and `*.jks` are already in `android/.gitignore`, so neither can be
committed by accident.

`android/app/build.gradle.kts` picks this up automatically. Without it the build
still works but falls back to **debug keys** — fine for local testing, never for
distribution.

Verify:

```powershell
flutter build apk --release
```

### 3. Add the GitHub secrets

CI has no access to your keystore, so it gets one from repository secrets.
Base64-encode the keystore and copy it:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/upload-keystore.jks")) | Set-Clipboard
```

Then in the repo: **Settings → Secrets and variables → Actions → New repository
secret**, and add four:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | the base64 string just copied |
| `KEYSTORE_PASSWORD` | store password |
| `KEY_ALIAS` | `upload` |
| `KEY_PASSWORD` | key password |

---

## Publishing a version

```powershell
git tag v1.0.1
git push origin v1.0.1
```

`.github/workflows/release.yml` then builds the signed APK and creates the
release. The tag sets the version name (`v1.0.1` → `1.0.1`); `versionCode` comes
from the CI run number, so it always increases.

**Why versionCode matters:** Android refuses to install an APK whose
`versionCode` isn't higher than the installed one. That's the usual reason a
rebuilt APK "doesn't update". CI handles it — but a manual local build won't,
since `pubspec.yaml` is still at `1.0.0+1`.

To test the pipeline without publishing, run the workflow manually from the
**Actions** tab; it uploads the APK as a workflow artifact instead of releasing.

---

## Installing

### One-off

Send people the release page. They download the `.apk` and allow installation
from unknown sources when prompted.

### Automatic updates (Obtainium)

[Obtainium](https://github.com/ImranR98/Obtainium) watches this repo's releases
and updates the app when a new one appears — a store-like experience without a
store.

1. Install Obtainium (from its own
   [GitHub releases](https://github.com/ImranR98/Obtainium/releases) or F-Droid).
2. **Add App** → paste the repo URL:
   ```
   https://github.com/jonathanaldo87-debug/Liftr
   ```
3. Obtainium finds the latest release, installs the APK, and checks for new ones
   from then on.

**This requires the repo to be public.** Obtainium reads releases through the
GitHub API; against a private repo it 404s unless every user configures a
personal access token with repo access in Obtainium's settings.

**"Automatic" means auto-check and auto-download, not silent install.** Android
still shows its package-installer confirmation for each update and you tap
Install. Unattended installs need Shizuku or root — out of scope here, and rarely
worth it for a personal app.

Updates only apply because every release is signed with the *same* key and gets a
higher `versionCode`. Both are handled by the keystore setup above and by CI —
which is exactly why a debug-signed or hand-built APK breaks the update chain.

---

## Notes

- **iOS is not covered here.** Distributing to other people's iPhones requires
  the Apple Developer Program ($99/yr); TestFlight is the practical route. There
  is no APK-style sideload equivalent.
- **If you add Google Sign-In later**, register this keystore's SHA-1 in Google
  Cloud Console (plus your debug key's, for development):
  ```powershell
  & "C:\Program Files\Java\jdk-17\bin\keytool.exe" -list -v `
    -keystore android/upload-keystore.jks -alias upload
  ```
