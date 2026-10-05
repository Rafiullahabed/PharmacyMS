# Dependencies and offline assets

Resolved with Flutter 3.41.5 / Dart 3.11.3 on 2026-10-05. Exact direct/transitive versions and hashes are in `pubspec.lock`. Dependencies were selected against the installed SDK; newer incompatible versions were not forced.

| Direct dependency | Locked version | License | Purpose |
|---|---|---|---|
| Flutter SDK | 3.41.5 | BSD-3-Clause | UI, ChangeNotifier, built-in platform navigation |
| sqflite | 2.4.2+1 | BSD-2-Clause | Native Android/iOS SQLite |
| path | 1.9.1 | BSD-3-Clause | Database path joining |
| uuid | 4.6.0 | MIT | Secure random local UUIDs |
| shamsi_date | 1.1.1 | BSD-3-Clause | Gregorian / Solar Hijri conversion |
| cupertino_icons | 1.0.9 | MIT | Existing Flutter starter icon dependency |
| flutter_test | SDK | BSD-3-Clause | Domain, repository and widget tests |
| flutter_lints | 6.0.0 | BSD-3-Clause | Static analysis |
| sqflite_common_ffi | 2.4.0+3 | BSD-2-Clause | Real SQLite host tests (development only) |

Native mobile SQLite is supplied through sqflite's Android/Darwin plugins. The host test implementation uses sqlite3 native assets, which may be downloaded on the first development test run. This is a build/test dependency, not an app runtime network dependency.

The bundled `assets/fonts/Vazirmatn.ttf` variable font supports Latin and Persian text. Its full SIL Open Font License 1.1 is in `assets/fonts/OFL.txt` and registered in the app's licenses page. Flutter Material icons are bundled. There is no runtime font download or remote asset loading.

Bundled font SHA-256: `696249a2c74b39ffdef55de4df2809c5b639d3ff80d618d8160a095d2fd49dca`.

Primary references: [sqflite](https://pub.dev/packages/sqflite), [shamsi_date](https://pub.dev/packages/shamsi_date), [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi), [Vazirmatn font source and license](https://github.com/google/fonts/tree/main/ofl/vazirmatn).

Android uses the existing Flutter-managed SDK values and Java 17 source compatibility. The existing iOS project targets iOS 13.0. On macOS, Flutter resolves the iOS plugin integration; Xcode/signing and actual device behavior remain to be verified. Existing example application identifiers and debug signing are development defaults; release identity/signing is not configured.
