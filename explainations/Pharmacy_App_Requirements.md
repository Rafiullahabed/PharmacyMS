# Pharmacy Companion — Complete Product and Implementation Requirements

Version: 1.0 | Language: English | Target: Flutter mobile app for iOS and Android

## 1. Instructions for the implementing Codex agent

Build a complete, working application using this document together with `Pharmacy_App_UI_UX_Workflows.md`. Read both before implementing. This document defines behavior and data integrity; the companion defines screens, interaction, and visual quality. Implement real local persistence, validation, reports, backup, and restore—not a collection of mock screens. Do not introduce a POS or turn this simple application into an enterprise pharmacy system.

The confirmed owner decisions below are mandatory. Detailed edge-case policies marked “implementation default” resolve unspecified behavior without claiming that the owner explicitly requested them. Apply these defaults unless the owner changes them. If a material contradiction appears, preserve the confirmed decisions and ask one targeted question; do not silently broaden scope.

## 2. Purpose and confirmed scope

The owner operates a retail pharmacy and wants to know what is available, what needs replenishment, what is approaching expiration, how manually recorded daily sales/profit change, and how much each customer owes.

- One person uses the app on one phone. The current phone is an iPhone; both iOS and Android must work well.
- Flutter/Dart application, fully functional offline from first launch.
- English interface, including navigation, labels, validation, and help. User-entered Persian/Dari names and notes must work correctly.
- No account, login, password, PIN, biometric gate, roles, or server requirement.
- Future connection to the owner's existing website should be architecturally possible; no website integration or synchronization is required in version 1.
- Three independent operational modules: inventory; manually entered daily sales/profit; customer debt ledger.
- In-app alerts only. Do not request push/local-notification permission or schedule background notifications.
- Export and restore a complete portable backup file across iOS and Android.
- Gregorian and Solar Hijri/Jalali calendar support for item/batch dates. Solar Hijri is not the Islamic lunar calendar.
- Beautiful, carefully finished mobile UI with simple, short workflows.

## 3. Critical separation rules

| Action | Inventory impact | Daily record impact | Debt impact |
|---|---|---|---|
| Manually add/remove batch quantity | Change selected batch only | None | None |
| Save daily sales/profit | None | Save entered figures | None |
| Add customer debt | None | None | Increase amount owed |
| Record customer payment | None | None | Decrease amount owed |
| Insert item name into debt description | None | None | No monetary change by itself |

There is no checkout, sales invoice, shopping cart, per-item sale, automatic sales/profit calculation, automatic batch allocation, or automatic inventory deduction from debt. Inventory reduction does not prove that an item was sold: it can represent any manual removal. Do not label stock movements as financial sales or infer clinical consumption.

## 4. Inventory requirements

### INV-01 — Products

Support medicines, hygiene products, infant formula, medical equipment, and other pharmacy goods in the same inventory.

Product fields:

| Field | Rule |
|---|---|
| ID | Stable locally generated UUID |
| Name | Required, trimmed Unicode text; English/Persian supported |
| Unit | Required reference to a user-managed unit |
| Minimum stock | Nonnegative whole number; default 0 |
| Expiry warning days | Nonnegative whole number, explicitly shown and editable per product; suggested default 30 |
| Category | Optional simple text or lightweight classification; never required to add stock |
| Notes | Optional multiline text |
| Archived state | Preserve records and history |
| Created/updated timestamps | Managed internally |

Product names need not be unique: different strengths or brands may be similar. Show a possible duplicate warning with an option to continue. Encourage recognizable names such as medicine name plus strength; do not implement a medical catalog or require medical metadata.

Product creation may include an optional first batch. A product without a batch is valid and has zero stock. New installations must contain no sample inventory, debt, or financial records.

### INV-02 — User-managed units

Settings must allow adding, renaming, removing unused units, and deactivating used units. Suggested initial units: Strip, Bottle, Box, Piece, Pack, Tube. They are editable conveniences, not a fixed enumeration.

