import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/scanner/scan_result_screen.dart';

/// Real server (http://localhost:8080) ustida skaner OUT oqimini tekshiradi.
/// setUpAll konteyner yaratadi (batch 3 — approved, 20 dona x 25 kg = 500 kg).
/// Eslatma: batch 18/19 quality_status=pending_inspection -> OUT 400
/// batch_not_approved beradi, shuning uchun approved batch 3 ishlatiladi.

const _batchId = 3;
late String _token;
late Map<String, dynamic> _container;

class _FakeAuth extends AuthNotifier {
  _FakeAuth(String token) {
    state = AuthState(
      status: AuthStatus.loggedIn,
      token: token,
      user: {'role': 'super_admin'},
    );
  }
}

Future<void> _pumpResult(
  WidgetTester tester,
  Map<String, dynamic> data,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith((ref) => _FakeAuth(_token))],
      child: MaterialApp(
        home: ScanResultScreen(
          type: ScanResultType.container,
          data: data,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Real HTTP (Dio) testWidgets ichida ishlashi uchun Live binding kerak —
  // Automated binding FakeAsync da real tarmoq hodisalarini yetkazmaydi.
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    final api = ApiClient();
    final login = await api.login('admin@eclair.uz', 'Test1234!');
    _token = login['token'] as String;
    final created = await api.createBatchContainer(_token, _batchId, {
      'unit_count': 20,
      'unit_weight_kg': 25,
    });
    final barcode = created['container_barcode'] as String;
    final full = await api.getContainerByBarcode(_token, barcode);
    expect(full, isNotNull, reason: 'konteyner topilmadi: $barcode');
    _container = full!;
  });

  testWidgets('konteyner kartasi + OUT dialog (idish rejimi) + real saqlash',
      (tester) async {
    HttpOverrides.global = null;
    await _pumpResult(tester, _container);

    // --- karta ---
    expect(find.text(_container['container_barcode'] as String), findsOneWidget);
    expect(find.text('Mahsulot'), findsOneWidget);
    expect(find.text(_container['product_name'] as String), findsOneWidget);
    expect(find.text('SKU'), findsOneWidget);
    expect(find.text(_container['product_sku'] as String), findsOneWidget);
    expect(find.text('Joriy miqdor'), findsOneWidget);
    expect(find.text('20 dona x 25 kg = 500 kg'), findsOneWidget);
    expect(find.text('1 idish'), findsOneWidget);
    expect(find.text('25 kg'), findsOneWidget);
    expect(find.text('Chiqarish (OUT)'), findsOneWidget);
    expect(find.text('Yana skanerlash'), findsOneWidget);

    // --- OUT dialog ---
    await tester.tap(find.text('Chiqarish (OUT)'));
    await tester.pumpAndSettle();

    expect(find.text('Chiqarish (OUT)'), findsWidgets); // title + appbar button
    expect(
      find.text('${_container['product_sku']} | ${_container['product_name']}'),
      findsOneWidget,
    );
    expect(
      find.text(
          '${_container['container_barcode']} | mavjud: 20 dona x 25 kg = 500 kg'),
      findsOneWidget,
    );
    expect(find.text('1 idishda: 25 kg'), findsOneWidget);
    expect(find.text('Idish soni'), findsOneWidget);
    expect(find.text('Izoh (ixtiyoriy)'), findsOneWidget);

    // --- Jami: 10 dona -> 250 kg ---
    await tester.enterText(find.byType(TextFormField).first, '10');
    await tester.pump();
    expect(find.text('Jami: 250 kg'), findsOneWidget);

    // --- validator: 100 dona (2500 kg) mavjuddan ko'p ---
    await tester.enterText(find.byType(TextFormField).first, '100');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Chiqarish'));
    await tester.pump();
    expect(find.text("Mavjuddan ko'p bo'lishi mumkin emas"), findsOneWidget);
    expect(find.text('Chiqarish bajarildi, qoldi: 250'), findsNothing);

    // --- real API orqali saqlash ---
    await tester.enterText(find.byType(TextFormField).first, '10');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Chiqarish'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chiqarish bajarildi'), findsOneWidget);
    expect(find.textContaining('qoldi: 250'), findsOneWidget);

    // serverda qoldi 250 kg bo'lishi kerak
    final after = await ApiClient().getContainerByBarcode(
        _token, _container['container_barcode'] as String);
    expect(after!['quantity'], 250);
  });

  testWidgets("eski konteyner: unit_weight_kg yo'q -> Miqdor (kg) rejimi",
      (tester) async {
    HttpOverrides.global = null;
    final legacy = <String, dynamic>{
      'id': 999001,
      'container_barcode': 'LEG-TEST-001',
      'product_sku': 'LEG-SKU',
      'product_name': 'Legacy Mahsulot',
      'lot_number': 'LEG-LOT',
      'quantity': 120,
      'unit_weight_kg': null,
    };
    await _pumpResult(tester, legacy);

    expect(find.text('LEG-TEST-001'), findsOneWidget);
    expect(find.text('120 kg'), findsOneWidget); // _amountText (kg)
    expect(find.text('1 idish'), findsNothing);

    await tester.tap(find.text('Chiqarish (OUT)'));
    await tester.pumpAndSettle();

    expect(find.text('Miqdor (kg)'), findsOneWidget);
    expect(find.text('Idish soni'), findsNothing);
    expect(find.textContaining('Jami:'), findsNothing);
    expect(find.textContaining('1 idishda:'), findsNothing);
    expect(find.text('LEG-SKU | Legacy Mahsulot'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '30');
    await tester.pump();
    expect(find.textContaining('Jami:'), findsNothing); // rejim yo'q

    await tester.tap(find.widgetWithText(TextButton, 'Bekor qilish'));
    await tester.pumpAndSettle();
    expect(find.text('Chiqarish (OUT)'), findsOneWidget); // dialog yopildi
  });
}
