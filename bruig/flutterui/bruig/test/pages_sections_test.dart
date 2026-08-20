import 'package:bruig/screens/pages/sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// pages_sections_test.dart covers the one thing PagesSections exists for:
// a section that is not being looked at is still built, so anything half
// done in it is still there on the way back.
//
// Written against stand-ins rather than the real sections, which need a
// running client. What is being pinned is the decision -- keep them all
// alive -- so swapping this back to a switch on the visible section has to
// fail here.

class _Editor extends StatefulWidget {
  final String label;
  const _Editor(this.label);
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final ctrl = TextEditingController();
  static int built = 0;

  @override
  void initState() {
    super.initState();
    built++;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(widget.label),
        Expanded(child: TextField(controller: ctrl)),
      ]);
}

void main() {
  Future<void> pump(WidgetTester tester, int index) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PagesSections(
            index: index,
            visit: const _Editor("visit"),
            mySite: const _Editor("mySite"),
            store: const _Editor("store"),
            browser: const _Editor("browser"),
          ),
        ),
      ));

  testWidgets('what was typed survives a trip to another section',
      (tester) async {
    await pump(tester, 1); // My Site
    // skipOffstage: false throughout -- a section that is not showing is
    // still in the tree, which is the property under test. The finder's
    // default hides exactly the widgets this is about.
    var fields = find.byType(TextField, skipOffstage: false);
    await tester.enterText(fields.at(1), "half a page");

    // Off to an open page, then back.
    await pump(tester, PagesSections.browserIndex);
    await pump(tester, 1);

    var field = tester.widget<TextField>(fields.at(1));
    expect(field.controller?.text, "half a page");
  });

  testWidgets('a section is built once, not once per visit', (tester) async {
    _EditorState.built = 0;
    await pump(tester, 0);
    expect(_EditorState.built, 4, reason: "all four built up front");

    await pump(tester, 2);
    await pump(tester, 0);
    await pump(tester, PagesSections.browserIndex);
    // No section was rebuilt from scratch, which is what would have thrown
    // an editor's State away.
    expect(_EditorState.built, 4);
  });

  testWidgets('only the chosen section is on screen', (tester) async {
    await pump(tester, 2);
    expect(find.text("store"), findsOneWidget);
    // The others are built but not shown -- present in the tree, absent
    // from the screen.
    expect(find.text("visit"), findsNothing);
    expect(find.text("browser"), findsNothing);
    expect(find.text("visit", skipOffstage: false), findsOneWidget);
  });

  testWidgets('an index past the end does not throw', (tester) async {
    await pump(tester, 99);
    expect(tester.takeException(), isNull);
  });
}
