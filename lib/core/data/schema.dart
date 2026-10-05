import 'package:sqflite/sqflite.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Append new numbered migrations; never change a released migration.
const schemaVersion = 5;
const _maxMoney = 9000000000000000;
// Materialize the conversion library's leap-year set into a portable SQL CHECK.
// No native custom SQLite function is required on iOS or Android.
final _solarLeapYears = [
  for (var y = 1; y <= 3177; y++)
    if (Jalali(y).isLeapYear()) y,
].join(',');
final _sourceMonthLength =
    '''CASE WHEN calendar='solarHijri' THEN
  CASE WHEN month<=6 THEN 31 WHEN month<=11 THEN 30 ELSE 29+(year IN ($_solarLeapYears)) END
  ELSE CASE WHEN month IN (4,6,9,11) THEN 30 WHEN month=2 THEN
  28+(year%4=0 AND (year%100!=0 OR year%400=0)) ELSE 31 END END''';
String _uuid(String column) =>
    '''$column TEXT NOT NULL CHECK(
 length($column)=36 AND substr($column,9,1)='-' AND substr($column,14,1)='-'
 AND substr($column,19,1)='-' AND substr($column,24,1)='-'
 AND length(replace($column,'-',''))=32
 AND replace($column,'-','') NOT GLOB '*[^0-9a-f]*')''';
String _id() => '${_uuid('id')} PRIMARY KEY';
const _timestamps =
    '''created_at INTEGER NOT NULL CHECK(typeof(created_at)='integer' AND created_at>=0),
 updated_at INTEGER NOT NULL CHECK(typeof(updated_at)='integer' AND updated_at>=created_at)''';
String _flag(String name) =>
    '$name INTEGER NOT NULL DEFAULT 0 CHECK($name IN (0,1))';
String _quantity(String name) =>
    "$name INTEGER NOT NULL CHECK(typeof($name)='integer' AND $name BETWEEN 0 AND 2147483647)";
String _money(String name, {int min = -_maxMoney}) =>
    "$name INTEGER NOT NULL CHECK(typeof($name)='integer' AND $name BETWEEN $min AND $_maxMoney)";
String _text(String name) =>
    "$name TEXT NOT NULL CHECK(length(trim($name))>0 AND $name=trim($name))";

/// Explicit civil-date validation works on older native SQLite versions too.
String _date(String name) =>
    '''$name TEXT NOT NULL CHECK(
 $name GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND
 cast(substr($name,1,4) AS INTEGER) BETWEEN 1 AND 9999 AND
 cast(substr($name,6,2) AS INTEGER) BETWEEN 1 AND 12 AND
 cast(substr($name,9,2) AS INTEGER) BETWEEN 1 AND CASE
 WHEN cast(substr($name,6,2) AS INTEGER) IN (4,6,9,11) THEN 30
 WHEN cast(substr($name,6,2) AS INTEGER)=2 THEN 28 +
 (cast(substr($name,1,4) AS INTEGER)%4=0 AND
 (cast(substr($name,1,4) AS INTEGER)%100!=0 OR cast(substr($name,1,4) AS INTEGER)%400=0))
 ELSE 31 END)''';

Future<void> migrate(DatabaseExecutor db, int from, int to) async {
  if (from > to || to > schemaVersion) {
    throw StateError('Unsupported database version.');
  }
  for (var version = from + 1; version <= to; version++) {
    for (final sql in switch (version) {
      1 => _tables,
      2 => _guards,
      3 => _inventoryOperations,
      4 => _dailyOperations,
      5 => _debtOperations,
      _ => throw StateError('Missing migration'),
    }) {
      await db.execute(sql);
    }
  }
}

