# Android release APK

The Android Codemagic workflow is **Android - signed release APK** (`android-release`). It builds the normal `lib/main.dart` application with `flutter build apk --release`, uses the private `pharmacy_release` signing identity, and collects `build/app/outputs/flutter-apk/app-release.apk`. Release builds are not debuggable and never fall back to the Android debug key. No workflow publishes to a store.

## One-time Codemagic setup

The owner authorized creation of the first release key. It has been generated locally with a 3072-bit RSA key, alias `pharmacy_release`, a 10,000-day certificate, and randomly generated passwords. Keep this identity for every future release of this application.

1. Open Codemagic **Team settings > codemagic.yaml settings > Code signing identities > Android keystores**.
2. Upload `D:\PharmacyMS\pharmacyms\.signing\pharmacy-release.jks`.
3. Open `.signing/pharmacy-release.credentials.json` locally. Enter its `keystore_password`, `key_alias` and `key_password` into the matching Codemagic fields. Set the reference name to exactly **`pharmacy_release`**. Do not paste passwords into build scripts, Git, chat, or logs.
4. Commit/push the public project changes, including `codemagic.yaml` and `android/app/build.gradle.kts`, to the connected branch. The keystore, credentials and local `android/key.properties` are ignored and must remain private.
5. Start a build using the repository YAML configuration and select **Android - signed release APK**. The older workflow-editor debug job does not change automatically. Download **`app-release.apk`** from the successful build's artifacts and transfer it to the Android phone to install.

Codemagic injects `CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS` and `CM_KEY_PASSWORD` from that identity. Missing or incomplete signing information fails the build explicitly. See [Codemagic Android signing](https://docs.codemagic.io/yaml-code-signing/signing-android/).

Keep a secure backup of **both** the `.jks` file and its credentials outside this checkout. Codemagic does not let you download an uploaded keystore. A new signing key cannot update an already installed app signed with the original key.

## Local builds and updates

This workstation already has the ignored `android/key.properties` configured. With Flutter 3.41.5, Java 21 and the Android SDK installed:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter build apk --release --target=lib/main.dart
```

On another workstation, restore the existing keystore and create `android/key.properties` containing `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Use an absolute path with forward slashes for `storeFile` on Windows. Do not generate a replacement key for an existing app. If any Codemagic signing environment variable is present, Gradle requires the complete environment set instead of mixing it with local properties.

`tool/create_android_release_key.py` is only for an app that has never had a release key. It refuses to overwrite any existing signing file. The `.signing/` directory is excluded from Git, Odevio source uploads and delivery source archives. Signing files contain private credentials; these exclusions are not encryption.

For subsequent releases, keep the same application ID and key and increase the build number after `+` in `pubspec.yaml`. The application ID currently remains `com.example.pharmacyms`; store publication and a production package-name migration are separate work.

**If the debug app is already installed:** first create an app backup in Settings and save it outside the app's storage. Android cannot install this release over a copy signed with the debug key. After confirming the exported backup exists, uninstall the debug copy, install this release, and restore the backup. Uninstalling removes local app data and internal safety snapshots. Do not uninstall an app with unsaved records.

## Verification and delivery

Use Android SDK `apksigner verify --verbose --print-certs` to verify the APK signature and compare its certificate with the retained release keystore. Check the packaged manifest to confirm it is not debuggable. A successful build does not claim a Codemagic run or physical-phone acceptance; see [implementation status](../IMPLEMENTATION_STATUS.md) for actual results.

After verifying the APK, run `python tool/package_delivery.py`. It defaults to release mode and creates source/APK copies plus SHA-256 hashes in `build/delivery/`, excluding credentials and keystores. `--build-mode debug` is available for explicitly requested development packaging.
