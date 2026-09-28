import 'package:blabliblu/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoneyFormat.rupees (paise -> ₹)', () {
    test('drops whole-rupee fractions', () {
      expect(MoneyFormat.rupees(69500), '₹695');
      expect(MoneyFormat.rupees(0), '₹0');
      expect(MoneyFormat.rupees(100000), '₹1,000');
    });

    test('keeps paise when the amount is not a round rupee', () {
      expect(MoneyFormat.rupees(1050), '₹10.50');
      expect(MoneyFormat.rupees(1), '₹0.01');
    });

    test('groups thousands', () {
      expect(MoneyFormat.rupees(123456700), '₹1,234,567');
    });
  });

  group('ProductPage.fromJson', () {
    test('reads pagination meta and keeps supplied items', () {
      const item = ProductCard(id: 'p1', handle: 'love-drunk', title: 'Love Drunk', price: 69500);
      final page = ProductPage.fromJson(const {'total': 69, 'page': 2, 'totalPages': 3}, items: const [item]);

      expect(page.items, hasLength(1));
      expect(page.total, 69);
      expect(page.page, 2);
      expect(page.totalPages, 3);
    });

    test('falls back to the item count when meta is missing', () {
      final page = ProductPage.fromJson(const {}, items: const [
        ProductCard(id: 'a', handle: 'a', title: 'A', price: 100),
        ProductCard(id: 'b', handle: 'b', title: 'B', price: 200),
      ]);

      expect(page.total, 2);
      expect(page.page, 1);
      expect(page.totalPages, 1);
    });
  });

  group('Address.toShipping', () {
    test('flattens the saved book entry into a checkout address', () {
      const address = Address(
        id: 'a1',
        label: 'Office',
        line1: '404, Palm Court',
        line2: 'MG Road',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560001',
        phone: '9876543210',
      );

      final shipping = address.toShipping('Aditi Sharma');

      expect(shipping.name, 'Aditi Sharma');
      expect(shipping.phone, '9876543210');
      expect(shipping.label, 'Office');
      expect(shipping.singleLine, '404, Palm Court, MG Road, Bengaluru, Karnataka, 560001');
    });
  });
}
