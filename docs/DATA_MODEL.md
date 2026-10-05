# Local data foundation

The two files in `explainations/` govern the product. This describes Phase 1–5 implementation decisions, not additional product scope.

## Ownership and layers

`lib/app` composes repositories and owns the `ChangeNotifier` application controller. `lib/features/<feature>/domain` contains models and repository interfaces, `data` contains SQLite adapters, and `presentation` contains screens. Shared values, validation, database migrations, and design components live in `lib/core`. Inventory's `application/InventoryController` supplies dependencies and a shared refresh signal; forms use a reusable ChangeNotifier save controller. There is one state-management approach.

Presentation does not write SQL. Inventory, daily records, and debt repositories never mutate one another's operational data. A future API adapter would implement the repository interfaces; identity/conflict policy would be designed at that time. No sync code, remote endpoint, account, or network client is present.

## SQLite schema and migrations

`lib/core/data/schema.dart` contains ordered migrations. Version 1 creates the relational tables; version 2 adds indexes, persistent sequence counters, and integrity triggers; version 3 adds immutable inventory operation receipts and a batch lookup index; version 4 adds immutable daily-record operation receipts; version 5 adds immutable debt operation receipts and a normalized phone search column/index, backfilled without changing original phone text. Fresh installations execute all five. Existing migrations are preserved. sqflite runs create/upgrade callbacks transactionally. Downgrades reject opening without deleting data. Add new migrations when shipping changes; do not rewrite released migrations.

| Table | Purpose / constraints |
|---|---|
| units | UUID, trimmed name, normalized active-name uniqueness, inactive flag |
| products | Unit FK, nonnegative integer minimum/warning days, archive and timestamps |
| date_specs | Immutable original calendar/precision/components and canonical Gregorian date range |
| batches | Product/date FKs, explicit expiry mode, received civil date, integer stock, archive |
| stock_movements | Immutable UUID, increasing sequence, signed delta/result, optional one-time reversal FK |
| daily_records | One unique Gregorian business date, exact integer sales and signed profit |
| customers | UUID, Unicode name, text phone, archive and timestamps |
| ledger_entries | Customer FK, positive money, stable sequence, business date and type |
| correction_audits | Immutable before/after JSON snapshots, entry identity, customer FK, action/reason/timestamps |
| debt_operations | Immutable request/result receipts for customer save, ledger add/edit/delete and archive/restore |
| app_settings | Versioned key/value preferences with UUID and timestamps; can hold later backup metadata |
| sequence_counters | Internal monotonic ordering counters; deletion does not reuse a sequence |
| inventory_operations | Immutable UUID, mutation kind, exact JSON request payload, result entity identity and timestamps; persisted in the same transaction as the change |
| daily_operations | Immutable UUID, save/delete kind, exact request and result snapshot JSON, timestamps; atomic with the daily mutation |

Foreign keys are enabled on every connection. Writes use SQLite's full synchronous durability setting. Product totals and customer balances are derived; neither has an editable total column. Batch quantity starts at zero; an opening movement applies initial stock. Each movement insertion validates its result and updates batch quantity by trigger within the same transaction. Direct quantity overwrites, movement changes/deletion, repeat reversals, negative quantities, and archiving physical stock are blocked. Unit changes after stock history are blocked; inactive units remain usable through existing products.

Ledger insert/edit/delete validates chronological balances ordered by `(business_date, sequence)`. SQL guards reject negative/out-of-range running balances, including backdated mutations. Repository corrections save before/after audit snapshots in the same transaction. Raw SQL is infrastructure-only: callers must use repositories to retain correction audit semantics and domain validation. Entry deletion intentionally leaves its audit identity without an entry FK. A deleted ledger operation ID cannot be replayed. Adjustments and ledger insertions accept caller-owned UUID operation IDs for safe identical retries; mismatched reuse fails.

Phase 2 product, batch, unit and archive mutations accept durable operation IDs. A receipt is saved only if the whole transaction commits. A matching retry returns the same entity without applying a second change; mismatched payload reuse is rejected. Product plus optional initial batch/date specs/opening movement is one transaction. Metadata edits never overwrite quantity; date corrections create new immutable date specifications. UI review shows old/new dates and unchanged quantity. Orphaned old date specifications are retained. Archive/restore preserves UUIDs and history; an archived product's batches remain independently archived or active when the product is restored.

The save controller disables concurrent submission. For a confirmed validation/database rollback, edited input can start a new operation. An unknown save outcome keeps the same operation ID and freezes input until an identical retry reconciles the receipt/movement. Undo has its own stable reversal ID and cannot make stock negative. Any future complete backup must include operation receipts, movements, inactive units, date specifications and sequence counters; do not strip retry identities during restore.

