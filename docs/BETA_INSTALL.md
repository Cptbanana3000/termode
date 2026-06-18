# Beta Install

How to install the Termode beta candidate debug APK on a real Android device.

## Artifact

The beta build is distributed as a renamed debug APK:

```
Termode-v0.41-rc-debug.apk
```

The raw Flutter output is `build/app/outputs/flutter-apk/app-debug.apk`. See
[Release Artifact Naming](#release-artifact-naming) for how to produce the
renamed file.

## Install the Debug APK Manually

1. Copy `Termode-v0.41-rc-debug.apk` to the device (USB, download, or share).
2. On the device, open the file with a file manager or your browser.
3. When prompted, allow installation.

### Android "Install unknown apps" Permission

Android blocks installs from outside the Play Store by default:

- Open **Settings → Apps → Special app access → Install unknown apps**.
- Select the app you are installing from (Files, Chrome, etc.).
- Toggle **Allow from this source**.
- Return and tap the APK again to install.

### Install with adb (optional)

If you have developer tools:

```sh
adb install -r Termode-v0.41-rc-debug.apk
```

## Clear App Data (if needed)

If a build behaves oddly, you can reset Termode's local state:

- **Settings → Apps → Termode → Storage → Clear data**, or
- `adb shell pm clear com.termode.termode`

This removes sessions, settings, packages, and workspace files. Inside the app,
prefer `settings-reset-safe --confirm` to reset only visual/terminal settings
without deleting your data.

## First Checks After Install

Launch Termode and run:

```sh
welcome
doctor
beta-candidate status
rc-status
qa-status
```

A healthy build reports `BETA CANDIDATE` / `RC CLEANUP READY` (and `READY WITH
LIMITATIONS` for `qa-status`). Frozen runtime and unlinked storage are expected
limited states, not failures.

## Release Artifact Naming

Beta artifacts use:

```
Termode-v0.41-rc-debug.apk
```

After `flutter build apk --debug`, copy the output to the named file:

```sh
# from the project root
cp build/app/outputs/flutter-apk/app-debug.apk Termode-v0.41-rc-debug.apk
```

On Windows PowerShell:

```powershell
Copy-Item build\app\outputs\flutter-apk\app-debug.apk Termode-v0.41-rc-debug.apk
```

This is a manual copy step on purpose — no fragile build automation is added.
`build-info` prints the expected artifact name from inside the app.
