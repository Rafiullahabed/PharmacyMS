# Pharmacy Companion — Phase 8 delivery

An offline Flutter app for Android and iOS. The English interface supports Persian/Dari content. Inventory, manually recorded daily sales/profit, and customer debt remain independent.

Version **0.8.0+8** includes inventory, calendar-aware alerts, manual daily records/reports, the customer debt notebook and portable backup/restore. Layouts support narrow screens and enlarged text, with offline Persian-capable fonts and preserved tab state. Home shows actual inventory alerts, daily figures and outstanding debt. Only six suggested counting units are seeded; operational data starts empty. The [final requirement and acceptance audit](docs/FINAL_VERIFICATION.md) maps every requirement and workflow to code and verification evidence.

Settings > Appearance offers Small, Medium (default), and Large (the previous text size). Your choice is stored on this device and included in backups; system accessibility scaling still applies. Cards use soft shadows, consistent rounded surfaces and spacing, with compact button padding and 48px touch targets.

Start in Inventory > Add item. Choose or add a counting unit and optionally enter initial stock. From item detail, use Add new batch for a delivery, or Add/Remove stock for an existing batch. When several batches are eligible, choose one explicitly. Settings > Manage units handles rename, deactivate/reactivate and deletion of unused units.

Inventory list cards now have **− / +** shortcuts for exactly one unit. A single eligible batch updates immediately; multiple batches open an explicit chooser. Undo is available after saving. An item with no batch opens the new-batch form for its first delivery. Item detail retains the full quantity-entry forms. **Delete item** is available there for unused, empty items and requires confirmation. Stock history prevents permanent deletion; empty used items can be archived instead.

Home opens low-stock/out-of-stock product lists or expiring-soon/expired/expires-today batch lists. Needs attention links directly to the affected item or batch. Edit an item to set its minimum usable quantity and inclusive expiry-warning window. Minimum zero disables only low-stock warnings. Today's expiry stays usable until the next local day; month-only expiry uses the original calendar's month end. Alerts are inside the app only.

Use Daily Records > Add record for today or a previous Gregorian business date. Enter both amounts explicitly; zero is valid and profit can be negative. Existing dates offer editing, and deletion requires confirmation. Filter reports by Today, Last 7 days, This month (through today), or an inclusive Custom range. Switch Sales/Profit and Daily/Monthly charts; tap a point or use Previous/Next value for exact figures. The daily and monthly data lists provide accessible alternatives. Gaps remain Not recorded, and comparisons disclose coverage and unavailable baselines.

Use Debtors > Add customer with a name; phone and note are optional. Similar names warn and permit continuing. Search names or phone numbers and filter All/Outstanding/Settled or Archived. Customer detail offers Add debt, Record payment and explicit Pay full balance. Entries accept exact positive amounts, today/past dates and any multiline English/Persian description. Insert item name inserts only text at the selected cursor position. Tap a transaction to read, correct or delete it; deletion shows the balance effect and requires confirmation. Every correction retains an audit, and historical negative balances/overpayments are rejected. Settled customers can be archived and restored without losing history. No ledger action changes stock or daily sales/profit.

Use Settings > Portable backup and restore > Create backup, then choose a local destination. Save/share cancellation is neutral; sharing is never labelled as confirmed external saving. To restore, select an original backup ZIP, review its date and counts, then explicitly confirm replacement. An internal safety snapshot precedes the atomic replacement; Home refreshes afterward. Keep exported files private: they contain customer and financial data. See the [versioned format and recovery details](docs/BACKUP_FORMAT.md).

## Run and verify

