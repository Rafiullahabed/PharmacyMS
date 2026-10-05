# Pharmacy Companion — UI/UX Design and Complete Workflows

Version: 1.0 | Companion: `Pharmacy_App_Requirements.md`

## 1. Design brief and governing rules

Design a polished, calm, practical Flutter app for a retail pharmacy owner using one phone. The owner needs fast stock adjustments, easy daily number entry, and a readable debt notebook. iPhone is the current primary device; Android must receive the same quality and functionality.

This document specifies the visual and interaction direction. Product rules and validation are defined in the companion requirements document and take precedence if an interaction detail conflicts. Numeric design tokens below are proposed implementation defaults, not previously selected branding.

The app must feel finished and uncluttered: clear hierarchy, comfortable spacing, readable numbers, consistent components, and short forms. Avoid dense desktop tables, tiny text, medical imagery, decorative dashboards, excessive gradients, or a generic screen full of identical cards.

No login/onboarding questionnaire. First launch opens a useful empty Home screen with an “Add your first item” action. Do not prepopulate fictional financial/customer data.

## 2. Navigation architecture

Use four persistent bottom navigation destinations:

| Tab | Purpose | Primary action |
|---|---|---|
| Home | Status, alerts, shortcuts | Add item / Record today |
| Inventory | Products, batches, quantity changes | Add item |
| Daily Records | Daily figures and trends | Add record / Edit today |
| Debtors | Customers and debt/payment history | Add customer |

Settings opens from a consistently located gear button in the Home app bar. It contains Units, Backup & Restore, and a small About section. Do not add a fifth crowded bottom tab or a side drawer.

Retain each tab's scroll position, search, and filters during navigation. A detail page has a back button with native back behavior. Tapping a Home alert opens the relevant filtered view with a clear route back. Android Back closes the keyboard/sheet before leaving the screen; iOS edge-back works where appropriate.

On larger devices use a centered comfortable content width and, where justified, a navigation rail; phone use is primary. All primary actions remain reachable above safe-area insets.

## 3. Visual system

### 3.1 Color and surfaces

Suggested light theme:

| Token | Value | Use |
|---|---|---|
| primary | #0F766E | Main actions and selected navigation |
| onPrimary | #FFFFFF | Text/icons on primary |
| background | #F6F8FA | Main canvas |
| surface | #FFFFFF | Cards, sheets, forms |
| textPrimary | #172B3A | Headings and body |
| textSecondary | #526474 | Supporting information |
| border | #DCE4EA | Dividers and field outlines |
| success | #166534 | Healthy/settled states |
| warning | #92400E | Low stock/expiring soon text |
| danger | #B91C1C | Expired/errors/destructive actions |

Use subtle tinted backgrounds for status chips; pair color with text and an icon. Verify actual contrast in implemented combinations. Warning is not an inaccessible pale-yellow label. Keep shadows soft and rare; separation comes primarily from spacing and borders. A polished light theme is required; dark mode is optional and must not delay or reduce core completion.

### 3.2 Typography and layout

- Use a legible bundled English font or native system font with bundled Persian-capable fallback. No online font loading.
- Suggested sizes: screen title 24–28, major totals 28–32, section title 18–20, body/input 16, secondary 14, small labels 12–13 logical pixels. Do not apply the owner's unrelated projects' tiny typography rules here.
- Financial amounts use tabular figures where available and aligned numeric baselines.
- Spacing scale: 4, 8, 12, 16, 24, 32. Typical page padding 16–20; card padding 16; radius 12–16; sheet top radius about 24.
- Touch targets at least 48 x 48 logical pixels on both platforms. Icon-only actions need semantics and tooltips; critical actions also have visible labels in their sheet.
- Minimum normal contrast 4.5:1 for text; test large text and accessible controls. Support system font scaling up to 200% without clipped amounts, overlapping controls, or lost actions.
- Money: `AFN 50,000` or `AFN 50,000.50`, consistently. Unit next to quantity: `17 strips`. Use unambiguous date labels such as `05 Oct 2026 · Gregorian`, not ambiguous numeric slash dates.
- Use brief, restrained transitions (roughly 150–220 ms), respect reduced motion, and use optional light haptic feedback for committed actions.