- Each product uses one counting unit. Example: record a medicine entirely in strips, even if supplies arrive in boxes.
- Version 1 uses nonnegative integer quantities; no fractional dispensing or conversion hierarchy.
- Do not automatically convert box/strip/tablet quantities.
- Unit labels are required; avoid duplicate active names ignoring surrounding whitespace/case.
- Rename updates the label consistently; unit identity stays stable.
- Used units cannot be destructively deleted; deactivate them instead. Existing products retain their unit and remain operable; inactive units are unavailable for new selection. Reactivation is allowed.
- Implementation default: lock a product's unit once any stock history exists. Explain this and offer creating a new product for a genuinely different unit. Never relabel historical quantities into a different physical unit silently.

### INV-03 — Batches / deliveries

A product can have multiple deliveries with different production and expiration dates. Keep them separate even when dates happen to match. Display aggregate product quantities and individual batch quantities.

Batch fields: UUID, product ID, optional batch/lot label, required received date (default today), current quantity, optional production date specification, expiry mode/specification, optional notes, created/updated timestamps, archived state.

Generate a readable local batch label if none is supplied. Batch numbers are not mandatory. Zero-stock batches remain visible in history and an optional “Show empty batches” view.

### INV-04 — Explicit manual quantity changes

Provide prominent Add stock and Remove stock actions.

- Add stock lets the user choose an existing batch or create a new batch. Present “Different dates? Add a new batch.”
- Never merge a new delivery into a previous batch automatically.
- Remove stock requires the user to choose a batch when several eligible batches exist. Do not select or allocate by earliest expiry, newest delivery, or any hidden rule.
- When there is exactly one eligible batch, display it explicitly in the adjustment sheet; it is unambiguous and must remain visible before saving.
- A batch-detail action already identifies the user's selected batch.
- Enter a positive whole quantity. Show current quantity and resulting quantity before saving.
- Block removal greater than that batch's available quantity. Do not silently split removal across batches.
- An optional note is available without slowing routine adjustments.
- Save quantity and movement atomically; disable duplicate submission.
- Refresh product totals, batch totals, and alerts immediately after success.
- Keep a movement history: batch, add/remove/opening/reversal kind, quantity delta, timestamp, optional note, and resulting quantity.
- Preserve immutable movements; corrections use reversing movements rather than erasing history. Offer Undo immediately after an adjustment. Reject any reversal that would make stock negative, and explain how to correct manually.
- Removing expired stock is allowed because it may represent disposal or correction. Label it as stock removal, not a sale.
- Never allow stock below zero. Product stock is derived from batches; no independent editable product total.

### INV-05 — Dates and expiration precision

Support three explicit expiry modes per batch:

1. Full date.
2. Month and year only.
3. No expiry date (for goods that have none).

Allow Gregorian or Solar Hijri input for each production/expiry date independently. Production date is optional and may also be month/year. Keep original calendar, precision, and supplied components; do not lose them after converting dates internally.

- Use a tested calendar-conversion implementation with leap-year coverage.
- Canonical full dates are date-only Gregorian values, not UTC instants that shift when time zones change.
- For expiry month/year, use the last day of the entered month in its original calendar, then convert to the canonical date. Explain this UI convention. Display the original month/year with a “Month only” indicator; do not pretend the user supplied an exact day.
- A full expiry date is considered expired the next local calendar day. If expiry equals today, show “Expires today.” This is an inventory display convention, not clinical advice.
- Production month/year describes a date range. Reject dates only when production is unambiguously after expiry; do not invent day-level precision. Full production after full expiry is invalid; overlapping partial-date ranges may be saved.
- No-expiry batches have no countdown and never appear in expiry alerts. They still count for availability and low-stock checks.
- Calendar switching must preserve the date. For partial dates, preserve the original calendar/month as authoritative; do not convert a month-only value into another calendar's month-only value silently. Show an equivalent date range, or require explicit re-entry to change the original calendar.
- Validate actual month lengths and leap years for both calendars. Never silently normalize an impossible date.
- Refresh computed expiry states on app launch, resume, and local day rollover. Tests must use a controllable clock.

### INV-06 — Alerts and inventory views

For each product show physical stock = sum of all batch quantities and usable stock = sum of non-expired batch quantities, including no-expiry batches. If the two differ, clearly show both; never hide expired quantities.

