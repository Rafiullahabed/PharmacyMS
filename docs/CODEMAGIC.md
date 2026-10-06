# Codemagic builds

The owner now uses Codemagic. The repository-root `codemagic.yaml` defines separate Android, unsigned iOS-device and iOS-simulator workflows. No workflow uploads to an app store, creates an Apple account or contains signing secrets.

## Reported failure and fix

The Android log reported `Method not found: CupertinoPageTransitionsBuilder` in `app_theme.dart`. Flutter 3.44 moved that class from the Material library to Cupertino. The theme now imports both libraries, retaining compatibility with the locally verified Flutter 3.41.5 baseline and the newer export location. A narrowly scoped analyzer suppression keeps the compatibility import on the older SDK. Native transitions and reduced-motion behavior are unchanged. See [Flutter's migration guide](https://docs.flutter.dev/release/breaking-changes/decouple-page-transition-builders).

The Kotlin 2.2.20 message was a **warning**. The failing task was Dart compilation, not a Kotlin compiler or Android signing failure. Do not hide it with `--android-skip-build-dependency-validation` or change Kotlin/AGP just to address that warning.

The supplied iOS excerpt does not contain the underlying Xcode/Dart error. Flutter can emit its generic Development Team instructions after an unsigned build failure when it cannot extract a more specific issue. The same shared Dart import defect can affect both platforms, but the iOS cause must be confirmed by a new build. Neither a fake team ID nor permanently disabling project signing fixes a Dart compiler error.

## Start the corrected build

1. Commit/push the changed theme and `codemagic.yaml` to the repository and branch connected to Codemagic. The YAML file must be at the repository root. Existing UI-configured jobs do not automatically become this workflow just because the file exists locally.
2. In Codemagic, select **Start new build**, choose that branch and a workflow from the YAML configuration. If currently using the Flutter workflow editor, switch to the repository's YAML configuration. See [Codemagic's YAML instructions](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/).
3. Run **Android - installable debug APK** first to verify the fixed Dart compilation. It produces `build/app/outputs/flutter-apk/app-debug.apk`. This is a development APK, not an AAB or a store release.
4. Run **iOS - unsigned device build (not installable)** to check device compilation without Apple signing. It produces `pharmacy-unsigned-device.app.zip` only after compilation succeeds. It does not produce an installable IPA.
5. Alternatively run **iOS - simulator app (no Apple membership)** for `pharmacy-simulator.app.zip`. This runs in an iOS simulator, not on a physical iPhone.

The workflows pin Flutter **3.41.5** to match the tested Dart SDK and dependency lockfile. Android pins Java **21**; iOS selects Xcode **26.2**. CocoaPods/Swift package setup is handled by the selected Flutter SDK; no native dependency system is replaced speculatively. The dependency step enforces `pubspec.lock`. No tests are silently ignored and shell pipeline failures propagate through `tee`.

Every job runs static analysis before the native build. Version, dependency, analysis and verbose build logs are collected under `build/ci-logs/`. If iOS still fails, download `ios-build.log` and provide the **first actual compiler/Xcode error**, not just the final Development Team banner. Do the same with `android-build.log` for Android. A remote build success is not claimed until Codemagic reports it.

## Installing on an iPhone

`--no-codesign` permits compilation without Apple signing; it does not permit installation of an unsigned app. For a directly installable IPA in Codemagic, configure the real Apple identity, signing certificate and matching ad-hoc provisioning profile containing the iPhone's registered UDID. The owner previously confirmed no paid Apple Developer membership, so that signing setup remains outstanding. No team, bundle identity, key or profile has been invented or committed. See [Codemagic iOS signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/) and [Apple device registration](https://developer.apple.com/help/account/devices/register-a-single-device).

The earlier [Odevio setup](IOS_ODEVIO.md) remains documented as an alternative. These Codemagic jobs do not require Odevio, and no local Xcode/fastlane invocation is needed on the Windows workstation.
