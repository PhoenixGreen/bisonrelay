import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// markdown_list_marker_test.dart covers the number beside a numbered list.
//
// Reported: in a list of more than nine items, every item from 10 onwards
// broke across two lines with the full stop alone on the second. The package
// puts the marker in a SizedBox one indent wide, the app draws its own marker
// into it, and a Text in a box too narrow wraps -- so "10." came out as "10"
// and ".". Single digits fitted, which is why every list anyone had looked at
// until then was fine.
//
// Pumped through MarkdownArea rather than MarkdownBody, which is the whole
// reason this file exists rather than a group in markdown_render_test.dart:
// the marker and the width it is given are both the app's, and a test that
// builds MarkdownBody itself gets flutter_markdown's own marker and proves
// nothing about either.

Future<void> _pump(WidgetTester tester, String data) =>
    tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
      ],
      child: MaterialApp(home: Scaffold(body: MarkdownArea(data, false))),
    ));

/// _markers is every list marker drawn, in order.
List<String> _markers(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? "")
    .where((s) => RegExp(r"^\d+\.$").hasMatch(s))
    .toList();

/// _marker finds one marker's Text, or null.
Text? _marker(WidgetTester tester, String label) {
  for (var t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data == label) return t;
  }
  return null;
}

/// _numbered is a list from [first] to [last], one item per line.
String _numbered(int first, int last) =>
    [for (var i = first; i <= last; i++) "$i. item number $i"].join("\n");

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("a two-digit marker survives as one string", (tester) async {
    await _pump(tester, _numbered(1, 12));
    await tester.pump();

    expect(_markers(tester), contains("10."));
    expect(_markers(tester), contains("12."));
    expect(find.text("."), findsNothing,
        reason: "a full stop on its own is the wrap this exists to prevent");
  });

  testWidgets("a two-digit marker is not allowed to wrap", (tester) async {
    await _pump(tester, _numbered(8, 11));
    await tester.pump();

    var ten = _marker(tester, "10.");
    expect(ten, isNotNull);
    expect(ten!.maxLines, 1);
    expect(ten.softWrap, isFalse);
  });

  testWidgets("a three-digit list keeps its markers whole", (tester) async {
    await _pump(tester, _numbered(98, 103));
    await tester.pump();

    expect(_markers(tester), contains("100."));
    expect(find.text("."), findsNothing);
  });

  testWidgets("a list of nine is still numbered one to nine", (tester) async {
    await _pump(tester, _numbered(1, 9));
    await tester.pump();

    expect(_markers(tester),
        ["1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "9."]);
  });

  // The marker column is widened to fit the widest number actually written,
  // so a list that needs the room gets it and a short one is not pushed
  // across the page for nothing.
  //
  // Measured as the width of the box the package puts the marker in, which
  // is the thing that was too small. Kept to twelve items because a list
  // long enough to overflow the test viewport fails for that reason instead.
  testWidgets("the marker column grows with the widest number", (tester) async {
    double markerWidth(WidgetTester t) => t
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((b) => b.width ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    await _pump(tester, _numbered(1, 9));
    await tester.pump();
    var short = markerWidth(tester);

    await _pump(tester, _numbered(1, 12));
    await tester.pump();
    var long = markerWidth(tester);

    expect(long, greaterThan(short),
        reason: "two digits need more room than one, and asking for it is "
            "what keeps the marker inside its column");
  });
}