final _dailyOperations = <String>[
  '''CREATE TABLE daily_operations (${_id()}, kind TEXT NOT NULL CHECK(kind IN ('save','delete')),
    payload TEXT NOT NULL, result TEXT NOT NULL, $_timestamps)''',
  for (final operation in ['UPDATE', 'DELETE'])
    '''CREATE TRIGGER daily_operations_${operation.toLowerCase()} BEFORE $operation ON daily_operations
    BEGIN SELECT RAISE(ABORT,'Operation receipts are immutable'); END''',
];

final _debtOperations = <String>[
  '''CREATE TABLE debt_operations (${_id()}, kind TEXT NOT NULL,
    payload TEXT NOT NULL, result TEXT NOT NULL, $_timestamps)''',
  for (final operation in ['UPDATE', 'DELETE'])
    '''CREATE TRIGGER debt_operations_${operation.toLowerCase()} BEFORE $operation ON debt_operations
    BEGIN SELECT RAISE(ABORT,'Operation receipts are immutable'); END''',
  "ALTER TABLE customers ADD COLUMN phone_key TEXT NOT NULL DEFAULT ''",
  "UPDATE customers SET phone_key=replace(replace(replace(replace(replace(coalesce(phone,''),' ',''),'-',''),'(',''),')',''),'+','')",
  for (var digit = 0; digit < 10; digit++)
    "UPDATE customers SET phone_key=replace(replace(phone_key,'${'۰۱۲۳۴۵۶۷۸۹'[digit]}','$digit'),'${'٠١٢٣٤٥٦٧٨٩'[digit]}','$digit')",
  'CREATE INDEX customer_phone_search ON customers(archived,phone_key)',
];

final _inventoryOperations = <String>[
  '''CREATE TABLE inventory_operations (${_id()}, kind TEXT NOT NULL,
    payload TEXT NOT NULL, entity_id TEXT NOT NULL, $_timestamps)''',
  for (final operation in ['UPDATE', 'DELETE'])
    '''CREATE TRIGGER inventory_operations_${operation.toLowerCase()} BEFORE $operation ON inventory_operations
    BEGIN SELECT RAISE(ABORT,'Operation receipts are immutable'); END''',
  'CREATE INDEX batch_received ON batches(product_id,received_date,id)',
];