### 3.3 Reusable components

Create shared app bars, bottom navigation, search field, filter chips, status badges, metric cards, item rows, customer rows, batch cards, money/date/quantity inputs, save footer, adjustment sheets, ledger timeline rows, empty/error states, confirmation dialogs, and snackbars with optional Undo. Centralize tokens and validation display.

Do not make a whole row tap conflict with its plus/minus buttons. Parent row opens details; action buttons open the correct adjustment sheet once.

## 4. Home screen

Order content by practical importance:

1. App title, today's date, Settings button.
2. Compact inventory status overview with actionable counts: Low stock, Expiring soon, Expired. Include Out of stock access. Clearly distinguish product counts from batch counts.
3. Today's manually recorded Sales and Profit. If missing, show “Not recorded” and “Record today”; do not show fabricated zeros. If present, offer “Edit today's record.”
4. Total outstanding customer debt with a link to Outstanding customers.
5. A short “Needs attention” list with the most urgent stock issues and “View all.”

Useful shortcuts may be Add item, Record today, and Add customer. Avoid a large grid duplicating every navigation action. A zero-alert state says “No current inventory alerts,” not that all medications are clinically safe.

Empty Home still explains each section and offers the relevant action. Large totals wrap or resize within accessible limits; never truncate significant digits.

## 5. Inventory screen and product detail

### 5.1 Inventory list

Top: title and Add item action; persistent search; horizontally scrollable labeled filters: All, Low stock, Out of stock, Expiring soon, Expired.

Each product row shows name (up to two lines), unit, usable quantity, relevant status badges, and compact Add/Remove buttons. If expired quantities exist, show secondary physical/expired quantities so the displayed count is not misleading. Optional category remains secondary.

Product list search and filtering must remain responsive. Provide a clear-search control, result count when useful, and distinct messages for “No items yet” and “No matching items.” The latter includes “Clear filters.”

### 5.2 Product detail

Show product name, unit, usable and physical quantities, minimum stock, and expiry warning rule. Provide Edit item and an overflow menu for archive where valid. Below, list batches with explicit labels, dates, remaining quantity, and status. Sort predictably (for example expiry ascending, no-expiry last), but sorting never selects a batch for stock changes.

Each batch row opens detail and provides Add/Remove actions. “Add new batch” is visible. Hide empty batches by default with a visible “Show empty batches” toggle. Provide stock movement history with date, signed quantity, batch, optional note, and resulting quantity.

### 5.3 Batch detail

Show batch label, quantity and unit, received date, production date or “Not entered,” expiry or “No expiry date,” original calendar, precision, and optional equivalent Gregorian date/range. Month-only values display “Month only”; an expandable explanation clarifies the end-of-month alert convention.

Expired and expires-today states are prominent but do not block manual stock removal. Add stock, Remove stock, Edit batch metadata, and History are available. Date corrections show the old and new dates for review; do not change quantities.

## 6. Inventory workflows

### WF-01 — Add a product

1. Inventory > Add item.
2. Enter name and choose a unit. The unit selector includes “Manage units” and a quick Add unit option that returns to the form with the new unit selected.
3. Enter minimum stock and expiry warning days. Show helper text: “Warn when usable stock is below this amount” and “Warn this many days before expiry.” Suggested values remain editable.
4. Optional category/notes under a secondary section.
5. Optional “Add initial stock” section, off by default. When enabled, enter quantity and full batch date fields.
6. Save atomically; open product detail and show success. If initial batch validation fails, preserve all input and do not create half a product/batch submission.

The minimal product form should feel short; do not force production date, lot number, price, supplier, or customer data.

### WF-02 — Add a new delivery

1. Product detail > Add new batch, or Add stock > New batch.
2. Show product name and fixed counting unit.
3. Enter positive quantity, optional lot label, received date (today), optional production date, and expiry mode.
4. Expiry modes: Full date / Month & year / No expiry date. Date fields expose Gregorian / Solar Hijri.
5. Review quantity and date summary; Save.
6. New batch appears separately; totals and alerts refresh. Dates on existing batches do not change.

### WF-03 — Increase an existing batch