- Low stock: usable quantity is strictly less than minimum stock. Equal to threshold is not low. Minimum 0 disables low-stock warnings; zero stock can still appear under Out of stock.
- Expired: positive-quantity batches whose effective expiry is before today.
- Expiring soon: positive-quantity batches with 0 <= days until expiry <= product warning days. Threshold is inclusive.
- Zero-day warning means show “Expires today,” not “disabled.”
- Zero-quantity batches do not contribute expiry warnings. Archived records are excluded from active alerts.
- One product may be low stock while also containing expired or near-expiry batches; these states must not overwrite each other.
- Provide searchable inventory and filters: All, Low stock, Out of stock, Expiring soon, Expired. Expiry views expose affected batches and dates, not only the product's nearest date.
- Product list counts and batch alert counts must be labeled consistently.
- Search product names in English and Persian; normalize Arabic/Persian yeh and kaf for matching without modifying stored text.
- Batch detail and product detail must include quantity history and date status.

## 5. Daily sales and profit records

### FIN-01 — Manual daily entry

The owner calculates figures outside the app. Store them as supplied; profit is not inferred from products, debts, purchases, expenses, or sales.

Fields: UUID, unique local business date, total sales in AFN, manually entered profit in AFN, optional note, created/updated timestamps.

- One record per local calendar day. Default to today; allow previous dates. Implementation default: reject future dates.
- If a date already exists, open its record for editing or explain the conflict; never create a duplicate or add the amounts together automatically.
- Both amounts must be explicitly entered; zero is valid.
- Sales must be nonnegative. Implementation default: signed profit is allowed for a reported loss; label clearly. Do not impose a profit <= sales validation because these are externally estimated figures.
- Store money as exact minor-unit integers (100 minor units per AFN), not binary floating point. Accept up to two decimal places, with separators handled safely.
- Display AFN consistently. Edits replace that day's figures; they do not append another sale.
- Allow confirmed deletion with immediate report refresh.
- Show “Not recorded” for a missing day, distinct from a recorded zero.

### FIN-02 — Reports and charts

- List daily records newest first; open any record to view/edit.
- Date filters: Today, Last 7 days, This month, Custom range (inclusive).
- Show total recorded sales, total recorded profit, and days recorded.
- Show daily sales and profit trends with readable labels and exact values on selection. Negative profit must be represented below zero.
- Show monthly aggregates for longer-term comparison.
- Missing dates are gaps/unrecorded, never fabricated zero entries. Monthly sums include only recorded days and disclose coverage.
- A period comparison, if displayed, uses an equal-length previous period and discloses missing entries. If prior total is zero or there is no comparable data, show “Not available” instead of dividing by zero or inventing a percentage.
- Dashboard/report copy must make clear that profit was entered manually. Do not describe it as calculated net profit.

## 6. Customer debt notebook

### DEBT-01 — Customers

Fields: UUID, required name, optional phone stored as text, optional note, archived state, created/updated timestamps. Support Persian/Dari text, mixed scripts, spaces, and leading-zero phone numbers. Phone is never mandatory. Do not require address, identity documents, or email.

Names may duplicate; warn gently and use optional phone/notes to distinguish. Search name and phone. Show outstanding balance and latest activity. Provide All / Outstanding / Settled filters and total outstanding for active customers.

### DEBT-02 — Ledger

Each customer has dated entries of type Debt or Payment, with a positive AFN amount, multiline description, UUID, created/updated timestamps, and a deterministic ordering key.

- New debt increases the amount owed; payment reduces it.
- Descriptions contain whatever the owner writes about goods, materials, services, or cash. No structured cart is required. Description is strongly encouraged but not mandatory.
- No separate cash-loan module is needed: free text can explain the reason.
- Default date to today; allow past dates. Implementation default: no future-dated actual transactions.
- Multiple entries per day are allowed. Show chronological running balances in history and newest-first viewing where helpful.
- Customer balance = sum of debt amounts - sum of payment amounts; derive it from the valid ledger, not a separately editable balance.
- Opening balances are entered as an ordinary debt entry with an “Opening balance” note.
- Optional item-name suggestions operate entirely offline and insert plain text at the cursor. The user can ignore them or type anything. They do not reserve stock, create product links, or calculate money.
- Recording a payment must not change daily sales/profit.
- Implementation default: no customer-credit/overpayment feature. Reject payments greater than the applicable outstanding amount. Backdated edits and deletions must validate chronological running balances as well as the final balance; do not allow any historical balance below zero.
- Allow entry edits and confirmed deletions for mistakes; recompute the whole affected ledger transactionally. Preserve an internal correction audit sufficient to understand changes.
- At equal dates use a stable persisted sequence, not a changing screen order. Show before/after balance when editing/deleting.
- Keep settled customers and history. Block archiving a customer with outstanding debt; allow restoring an archived settled customer.