Paged product/customer/daily/history reads default to 50 (maximum 200). Phase 3 expiry pages join products, units and source dates in one data query, with exact affected-batch and distinct-product counts. Product detail still loads every batch for that product; individual batch date reads and affected-ledger validation prioritize correctness over the later large-dataset performance target. The 5,000/20,000/50,000 performance target has **not** been verified.

## Inventory alert read models

`BatchInventoryStatus` combines the shared `expiryState`/`DateSpec.effectiveExpiry` rules with inventory eligibility. `InventoryItem.fromBatches` computes detail totals and independent stock/expiry flags. Widgets format these results; they do not decide date or quantity thresholds. `InventoryQueries` provides SQL projections for filtering/counting, with contract tests comparing every filter against the domain model across clock boundaries. No schema migration or stored alert flags are needed.

- Physical stock includes expired quantities. Usable stock excludes expired batches; a batch expiring today is still usable.
- Low stock requires a positive minimum and usable quantity strictly below that minimum. Out of stock means zero usable quantity independently of the minimum. Both flags can coexist.
- Expiring soon includes today through the per-product warning-day boundary, inclusively. Expires today has its own count/filter and becomes expired the next local day.
- Empty batches, archived batches/products and no-expiry batches never contribute expiry alerts. Active no-expiry quantities remain usable. Month-only expiry uses the last day of the original Gregorian or Solar Hijri month.

Home's dashboard is one SQLite transaction containing counts and a bounded Needs attention selection: up to two expired batches, two expiring-soon batches (today first), and two stock issues (out of stock first). Expiry results sort by effective expiry, product name and batch identity. Stock rows sort by urgency, name and identity. The complete Needs attention filter is the union of stock and expiry issues, with one row per product. Expiry filters show separate batches, source date precision and exact affected-product/batch totals.

`InventoryController` owns the injected clock and a 30-second local-day check while the shell is alive. Resume and committed edits emit the same refresh signal, so visible Home/list/detail views reload. Each read captures one civil day, and widgets replace obsolete pending futures. Application summary refreshes coalesce requests received during an active read and suppress a result from an obsolete day. This is in-app refresh only; no notification permission, scheduling or background service is introduced. Tests control both the clock and timer progression.

## Daily records and reports

Daily records keep one unique Gregorian civil date, exact AFN sales and manually entered signed profit, optional Unicode note, UUID and event timestamps. Sales must be nonnegative; both values may be zero and profit may exceed sales. Future business dates are rejected against the injected local clock at commit time. Edits replace values and may move a record to an unused date while retaining identity. Conflicts preserve existing data and offer the saved record for editing.

Every UI save/delete supplies a stable operation UUID. A v4 `daily_operations` receipt stores the exact request and result in the same transaction. Identical retries return the original result without applying the mutation again, including after reopening, later edits or deletion. Mismatched reuse is rejected. Deleted records are not resurrected by replaying an older save. As with inventory, an unknown outcome freezes input until the same operation is reconciled; errors never announce success. The future backup format must include these receipts, including snapshots retained after deletion.

`DailyRecordsController` emits financial refreshes to its views and application Home summaries without invoking inventory/debt writes. Shell resume and the existing local-day watcher invalidate time-sensitive financial reads. Report range validation, inclusive date arithmetic, coverage, monthly buckets and comparisons live in `daily_report.dart`, outside widgets. The repository reads current and previous periods in one SQLite transaction using the unique business-date index.

- Today is one day; Last 7 days includes today and six prior days. This month runs from the first day through today. Custom ranges include both endpoints, may span future dates for viewing, and must have start <= end. Future dates have no add action.
- Totals sum recorded entries only. Missing days/months have nullable chart values and display Not recorded; a saved zero remains a real point and contributes coverage. Monthly totals intersect each Gregorian month with the selected range and disclose that partial coverage.
- Report sums use BigInt, not SQLite `SUM` or bounded single-entry `Money`, so many individually valid values cannot overflow or round. Display shares the exact AFN formatter. Doubles are used only for chart coordinates and explicitly approximate axis ticks.
- Optional comparisons use the immediately preceding equal-length period. Current and previous coverage are shown. Missing current/prior data or a zero prior total gives Not available. Percentage display uses integer arithmetic rounded to two decimals; negative prior totals use their absolute magnitude as the denominator, stated in the UI.
- Daily charts show windows of at most 31 days and monthly charts at most 12 months, with earlier/later controls. Lines break at missing values; negative profit lies below zero. Point taps and labeled previous/next controls expose exact amounts. Daily data is a lazy newest-first list including gaps, revealed in groups of 50; monthly chart windows also have an accessible data list.

Report queries currently load the selected and comparable periods into memory for exact aggregation. A 1,100-record maximum-value dataset is tested for arithmetic correctness, not a performance benchmark. Whole-history large-range performance and native assistive-technology behavior remain unverified.

