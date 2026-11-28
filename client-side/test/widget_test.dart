import 'package:calculate/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App starts on Homepage with Přidat jídlo button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Přidat jídlo'), findsOneWidget);
  });
}
