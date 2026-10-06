# Portable backup format — version 1

Implemented by app **0.6.0+6**, exporting database schema **5**. The `.zip` is a logical snapshot, not a copied SQLite file. No device path, account, network connection or password is needed to interpret it. Backups contain readable customer and financial information: keep exported copies private. SHA-256 detects accidental corruption; it is neither encryption nor authentication.

## Container and limits

The suggested filename is `pharmacy-backup-YYYYMMDD-HHmmss.zip`, using local creation time. The ZIP contains exactly two UTF-8 files at its root: `manifest.json` and `data.json`.

Version 1 deliberately uses the [ZIP STORE method](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) (method 0, no compression). Limits are 64 MiB for the whole file, 63 MiB for `data.json`, 64 KiB for the manifest, and 250,000 rows across all tables. JSON nesting is limited to 32 and individual database text values to 1,048,576 UTF-16 code units. Export applies the same limits as import. This is a bounded in-memory format; it is not a streaming large-database format.

The reader accepts ordinary STORE ZIPs with flags 0 or UTF-8 (0x800). It rejects encrypted/compressed entries, ZIP64, spanning, data descriptors, extras/comments, trailing data, directories, symlinks and special files. Central and local headers must agree; lengths, offsets and CRC-32 must match. Duplicate entries, unknown names, absolute paths and traversal paths cannot pass the exact two-name whitelist. Entries are read as bytes; nothing is extracted using an archive-supplied path. Recompressing or modifying a backup can make it unsupported; retain the original file.

## Manifest

`manifest.json` is a JSON object with these fields:

| Field | Meaning |
|---|---|
| `format` | `pharmacy-companion-backup` |
| `format_version` | Integer `1` |
| `schema_version` | Source SQLite logical schema, currently integer `5` |
| `app_version` | Informational producing app version, e.g. `0.6.0+6` |
| `created_utc` | Canonical Dart ISO-8601 UTC timestamp, e.g. `2026-10-06T08:00:00.000Z` |
| `timezone` | OS-provided local timezone name at export; may be a name/abbreviation rather than an IANA identifier |
| `utc_offset_minutes` | Local UTC offset at export, e.g. `270` for Kabul |
| `counts` | Object mapping every included table name to its row count, including zero counts |
| `payload_bytes` | Exact byte length of `data.json` |
| `checksum_algorithm` | `SHA-256` |
| `payload_sha256` | Lowercase hex SHA-256 of the exact UTF-8 bytes of `data.json` |
| `integer_encoding` | `decimal-strings` |

Counts and lengths are bounded JSON integers. The manifest's ZIP CRC also protects its bytes against accidental corruption. Schema/format versions govern compatibility, not app-version string comparisons. Newer unsupported schema/format versions are rejected with an update-app instruction.

## Data representation

`data.json` contains one property, `tables`, mapping each table to an array of full rows. Every column defined by the declared schema must be present; no extra columns are accepted. Column names and constraints are defined by the ordered migrations in `lib/core/data/schema.dart`.

- All SQLite INTEGER values are canonical base-10 **JSON strings**, including money, timestamps, quantities, booleans ("0"/"1"), date components and sequences. Example: `"profit_minor":"-12345"` means AFN -123.45. Fractions, exponent notation, leading zeros and negative zero are rejected for these columns. Conversion never passes through floating point.
- SQLite TEXT values remain JSON strings; nullable values remain JSON `null`. JSON escaping does not normalize Unicode. Phone numbers, leading zeros, Persian text, newlines and zero-width characters are retained exactly.
- Existing audit/operation `payload`, `result`, `previous_value` and `new_value` columns remain their original JSON **text**, including their original numeric tokens. These are not parsed and rewritten during serialization. Readers inspecting those nested snapshots must preserve integer precision; Dart native integers, Python integers, or a lossless JSON reader are appropriate.
- UUIDs and relationships are preserved. Event timestamps remain UTC epoch milliseconds; business dates remain Gregorian civil `YYYY-MM-DD` strings and are never shifted to the importing device's timezone. Original calendar, full/month precision, source components and canonical endpoints remain in `date_specs`.
- Record order has no independent meaning. Stable history sequences are preserved and validated. The exporter sorts history by sequence, counters by name and other entities by ID for deterministic reads.

| Included table | Preserved information |
|---|---|
| `units` | Active/inactive units, identity and normalized lookup keys |
| `products` | Unit identity, alert thresholds, notes, archive state |
| `date_specs` | Gregorian/Solar Hijri originals, full/month precision, canonical ranges, retained old specifications |
| `batches` | Identity, product/date references, no-expiry modes, received dates, physical quantities and archives |
| `stock_movements` | Complete immutable opening/add/remove/reversal history |
| `daily_records` | Exact sales and signed manual profit, business date, note |
| `customers` | Original name/phone/note, normalized search keys, archive state |
| `ledger_entries` | Debt/payment amounts, descriptions, dates and stable sequences |
| `correction_audits` | Full before/after snapshots, deleted entry identities, reasons |
| `app_settings` | All versioned preferences and backup/restore metadata; per-product warning days remain in `products` |
| `sequence_counters` | Monotonic history counters, including gaps caused by deletion |
| `inventory_operations` | Durable retry identities and request/result identities |
| `daily_operations` | Durable save/delete requests and retained result snapshots |
| `debt_operations` | Durable customer/ledger/correction/archive requests and results |

