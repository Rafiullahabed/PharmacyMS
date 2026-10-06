# Pharmacy Companion — Phase 6

An offline Flutter app for Android and iOS. The English interface supports Persian/Dari content. Inventory, manually recorded daily sales/profit, and customer debt remain independent.

Phase 6 adds portable backup and restore to the inventory, manual daily records and customer debt notebook. Home shows actual inventory alerts, daily figures and outstanding debt. Only six suggested counting units are seeded; operational data starts empty.

Start in Inventory > Add item. Choose or add a counting unit and optionally enter initial stock. From item detail, use Add new batch for a delivery, or Add/Remove stock for an existing batch. When several batches are eligible, choose one explicitly. Settings > Manage units handles rename, deactivate/reactivate and deletion of unused units.

Home opens low-stock/out-of-stock product lists or expiring-soon/expired/expires-today batch lists. Needs attention links directly to the affected item or batch. Edit an item to set its minimum usable quantity and inclusive expiry-warning window. Minimum zero disables only low-stock warnings. Today's expiry stays usable until the next local day; month-only expiry uses the original calendar's month end. Alerts are inside the app only.

Use Daily Records > Add record for today or a previous Gregorian business date. Enter both amounts explicitly; zero is valid and profit can be negative. Existing dates offer editing, and deletion requires confirmation. Filter reports by Today, Last 7 days, This month (through today), or an inclusive Custom range. Switch Sales/Profit and Daily/Monthly charts; tap a point or use Previous/Next value for exact figures. The daily and monthly data lists provide accessible alternatives. Gaps remain Not recorded, and comparisons disclose coverage and unavailable baselines.

Use Debtors > Add customer with a name; phone and note are optional. Similar names warn and permit continuing. Search names or phone numbers and filter All/Outstanding/Settled or Archived. Customer detail offers Add debt, Record payment and explicit Pay full balance. Entries accept exact positive amounts, today/past dates and any multiline English/Persian description. Insert item name inserts only text at the selected cursor position. Tap a transaction to read, correct or delete it; deletion shows the balance effect and requires confirmation. Every correction retains an audit, and historical negative balances/overpayments are rejected. Settled customers can be archived and restored without losing history. No ledger action changes stock or daily sales/profit.

Use Settings > Portable backup and restore > Create backup, then choose a local destination. Save/share cancellation is neutral; sharing is never labelled as confirmed external saving. To restore, select an original backup ZIP, review its date and counts, then explicitly confirm replacement. An internal safety snapshot precedes the atomic replacement; Home refreshes afterward. Keep exported files private: they contain customer and financial data. See the [versioned format and recovery details](docs/BACKUP_FORMAT.md).

## Run and verify

Use Flutter 3.41.5 stable / Dart 3.11.3 or a compatible SDK. Python 3 on PATH is needed for the independent ZIP/JSON interoperability test. Initial dependency installation needs internet; the mobile app has no runtime network dependency.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run -d <android-or-ios-device-id>
flutter build apk --debug
```

For iOS, use macOS with Xcode and its command-line tools configured, then `flutter build ios --simulator` or `flutter run` on an iOS simulator/device. Configure a development team for a physical iPhone. These Apple toolchain steps cannot be verified on this Windows host. Android SDK/licensing is available here. Existing example bundle IDs and debug signing are for development; publishing is not configured.

## Architecture and scope

- `lib/features/`: inventory, daily records, debtors, home, settings and backup; domain interfaces, SQLite/native-file adapters and presentation are separated.
- `lib/core/`: schema/migrations, exact value types, validation, theme and reusable forms.
- `lib/app/`: dependency composition and ChangeNotifier application state. Inventory, daily-record and debt controllers refresh their views and Home after commits. Resume and day changes refresh time-sensitive data (checked every 30 seconds while open). SQLite opens before data is displayed; failures show a working retry.
- `test/`: domain boundaries, real on-disk persistence/migrations, and widget checks. Fixtures never seed the app.

Money is integer AFN minor units; event timestamps are UTC; business dates are civil dates. Batch dates retain their original calendar, precision and source components. No POS, invoices, accounts, server, automatic batch selection, automatic profit calculation, or synchronization is implemented.

The database is versioned and protected by foreign keys, checks, indexes and transactional guards. Schema v5 retains durable operation receipts and normalized phone search. Initial product/stock creation and ledger corrections are transactional; Undo creates a reversing movement. Report and global debt totals use BigInt. Backups preserve all 14 tables and preferences, including archived records, original dates, histories and retry identities, using a bounded ZIP/UTF-8 JSON format with SHA-256. Every imported row is staged, migrated and validated before confirmation. See [data model and bounds](docs/DATA_MODEL.md).

## Status

All **152 tests pass** (120 retained plus 25 backup persistence/format and 7 backup UI tests); formatting and analysis are clean. Checks include exact round trips, malformed files, invariant rejection, repeated replacement, migration, rollback/reopening, cancellation and Home refresh. The Android debug APK builds for ARM64/x86_64. Actual Android 16 emulator checks passed offline native save/share cancellation, picker/preview/confirmed restore, app restart and corrupt-file rejection; the re-export matches the source's 14 tables. iOS and physical-device verification remain pending.

`flutter test test/backup_workflow_test.dart --dart-define=PHASE6_SCREENSHOTS=true` saves host-rendered 320px/200% text images in `build/phase6-review/`. These widget tests mock native dialogs; separate Python ZIP compatibility and Android emulator execution are recorded distinctly in the status log. No actual iPhone-to-Android transfer is claimed.

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for exact specification coverage, verification results and limitations, and [dependencies](docs/DEPENDENCIES.md) for locked versions/licenses. Both original specifications in `explainations/` remain the source of truth.

Next work: native platform acceptance, accessibility/device failure testing and large-dataset benchmarks. No synchronization or additional product module is introduced.