1. Tap Add on a product or batch.
2. Product-level entry shows “Existing batch” and “New batch.” If several existing batches are available, require an explicit choice with no automatic preselection.
3. Show the selected batch's dates and quantity.
4. Enter quantity. Display `Current 12 → After adding 17` with the actual unit.
5. Optional note; Add stock saves once.
6. Snackbar: “Added 5 strips” with Undo. Invalid/cancelled input changes nothing.

### WF-04 — Remove quantity manually

1. Tap Remove on a product; select a positive-quantity batch if several exist. A batch-specific action already defines the selection.
2. Show name, batch, dates/status, available quantity, numeric input, and optional note.
3. Display the resulting quantity live. Keep focus on the quantity field, not on a hidden sales form.
4. If amount exceeds availability, show “Only 9 strips are available in this batch.” Disable commit until corrected; never take the remainder from another batch.
5. Tap Remove stock; save and refresh. Snackbar with Undo.
6. Expired batch removal is allowed with a visible “Expired stock” label; no sale is recorded.

A routine operation should require at most opening the sheet, choosing a batch when necessary, entering quantity, and confirming. Do not add confirmation dialogs after an already explicit Add/Remove button for ordinary valid adjustments.

### WF-05 — Undo and correction

Undo creates a reversing movement. Show success only after persistence. If intervening stock use prevents reversal, explain “This change can no longer be undone because stock has changed” and provide View batch. Keep the original movement history. For older mistakes, use a new manual adjustment with an explanatory note; do not expose an untracked direct quantity overwrite.

### WF-06 — Act on alerts

Tap Low stock to see product name, usable amount, unit, and minimum. Tap Expiring soon/Expired to see product and affected batch, quantity, exact/original expiry label, and remaining days/status. Opening a result goes to the relevant product/batch. No notification permission, push prompt, or reminder scheduling appears.

## 7. Date input experience

Use one reusable calendar-aware control wherever batch dates are entered:

- Explicit calendar choice: Gregorian / Solar Hijri.
- Explicit precision: Full date / Month & year; expiry also offers No expiry date.
- Full-date picker supports practical navigation through years and months plus accessible typed input.
- Month/year input shows only those fields; do not force choosing a fictional day.
- Example labels: `Oct 2026 · Gregorian · Month only` and `1405/07 · Solar Hijri · Month only`.
- Helper: “For alerts, a month-only expiry is treated as the end of that month.”
- For a full date, calendar switching changes representation without changing the date. For partial dates, preserve the original month and show an equivalent range; require explicit re-entry to change its source calendar.
- Production date supports clearing. No-expiry mode clears/ignores hidden expiry fields only when committed, without saving stale contradictory values.
- Inline errors explain invalid dates or production unambiguously later than expiry.

Daily record and ledger date pickers use Gregorian by default as an implementation default. Stored local business dates remain stable; supporting two calendars for batch labels does not mean shifting financial record days.

## 8. Daily Records screens and workflows

### Screen structure

At the top place a date-range selector: Today, Last 7 days, This month, Custom. Display Total sales, Recorded profit, and Days recorded. Use two readable compact trend panels or a clearly labeled Sales/Profit toggle, so a much larger sales figure does not flatten the profit series. Monthly view provides longer-term aggregates.

Show a daily list below with date, sales, profit, and an optional note indicator. Negative profit is labeled and shown below zero on charts. Exact chart values appear when tapping a point; an accessible list provides the same information. Avoid 3D charts, unnecessary legends, clipped labels, and charts fabricated from sample data.

### WF-07 — Record a day

1. Home > Record today or Daily Records > Add record.
2. Date defaults to today; Sales (AFN), Profit (AFN), and optional Note appear.
3. Helper text: “Enter your own daily totals. Profit is calculated outside this app.”
4. Amount fields start empty, accept exact decimal values, and use an appropriate keyboard. Accept Persian/Arabic digit input by normalizing digits internally. Negative profit entry remains possible even on a keyboard without a minus key through an accessible sign control.
5. Save; show record and updated report totals.
6. If that date already exists, offer/open Edit record with existing values. Never silently append or sum.

### WF-08 — Edit or delete

