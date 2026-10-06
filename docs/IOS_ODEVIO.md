# iPhone builds through Odevio

This project uses Odevio for remote iOS builds. Do not run local Xcode or fastlane commands. The requested deliverable is a signed `.ipa` for the owner's registered iPhone, not an App Store submission. Building through Odevio uploads the application source to its remote Mac; the installed mobile app still works offline.

## Current state — 2026-10-06

- Odevio CLI 1.3.1 is installed on the Windows workstation. Its bundled skill was installed at `.claude/skills/odevio/SKILL.md` with project-local files and without changing command approval settings. This installed CLI has no `--agent` option; the skill has been read directly by Codex.
- The sign-in check reported no authenticated account. The owner must sign in privately in the terminal. Never paste a password or private-key contents into chat.
- The owner confirmed they do not have a paid Apple Developer Program membership. Odevio's installable iPhone build requires one. No remote build, source upload, signing, `.ipa`, device installation, TestFlight delivery or App Store submission has occurred.
- Project version is 0.8.0+8, using Flutter 3.41.5 / Dart 3.11.3. The iOS project still contains the development placeholder `com.example.pharmacyms`; the real identity must be selected from, or registered in, the owner's account. Odevio applies the selected identity remotely. No identity or signing credentials have been invented.
- `.odevioignore` excludes other platforms, development fixtures, review files, local caches/configuration and assistant metadata. Odevio 1.3.1 compares **literal basenames**, not gitignore patterns. Its built-in rules also exclude `build`, `.git`, `.dart_tool`, `.pub-cache`, `.pub` and `.gradle`. Keep signing keys outside the project; this is not a wildcard secret scanner. Review the upload contents again before the first remote build.

## Resume the iPhone installation

1. Complete [Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/) if choosing Odevio's signed iPhone route. Enrollment and any payment must be handled by the owner.
2. Sign in to Odevio privately in the IDE terminal using `odevio signin`, or create an account with `odevio signup`. Then ask the assistant to continue the iPhone build.
3. The assistant checks the existing Odevio apps and Apple account before requesting anything. If Apple access is not connected, use the [Odevio Apple setup guide](https://odevio-cli.readthedocs.io/en/latest/tutorial/6_configure_app_store_connect.html). The required items are Team ID, Issuer ID, Key ID and the local path to the downloaded `.p8` file. Keep a safe copy outside this repository; do not paste its contents. Account linkage gives Odevio signing access.
4. Confirm the app name/identity if a new app must be registered. Register the iPhone's UDID with Apple for direct installation; see [Apple's device registration instructions](https://developer.apple.com/help/account/devices/register-a-single-device). The assistant then refreshes Odevio's registered devices. Do not initiate TestFlight or App Store publication for this request.
5. The assistant checks supported Flutter versions, the prior build number and local validation, then starts a single **ad-hoc** build targeting `lib/main.dart`, observes its result, fixes actual build failures, and retrieves the resulting IPA/install link. Native plugin resolution and signing are verified only by that remote build, not by the Android or host test results.
6. After success, save the actual IPA under `build/delivery/`, record its SHA-256, remote build identity and signing/device limitations, and test installation/offline workflows on the registered iPhone. A downloaded IPA alone is not evidence that installation or iOS acceptance passed.

The `.odevio` configuration is intentionally absent until the real account/app is known. No placeholder app key should be committed. Keep build type explicit for each operation so a device build cannot silently become a publication.

## Without paid Apple membership

Odevio offers a remote Mac/iOS **simulator preview** without Apple signing credentials; it still needs an Odevio sign-in and is subject to its service availability. This preview does not produce an app installable on the owner's iPhone. It is a different outcome and should only be started if requested. See [Odevio's Windows guide](https://odevio.com/flutter-ios-build-windows/).

Apple separately documents free Personal Team testing through Xcode with short-lived provisioning. That is not Odevio's signed-IPA workflow and is not configured here; local Xcode builds are outside the owner's chosen process. See [Apple's account comparison](https://developer.apple.com/help/account/basics/about-your-developer-account).

Actual iOS keyboard, navigation, file/share and VoiceOver checks remain pending. Remote compilation, simulator review, signed export and physical-device acceptance must be recorded separately.