final _tables = <String>[
  '''CREATE TABLE units (${_id()}, ${_text('name')}, ${_text('name_key')},
    ${_flag('inactive')}, $_timestamps)''',
  '''CREATE TABLE products (${_id()}, ${_text('name')}, name_key TEXT NOT NULL,
    unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
    ${_quantity('minimum_stock')}, ${_quantity('warning_days')},
    category TEXT, notes TEXT, ${_flag('archived')}, $_timestamps)''',
  '''CREATE TABLE date_specs (${_id()},
    calendar TEXT NOT NULL CHECK(calendar IN ('gregorian','solarHijri')),
    precision TEXT NOT NULL CHECK(precision IN ('full','month')),
    year INTEGER NOT NULL CHECK(typeof(year)='integer' AND
      ((calendar='gregorian' AND year BETWEEN 622 AND 3798) OR
       (calendar='solarHijri' AND year BETWEEN 1 AND 3177))),
    month INTEGER NOT NULL CHECK(typeof(month)='integer' AND month BETWEEN 1 AND 12),
    day INTEGER CHECK(day IS NULL OR (typeof(day)='integer' AND day BETWEEN 1 AND 31)),
    ${_date('canonical_start')}, ${_date('canonical_end')},
    CHECK((precision='month' AND day IS NULL) OR (precision='full' AND day IS NOT NULL)),
    CHECK(canonical_start<=canonical_end),
    CHECK(precision!='full' OR canonical_start=canonical_end),
    CHECK(day IS NULL OR day<=($_sourceMonthLength)),
    CHECK(precision!='month' OR julianday(canonical_end)-julianday(canonical_start)=($_sourceMonthLength)-1),
    CHECK(calendar!='gregorian' OR
      (canonical_start=printf('%04d-%02d-%02d',year,month,coalesce(day,1)) AND
       canonical_end=printf('%04d-%02d-%02d',year,month,coalesce(day,($_sourceMonthLength))))))''',
  '''CREATE TABLE batches (${_id()}, product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    ${_text('label')}, ${_date('received_date')}, ${_quantity('quantity')},
    production_spec_id TEXT REFERENCES date_specs(id) ON DELETE RESTRICT,
    expiry_spec_id TEXT REFERENCES date_specs(id) ON DELETE RESTRICT,
    expiry_mode TEXT NOT NULL CHECK(expiry_mode IN ('full','month','none')),
    notes TEXT, ${_flag('archived')}, $_timestamps,
    CHECK((expiry_mode='none' AND expiry_spec_id IS NULL) OR
      (expiry_mode!='none' AND expiry_spec_id IS NOT NULL)))''',
  '''CREATE TABLE stock_movements (${_id()},
    sequence INTEGER NOT NULL UNIQUE CHECK(typeof(sequence)='integer' AND sequence>0),
    batch_id TEXT NOT NULL REFERENCES batches(id) ON DELETE RESTRICT,
    kind TEXT NOT NULL CHECK(kind IN ('opening','add','remove','reversal')),
    delta INTEGER NOT NULL CHECK(typeof(delta)='integer' AND delta!=0 AND abs(delta)<=2147483647),
    ${_quantity('resulting_quantity')},
    reversal_of TEXT UNIQUE REFERENCES stock_movements(id) ON DELETE RESTRICT,
    note TEXT, $_timestamps,
    CHECK((kind IN ('opening','add') AND delta>0 AND reversal_of IS NULL) OR
      (kind='remove' AND delta<0 AND reversal_of IS NULL) OR
      (kind='reversal' AND reversal_of IS NOT NULL)))''',
  '''CREATE TABLE daily_records (${_id()}, ${_date('business_date')} UNIQUE,
    ${_money('sales_minor', min: 0)}, ${_money('profit_minor')}, note TEXT, $_timestamps)''',
  '''CREATE TABLE customers (${_id()}, ${_text('name')}, name_key TEXT NOT NULL,
    phone TEXT, note TEXT, ${_flag('archived')}, $_timestamps)''',
  '''CREATE TABLE ledger_entries (${_id()},
    customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    ${_date('business_date')},
    sequence INTEGER NOT NULL UNIQUE CHECK(typeof(sequence)='integer' AND sequence>0),
    kind TEXT NOT NULL CHECK(kind IN ('debt','payment')),
    ${_money('amount_minor', min: 1)}, description TEXT NOT NULL, $_timestamps)''',
  // entry_id deliberately has no FK: deletion must retain the correction audit.
  '''CREATE TABLE correction_audits (${_id()}, ${_uuid('entry_id')},
    customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    action TEXT NOT NULL CHECK(action IN ('edit','delete')),
    previous_value TEXT NOT NULL, new_value TEXT,
    ${_text('reason')}, $_timestamps,
    CHECK((action='delete' AND new_value IS NULL) OR (action='edit' AND new_value IS NOT NULL)))''',
  '''CREATE TABLE app_settings (${_id()}, preference_key TEXT NOT NULL UNIQUE,
    value TEXT NOT NULL, version INTEGER NOT NULL CHECK(version>0), $_timestamps)''',
];

