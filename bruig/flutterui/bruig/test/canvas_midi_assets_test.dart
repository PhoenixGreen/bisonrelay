import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';

// canvas_midi_assets_test.dart is MIDI files among the sounds: kept in the
// library, found by the Audio section's filter, played by a MIDI channel --
// and sounds and MIDI files dragged from the assets onto clip slots.

const song = "a1b2c3d4e5f60718.mp3";
const take = "b1b2c3d4e5f60718.wav";
const tune = "c1b2c3d4e5f60718.mid";

void main() {
  late Directory root;
  late Future<MidiImport?> Function(String) midiWas;

  setUp(() async {
    DoubleClick.window = const Duration(days: 1);
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("canvas_midi_assets");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    var when = DateTime(2026, 10, 29);
    for (var (id, name) in [
      (song, "Anthem"),
      (take, "Voice"),
      (tune, "Melody")
    ]) {
      await CanvasLibrary.add(LibraryAsset(
          id: id, kind: AssetKind.audio, name: name, added: when, length: 4));
    }
    midiWas = CanvasController.midiOfAsset;
    CanvasController.midiOfAsset = (id) async => isMidiId(id)
        ? const MidiImport([MidiNote(60, 0, 0.5), MidiNote(64, 0.5, 1.5)], 0)
        : null;
  });

  tearDown(() async {
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

  CanvasController make() => CanvasController(
      CanvasDocument(
          frames: 400,
          frameRate: 25,
          audio: const AudioSettings(tempo: 120),
          elements: [
            AudioElement(const ElementBase(id: "a", name: "Drums"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: song, length: 4)],
                    timed: true)),
            const AudioElement(ElementBase(id: "keys", name: "Keys"),
                clip: MediaClip(timed: true), instrument: InstrumentPart()),
          ]),
      audioEngine: FakeEngine(const {}));

  test("a MIDI file is known by its own first bytes", () {
    expect(CanvasMedia.extensionOf("MThd\x00\x00\x00\x06".codeUnits), ".mid");
    expect(isMidiId(tune), isTrue);
    expect(isMidiId(song), isFalse);
    expect(audioTypeLabel(".mid"), "MIDI");
    expect(audioTypeOf(song), ".mp3");
  });

  test("a MIDI file makes a MIDI channel, joins one, or fills a slot",
      () async {
    var c = make();
    addTearDown(c.dispose);
    // A channel of its own, from where it is put.
    var e = await c.addMidiChannelFrom(
        const MediaSource(assetId: tune, name: "Melody"),
        frame: 50);
    expect(e!.instrument!.notes, hasLength(2));
    expect(e.clip.at, 50);
    expect(e.name, "Melody");
    // Onto a MIDI channel's part, from the frame it is dropped at: two
    // seconds in.
    expect(await c.putMidiOn("keys", tune, 50), isTrue);
    var keys = c.document.elementById("keys") as AudioElement;
    expect(keys.instrument!.notes.map((n) => n.start), [2.0, 2.5]);
    // Into a clip slot, in beats: two seconds at 120 is four beats, a bar.
    expect(await c.midiClipFromFile("keys", 0, tune, name: "Melody"), isTrue);
    var clip = c.session.at("keys", 0)!;
    expect(clip.midi, isTrue);
    expect(clip.notes.map((n) => n.start), [0, 1]);
    expect(clip.bars, 1);
    expect(clip.name, "Melody");
  });

  Future<CanvasController> showBoth(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = make();
    addTearDown(c.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Row(children: [
        SizedBox(width: 280, child: CanvasAssetsPanel(controller: c)),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: CanvasMixer(
                controller: c, height: 460, onResize: (_) {}, onClose: () {}),
          ),
        ),
      ]))),
    ));
    await idle(tester);
    return c;
  }

  testWidgets("the Audio section is filtered by the kind of file",
      (tester) async {
    await showBoth(tester);
    for (var t in ["all", "mid", "mp3", "wav"]) {
      expect(find.byKey(ValueKey("audioType-$t")), findsOneWidget, reason: t);
    }
    expect(find.text("Voice"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("audioType-mid")));
    await tester.pump();
    expect(find.text("Melody"), findsOneWidget);
    expect(find.text("Voice"), findsNothing);
    await tester.tap(find.byKey(const ValueKey("audioType-wav")));
    await tester.pump();
    expect(find.text("Voice"), findsOneWidget);
    expect(find.text("Melody"), findsNothing);
    await tester.tap(find.byKey(const ValueKey("audioType-all")));
    await tester.pump();
    expect(find.text("Melody"), findsOneWidget);
  });

  /// dragTo drags library asset [id] from the Audio section to [target].
  Future<void> dragTo(WidgetTester tester, String id, Finder target) async {
    // From its icon, in view: its name is for renaming.
    await tester.ensureVisible(find.byKey(ValueKey("asset-$id")));
    await tester.pump();
    var from = tester.getRect(find.byKey(ValueKey("asset-$id"))).centerLeft +
        const Offset(24, 0);
    var to = tester.getCenter(target);
    var g = await tester.startGesture(from);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await g.up();
    await idle(tester);
  }

  testWidgets("a sound dragged from the assets onto a clip slot is its clip",
      (tester) async {
    var c = await showBoth(tester);
    await dragTo(tester, take, find.byKey(const ValueKey("clip-a-1")));
    expect(c.session.at("a", 1)?.name, "Voice");
    expect(c.session.at("a", 1)?.sound?.assetId, take);
  });

  testWidgets("a MIDI file goes on a MIDI channel's slot, not an audio one's",
      (tester) async {
    var c = await showBoth(tester);
    await dragTo(tester, tune, find.byKey(const ValueKey("clip-a-0")));
    expect(c.session.at("a", 0), isNull, reason: "an audio channel");
    await dragTo(tester, tune, find.byKey(const ValueKey("clip-keys-0")));
    expect(c.session.at("keys", 0)?.midi, isTrue);
    expect(c.session.at("keys", 0)?.notes, hasLength(2));
  });

  testWidgets("a MIDI file clicked in the assets is a MIDI channel",
      (tester) async {
    var renderer = CanvasController.partRenderer;
    var store = CanvasController.partStore;
    CanvasController.partRenderer = (part, {bankPath}) async => Uint8List(0);
    CanvasController.partStore = (_) async => null;
    addTearDown(() {
      CanvasController.partRenderer = renderer;
      CanvasController.partStore = store;
    });
    var c = await showBoth(tester);
    var channels = c.midiChannels.length;
    // On its icon: a click on its name is for renaming.
    await tester.tapAt(
        tester.getRect(find.byKey(const ValueKey("asset-$tune"))).centerLeft +
            const Offset(24, 0));
    await idle(tester);
    expect(c.midiChannels, hasLength(channels + 1));
    // Its part is played into a file a moment later: let that be.
    await tester.pump(const Duration(milliseconds: 400));
    await idle(tester);
  });
}