No operational rows are filtered out because they are archived, inactive, empty or deleted-but-retained in history. Settings use the existing versioned key/value repository; no preference whitelist silently drops future keys.

The optional `appearance.display_size` preference (version 1) stores `small`, `medium`, or `large`. Absent or unrecognized values use Medium. Restore refreshes the app's appearance controller. Unused-item deletion receipts use `inventory_operations.kind = delete_product`; the deleted UUID remains in its retry receipt, without resurrecting the product. Neither addition changes the schema or backup format version.

## Consistency, validation and replacement

1. Export validates and reads every table in one database transaction. Encoding and hashing run in workers that receive plain data. The completed private file is flushed before preparation metadata is recorded. No live database/WAL copying occurs.
2. The system picker reads one selected file through scoped access. Both the declared size and actual bounded stream length are checked. The format, headers, checksum, counts and versions are checked before staging.
3. Import creates a separate private SQLite database at the declared source schema, inserts typed rows with parameterized SQL, and opens it through the existing migrations. Format 1 currently supports source schemas 1–5; older schemas must contain their exact historical tables/columns. For schema 1, newly introduced sequence counters also account for retained audit sequences of deleted entries. These are migration-compatible logical snapshots, not a claim that earlier app versions offered this exporter.
4. Temporary data must pass SQLite integrity/FK/constraint checks and domain validation: original calendar conversion, production/expiry ordering, search keys, timestamp ranges, money bounds, chronological nonnegative ledger balances, settled-only customer archives, stock reconciliation and reversing movements, empty archived stock, correction snapshots, operation receipts and monotonic counters. Future business dates are not compared with the receiving device's clock during restore; valid existing civil dates survive clock/timezone changes.
5. Only then does the UI expose a preview and the replacement action. Cancel discards staging. Confirmation explicitly says replacement, not merging. A digest ties the staged rows to the validated preview; staging is checked again before replacement.
6. Under one live SQLite write transaction, the current state is validated and a complete `safety-<uuid>.zip` is flushed into private app storage **before deleting any live rows**. Failure to create it aborts restoration. Trusted local triggers are temporarily suspended inside the transaction; all logical rows are replaced, trusted triggers reinstated, and integrity checked again. Incoming SQL is never executed.
7. `backup.last_restore` is written in the same commit. SQLite FULL synchronous transactions provide [atomic commit/rollback](https://www.sqlite.org/atomiccommit.html); exceptions roll back all rows and trigger definitions. The same connection remains open, avoiding platform-dependent database/WAL rename windows. A lost acknowledgment is reconciled using the committed operation marker rather than applying another replacement. The independent safety ZIP is retained for recovery; it is not required for ordinary transactional rollback.
8. After success, repository wrappers and cached views are refreshed, open routes are cleared, and Home reloads actual totals and alerts. Repeated restore replaces rows with the same identities rather than appending duplicates. Physical-device power interruption remains a separate acceptance check.

`backup.last_prepared` stores the prepared file's timestamp/name and latest save/share outcome. It is written after the snapshot, so the file contains the prior preparation metadata. Restore preserves the selected snapshot's preferences and adds/updates `backup.last_restore`; a historical successful export never implies the restored data has just been externally saved. No absolute path is stored in either metadata value.

Private copies live next to the database in `portable_backups`. On backup operations, stale staging older than one day is removed unless its preview is active. The newest two safety snapshots are retained, as are all safety snapshots younger than one day. Prepared files expire after seven days. Housekeeping checks owned filename patterns, does not follow links, and never removes user-selected source/destination files. Cleanup failures do not invalidate a committed restore. Private copies disappear on uninstall and are not a substitute for exporting elsewhere.

## Native workflows and verification boundary

[file_picker 10.3.10](https://pub.dev/packages/file_picker/versions/10.3.10) supplies native iOS/Android document selection and destination saving; [share_plus 12.0.1](https://pub.dev/packages/share_plus/versions/12.0.1) supplies the share sheet with an iPad anchor. No broad storage permission is requested. A successful destination save is labelled saved; a cancelled picker is neutral. Sharing success is labelled shared, and unavailable share completion is labelled handoff. Neither is claimed as confirmed external saving. Choosing a cloud provider is optional and may require that provider's network access; local storage works without an account.

Host tests exercise all-table round trips, exact values and relationships, migrations, rejection before replacement, failure rollback/reopening, duplicate restores, acknowledgment reconciliation, private-file retention and real SQLite through the UI. A separate Python `zipfile`/JSON reader verifies SHA-256, exact decimal strings and ZIP interoperability, rewrites a STORE ZIP, and the app restores it. Python 3 must be on PATH for that interoperability test. This is **format-level interoperability**, not proof of an iPhone-to-Android device transfer.

Separately, the app was installed on an isolated Android 16/API 36 x86_64 emulator with airplane mode enabled. Native destination saving, save/share cancellation, file selection, preview/confirmation, repeated restore, corrupt-file rejection and force-stop/relaunch were exercised. An Android-native re-export compared equal to the source's 14 tables, apart from the expected local backup metadata. iOS, physical devices, cloud-provider success, native screen readers and physical power/storage failure recovery remain unverified. See `IMPLEMENTATION_STATUS.md` for exact commands and evidence.
