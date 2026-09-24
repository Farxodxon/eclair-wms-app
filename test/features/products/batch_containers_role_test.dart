import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/batch_containers_screen.dart';

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier(String role) {
    state = AuthState(
      status: AuthStatus.loggedIn,
      token: 'test-token',
      user: {'role': role},
    );
  }
}

const _batch = <String, dynamic>{'id': 1, 'lot_number': 'LOT-TEST-001'};

const _containers = [
  {
    'id': 1,
    'container_barcode': 'BARCODE-001',
    'quantity': 10,
    'location_code': 'A-1-1',
    'status': 'in_stock',
  },
];

Future<void> _pumpScreen(
  WidgetTester tester,
  String role,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => FakeAuthNotifier(role)),
        batchContainersProvider.overrideWith(
          (arg, ref) => Future.value(_containers),
        ),
      ],
      child: MaterialApp(
        home: BatchContainersScreen(
          batch: _batch,
          productId: 1,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('OPERATOR: ADJUSTMENT yashirin, OUT/TRANSFER/history ochiq',
      (WidgetTester tester) async {
    await _pumpScreen(tester, 'operator');

    expect(find.text('Konteynerlar: LOT-TEST-001'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Chiqarish (OUT)'), findsOneWidget);
    expect(find.text("Ko'chirish (TRANSFER)"), findsOneWidget);
    expect(find.text('Tarix'), findsOneWidget);
    expect(find.text('Tuzatish (ADJUSTMENT)'), findsNothing);
  });

  testWidgets('SUPER_ADMIN: ADJUSTMENT mavjud', (WidgetTester tester) async {
    await _pumpScreen(tester, 'super_admin');

    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Chiqarish (OUT)'), findsOneWidget);
    expect(find.text("Ko'chirish (TRANSFER)"), findsOneWidget);
    expect(find.text('Tarix'), findsOneWidget);
    expect(find.text('Tuzatish (ADJUSTMENT)'), findsOneWidget);
  });

  test('canAdjust getter roli bo\'yicha to\'g\'ri ishlaydi', () {
    AuthState op(
            String role) =>
        AuthState(
            status: AuthStatus.loggedIn, token: 't', user: {'role': role});

    expect(op('operator').canAdjust, isFalse);
    expect(op('warehouse_manager').canAdjust, isTrue);
    expect(op('super_admin').canAdjust, isTrue);
  });
}