# Phase 8 integration and delivery audit

Audit date: 2026-10-06. Version 0.8.0+8; SQLite schema 5; portable backup format 1. Both original specifications were read and compared with implementation and tests. Later owner requests for Small/Medium/Large sizing, immediate one-unit inventory shortcuts, confirmed unused-item deletion and compact wrapping inventory cards are retained. In particular, a single eligible batch permits the requested immediate shortcut; multiple eligible batches still require an explicit choice. The detailed stock forms retain their review and Save workflow.

This document distinguishes automated host verification from execution on Android and outstanding Apple/physical-device acceptance. See `IMPLEMENTATION_STATUS.md` for the historical phase logs. No deployment or store publication is part of this delivery.

## Requirement and workflow coverage

| Requirement / workflow | Actual implementation | Verification evidence |
|---|---|---|
| Requirements 1–3, 12; UI 1–2 | Offline `main.dart` composition, repository interfaces, four retained tabs and Home Settings. No POS, account, notification, synchronization or runtime network client. Independent inventory/daily/debt mutations. | `widget_test`, module persistence/workflow tests, native suite. Main Android manifest excludes Internet and broad storage permissions; debug tooling uses its separate debug manifest. |
| INV-01; WF-01 | `product_form`, `detail_screens`, `SqliteInventoryRepository`: Unicode names, duplicates with Continue, unit/thresholds, optional atomic opening stock, editing, zero-stock archive/restore, confirmed unused-empty deletion. | `inventory_persistence_test`, `inventory_workflow_test`, `appearance_and_shortcuts_test`; native transaction rollback and retained product identity. |
| INV-02; WF-14 | `units_screen`, `SqliteSettingsRepository`, schema guards: add/rename/delete unused/deactivate/reactivate, uniqueness, stable identity, historical unit lock. | Unit lifecycle, used deletion/rename/deactivation, duplicate and inactive-unit tests; native lifecycle. |
| INV-03–04; WF-02–05 | Separate batches and optional metadata; full Add/Remove sheets, explicit batch selection and previews, insufficient-stock checks, immutable movements and reversing Undo. Quick list shortcuts reuse repository adjustment. | Two-batch, duplicate-tap, uncertain acknowledgment, reconciliation, Undo failure and delivery tests; native 8/12 → 8/9 → 8/12 scenario. |
| INV-05; UI 7 | `dates.dart`, `expiry.dart`, reusable date controls and immutable date specifications retain original calendar/precision; range-aware production validation. | `domain_test`, `calendar_boundary_test`, `inventory_alerts_test`: leap/range/month-end/threshold boundaries, 1900–2100 round trips; date UI and backup round trips. |
| INV-06; WF-06; UI 4–5 | Shared domain status with contract-tested SQL pages/counts; usable/physical distinction; strict low-stock and inclusive expiry alerts; search, batch results, Home routes; resume/local-day refresh. | `inventory_alerts_test`, `home_inventory_alerts_test`; all alert routes, independent day clock, errors, archived/empty/no-expiry exclusions. |
| FIN-01; WF-07–08 | Exact minor-unit manual sales/signed profit, unique civil date, future rejection, normalized digit entry, conflict handling, edit/delete and durable receipts. | `daily_records_test`, `daily_workflow_test`; native money persistence and form entry. Zero and absent data remain distinct; finance mutations do not touch stock/debt. |
| FIN-02; WF-09; UI 4, 8 | Inclusive ranges, BigInt totals, coverage, missing-day gaps, monthly aggregation, optional valid comparison, separately scaled trends and accessible exact data. | Daily domain/workflow and UI tests: losses below zero, zero/no-data baseline, exact values, month/custom boundaries, responsive chart and selection. Five-year report in large-data check. |
| DEBT-01; WF-10 | Customer name, optional raw phone/note, duplicate suggestion, normalized search, active/outstanding/settled/archive views and Home total. | `debt_notebook_test`, `debt_workflow_test`; Persian/absent/leading-zero phone, duplicate identities, settled archive/restore. Native Persian form. |
| DEBT-02; WF-11–13 | Plain-text descriptions, independent debt/payment amounts, Pay full balance, chronology/sequence, previews, edit/delete and immutable correction audit; offline names inserted at cursor. | 500+300−200=600, overpayment/backdate rejection, partial/settled payments, cursor replacement, audit and cross-module tests; native correction/reopen. |
| BACKUP-01–02; WF-15–16 | `BackupCodec`, bounded ZIP, `backup_integrity`, staging/migrations/safety snapshot and atomic replacement; scoped native file port and honest completion labels. All 14 tables, preferences and receipts included. | `backup_persistence_test`, `backup_workflow_test`, independent Python interoperability, native real-SQLite restore, large-data round trip. Separate native picker/share checks below. |
| Requirements 8; UI 11–12 | Schema migrations 1–5, FK/checks/guards, immutable history/receipts, transactional persistence; guarded dirty forms, saving/error/Retry and restore recovery. | `persistence_test`, populated daily/debt migration tests, backup old-schema migration and rejection tests, injected late failures/lost acknowledgments, native rollback/reopen. |
| Requirements 9; UI 3, 13–14 | Bundled Vazirmatn/Material icons, 48px targets, non-color status, composed text sizing, keyboard-aware forms, safe areas, reduced motion, content-level direction, accessible chart data. | Existing 22-screen gallery, contrast/semantics/touch tests, narrow/200%/landscape checks. Native and remaining manual accessibility boundaries below. |
| Requirements 9: data volume | Indexed/paged repository queries and lazy lists; 5,000 products, 20,000 batches, 40,000 stock movements + 10,000 ledger rows, 1,000 customers, 1,825 daily records. | `large_dataset_test.dart`: real on-disk SQLite with active guards, normalized search/counts, independent changes, integrity, backup/staging/replacement/reopen. Timings in `build/phase8-performance.json`. |
| Requirements 10–11 | Complete source/lockfile, migrations/tests, Android/iOS instructions, portable format documentation and this audit. | Acceptance-scenario mapping below; actual commands/results recorded in implementation status. |

