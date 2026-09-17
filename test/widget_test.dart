import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wms_app/main.dart';

void main() {
  testWidgets('Ilova login ekrani bilan ochiladi', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WmsApp()));
    await tester.pump();

    expect(find.text('Tizimga kirish'), findsOneWidget);
    expect(find.text('Kirish'), findsOneWidget);
  });
}