## 7. Backup and restoration

### BACKUP-01 — Portable backup

- Export one complete file through the native iOS/Android file/share workflow; user chooses a destination. Core export must work offline. A user-selected cloud destination may independently require internet.
- Include products, units (including inactive ones), batches, date specifications, stock movements, daily records, customers, ledger/correction history, and app preferences needed to restore behavior.
- Use a documented, versioned, cross-platform format, e.g. a ZIP containing manifest.json and UTF-8 data.json. Include format/schema version, app version, export timestamp/timezone, counts, and a payload checksum for corruption detection. A checksum is not encryption or authentication.
- Never depend on device-specific absolute paths. Unicode, date precision, IDs, money precision, and references must survive round-trip restore.
- Build from a consistent database snapshot. Do not export a live SQLite file without correctly handling transactions/WAL.
- Suggested filename: pharmacy-backup-YYYYMMDD-HHmmss.zip.
- No password requirement or password gate. Do not silently send backups to a server. Clearly state that the exported file contains customer/financial data and should be kept privately.
- Show last successfully created backup time; do not call a cancelled or failed export “saved.” Where the platform only confirms handoff to a share sheet, state that the file was prepared/shared rather than claiming a confirmed external save.

### BACKUP-02 — Restore

- User selects a file using the system picker.
- Validate format, schema compatibility, checksum, file/expanded size limits, dates, money, references, duplicate IDs, and balance/quantity invariants before changing live data. Prevent ZIP path traversal and unsafe extraction.
- Show backup date, version, record counts, and a clear explanation: restore replaces current data; it does not merge it.
- Require explicit confirmation. Create an internal safety snapshot before replacement and allow rollback if restoration fails.
- Import into a temporary database, validate/migrate, then atomically replace live state. Reopen repositories and refresh all screens/derived alerts.
- A corrupt, truncated, incompatible, cancelled, or failed restore must leave current data intact. Reject newer unsupported backup versions with an actionable message.
- Support backups created on either platform restoring on the other. Reimporting the same backup replaces state without duplication.
- Do not put a destructive “Reset all data” feature in version 1 unless requested.

## 8. Architecture and local data

Implementation direction (engineering defaults, not a requirement to use a particular package): use a relational SQLite database with migrations and foreign keys; Drift is an acceptable wrapper. Keep presentation, state/application logic, domain rules, and repository/data access separate. Use one consistent Flutter state-management approach; avoid unnecessary frameworks.

Suggested entities and relationships:

| Entity | Relationships / key constraints |
|---|---|
| Unit | One unit to many products; stable ID |
| Product | Unit FK; one product to many batches |
| Batch | Product FK; quantity >= 0; original date specifications retained |
| StockMovement | Batch FK; append-only signed delta; transactional with batch quantity |
| DailyRecord | Unique business date; exact sales/profit money |
| Customer | One customer to many ledger entries |
| LedgerEntry | Customer FK; Debt/Payment; positive amount; stable date/sequence order |
| CorrectionAudit | Previous/new ledger values and change metadata |
| AppSettings | Versioned preferences, last backup metadata |

- Store event timestamps in UTC; store business dates as date-only values. Calculations use the device's current local date. Do not shift a saved daily record date when timezone changes.
- Product/batch totals must reconcile with movement history; ledger balances must reconcile with entries.
- Use transactions for multi-record mutations, corrections, and restoration. Handle double taps and interrupted writes safely.
- Protect referential integrity. Product/batch records with history are archived, not destructively removed. Implementation default: require zero physical stock before archiving a product/batch. Unused empty records may be deleted after confirmation.
- Include archived data in backups. Exclude it from active totals unless a history view explicitly includes it.
- Bundle fonts/icons needed for offline display. No runtime web fonts, AI calls, analytics, remote assets, or network dependency for core tasks.
- Keep stable UUIDs and created/updated timestamps and repository interfaces so a future API adapter can be added. Document where future synchronization/conflict handling would fit; do not implement fake sync, endpoints, or account screens now.
- Select compatible stable dependencies at implementation time; document versions, licenses, and platform setup. Do not promise iOS build verification without a macOS/Xcode environment.