## Acceptance scenario mapping

| Requirements §10 scenario | Focused automated evidence |
|---|---|
| 1–4: units/product, two dates, explicit removal, rejection, new delivery | `inventory_persistence_test.dart`, `inventory_workflow_test.dart`, native integration persistence test |
| 5–6: low-stock/expiry boundary, today/next day, zero/no expiry | `inventory_alerts_test.dart`, `calendar_boundary_test.dart`, Home route/lifecycle tests |
| 7: full/month dates, two calendars, leap years, preservation | `domain_test.dart`, `calendar_boundary_test.dart`, inventory date UI and backup round-trip tests |
| 8: expired removal without financial impact | Inventory persistence/workflow and gallery stock-commit independence tests |
| 9–10: daily manual values, edit/delete, missing vs zero | Daily repository/workflow tests and native entry/persistence |
| 11: Persian customer, 500+300−200=600 | Debt repository/workflow and native integration persistence test |
| 12: product-name suggestion is plain text | Debt workflow cursor-replacement and unchanged amount/inventory/daily tests |
| 13: overpayment and invalid backdated correction | Debt repository/workflow plus native chronology rejection |
| 14: complete cross-platform-format backup and invalid replacement | Backup tests and Python ZIP/JSON interoperability; native same-platform replacement. Actual iPhone↔Android transfer remains unverified. |
| 15: stable used unit identity | Inventory/unit lifecycle tests and native lifecycle |
| 16: duplicate Save, interruption, relaunch, cancellation | Durable-receipt/fault-injection tests, native repeated operation/rollback/reopen; native force-stop/cold-start checks recorded separately |
| 17: airplane-mode iOS/Android workflows | Android execution only; iOS toolchain unavailable on this Windows host |
| 18: small/large text, Persian, keyboard/back, empty/errors | Existing responsive gallery and workflow tests; native checks and explicit remaining limits below |

## Reproduction and remaining platform acceptance