## Customer debt notebook

Customers have a required trimmed name, optional raw text phone and note, stable UUID and timestamps. Names need not be unique: normalized matches produce a warning that permits continuing, including archived matches. Only search keys normalize case, yeh/kaf, phone punctuation and Persian/Arabic digits; saved content is preserved. Search matches substrings of name or phone. All, Outstanding and Settled filters refer to active customers by default, with a separate archived view. Zero-balance customers may be archived and restored with their full history; outstanding customers cannot be archived. Archived ledgers cannot be modified until restoration.

Ledger entries are independent positive AFN amounts with type Debt or Payment, Gregorian business date, free-text multiline description and permanent saved sequence. Dates default to the injected clock's local day, with past dates allowed and future dates rejected at commit. The balance is derived from entries. `projectLedger` orders by business date then sequence and validates every running balance using BigInt; both previews and writes use it. It rejects overpayments, historical deficits and amounts beyond the supported per-customer limit. Edits keep identity, sequence and created time. Deletes and edits append full before/after correction snapshots atomically and never rewrite dependent entries.

The UI supplies durable operation IDs for every mutation. The same request after duplicate taps, a lost acknowledgment or database reopen returns the saved receipt; changed reuse is rejected. An older receipt never overwrites subsequent corrections or resurrects deleted entries. Deleted add-entry IDs remain unusable. Receipt/audit failures roll back all changes. Unknown outcomes freeze form input for reconciliation. The future backup format must include debt receipts as well as correction audits and sequence counters.

Customer, transaction and correction lists load pages of 50. Transaction rows are newest first and calculate the correct running balance using the older prefix, without loading the complete history for display. Preview and mutation validation recompute the whole affected customer's ledger. Search/list aggregates use SQL per-customer balances; global outstanding totals in customer lists and Home use BigInt, so several valid customer balances can exceed a single-customer amount bound without rounding.

`DebtController` refreshes the notebook and Home after commits and app resume; the existing local-day signal refreshes date defaults/validation. The shared business-date input also serves daily records. Optional product-name suggestions only read active product names and replace the selected description text at the cursor. They store no inventory reference and never infer prices, quantities or amounts. Debt/payment/correction writes do not touch inventory or daily sales/profit. English navigation remains LTR; editable Persian content follows its first strong character, with money and phone text LTR.

## Exact values and calendars

- Event timestamps are integer UTC epoch milliseconds. Repository updates preserve stable IDs and created timestamps; clock rollback cannot decrease updated timestamps.
- Business dates are strict `YYYY-MM-DD` Gregorian civil values. UTC `DateTime` is used only for timezone-independent day arithmetic, never as the stored business date.
- AFN money uses 100 minor units per AFN, with a documented bound of ±9,000,000,000,000,000 minor units (±90,000,000,000,000.00 AFN). Parsing/arithmetic uses integers/BigInt, never binary floating point. Sales are nonnegative, profit may be signed, ledger amounts are positive. Display consistently includes two decimals.
- Money input accepts ASCII, Persian and Arabic digits; `.`/`٫` decimals; correctly grouped `,`/`٬` thousands. Ambiguous grouping, spaces inside an amount, exponents, and excess precision are rejected. No implicit rounding.
- Quantities and warning/minimum values are bounded whole integers from 0 to 2,147,483,647; adjustment magnitude must be positive.
- `DateSpec` supports Gregorian and Solar Hijri with full-date or month precision. A null expiry is explicitly persisted as `expiry_mode=none`. Original components are authoritative. Canonical ranges derive from `shamsi_date`; month expiry uses the original calendar's last day.
- Convertible batch-date range: Solar Hijri 0001/01/01 through 3177/10/11, ending Gregorian 3798-12-31. A month-only input must have both endpoints in range. Business dates independently support Gregorian years 1–9999.
- Calendar display conversion creates a new full-date representation without modifying the original. The reusable date control retains that source on display-only switching. Month-only values show their equivalent range and require confirmed clearing/re-entry to change the source calendar. Both calendars support typed input and full-date component pickers. Invalid dates are rejected rather than normalized.
- SQL validates civil date shapes/actual lengths, source month lengths/leaps, precision, expiry-mode consistency, and production/expiry ordering. Repository/domain code computes and validates the Solar Hijri-to-Gregorian correspondence. A future restore importer must independently reconstruct DateSpec and compare canonical endpoints before import.
- Search keys normalize case and Arabic/Persian yeh/kaf without changing saved names/notes. Required names are trimmed; phone strings retain leading zeros. Content direction follows the first strong English/Persian character while interface labels and money stay LTR.

Only six suggested units are seeded. No operational records or backup-success metadata are fabricated. Export/restore and its ZIP/JSON format remain unimplemented; do not treat the internal SQLite file as a portable backup.
