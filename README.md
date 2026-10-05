# Pharmacy Companion — Phase 4

An offline Flutter app for Android and iOS. The English interface supports Persian/Dari content. Inventory, manually recorded daily sales/profit, and customer debt remain independent.

Phase 4 adds manually recorded daily sales/profit, reports and charts to the existing inventory workflows. Home shows real daily figures and Record today/Edit today's record. Debt entry and backup/restore remain later phases. Only six suggested counting units are seeded; operational data starts empty.

Start in Inventory > Add item. Choose or add a counting unit and optionally enter initial stock. From item detail, use Add new batch for a delivery, or Add/Remove stock for an existing batch. When several batches are eligible, choose one explicitly. Settings > Manage units handles rename, deactivate/reactivate and deletion of unused units.

Home opens low-stock/out-of-stock product lists or expiring-soon/expired/expires-today batch lists. Needs attention links directly to the affected item or batch. Edit an item to set its minimum usable quantity and inclusive expiry-warning window. Minimum zero disables only low-stock warnings. Today's expiry stays usable until the next local day; month-only expiry uses the original calendar's month end. Alerts are inside the app only.

Use Daily Records > Add record for today or a previous Gregorian business date. Enter both amounts explicitly; zero is valid and profit can be negative. Existing dates offer editing, and deletion requires confirmation. Filter reports by Today, Last 7 days, This month (through today), or an inclusive Custom range. Switch Sales/Profit and Daily/Monthly charts; tap a point or use Previous/Next value for exact figures. The daily and monthly data lists provide accessible alternatives. Gaps remain Not recorded, and comparisons disclose coverage and unavailable baselines.

## Run and verify

Use Flutter 3.41.5 stable / Dart 3.11.3 or a compatible SDK. Initial dependency installation needs internet; the mobile app has no runtime network dependency.

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

- `lib/features/`: inventory, daily records, debtors, home and settings; domain interfaces, SQLite adapters and presentation are separated.
- `lib/core/`: schema/migrations, exact value types, validation, theme and reusable forms.
- `lib/app/`: dependency composition and ChangeNotifier application state. Inventory and daily-record controllers refresh their views and Home after commits. Resume and day changes refresh time-sensitive data (checked every 30 seconds while open). SQLite opens before data is displayed; failures show a working retry.
- `test/`: domain boundaries, real on-disk persistence/migrations, and widget checks. Fixtures never seed the app.

Money is integer AFN minor units; event timestamps are UTC; business dates are civil dates. Batch dates retain their original calendar, precision and source components. No POS, invoices, accounts, server, automatic batch selection, automatic profit calculation, or synchronization is implemented.

The database is versioned and protected by foreign keys, checks, indexes and transactional guards. Schema v4 adds durable daily save/delete receipts alongside the v3 inventory receipts. Initial product/batch/movement creation is one transaction. Date corrections cannot change stock; Undo creates a reversing movement. Report totals use BigInt to remain exact beyond a single-entry amount limit. See [data model and bounds](docs/DATA_MODEL.md). Portable backups are not yet implemented; the internal SQLite file is not the future backup format.

## Status

All 100 tests pass, formatting passes, and static analysis is clean. Checks cover real on-disk SQLite, inventory regressions, daily CRUD/retries, exact money, report coverage/ranges, monthly gaps, Home refresh and accessible narrow-screen workflows. `flutter test --dart-define=PHASE4_SCREENSHOTS=true` also saves isolated fixture screenshots in `build/phase4-review/`. The Android debug artifact is `build/app/outputs/flutter-apk/app-debug.apk`. No native-device run or iOS build is claimed; see the status log for actual commands/results.

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for exact specification coverage, verification results and limitations, and [dependencies](docs/DEPENDENCIES.md) for locked versions/licenses. Both original specifications in `explainations/` remain the source of truth.

Next planned feature work: customer debt notebook workflows. Native device/accessibility review and large-dataset benchmarks remain unverified.
