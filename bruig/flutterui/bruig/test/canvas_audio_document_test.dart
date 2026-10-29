import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/publish_sheet.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_audio_document_test.dart is a document whose sound is the point: the
// Audio type, which opens on the mixer with no canvas to look at, and the
// sound settings every document has -- where it is going, how it is written,
// how loud, and for a piece of sound its tempo and metre.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("its settings are saved, and the defaults take no room", () {
    const a = AudioSettings(
        tempo: 96,
        beatsPerBar: 6,
        beatUnit: 8,
        export: AudioOptions(format: AudioFormat.flac, sampleRate: 44100));
    var doc = CanvasDocument.fromJson(
        const CanvasDocument(kind: CanvasKind.audio, audio: a).toJson());
    expect(doc.kind, CanvasKind.audio);
    expect(doc.audio.toJson(), a.toJson());
    expect(const CanvasDocument().toJson().containsKey("audio"), isFalse);
    expect(const AudioSettings(tempo: 120).secondsPerBar, 2);
    expect(const AudioSettings(tempo: 120, beatsPerBar: 6, beatUnit: 8)
        .secondsPerBar, 1.5, reason: "six quavers at 120 crotchets");
    expect(CanvasKind.audio.many, "sections");
    expect(CanvasKind.audio.oneCap, "Section");
  });

  test("the size estimate can be for the sound alone", () {
    // Four seconds of 24-bit, 48kHz stereo WAV.
    var doc = const CanvasDocument(frames: 100, frameRate: 25);
    expect(
        estimateBytes(doc, const CanvasEstimate(format: EstimateAs.audio)),
        4 * 48000 * 2 * 3);
    var mp3 = doc.copyWith(
        audio: const AudioSettings(
            export: AudioOptions(format: AudioFormat.mp3, kbps: 128)));
    expect(
        estimateBytes(mp3, const CanvasEstimate(format: EstimateAs.audio)),
        4 * 128000 ~/ 8);
  });

  test("the type decides the estimate, and a piece of sound has no canvas",
      () {
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
    expect(c.document.estimate.format, EstimateAs.audio);
    expect(c.document.hasCanvas, isFalse, reason: "Ratio None to begin with");
    expect(CanvasDocument.fromJson(c.document.toJson()).hasCanvas, isFalse);
    c.setKind(CanvasKind.scenes);
    expect(c.document.estimate.format, EstimateAs.png,
        reason: "a still is estimated as a picture");
    expect(c.document.hasCanvas, isTrue);
    c.setKind(CanvasKind.pages);
    expect(c.document.hasCanvas, isTrue);
  });

  test("an audio document opens on the mixer and the effects", () {
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    expect(c.mixerOpen, isFalse);
    c.setKind(CanvasKind.audio);
    expect((c.mixerOpen, c.effectsOpen), (true, true));
    var d = CanvasController(const CanvasDocument());
    addTearDown(d.dispose);
    d.load(const CanvasDocument(kind: CanvasKind.audio));
    expect((d.mixerOpen, d.effectsOpen), (true, true));
  });

  testWidgets("a destination sets the format and the loudness at once",
      (tester) async {
    tester.view.physicalSize = const Size(3200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument(kind: CanvasKind.audio));
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
          home: Scaffold(body: CanvasSettingsPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    var preset = find.byKey(const ValueKey("audioPreset"));
    expect(preset, findsOneWidget);
    expect(
        tester.getRect(find.byKey(const ValueKey("estimateAs"))).left,
        greaterThan(tester.getRect(preset).right),
        reason: "the estimate is at the far end, after the Audio settings");
    expect(tester.widget<CanvasDropdown<String>>(preset).value, "",
        reason: "nothing chosen yet is Custom");
    expect(find.byKey(const ValueKey("audioTempo")), findsNothing,
        reason: "the tempo is on the timeline's control bar now");
    tester.widget<CanvasDropdown<String>>(preset).onChanged("podcast");
    await tester.pumpAndSettle();
    var doc = c.document;
    expect(doc.audio.export.format, AudioFormat.mp3);
    expect((doc.masterMix.normalise, doc.masterMix.target), (true, -16));
    expect(tester.widget<CanvasDropdown<String>>(preset).value, "podcast");
    // Changed afterwards, it is the document's own.
    tester
        .widget<CanvasDropdown<AudioFormat>>(
            find.byKey(const ValueKey("audioFormat")))
        .onChanged(AudioFormat.flac);
    await tester.pumpAndSettle();
    expect(tester.widget<CanvasDropdown<String>>(preset).value, "");
    expect(find.byKey(const ValueKey("audioDepth")), findsOneWidget,
        reason: "FLAC is lossless: a depth, not a bitrate");
    c.undo();
    await tester.pumpAndSettle();
    expect(tester.widget<CanvasDropdown<String>>(preset).value, "podcast",
        reason: "each change undoable");
    expect(tester.takeException(), isNull);
  });

  testWidgets("Ratio None hides the size and the rate; a ratio brings them",
      (tester) async {
    tester.view.physicalSize = const Size(3200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(body: CanvasSettingsPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    var ratio = find.byKey(const ValueKey("canvasRatio"));
    expect(tester.widget<CanvasDropdown<String>>(ratio).value, "");
    expect(find.byKey(const ValueKey("canvasRatePreset")), findsNothing);
    expect(find.byKey(const ValueKey("canvasWidthPreset")), findsNothing);
    expect(find.byKey(const ValueKey("canvasScalesDesign")), findsNothing);
    expect(
        tester.getRect(find.byKey(const ValueKey("estimateAs"))).left,
        greaterThan(
            tester.getRect(find.byKey(const ValueKey("audioPreset"))).right),
        reason: "the estimate is the last thing on the bar");
    tester.widget<CanvasDropdown<String>>(ratio).onChanged("wide");
    await tester.pumpAndSettle();
    expect(c.document.hasCanvas, isTrue);
    expect(find.byKey(const ValueKey("canvasRatePreset")), findsOneWidget);
    c.undo();
    expect(c.document.hasCanvas, isFalse, reason: "one choice, one undo");
    expect(tester.takeException(), isNull);
  });

  testWidgets("a scenes document has no tempo to set", (tester) async {
    tester.view.physicalSize = const Size(3200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument());
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
          home: Scaffold(body: CanvasSettingsPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("audioPreset")), findsOneWidget);
    expect(find.byKey(const ValueKey("audioTempo")), findsNothing);
  });

  testWidgets("the publish sheet starts from the document's sound",
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPublishSheet(context,
                  document: const CanvasDocument(
                      frames: 12,
                      audio: AudioSettings(
                          export: AudioOptions(format: AudioFormat.opus))),
                  images: null,
                  frame: 0,
                  name: "Song"),
              child: const Text("open"),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<PublishAs>));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Audio").last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<AudioFormat>>(
                find.byType(DropdownButton<AudioFormat>))
            .value,
        AudioFormat.opus);
  });
}
