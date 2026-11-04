import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tracking/nav_widgets.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('the turn banner shows the distance, the instruction and the icon', (tester) async {
    await tester.pumpWidget(wrap(const TurnBanner(icon: Icons.turn_left, distance: '120 m', text: 'Turn left onto Waiyaki Way')));
    expect(find.text('120 m'), findsOneWidget);
    expect(find.text('Turn left onto Waiyaki Way'), findsOneWidget);
    expect(find.byIcon(Icons.turn_left), findsOneWidget);
  });

  testWidgets('the bottom card shows the ETA, the detail, the note and its buttons', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(Column(children: [
      const Spacer(),
      NavBottomCard(
        title: '5 min',
        subtitle: '2.4 km · arrive about 10:42',
        note: 'An estimate. Traffic can change it.',
        actions: [
          FilledButton(onPressed: () => taps++, child: const Text('Call caller')),
          OutlinedButton(onPressed: () {}, child: const Text('Google Maps')),
        ],
      ),
    ])));
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('2.4 km · arrive about 10:42'), findsOneWidget);
    expect(find.text('An estimate. Traffic can change it.'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
    await tester.tap(find.text('Call caller'));
    expect(taps, 1);
  });

  testWidgets('the bottom card works with no note and no buttons', (tester) async {
    await tester.pumpWidget(wrap(const Column(children: [Spacer(), NavBottomCard(title: 'Arrived', subtitle: 'Unit is with you')])));
    expect(find.text('Arrived'), findsOneWidget);
    expect(find.text('Unit is with you'), findsOneWidget);
  });

  testWidgets('a round map button reacts to a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(MapRoundButton(icon: Icons.satellite_alt, tooltip: 'Satellite view', onTap: () => taps++)));
    await tester.tap(find.byIcon(Icons.satellite_alt));
    expect(taps, 1);
  });

  testWidgets('the freshness chip shows its label', (tester) async {
    await tester.pumpWidget(wrap(const FreshChip(label: 'Live', color: Colors.green)));
    expect(find.text('Live'), findsOneWidget);
  });
}
