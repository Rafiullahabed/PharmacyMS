# Phase 7 UI/UX review

Reviewed on 2026-10-06 against the complete `Pharmacy_App_UI_UX_Workflows.md` and requirements document. App version: 0.7.0+7; database schema: 5; backup format: 1. This pass extends the existing presentation layer. Stock, calendar eligibility, money, ledger chronology, correction audit and backup validation rules are unchanged.

## Screens and workflows

The host gallery exercises all 22 entries below at 390×844 / 100% text and 320×640 / 200% text, including scrolling beyond the initial viewport. Screenshots were inspected directly; a successful build alone was not used as visual evidence.

| Specification | Screens reviewed | Refinement / retained behavior |
|---|---|---|
| UI §§2–4 | Home, navigation shell | Consistent alert rows; separate semantic sections; honest empty state; compact heading at large text; all four tab names remain visible in two rows when necessary. Search/filter state survives tab changes and Home read failure. Settings remains available. |
| UI §5; WF-01–02, WF-06 | Inventory, batch expiry results, product detail, batch detail, product form, batch form | Search and filter headers scroll with results instead of clipping at large text; selected chips keep their status icon and a separate check. Long names wrap. Physical quantity remains visible whenever it differs from usable quantity. |
| WF-03–05 | Stock adjustment sheet, stock history | Explicit batch choice and identity; current/after quantity preview; quantity focus after selection; optional note expansion; reachable Save with keyboard; dirty Back/Close guard; Undo still creates a reversal. |
| UI §7 | Batch date controls and Solar Hijri month picker | English labels outside dropdowns; readable Year/Month/Day controls; picker omits day for month-only precision; original calendar/precision retained; received date uses the shared business-date input. |
| UI §8; WF-07–09 | Daily Records/reports, daily detail, daily form | Exact negative values, visible below-zero trend, larger axes and measured label gutter; exact selected values and accessible daily/monthly lists. Missing days remain Not recorded. |
| UI §9; WF-10–13 | Debtors, customer detail, customer form, ledger detail, payment form, correction form, correction history | Long customer names wrap; clearer transaction dates; prominent current/resulting balance; full descriptions and audit remain available; local event times are readable. Add debt uses the same refined ledger form and retained workflow tests. |
| UI §10; WF-14 | Settings, units, unit form | Consistent route titles, controls, form errors and spacing; existing unit lifecycle retained. |
| UI §10; WF-15–16 | Backup/restore, preview and replacement confirmation | Clear progress and replacement warning; scrollable preview/confirmation; local timestamps; unchanged neutral cancellation and honest save/share status. |
| UI §§11–13 | Shared forms, dialogs, loading, errors and recovery | Adaptive title heights, 48px controls, keyboard-aware form footer, bounded/scrollable short viewports, live error/preview semantics and no-motion loading/route transitions. |

Typography uses the bundled offline Vazirmatn font. English labels/navigation remain LTR; search/input direction responds to the content without rewriting text or changing selection. Multiline editing follows the caret's paragraph; complete read-only descriptions render each paragraph in its own direction. Money/phone/date controls remain LTR. Helpers and validation messages remain LTR even beside Persian input.

## Development-only visual data

`test/support/visual_fixture.dart` writes to an isolated temporary SQLite database. It includes separate today/month-only/expired medicine batches, a long Persian product name, no-expiry stock, an archived item, recorded zero and negative profit with missing days, duplicate customer names and an absent phone, mixed descriptions, a correction audit, and the 500 + 300 − 200 = 600 debt scenario. It is never imported by `lib/` or seeded into production.

Generate the host gallery and an optional portable fixture ZIP:

```sh
flutter test test/ui_refinement_test.dart --dart-define=PHASE7_SCREENSHOTS=true
```

Artifacts are ignored development files in `build/phase7-review/`. Useful examples: `home-390-1x.png`, `inventory-320-2x.png`, `stock-before-after-2x.png`, `solar-hijri-month-picker-2x.png`, `chart-exact-loss-2x.png`, `monthly-accessible-data-2x.png`, `customer-landscape-keyboard-2x.png`, `mixed-paragraphs-2x.png`, and `restore-confirmation-2x.png`. The fixture ZIP is only for a disposable test installation: restoring it replaces that installation's data.