Open an existing date, edit amounts/date/note, and Save changes. A date conflict is explained inline. Overflow > Delete record opens a confirmation with date and amounts; confirmed deletion refreshes reports and Home. Cancel keeps data unchanged.

### WF-09 — Review trends

Choose a period, inspect totals, tap points for exact daily values, or open the daily list. Custom range validates start <= end. Show “No records in this period” with Add record if empty. One point is displayed meaningfully without inventing a trend. Missing dates appear as gaps, not zeros. Coverage such as “5 of 7 days recorded” remains visible.

## 9. Debtors screens and workflows

### Customer list

Top: total outstanding, search by name/phone, All / Outstanding / Settled filters, and Add customer. Rows show name, optional phone, outstanding balance, and latest transaction date. Do not display blank phone placeholders for customers without a number. Persian names are right-aligned within their content area while navigation remains English/LTR.

### Customer detail

Header: name, optional phone, Edit customer. Prominent Outstanding balance card, with labeled Add debt and Record payment buttons. Disable payment when balance is zero and explain why if necessary. History rows distinguish Debt added from Payment received by icon, label, and signed amount; never rely on red/green alone.

Each history row shows date, description preview, and resulting balance where helpful. Tap to read the full untruncated description and edit/delete. Long descriptions expand without squeezing the amount off screen.

### WF-10 — Add a customer

1. Debtors > Add customer.
2. Required Name; optional Phone and Note. No account creation.
3. Save and open detail with zero balance and Add debt action.
4. Similar names trigger a nonblocking duplicate suggestion; show phone/notes to disambiguate.

### WF-11 — Add debt

1. Customer detail > Add debt.
2. Show customer and current outstanding balance.
3. Enter positive Amount (AFN), date (today), and multiline Description.
4. Description placeholder: “Write what the customer received or why this amount is owed.”
5. Optional item-name suggestions appear unobtrusively while typing, or via Insert item name. Selection inserts plain text at the cursor; it does not ask for quantity, price, or batch.
6. Show `Outstanding after saving: AFN …`.
7. Save; timeline and customer total update. No inventory or daily record changes.

### WF-12 — Record payment

1. Customer detail > Record payment.
2. Show outstanding amount; enter positive Payment amount, date, optional description.
3. Provide “Pay full balance” as an explicit user action, not an automatic default submission.
4. Show remaining balance before save. Overpayment/backdated balance conflicts have specific inline explanations.
5. Save; show “Payment recorded” and the resulting balance. If zero, display Settled while retaining history.

### WF-13 — Correct a ledger entry

Open entry > Edit. Show original type, date, amount, description and the recalculated outcome. Save only if all affected chronological balances remain valid. Deleting uses confirmation stating the amount and effect on balance. If correction would make a historical balance negative, preserve the ledger and explain that the dependent payment/debt must be corrected first. Never silently rewrite another entry.

### Persian and mixed-language editing

Detect direction from the first strong character or content context in names/descriptions. Keep English form labels LTR and money/phone values in isolated LTR spans. Persian paragraphs render RTL; English medicine names and numerals within them remain readable. Never reverse strings manually. Cursor movement, text selection, multiline paste, and insertion at the cursor must work with a Persian keyboard. Search may normalize characters but storage preserves the user's exact content.

## 10. Settings workflows

### WF-14 — Units

Settings > Units lists active units and a secondary inactive section. Add unit uses a short name form. Rename preserves identity. Delete is available only when unused; otherwise offer Deactivate with explanation: “Existing items will keep this unit. It will be hidden when choosing a unit for new items.” Provide Reactivate. Attempting to change the unit on a product with stock history explains the constraint and suggests a new product, never an implicit conversion.

### WF-15 — Create a backup

Settings > Backup & Restore shows Create backup, Restore backup, and last successful backup/preparation status. Brief copy: “Includes your inventory, daily records, customer debts, and settings. Keep the file somewhere private.”

Tap Create backup > local preparation with progress > native Save/Share flow. Keep controls disabled only while necessary. Cancellation is neutral, not an error. Report only the completion state the platform actually confirms. No sign-in, password, or cloud setup is required.

### WF-16 — Restore a backup

