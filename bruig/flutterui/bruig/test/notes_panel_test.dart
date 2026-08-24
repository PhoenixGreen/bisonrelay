import 'dart:io';

import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/notes/notes.dart';
import 'package:bruig/plugin_system/writing_tools/notes/ui/notes_button.dart';
import 'package:bruig/plugin_system/writing_tools/notes/ui/notes_panel.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// notes_panel_test.dart drives the notes UI rather than the model under it.
//
// That distinction has bitten this codebase before: a model-only suite let two
// controls ship that were wired to nothing, because every test called the
// model directly and none of them ever pressed anything. So these press the
// button, drag the handle and tap the switch, through the same NotesHost the
// app wraps its content area in.

/// _idle lets the real filesystem work these tests provoke actually finish.
///
/// Notes read and write through PostStorage, which is real file I/O against a
/// real temp directory -- deliberately, because "a note is an ordinary
/// document in the library" is a claim about disk, and a stubbed filesystem
/// would agree with whatever the code did.
///
/// testWidgets runs in a fake-async zone, where a dart:io future completes on
/// the real event loop but its continuation is a microtask in the fake one. So
/// one step of the chain needs one runAsync (to turn the real loop) followed
/// by one pump (to drain the microtask it queued) -- and reading a note is
/// half a dozen such steps deep, through the index, the listing and the file.
/// A single runAsync gets one step in and stops.
///
/// The symptom when this is wrong is worth recording, because it looks like
/// nothing: the panel is left on its loading spinner, the spinner animates
/// forever, and pumpAndSettle hangs the whole suite with no error.
///
/// The count was generous rather than tuned, and generous is not a property
/// a wait can have: it is a fixed budget of turns, so whether it is enough
/// depends on how busy the machine is. That is the shape of a test that
/// passes on its own and fails once in a while in a full run, which is what
/// this file did twice -- in two different tests, neither reproducible
/// afterwards.
///
/// So the floor stays exactly what it was, and the wait now keeps going past
/// it while the panel is visibly still working. Never fewer turns than
/// before, more when there is something to wait for.
///
/// The spinner is the condition because it is the documented symptom: the
/// panel left on its loading spinner is what a wait that ended too early
/// looks like from the outside.
const _idleFloor = 40;
const _idleCeiling = 400;