## Actual checks

- Real SQLite-backed host gallery and interaction checks cover the 22 screen entries, stock choice/preview/commit/Undo, unchanged financial/debt balances, search retention/recovery, month precision, restore cancellation and exact chart values.
- Android 48px touch-target and labelled-target guidelines are checked on each gallery screen at normal text. Dedicated checks cover live errors, loading, reduced motion and semantic actions. Actual text/background palette pairs pass a 4.5:1 contrast check. These automated checks are not a spoken screen-reader audit.
- Additional layout/interaction checks use 568×320 landscape with a 120px simulated keyboard inset and 200% text. Persian selection/cursor replacement preserves the exact stored string. Read-only multiline paragraph direction is checked separately.
- A dedicated Android 16/API 36 x86_64 emulator ran the debug APK in airplane mode. Native file selection, restore preview and explicit replacement were exercised using the development fixture. Home refreshed with its real persisted amounts. Native stock adjustment exercised explicit batch choice, quantity entry with the Android keyboard, keyboard dismissal, dirty Back/Cancel, commit and Undo. Screens and Android accessibility nodes were inspected. The final build was also reviewed at system font scale 2.0 and a 320dp-wide viewport; this caught and prompted fixes for clipped list filters and nonlinear text scaling. Home, Inventory, Debtors, customer detail and payment screens were rechecked; Pay full balance showed 600→0 and discard retained the original debt. The disposable emulator was removed after review; artifacts remain.
- Android debug APK compilation covers ARM64 and x86_64. Full-suite counts, formatting, analysis and final build results are recorded in `IMPLEMENTATION_STATUS.md`. The final shared Daily Records loading-state integration was made after emulator shutdown; it is covered by host checks and compilation, not an additional native run.

## Requested styling and inventory follow-up

Settings now offers persisted Small, Medium (default), and Large (previous base size). System text scaling still applies. Shared cards use softer shadows, rounded borders, accent headers and consistent interior spacing; compact control padding retains 48px touch targets. Inventory cards show only minus/plus actions for one unit, while detail screens keep their full stock forms. Multiple eligible batches require explicit selection with identity, dates and before/after quantities. Unused empty items have confirmed deletion; used empty items can be archived with their history retained.

Directly inspected the updated host screenshots for all three Settings sizes, Medium Home/Inventory/Daily Records/Debtors, inventory card controls, the batch chooser at 320px/200% with Large selected, and item deletion confirmation. Production shadows and offline fonts render in these tests. The existing 22-screen gallery and layout/accessibility checks also pass with the updated theme. Seven new tests exercise real preference persistence, backup restoration, exact one-unit changes, duplicate taps, Undo/retry, batch choice, deletion rollback and history restrictions. Full-suite results and final-source checks are in `IMPLEMENTATION_STATUS.md`.

Generate the additional screenshots with:

```sh
flutter test test/appearance_and_shortcuts_test.dart --dart-define=APP_STYLE_SCREENSHOTS=true
```

Images are in `build/style-review/` and use isolated development fixtures. These follow-up changes were **not rerun on a native emulator or device**; the earlier native review above applies to the earlier build.

## Concrete limits

No iOS build, simulator, physical phone, spoken VoiceOver/TalkBack session or native Persian IME composition session was available in this review. Native Android keyboard checks used numeric input; Persian typing/selection checks use Flutter's test input connection. A multiline editable field has one paragraph base direction at a time: it follows the caret's paragraph, so punctuation/alignment in an inactive paragraph of the other direction can temporarily follow that base direction. Saved read-only paragraphs render independently and the original text is preserved. A dedicated bilingual editor would require further editing/IME validation.

Native screen-reader traversal/announcements, Persian IME composition and selection handles, iOS back-swipe/safe-area behavior, real device interruption/low storage, physical cutouts/tablets and the specified large-data/performance targets remain acceptance work. Reduced motion was tested via Flutter accessibility settings, not a native OS toggle. These limitations are not represented as passed by screenshots or compilation.
