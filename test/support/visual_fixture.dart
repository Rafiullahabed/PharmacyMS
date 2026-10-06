import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:uuid/uuid.dart';
import 'inventory_database.dart';

extension FixtureDate on BusinessDate {
  BusinessDate addDays(int days) =>
      BusinessDate.fromLocal(DateTime.utc(year, month, day + days));
}

/// Development-only review data. Never imported by lib/ or a production entrypoint.
class VisualFixture extends InventoryDatabase {
  late Product medicine, persian;
  late Batch todayBatch, laterBatch;
  late Customer customer, settled;
  late LedgerEntry payment;
  String get operation => const Uuid().v4();

  Future<void> seed() async {
    clock.date = BusinessDate(2026, 10, 6);
    final units = await services.settings.units();
    final unit = units.first.meta.id;
    medicine = await services.inventory.createProduct(
      name: 'Amoxicillin 250 mg · Family pack',
      unitId: unit,
      minimumStock: 20,
      warningDays: 30,
      category: 'Medicine',
      notes: 'Count each sealed bottle. Keep deliveries separate.',
    );
    todayBatch = await services.inventory.createBatch(
      productId: medicine.meta.id,
      label: 'October delivery · A-1026',
      receivedDate: clock.today(),
      openingQuantity: 8,
      expiry: DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 10,
        day: 6,
      ),
    );
    laterBatch = await services.inventory.createBatch(
      productId: medicine.meta.id,
      label: 'تحویل دوم · B-1026',
      receivedDate: clock.today(),
      openingQuantity: 5,
      production: DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1405,
        month: 1,
      ),
      expiry: DateSpec(calendar: DateCalendar.solarHijri, year: 1405, month: 7),
    );
    await services.inventory.createBatch(
      productId: medicine.meta.id,
      label: 'September delivery · expired',
      receivedDate: clock.today().addDays(-12),
      openingQuantity: 3,
      expiry: DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 9,
        day: 30,
      ),
    );
    persian = await services.inventory.createProduct(
      name: 'کریم مرطوب‌کننده مخصوص پوست حساس · Sensitive skin 100 ml',
      unitId: unit,
      minimumStock: 5,
    );
    await services.inventory.createBatch(
      productId: persian.meta.id,
      label: 'تحویل کابل',
      receivedDate: clock.today(),
      openingQuantity: 24,
    );
    final equipment = await services.inventory.createProduct(
      name: 'Digital thermometer',
      unitId: unit,
    );
    await services.inventory.createBatch(
      productId: equipment.meta.id,
      receivedDate: clock.today(),
      openingQuantity: 6,
    );
    final archived = await services.inventory.createProduct(
      name: 'Archived vitamin supplement',
      unitId: unit,
    );
    await services.inventory.archiveProduct(
      archived.meta.id,
      archived: true,
      operationId: operation,
    );
    for (final row in [
      (0, '15400.50', '2100.25'),
      (1, '9800', '-350.75'),
      (3, '0', '0'),
      (4, '18420.10', '2430.50'),
      (6, '12100', '950'),
    ]) {
      await services.dailyRecords.save(
        date: clock.today().addDays(-row.$1),
        sales: Money.parse(row.$2),
        profit: Money.parse(row.$3),
        note: row.$1 == 1
            ? 'مصارف امروز · Manually recorded loss\nDelivery and operating costs.'
            : null,
      );
    }
    customer = await services.debtors.createCustomer(
      name: 'احمد محمدی · Ahmad Mohammadi',
      phone: '00700123456',
      note: 'همسایه دواخانه · Call in the afternoon.',
    );
    await services.debtors.createCustomer(
      name: customer.name,
      note: 'Different customer · No phone supplied',
    );
    settled = await services.debtors.createCustomer(name: 'Maryam Rahimi');
    for (final amount in ['500', '300']) {
      await services.debtors.addEntry(
        operationId: operation,
        customerId: customer.meta.id,
        date: clock.today().addDays(-2),
        kind: LedgerKind.debt,
        amount: Money.parse(amount),
        description:
            'دو بوتل شربت و کریم برای خانواده\nAmoxicillin 250 mg · Payment promised after the weekend.',
      );
    }
    payment = await services.debtors.addEntry(
      operationId: operation,
      customerId: customer.meta.id,
      date: clock.today(),
      kind: LedgerKind.payment,
      amount: Money.parse('200'),
      description: 'پرداخت نقدی · Cash received',
    );
    payment = await services.debtors.editEntry(
      operationId: operation,
      id: payment.meta.id,
      date: payment.date,
      kind: payment.kind,
      amount: payment.amount,
      description: '${payment.description}\nReceipt checked with customer.',
      reason: 'Clarified description',
    );
  }
}