Future<void> _idle(WidgetTester tester) async {
  for (var i = 0; i < _idleCeiling; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4)));
    await tester.pump();
    if (i >= _idleFloor &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

/// _dragHandle drags the panel's top edge by [dy], negative being upwards.
///
/// By position rather than by finding the widget: the handle is a strip a few
/// pixels tall along the panel's top edge, and dragging the panel itself would
/// land in the middle of it -- on the text field, which takes the gesture as a
/// text selection and leaves the height exactly where it was.
Future<void> _dragHandle(WidgetTester tester, double dy) async {
  var panel = find.byType(NotesPanel);
  var top = tester.getTopLeft(panel);
  var width = tester.getSize(panel).width;
  await tester.dragFrom(top + Offset(width / 2, 4), Offset(0, dy));
  await tester.pump();
  await _idle(tester);
}

/// _openNotes presses the notes button and waits for the note to load.
Future<void> _openNotes(WidgetTester tester) async {
  await tester.tap(find.byType(NotesButton));
  await tester.pump();
  await _idle(tester);
}

/// _closeNotes presses the panel's own close button.
///
/// The only way to shut it: the notes button is not drawn while the panel is
/// open, so there is exactly one control for this rather than two.
Future<void> _closeNotes(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
  await tester.pump();
  await _idle(tester);
}

/// _pump builds the real host around a page, optionally one declaring a
/// target of its own.
Future<NotesPreferences> _pump(
  WidgetTester tester, {
  NoteTarget? target,
  bool enabled = true,
  bool pluginOn = true,
  NotesButtonPosition position = NotesButtonPosition.leftTriangle,
  double height = 600,
}) async {
  var prefs = NotesPreferences()
    ..enabled = enabled
    ..position = position;
  var targets = NoteTargetModel();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<PluginManagerModel>.value(
          value: FakePlugins(
              pluginOn ? {PluginCapability.spellcheckData} : const {})),
      ChangeNotifierProvider<NotesPreferences>.value(value: prefs),
      ChangeNotifierProvider<NoteTargetModel>.value(value: targets),
      ChangeNotifierProxyProvider<NoteTargetModel, NotesModel>(
        create: (c) => NotesModel(),
        update: (c, t, notes) => notes!..setTarget(t.target),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: height,
          child: NotesHost(
            child: NoteTargetScope(
              target: target,
              child: const Center(child: Text("PAGE")),
            ),
          ),
        ),
      ),
    ),
  ));
  await _idle(tester);
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("bruig-notes-ui-test");
    PostStorage.rootOverride = root.path;
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group("the button", () {
    testWidgets("opens the panel, and stands down while it is open",
        (tester) async {
      await _pump(tester, target: NoteTarget.page("/x", "Downloads"));
      expect(find.byType(NotesPanel), findsNothing);

      await _openNotes(tester);
      expect(find.byType(NotesPanel), findsOneWidget);
      // The panel carries its own close button, so a second control doing the
      // same thing an inch below it would only be something to choose between.
      expect(find.byType(NotesButton), findsNothing);

      await _closeNotes(tester);
      expect(find.byType(NotesPanel), findsNothing);
      expect(find.byType(NotesButton), findsOneWidget);
    });

    testWidgets("appears in whichever corner the setting names",
        (tester) async {
      for (var position in NotesButtonPosition.values) {
        await _pump(tester, position: position);
        expect(find.byType(NotesButton), findsOneWidget, reason: position.name);
      }
    });

    testWidgets("is not built at all when notes are switched off",
        (tester) async {
      await _pump(tester, enabled: false);
      // Not hidden, not disabled: the host returns the page untouched, so the
      // line in overview.dart costs nothing to anyone who does not want it.
      expect(find.byType(NotesButton), findsNothing);
      expect(find.text("PAGE"), findsOneWidget);
    });

    testWidgets("is not built when the writing tools plugin is off",
        (tester) async {
      await _pump(tester, pluginOn: false);
      expect(find.byType(NotesButton), findsNothing);
      expect(find.text("PAGE"), findsOneWidget);
    });

    testWidgets("is not built where there is no room for a panel",
        (tester) async {
      await _pump(tester, height: 150);
      expect(find.byType(NotesButton), findsNothing);
      expect(find.text("PAGE"), findsOneWidget);
    });
  });

  group("where it is drawn", () {
    testWidgets("the button and panel stay inside the content area",
        (tester) async {
      // The shape that was wrong twice: a page whose own sidebar sits to the
      // left of its content. The button belongs at the foot of the CONTENT,
      // not at the foot of everything past the app's navigation -- on the Chat
      // page that second thing is under the chat list, which is not the page.
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<PluginManagerModel>.value(
              value: FakePlugins({PluginCapability.spellcheckData})),
          ChangeNotifierProvider<NotesPreferences>(
              create: (c) => NotesPreferences()),
          ChangeNotifierProvider<NoteTargetModel>(
              create: (c) => NoteTargetModel()),
          ChangeNotifierProxyProvider<NoteTargetModel, NotesModel>(
            create: (c) => NotesModel(),
            update: (c, t, notes) => notes!..setTarget(t.target),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(children: [
              const SizedBox(width: 200, child: Text("SIDEBAR")),
              Expanded(
                child: NotesHost(
                  child: NoteTargetScope(
                    target: NoteTarget.chat("uid-1", "Alice"),
                    child: const Center(child: Text("PAGE")),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ));
      await _idle(tester);

      var contentLeft = tester.getTopLeft(find.text("PAGE")).dx;
      expect(tester.getTopLeft(find.byType(NotesButton)).dx,
          greaterThanOrEqualTo(200.0),
          reason: "the button is under the sidebar, not the content");
      expect(contentLeft, greaterThanOrEqualTo(200.0));

      await _openNotes(tester);
      // The panel is the content area's, so it starts where the content does
      // rather than spanning the sidebar too.
      expect(tester.getTopLeft(find.byType(NotesPanel)).dx, 200.0);
    });

    testWidgets("a nested content area does not draw a second one",
        (tester) async {
      // The feed frames its own column inside a screen that frames the tab
      // containing it, so the hook fires twice on one page.
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<PluginManagerModel>.value(
              value: FakePlugins({PluginCapability.spellcheckData})),
          ChangeNotifierProvider<NotesPreferences>(
              create: (c) => NotesPreferences()),
          ChangeNotifierProvider<NoteTargetModel>(
              create: (c) => NoteTargetModel()),
          ChangeNotifierProxyProvider<NoteTargetModel, NotesModel>(
            create: (c) => NotesModel(),
            update: (c, t, notes) => notes!..setTarget(t.target),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NotesHost(
              child: NotesHost(child: Center(child: Text("PAGE"))),
            ),
          ),
        ),
      ));
      await _idle(tester);

      expect(find.byType(NotesButton), findsOneWidget);
    });
  });

  group("local and global", () {
    testWidgets("a page with a target opens its own note", (tester) async {
      await _pump(tester, target: NoteTarget.chat("uid-1", "Alice"));
      await _openNotes(tester);

      expect(find.text("Chat - Alice"), findsOneWidget);
    });

    testWidgets("switching to Global changes which note is shown",
        (tester) async {
      await _pump(tester, target: NoteTarget.chat("uid-1", "Alice"));
      await _openNotes(tester);

      await tester.tap(find.text("Global"));
      await _idle(tester);
      expect(find.text("Global Notes"), findsOneWidget);
      expect(find.text("Chat - Alice"), findsNothing);

      await tester.tap(find.text("Local"));
      await _idle(tester);
      expect(find.text("Chat - Alice"), findsOneWidget);
    });

    testWidgets(
        "a page with no target gets the app-wide note, and Local is "
        "offered but dead", (tester) async {
      await _pump(tester);
      await _openNotes(tester);

      // Shown rather than hidden, so the control does not change shape as you
      // walk around the app -- the greyed half is what says this page cannot
      // have one.
      expect(find.text("Global Notes"), findsOneWidget);
      expect(find.text("Local"), findsOneWidget);

      await tester.tap(find.text("Local"));
      await _idle(tester);
      expect(find.text("Global Notes"), findsOneWidget);
    });
  });

  group("what is typed", () {
    testWidgets("reaches the library as a Markdown document", (tester) async {
      await _pump(tester, target: NoteTarget.document("/d/Mastering Go.pdf"));
      await _openNotes(tester);

      await tester.enterText(find.byType(TextField), "the bit about ports");
      // Past both the debounce and the ceiling above it, then the write
      // itself, which is real I/O.
      await tester.pump(const Duration(seconds: 4));
      await _idle(tester);

      var file = File(
          "${root.path}/my-posts/$notesFolderName/Document - Mastering Go.md");
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), "the bit about ports");
    });
  });

  group("the drag handle", () {
    testWidgets("resizes the panel", (tester) async {
      await _pump(tester, target: NoteTarget.page("/x", "Downloads"));
      await _openNotes(tester);

      // Down first, because the panel opens at (or clamped to) its cap in a
      // window this size and so has nowhere up to go.
      await _dragHandle(tester, 60);
      var shrunk = tester.getSize(find.byType(NotesPanel)).height;
      expect(shrunk, lessThan(defaultNotesPanelHeight));

      // Upwards is taller, which is why the model subtracts the delta.
      await _dragHandle(tester, -40);
      expect(
          tester.getSize(find.byType(NotesPanel)).height, greaterThan(shrunk));
    });

    testWidgets("cannot grow past a third of the content area", (tester) async {
      await _pump(tester,
          target: NoteTarget.page("/x", "Downloads"), height: 600);
      await _openNotes(tester);

      // Dragged far past the top of the window. The panel is for writing
      // *about* what is on screen, so the page it refers to has to stay the
      // larger part of it.
      await _dragHandle(tester, -2000);
      expect(tester.getSize(find.byType(NotesPanel)).height,
          lessThanOrEqualTo(600 / 3));
    });

    testWidgets("closes the panel when dragged below one line", (tester) async {
      await _pump(tester, target: NoteTarget.page("/x", "Downloads"));
      await _openNotes(tester);
      expect(find.byType(NotesPanel), findsOneWidget);

      // A note squashed to nothing is somebody putting it away, not asking
      // for a smaller note.
      await _dragHandle(tester, 400);

      expect(find.byType(NotesPanel), findsNothing);
    });
  });
}
