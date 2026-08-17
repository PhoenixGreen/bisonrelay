import 'package:bruig/plugin_system/writing_tools/notes/notes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// notes_settings_test.dart covers the two decisions the reader gets to make
// about notes, and the fact that both of them stick.
//
// Persistence is the point of the second half. The writing tools' own
// "enabled" switch beside these deliberately does not persist -- it is "stop
// correcting me for a minute", a mood. These are the shape of the window, and
// a notes button that moved back to the middle on every restart would read as
// a bug rather than a default.

Future<NotesPreferences> _pumpSection(WidgetTester tester,
    {NotesPreferences? prefs}) async {
  var p = prefs ?? NotesPreferences();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<NotesPreferences>.value(value: p),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: NotesSettingsSection()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("notes are on to begin with", (tester) async {
    var prefs = await _pumpSection(tester);
    // On by default: notes are a feature of the writing tools, and somebody
    // who has enabled the writing tools has already said what they want.
    expect(prefs.enabled, isTrue);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets("switching notes off takes the button choice with it",
      (tester) async {
    var prefs = await _pumpSection(tester);
    expect(find.byType(DropdownButton<NotesButtonPosition>), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(prefs.enabled, isFalse);
    // Where a button that is not drawn would sit is not a question worth
    // leaving on the page.
    expect(find.byType(DropdownButton<NotesButtonPosition>), findsNothing);
  });

  testWidgets("the button position can be changed", (tester) async {
    var prefs = await _pumpSection(tester);
    expect(prefs.position, NotesButtonPosition.leftTriangle);

    await tester.tap(find.byType(DropdownButton<NotesButtonPosition>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesButtonPosition.threeDots.label).last);
    await tester.pumpAndSettle();

    expect(prefs.position, NotesButtonPosition.threeDots);
    // The description under the dropdown follows the choice, so the label and
    // where the thing actually lands are never read separately.
    expect(
        find.text(NotesButtonPosition.threeDots.description), findsOneWidget);
  });

  group("both choices survive a restart", () {
    testWidgets("what was saved is what loads", (tester) async {
      var first = await _pumpSection(tester);
      first.enabled = false;
      first.position = NotesButtonPosition.rightTriangle;
      await tester.pumpAndSettle();

      // A second run of the app, reading the same store.
      var next = NotesPreferences();
      await tester.runAsync(next.load);
      expect(next.enabled, isFalse);
      expect(next.position, NotesButtonPosition.rightTriangle);
    });

    testWidgets("a position that no longer exists falls back", (tester) async {
      SharedPreferences.setMockInitialValues(
          {"notesButtonPosition": "someShapeWeUsedToHave"});
      var prefs = NotesPreferences();
      await tester.runAsync(prefs.load);
      // Named rather than indexed, so a value written by another build lands
      // on the default instead of out of range.
      expect(prefs.position, NotesButtonPosition.leftTriangle);
      expect(prefs.enabled, isTrue);
    });
  });
}
