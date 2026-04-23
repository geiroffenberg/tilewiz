import 'package:flutter_test/flutter_test.dart';

import 'package:tilewiz/main.dart';

void main() {
  testWidgets('TileWiz app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TileWizApp());
    await tester.pump();
    expect(find.text('TileWiz'), findsWidgets);
  });
}