Host tests use isolated SQLite FFI databases. Native integration uses real sqflite in uniquely named private test directories and never opens the user's normal database. Test fixtures exist only in `test/`, `integration_test/` and ignored `build/`. No sample operational data enters `lib/main.dart` or shipped assets.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter test integration_test/native_app_test.dart -d <android-or-ios-device-id>
flutter test test/large_dataset_test.dart --reporter expanded
```

Optional `--dart-define=PHASE8_LARGE_FIXTURE=true` on the large-data test writes `build/phase8-large-fixture.zip` for a **disposable test installation only**. Restoring any fixture replaces that installation's current data. Host timing results are not a claim of native frame-time certification; debug emulator performance is not physical-phone release performance.

The owner initially selected Odevio, then reported failures on **Codemagic**. Follow [CODEMAGIC.md](CODEMAGIC.md) for the corrected Dart import and checked-in cloud workflows; [IOS_ODEVIO.md](IOS_ODEVIO.md) retains the earlier alternative. The supplied Android error is fixed locally and the APK rebuild passes. The iOS excerpt lacks its underlying error, so an iOS success is not claimed. Apple membership/signing/device setup remains outstanding for an installable IPA. Unsigned device compilation and simulator preview are separate from physical iPhone installation. No local Xcode/fastlane command was run.

Remaining manual acceptance must exercise iOS edge-back/safe areas, native file Save/Share/picker cancellation and return, iPhone↔Android backup transfer, spoken VoiceOver/TalkBack traversal/announcements, native Persian IME composition/selection handles, physical low-storage/interrupted-power behavior and release-mode performance on representative phones. Mixed-script text is stored exactly; multiline editing follows the caret's paragraph base direction, so inactive opposite-direction paragraphs may temporarily follow that alignment. Saved read-only paragraphs have independent direction. Do not interpret host cursor-insertion tests as certification of every native IME.

Example app identifiers and development signing remain. Android/iOS use custom pharmacy launcher artwork; desktop/web starter icons are unchanged. No release signing or store publication was performed. No essential workflow needs a server.

## Actual Phase 8 results

- Full host regression: **175 passed** in 5m10s (`build/phase8-all-tests.log`), including the larger-data round trip and regenerated host visual galleries.
- Android 16/API 36 x86_64 integration: **2 passed** in 41s on the isolated emulator in airplane mode (`build/phase8-native-integration.log`). Tests used real native SQLite and uniquely named private databases, not the app's user database. Flutter text entry verifies stored Persian text, not native Persian keyboard composition.
- Formatting: **95 Dart files, zero changes**. Static analysis: **No issues found** (`build/phase8-final-analysis.log`).
- Normal `lib/main.dart` Android debug build: **passed**, ARM64/x86_64, version 0.8.0+8, Java 21/Gradle 8.14 (`build/phase8-android-build.log`). Development signing only. The SDK integration-test plugin used an isolated Gradle-cache AGP override, documented in `DEPENDENCIES.md`; the SDK/project dependency sources were not rewritten.
- Manual normal-app Android check: offline empty Home; native English keyboard and keyboard-dismiss Back; create/select a unit, save a product and a Gregorian-dated 8-unit batch. Screens/semantics are retained in `build/phase8-review/`. The interrupted walkthrough did **not** finish a new Phase 8 picker/share or manual two-batch review. Earlier Phase 6/7 native checks remain historical evidence; automated latest native SQLite tests cover two batches, Undo and restore.
- Windows larger-data timings: cold reopen 19ms, inventory page 249ms, Persian search 231ms, dashboard 482ms, five-year report 92ms, integrity 3.8s, export 8.7s, staged validation 44.6s, replacement 27.9s. Backup size 25,581,236 bytes. Distribution: four batches/product and ten ledger entries/customer; not a benchmark of one unusually large product/customer. Details: `build/phase8-performance.json`.

The source/APK delivery packager is `tool/package_delivery.py`. Its output under `build/delivery/` includes SHA-256 checksums. The source includes fixtures only as test code, not operational app data. iOS delivery is explicitly blocked as described above, so the application is not labelled fully verified on both platforms.