final _guards = <String>[
  '''CREATE TABLE sequence_counters (name TEXT PRIMARY KEY NOT NULL,
    value INTEGER NOT NULL CHECK(typeof(value)='integer' AND value>=0))''',
  "INSERT INTO sequence_counters SELECT 'ledger_entries',coalesce(max(sequence),0) FROM ledger_entries",
  "INSERT INTO sequence_counters SELECT 'stock_movements',coalesce(max(sequence),0) FROM stock_movements",
  'CREATE UNIQUE INDEX active_unit_name ON units(name_key) WHERE inactive=0',
  'CREATE INDEX product_search ON products(archived,name_key)',
  'CREATE INDEX batch_product ON batches(product_id,archived)',
  'CREATE INDEX batch_expiry ON batches(expiry_spec_id) WHERE archived=0 AND quantity>0',
  'CREATE INDEX movement_history ON stock_movements(batch_id,sequence)',
  'CREATE INDEX customer_search ON customers(archived,name_key)',
  'CREATE INDEX ledger_history ON ledger_entries(customer_id,business_date,sequence)',
  'CREATE INDEX correction_history ON correction_audits(customer_id,created_at)',
  for (final table in [
    'units',
    'products',
    'date_specs',
    'batches',
    'stock_movements',
    'daily_records',
    'customers',
    'ledger_entries',
    'correction_audits',
    'app_settings',
  ])
    '''CREATE TRIGGER ${table}_stable_id BEFORE UPDATE OF id ON $table
       WHEN NEW.id!=OLD.id BEGIN SELECT RAISE(ABORT,'Identity is immutable'); END''',
  for (final table in ['stock_movements', 'correction_audits', 'date_specs'])
    for (final operation in ['UPDATE', 'DELETE'])
      '''CREATE TRIGGER ${table}_${operation.toLowerCase()} BEFORE $operation ON $table
         BEGIN SELECT RAISE(ABORT,'History and date specifications are immutable'); END''',
  '''CREATE TRIGGER product_unit_locked BEFORE UPDATE OF unit_id ON products
    WHEN NEW.unit_id!=OLD.unit_id AND EXISTS(SELECT 1 FROM stock_movements m
    JOIN batches b ON b.id=m.batch_id WHERE b.product_id=OLD.id)
    BEGIN SELECT RAISE(ABORT,'Unit is locked by stock history'); END''',
  for (final op in ['INSERT', 'UPDATE OF unit_id'])
    '''CREATE TRIGGER product_active_unit_${op == 'INSERT' ? 'insert' : 'update'} BEFORE $op ON products
      WHEN (SELECT inactive FROM units WHERE id=NEW.unit_id)=1
      AND ${op == 'INSERT' ? '1=1' : 'NEW.unit_id!=OLD.unit_id'}
      BEGIN SELECT RAISE(ABORT,'Choose an active unit'); END''',
  '''CREATE TRIGGER product_archive BEFORE UPDATE OF archived ON products
    WHEN NEW.archived=1 AND EXISTS(SELECT 1 FROM batches WHERE product_id=OLD.id AND quantity>0)
    BEGIN SELECT RAISE(ABORT,'Remove physical stock before archiving'); END''',
  '''CREATE TRIGGER batch_archive BEFORE UPDATE OF archived ON batches WHEN NEW.archived=1 AND NEW.quantity!=0
    BEGIN SELECT RAISE(ABORT,'Remove physical stock before archiving'); END''',
  '''CREATE TRIGGER batch_initial_quantity BEFORE INSERT ON batches WHEN NEW.quantity!=0 OR NEW.archived!=0
    BEGIN SELECT RAISE(ABORT,'Use an opening movement for initial stock'); END''',
  '''CREATE TRIGGER batch_product_locked BEFORE UPDATE OF product_id ON batches WHEN NEW.product_id!=OLD.product_id
    BEGIN SELECT RAISE(ABORT,'Batch product is immutable'); END''',
  for (final op in ['INSERT', 'UPDATE'])
    '''CREATE TRIGGER batch_dates_${op.toLowerCase()} BEFORE $op ON batches
      WHEN (NEW.expiry_spec_id IS NOT NULL AND NEW.expiry_mode!=(SELECT precision FROM date_specs WHERE id=NEW.expiry_spec_id))
      OR ((SELECT canonical_start FROM date_specs WHERE id=NEW.production_spec_id)>
          (SELECT canonical_end FROM date_specs WHERE id=NEW.expiry_spec_id))
      BEGIN SELECT RAISE(ABORT,'Invalid batch date range or precision'); END''',
  '''CREATE TRIGGER batch_quantity_guard BEFORE UPDATE OF quantity ON batches
    WHEN NEW.quantity!=coalesce((SELECT sum(delta) FROM stock_movements WHERE batch_id=NEW.id),0)
    BEGIN SELECT RAISE(ABORT,'Quantity must reconcile with movement history'); END''',
  '''CREATE TRIGGER movement_validate BEFORE INSERT ON stock_movements BEGIN
    SELECT CASE WHEN NEW.resulting_quantity!=(SELECT quantity FROM batches WHERE id=NEW.batch_id)+NEW.delta
      THEN RAISE(ABORT,'Movement result does not match batch quantity') END;
    SELECT CASE WHEN (SELECT archived FROM batches WHERE id=NEW.batch_id)=1 OR
      (SELECT p.archived FROM products p JOIN batches b ON p.id=b.product_id WHERE b.id=NEW.batch_id)=1
      THEN RAISE(ABORT,'Restore archived records before adjusting') END;
    SELECT CASE WHEN NEW.kind='opening' AND EXISTS(SELECT 1 FROM stock_movements WHERE batch_id=NEW.batch_id)
      THEN RAISE(ABORT,'Opening movement must be first') END;
    SELECT CASE WHEN NEW.kind='reversal' AND NOT EXISTS(SELECT 1 FROM stock_movements m
      WHERE m.id=NEW.reversal_of AND m.batch_id=NEW.batch_id AND m.delta=-NEW.delta AND m.kind!='reversal')
      THEN RAISE(ABORT,'Invalid reversal') END;
    SELECT CASE WHEN NEW.sequence<=coalesce((SELECT max(sequence) FROM stock_movements),0)
      THEN RAISE(ABORT,'Movement order must increase') END;
    END''',
  '''CREATE TRIGGER movement_apply AFTER INSERT ON stock_movements BEGIN
    UPDATE batches SET quantity=NEW.resulting_quantity,updated_at=max(updated_at,NEW.created_at) WHERE id=NEW.batch_id; END''',
  '''CREATE TRIGGER ledger_identity BEFORE UPDATE ON ledger_entries
    WHEN NEW.customer_id!=OLD.customer_id OR NEW.sequence!=OLD.sequence OR NEW.created_at!=OLD.created_at
    BEGIN SELECT RAISE(ABORT,'Ledger ordering and owner are immutable'); END''',
  for (final op in ['INSERT', 'UPDATE', 'DELETE'])
    '''CREATE TRIGGER ledger_balance_${op.toLowerCase()} AFTER $op ON ledger_entries
    WHEN EXISTS(SELECT 1 FROM ledger_entries a WHERE a.customer_id=${op == 'DELETE' ? 'OLD' : 'NEW'}.customer_id AND
      (SELECT sum(CASE WHEN b.kind='debt' THEN b.amount_minor ELSE -b.amount_minor END)
       FROM ledger_entries b WHERE b.customer_id=a.customer_id AND
       (b.business_date<a.business_date OR (b.business_date=a.business_date AND b.sequence<=a.sequence))) NOT BETWEEN 0 AND $_maxMoney)
    BEGIN SELECT RAISE(ABORT,'A chronological balance is outside the supported range'); END''',
  for (final op in ['INSERT', 'UPDATE'])
    '''CREATE TRIGGER ledger_active_${op.toLowerCase()} BEFORE $op ON ledger_entries
    WHEN (SELECT archived FROM customers WHERE id=NEW.customer_id)=1
    BEGIN SELECT RAISE(ABORT,'Restore customer before changing ledger'); END''',
  '''CREATE TRIGGER customer_archive BEFORE UPDATE OF archived ON customers WHEN NEW.archived=1 AND
    coalesce((SELECT sum(CASE WHEN kind='debt' THEN amount_minor ELSE -amount_minor END)
      FROM ledger_entries WHERE customer_id=OLD.id),0)!=0
    BEGIN SELECT RAISE(ABORT,'Settle debt before archiving'); END''',
];
