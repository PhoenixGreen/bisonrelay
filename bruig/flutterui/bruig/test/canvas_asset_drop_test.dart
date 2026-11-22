import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_asset_drop_test.dart is a library asset dragged from the Assets
// sidebar, or a chip from the Add panel, onto the canvas, on the page that
// takes the drop.

const tune = "c1b2c3d4e5f60718.mid";

void main() {
  late Directory root;
  late Future<MidiImport?> Function(String) midiWas;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CanvasScreen.framedForTest = (page) => page;
    root = await Directory.systemTemp.createTemp("canvas_asset_drop");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    await CanvasLibrary.add(LibraryAsset(
        id: tune,
        kind: AssetKind.audio,
        name: "Melody",
        added: DateTime(2026, 10, 29),
        length: 4));
    midiWas = CanvasController.midiOfAsset;
    CanvasController.midiOfAsset = (id) async => isMidiId(id)
        ? const MidiImport([MidiNote(60, 0, 0.5), MidiNote(64, 0.5, 1.5)], 0)
        : null;
  });

  tearDown(() async {
    CanvasScreen.framedForTest = null;
    CanvasController.midiOfAsset = midiWas;
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
    }
  }

  testWidgets(
      "a MIDI file dragged onto the canvas is a MIDI channel, as one "
      "clicked is", (tester) async {
    // Clicked in the assets, a MIDI file became a MIDI channel; dropped on
    // the canvas, it became a speaker playing the MIDI file as a sound,
    // which plays nothing.
    var renderer = CanvasController.partRenderer;
    var store = CanvasController.partStore;
    CanvasController.partRenderer = (part, {bankPath}) async => Uint8List(0);
    CanvasController.partStore = (_) async => null;
    addTearDown(() {
      CanvasController.partRenderer = renderer;
      CanvasController.partStore = store;
    });
    var c = CanvasController(const CanvasDocument(frames: 200),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    // Above the panels: the sidebar is then the page's own, where beside
    // everything it sits in the app's side menu, which needs the chat
    // client.
    var prefs = CanvasPreferences()
      ..sidebars =
          const SidebarLayout(mode: SidebarMode.above, current: "assets");
    // Tall enough that the Audio panel, among the Assets sidebar's panels,
    // lists its file.
    setTestScreen(tester, const Size(1600, 1500));
    await tester
        .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: c),
    ]));
    await idle(tester);

    var row = find.byKey(const ValueKey("asset-$tune"));
    await tester.ensureVisible(row);
    await tester.pump();
    // From its icon: its name is for renaming.
    var from = tester.getRect(row).centerLeft + const Offset(24, 0);
    var to = tester.getCenter(find.byType(CanvasStage));
    var channels = c.midiChannels.length;
    var g = await tester.startGesture(from);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await g.up();
    await idle(tester);

    var played = [
      for (var e in c.document.elements.whereType<AudioElement>())
        for (var s in e.clip.playlist) s.assetId,
    ];
    expect(played, isNot(contains(tune)),
        reason: "a MIDI file is notes for an instrument, not a sound");
    expect(c.midiChannels, hasLength(channels + 1));
    // Its part is played into a file a moment later: let that be.
    await tester.pump(const Duration(milliseconds: 400));
    await idle(tester);
    await tester.pumpWidget(canvasApp(const SizedBox(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: c),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
  });

  group("a chip dragged from the Add panel onto the canvas", () {
    // Drags the chip labelled [label] from the Add panel to a point on the
    // stage away from the page's middle, and gives back that point in the
    // document.
    Future<Offset> drag(
        WidgetTester tester, CanvasController c, String label) async {
      var prefs = CanvasPreferences()
        ..sidebars =
            const SidebarLayout(mode: SidebarMode.above, current: "design");
      setTestScreen(tester, const Size(1600, 1500));
      await tester
          .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
        ChangeNotifierProvider<CanvasController>.value(value: c),
      ]));
      await idle(tester);

      var chip = find.descendant(
          of: find.byType(CanvasElementsPanel), matching: find.text(label));
      await tester.ensureVisible(chip);
      await tester.pump();
      var from = tester.getCenter(chip);
      var stage = find.byType(CanvasStage);
      var to = tester.getCenter(stage) + const Offset(120, 60);
      var g = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump();
      }
      await g.up();
      await idle(tester);

      var box = tester.renderObject<RenderBox>(stage);
      return tester
          .state<CanvasStageState>(stage)
          .toDocumentPoint(box.globalToLocal(to));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets("Text lands centred where it was let go", (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      var at = await drag(tester, c, "Text");

      var text = c.document.elements.whereType<TextElement>().single;
      expect((text.center - at).distance, lessThan(2));
      expect(c.selection, {text.id});
      await close(tester);
    });

    testWidgets("Instrument lands centred where it was let go", (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      var at = await drag(tester, c, "Instrument");

      var keys = c.document.elements
          .whereType<AudioElement>()
          .where((e) => e.instrument != null)
          .single;
      expect((keys.center - at).distance, lessThan(2));
      expect(c.selection, {keys.id});
      await close(tester);
    });

    testWidgets("Synth puts its rack down centred where it was let go",
        (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      var at = await drag(tester, c, "Synth");

      // Centred as synthRack centres a rack on its point.
      var expected = {
        for (var m in synthRack(c.document, center: at, channel: ""))
          m.module: m.bounds.topLeft,
      };
      var modules = c.document.elements.whereType<SynthModuleElement>();
      expect(modules, hasLength(expected.length));
      for (var m in modules) {
        expect((m.bounds.topLeft - expected[m.module]!).distance, lessThan(2),
            reason: m.module.name);
      }
      await close(tester);
    });

    testWidgets("Code puts its two panels down centred where it was let go",
        (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      var at = await drag(tester, c, "Code");

      var code = c.document.elements.whereType<CodeElement>().single;
      var run = c.document.elements.whereType<CodeRunElement>().single;
      var both = code.bounds.expandToInclude(run.bounds);
      expect((both.center - at).distance, lessThan(2));
      expect(c.selection, {code.id});
      await close(tester);
    });
  });
}