## 9. Nonfunctional requirements

- Usable offline after a cold start, force-close, restart, and device reboot.
- Save operations acknowledged only after durable local success; errors preserve entered form values.
- Smooth search, scrolling, and adjustments with at least 5,000 products, 20,000 batches, and 50,000 combined history/ledger records as a performance test target. Use indexed queries and lazy lists; avoid loading all history for every screen.
- Accessible text scaling, screen-reader labels, adequate contrast, and touch targets at least 48 logical pixels.
- Respect safe areas, notches, keyboard insets, iOS back gestures, Android back behavior, and platform file pickers/share sheets.
- English app layout remains LTR; Persian content uses correct text direction at the field/content level.
- No financial/customer details in production diagnostic logs.
- All user-visible actions must work; no placeholder controls, fake charts, fabricated data, or successful-looking failed saves.

## 10. Acceptance scenarios

1. Create a Strip unit and a product with minimum 10. Add batch A with 8 and batch B with 12, different expiry dates. Total physical stock is 20; both batches remain separate.
2. Manually select B and remove 3. B becomes 9, A remains 8, total 17. No financial or debt record appears.
3. Attempt to remove 10 from B. Reject without changing any record; never borrow from A.
4. Add a new delivery with different dates. It creates a new batch only when chosen; old batches retain dates.
5. For minimum 10, usable stock 10 is not low; 9 is low. Expired stock remains in physical total but is excluded from usable stock.
6. With warning 45 days, a positive batch at 45 days is included; at 46 it is not. Expiry today is “Expires today”; tomorrow it is expired. Empty/no-expiry batches create no expiry alert.
7. Enter full and month-only dates in both calendars; verify leap years, invalid dates, cross-calendar comparison, month-end policy, and preservation through backup.
8. Remove expired stock manually for disposal. It succeeds as inventory removal, with no sale or profit.
9. Enter sales 50,000 and profit 1,000 for today. Values persist exactly; saving that date again edits it. Stock/debts remain unchanged.
10. Reports distinguish a missing day from a recorded zero and reflect edits/deletions immediately.
11. Add a Persian-named customer with no phone. Add debt 500, debt 300, payment 200. Balance is 600. Description can mix English medicine names and Persian prose.
12. Product-name suggestions insert text only; no quantity, financial, or debt amount changes automatically.
13. Reject overpayment and a backdated correction that makes a historical balance negative; preserve the previous ledger.
14. Export all records and restore on another platform. Counts, exact values, original date precision, Unicode, histories, and settings agree. Invalid restore leaves current data intact.
15. Rename a used unit without losing references; deactivate it without breaking existing products; reject destructive deletion while in use.
16. Double tap Save, terminate/relaunch, and cancel forms: no duplicated transactions, half-writes, or accidental stock changes.
17. Complete all core workflows in airplane mode on iOS and Android; no authentication or notification permission request appears.
18. Test small screens, large text, Persian input, keyboard visibility, back gestures, empty lists, and database/file errors.

## 11. Delivery and completion criteria

Deliver the Flutter source, dependency lockfile, database migrations, meaningful domain/unit tests, widget tests for critical forms, and integration tests for persistence and backup/restore. Include a concise README with setup, run/build steps for both platforms, architecture, backup format, assumptions, and actual test/build results.

Build in working vertical slices: foundation and persistence; inventory and date rules; daily records/reports; debt notebook; backup/restore; visual/accessibility polish and platform verification. Do not postpone persistence until after a mock UI is presented as complete.

Provide Android build output when the environment supports it. Build/test iOS with the required Apple toolchain and signing environment when available; otherwise state the exact unverified steps. Do not claim a simulator/device test or signed release was performed when it was not. No App Store/Play Store publishing is authorized by these requirements.

The application is complete only when both specifications are implemented, acceptance scenarios pass or concrete limitations are reported, and no essential flow relies on an unavailable server.

## 12. Explicit exclusions

No POS, invoices, receipts, barcode scanner, prescriptions, dosage/clinical advice, purchasing/supplier management, automated profit/costing, expenses/payroll, automatic batch depletion, unit conversions, debt-to-stock linking, payment gateway, cloud sync, accounts/roles, password lock, external notifications, AI service, or website implementation in version 1. Do not add these merely because they are common in pharmacy software.
