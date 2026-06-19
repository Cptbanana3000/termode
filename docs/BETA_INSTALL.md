# Beta Install

How to install the Termode beta candidate debug APK on a real Android device.

## Artifact

The beta build is distributed as a renamed debug APK:

```text
Termode-v0.47-git-pipeline-debug.apk
```

The raw Flutter output is `build/app/outputs/flutter-apk/app-debug.apk`. See
[Release Artifact Naming](#release-artifact-naming) for how to produce the
renamed file.

## Install The Debug APK Manually

1. Copy `Termode-v0.47-git-pipeline-debug.apk` to the device.
2. On the device, open the file with a file manager or browser.
3. When prompted, allow installation.

## Android Install Unknown Apps Permission

Android blocks installs from outside the Play Store by default:

- Open Settings, Apps, Special app access, Install unknown apps.
- Select the app you are installing from, such as Files or Chrome.
- Toggle Allow from this source.
- Return and tap the APK again to install.

## Install With adb

```sh
adb install -r Termode-v0.47-git-pipeline-debug.apk
```

## Clear App Data

If a build behaves oddly, you can reset Termode's local state:

- Android Settings, Apps, Termode, Storage, Clear data.
- `adb shell pm clear com.termode.termode`

This removes sessions, settings, packages, and workspace files. Inside the app,
prefer `settings-reset-safe --confirm` to reset only visual/terminal settings
without deleting user data.

## First Checks After Install

Launch Termode and run:

```sh
welcome
version
build-info
runtime-abi
runtime-pkg status
runtime-pkg doctor
doctor
beta-candidate status
rc-status
qa-status
```

A healthy build reports `BETA CANDIDATE` / `RC CLEANUP READY` and intentional
limited states for known limits such as unlinked storage. Missing Git,
Git has a v0.47 artifact pipeline but no bundled artifact; Node.js, npm, and Python remain planned, not installed.

## Release Artifact Naming

Beta artifacts use:

```text
Termode-v0.47-git-pipeline-debug.apk
```

After `flutter build apk --debug`, copy the output to the named file:

```sh
cp build/app/outputs/flutter-apk/app-debug.apk Termode-v0.47-git-pipeline-debug.apk
```

On Windows PowerShell:

```powershell
Copy-Item build\app\outputs\flutter-apk\app-debug.apk Termode-v0.47-git-pipeline-debug.apk
```

This is a manual copy step on purpose. `build-info` prints the expected artifact
name from inside the app. Do not commit generated APK files to the repository.