Use Flutter 3.41.5 stable / Dart 3.11.3 or a compatible SDK. Python 3 on PATH is needed for the independent ZIP/JSON interoperability test. Initial dependency installation needs internet; the mobile app has no runtime network dependency.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test/native_app_test.dart -d <android-or-ios-device-id>
flutter run -d <android-or-ios-device-id>
flutter build apk --debug
```

For iOS, use macOS with Xcode and its command-line tools configured, then `flutter build ios --simulator --debug` and the integration command above on an iOS simulator. Configure a development team and unique bundle identifier for a physical iPhone. Exact setup and pending checks are in the [final audit](docs/FINAL_VERIFICATION.md#reproduction-and-remaining-platform-acceptance). These Apple toolchain steps cannot be verified on this Windows host. Android SDK/licensing is available here. Use Java 21 with this Gradle 8.14 project; the host's unrelated Java 26 is incompatible. Existing example bundle IDs and debug signing are for development; publishing is not configured.

## Architecture and scope

- `lib/features/`: inventory, daily records, debtors, home, settings and backup; domain interfaces, SQLite/native-file adapters and presentation are separated.
- `lib/core/`: schema/migrations, exact value types, validation, theme and reusable forms.
- `lib/app/`: dependency composition and ChangeNotifier application state. Inventory, daily-record and debt controllers refresh their views and Home after commits. Resume and day changes refresh time-sensitive data (checked every 30 seconds while open). SQLite opens before data is displayed; failures show a working retry.
- `test/`: domain boundaries, real on-disk persistence/migrations, and widget checks. Fixtures never seed the app.
- `integration_test/`: real native sqflite, independent-module persistence/restore and Flutter form journeys. Tests use unique private databases, separate from the normal user database.

Money is integer AFN minor units; event timestamps are UTC; business dates are civil dates. Batch dates retain their original calendar, precision and source components. No POS, invoices, accounts, server, automatic batch selection, automatic profit calculation, or synchronization is implemented.

The database is versioned and protected by foreign keys, checks, indexes and transactional guards. Schema v5 retains durable operation receipts and normalized phone search. Initial product/stock creation and ledger corrections are transactional; Undo creates a reversing movement. Report and global debt totals use BigInt. Backups preserve all 14 tables and preferences, including archived records, original dates, histories and retry identities, using a bounded ZIP/UTF-8 JSON format with SHA-256. Every imported row is staged, migrated and validated before confirmation. See [data model and bounds](docs/DATA_MODEL.md).

## Status

All **174 tests pass**; formatting and static analysis are clean, and the Android debug APK builds for ARM64/x86_64. The Phase 7 review covers 22 screen entries at normal and 200% text, plus keyboard, chart, mixed-language and recovery cases. Actual Android 16 emulator review exercised native restore, numeric keyboard, stock adjustment/Undo, Back behavior and enlarged-text layouts. The subsequent appearance, one-unit shortcut and deletion changes were checked with host screenshots and real SQLite tests; they have not been rerun on a native device. iOS, physical devices, spoken screen readers and native Persian IME acceptance remain pending.

`flutter test test/ui_refinement_test.dart --dart-define=PHASE7_SCREENSHOTS=true` produces the development-only gallery in `build/phase7-review/`. See [UI/UX review and reproduction](docs/UI_UX_REVIEW.md) for reviewed screens, fixture isolation, native/host distinctions and known editing limits. No fixture data ships with the app.

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for exact specification coverage, verification results and limitations, and [dependencies](docs/DEPENDENCIES.md) for locked versions/licenses. Both original specifications in `explainations/` remain the source of truth.

The representative larger-data test is `flutter test test/large_dataset_test.dart`; timings are written to `build/phase8-performance.json`. It verifies 5,000 products, 20,000 batches and 50,000 history/ledger entries plus five years of daily records, including full backup restoration. Use `python tool/package_delivery.py` only after verifying the normal `lib/main.dart` debug build; it packages source and APK with SHA-256 hashes under `build/delivery/` and excludes build caches, local paths and signing keys.

Assumptions: one user/device, AFN with two decimal places, integer stock in one unit per product, local Gregorian financial/debt business dates, no future actual entries, signed manual profit, no customer credit, zero physical stock/debt before archive, and replacement-only restoration. Batch calendar/precision remains authoritative. No synchronization or additional product module is introduced. Remaining iOS/physical-device and native accessibility acceptance is explicitly documented.