1. Restore backup > system file picker.
2. Validate selected file before showing any destructive action.
3. Preview filename, backup creation date, version, and counts of products/batches/daily records/customers/ledger entries.
4. Warning: “Restoring this backup replaces the information currently in this app. It does not merge records.”
5. Explicit Cancel / Restore backup confirmation, with clear destructive emphasis.
6. Create safety snapshot and perform atomic restoration; prevent editing during the swap. Do not show a fake percentage if only stage-level progress is known.
7. On success, return to refreshed Home and show restored counts. On failure, retain/recover previous data and show actionable error text. Never leave a blank partly imported database.

## 11. Editing, archiving, and error behavior

- Short adjustment sheets may dismiss freely while untouched. If modified, ask “Discard changes?” on back/swipe dismissal. Preserve user input after validation or storage errors.
- Full forms use a persistent Save footer above the keyboard when space allows; long content remains scrollable to focused fields. Scroll to the first error after failed validation.
- Save shows an in-progress state and rejects repeat taps. Success appears only after durable persistence.
- Product/batch archive is available only at zero stock; retained history remains accessible. Customer archive requires zero debt. Explain why a blocked archive is unavailable.
- Routine quantity changes need one intentional commit, not stacked dialogs. Destructive deletes/restores require confirmation.
- App/database errors use Retry where safe; do not retry a mutation blindly if its outcome is unknown. Reconcile its transaction identifier/state first.
- Handle low device storage, file-picker cancellation, unavailable destination, invalid backup, and unsupported version with plain English text; never expose stack traces to users.
- Avoid a permanent “Offline” warning: offline is the normal operating mode. No loading spinner waits for a network that is not needed.

## 12. Screen/state checklist

| Screen | Required states |
|---|---|
| Home | First launch; normal; no alerts; missing daily record; stock/debt warnings |
| Inventory | Empty; populated; searching; no matches; each filter; large dataset |
| Product detail | No batches; multiple dates; expired quantity; zero/archived history |
| Batch form | Full/partial dates in both calendars; no expiry; invalid dates |
| Adjustment sheet | One/multiple batches; invalid amount; insufficient stock; saving; undo failure |
| Daily Records | No entries; one entry; gaps; zero values; loss; monthly/custom range |
| Daily record form | New; existing date; editing; invalid amount; deletion |
| Debtors | Empty; mixed-script names; duplicate names; outstanding; settled |
| Customer detail | Empty history; debt; partial payment; settled; long descriptions |
| Ledger form | New debt/payment; overpayment; backdated conflicts; editing |
| Units | Active/inactive; used/unused; duplicate label; rename/reactivate |
| Backup & Restore | Never backed up; preparing; picker cancel; valid preview; corrupt/newer file; success/failure |

## 13. Accessibility and platform quality review

- VoiceOver and TalkBack read product name, quantity, status, and Add/Remove purpose clearly. Example: “Remove stock from Amoxicillin 500 mg.”
- Correct focus order, descriptive button semantics, and live-region announcements for errors/success where appropriate.
- Charts have text summaries and equivalent accessible data. Status is conveyed through words as well as color.
- Test smallest supported iPhone/Android viewport, notched screens, large text, landscape keyboard, and very long English/Persian names.
- No content behind home indicators, navigation bars, or keyboards. Sheet drag handles do not replace a usable Close/Cancel action.
- Native file access uses scoped pickers/share APIs; do not request broad device storage access unnecessarily.
- Bundle text/icon resources so first launch in airplane mode looks complete.
- Test actual native back behavior, sheets, date entry, sharing, and file picking on both platforms when environments are available. Record any unverified device behavior honestly.

## 14. Design acceptance walkthrough

An owner must be able to add a product, define a new unit, add two differently dated batches, manually remove from the intended batch, review low stock and expiry, enter a daily sales/profit pair, add a Persian-named debtor, write a free-text debt description, record a partial payment, and export/restore a backup without encountering checkout fields, authentication, hidden automation, or network requirements.

Review every screen with realistic but clearly isolated development fixtures, including Persian names and mixed-language notes. Do not ship those fixtures as the user's real data. Verify before/after states and error recovery, not only attractive static screenshots.

The finished app should make the next action obvious, show what a change will do before it is committed, and preserve the user's manual control throughout.
