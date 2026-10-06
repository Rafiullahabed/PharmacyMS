# Dependencies and offline assets

Resolved with Flutter 3.41.5 / Dart 3.11.3; final integration additions on 2026-10-06. Exact direct/transitive versions and hashes are in `pubspec.lock`. Dependencies were selected against the installed SDK; newer incompatible versions were not forced.

| Direct dependency | Locked version | License | Purpose |
|---|---|---|---|
| Flutter SDK | 3.41.5 | BSD-3-Clause | UI, ChangeNotifier, built-in platform navigation |
| sqflite | 2.4.2+1 | BSD-2-Clause | Native Android/iOS SQLite |
| path | 1.9.1 | BSD-3-Clause | Database path joining |
| uuid | 4.6.0 | MIT | Secure random local UUIDs |
| shamsi_date | 1.1.1 | BSD-3-Clause | Gregorian / Solar Hijri conversion |
| cupertino_icons | 1.0.9 | MIT | Existing Flutter starter icon dependency |
| crypto | 3.0.7 | BSD-3-Clause | SHA-256 backup corruption detection |
| file_picker | 10.3.10 | MIT | Scoped native file selection and destination saving |
| share_plus | 12.0.1 | BSD-3-Clause | Native share sheet and completion status |
| flutter_test | SDK | BSD-3-Clause | Domain, repository and widget tests |
| integration_test | SDK | BSD-3-Clause | Real Android/iOS sqflite and UI integration tests (development only) |
| flutter_lints | 6.0.0 | BSD-3-Clause | Static analysis |
| sqflite_common_ffi | 2.4.0+3 | BSD-2-Clause | Real SQLite host tests (development only) |

Native mobile SQLite is supplied through sqflite's Android/Darwin plugins. The host test implementation uses sqlite3 native assets, which may be downloaded on the first development test run. This is a build/test dependency, not an app runtime network dependency.

The bundled `assets/fonts/Vazirmatn.ttf` variable font supports Latin and Persian text. Its full SIL Open Font License 1.1 is in `assets/fonts/OFL.txt` and registered in the app's licenses page. Flutter Material icons are bundled. There is no runtime font download or remote asset loading.

Bundled font SHA-256: `696249a2c74b39ffdef55de4df2809c5b639d3ff80d618d8160a095d2fd49dca`.

Primary references: [sqflite](https://pub.dev/packages/sqflite), [shamsi_date](https://pub.dev/packages/shamsi_date), [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi), [Vazirmatn font source and license](https://github.com/google/fonts/tree/main/ofl/vazirmatn).

Backup references: [crypto](https://pub.dev/packages/crypto), [file_picker 10.3.10](https://pub.dev/packages/file_picker/versions/10.3.10), [share_plus 12.0.1](https://pub.dev/packages/share_plus/versions/12.0.1). These execute local hashing and OS file/share workflows, with no runtime account/server requirement. The ZIP STORE profile is implemented in the repository and documented in [BACKUP_FORMAT.md](BACKUP_FORMAT.md); no general-purpose archive extraction package is used. Generated plugin registrants were updated by Flutter for retained starter platforms; this does not add supported desktop/web runtime targets.

Android retains Flutter-managed SDK values, Gradle 8.14, Kotlin 2.2.20 and Java 17 source compatibility. AGP was updated from 8.11.1 to **8.12.1**, the minimum required by the selected share plugin. Flutter builds here use Android Studio's Java 21 runtime; the unrelated system Java 26 is not compatible with this Gradle setup. The existing iOS project targets iOS 13.0. On macOS, Flutter resolves iOS plugin integration; Xcode/signing and actual iOS behavior remain to be verified. Existing example application identifiers and debug signing are development defaults; release identity/signing is not configured. Native picker access is scoped; the app adds no broad storage, photo-library, notification or network permission for backups.

Python 3 on PATH is needed only by the host backup interoperability test, which independently reads and rewrites the ZIP/JSON format. It is not an app dependency.

Phase 8 added only the Flutter SDK `integration_test` development dependency and its locked test tooling dependencies. See [Flutter's integration-test instructions](https://docs.flutter.dev/testing/integration-tests). On this host, external Gradle downloads were unavailable: the installed Gradle 8.14 distribution was copied to the workspace cache, and a local `build/phase6-gradle-home/init.d/phase8-integration.gradle` forces the integration-test plugin's AGP classpath to the app's already installed **8.12.1** instead of its **8.11.0** request. This is a build-host cache workaround, not a patch to the SDK or app's runtime behavior. A normally networked development setup can resolve the plugin's build dependencies with the documented Flutter commands.
