import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/audio_export.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/publish_sheet.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// canvas_audio_export_test.dart is publishing the sound alone, and how the
// sound of everything that has some is written: format, bitrate, rate and
// depth -- each file made by ffmpeg and read back by it.

void main() {
  test("the settings are kept, and anything unknown keeps the default", () {
    const o = AudioOptions(
        format: AudioFormat.flac, kbps: 256, sampleRate: 44100, bitDepth: 16);
    var back = AudioOptions.fromJson(o.toJson());
    expect(back.toJson(), o.toJson());
    var odd = AudioOptions.fromJson(
        const {"format": "tape", "kbps": 7, "rate": 11025, "depth": 12});
    expect(odd.toJson(), const AudioOptions().toJson());
  });

  test("a video's sound is its container's codec, at the bitrate asked", () {
    const o = AudioOptions(kbps: 128, sampleRate: 44100);
    expect(o.videoArgs(webm: false), ["-c:a", "aac", "-b:a", "128k", "-ar", "44100"]);
    expect(o.videoArgs(webm: true),
        ["-c:a", "libopus", "-b:a", "128k", "-ar", "48000"],
        reason: "Opus plays at 48kHz only");
  });

  test("every audio file has its own extension", () {
    for (var f in AudioFormat.values) {
      expect(extensionFor(f.mime), f.extension);
    }
  });

  group("written by ffmpeg", () {
    late Directory dir;
    late String tone;
    var ready = false;

    setUpAll(() async {
      var which = await Process.run("which", ["ffmpeg"]);
      if (which.exitCode != 0) return;
      dir = await Directory.systemTemp.createTemp("canvas-audio-export");
      tone = path.join(dir.path, "tone.wav");
      await Process.run("ffmpeg", [
        "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", tone //
      ]);
      ready = true;
    });

    tearDownAll(() async {
      if (ready) await dir.delete(recursive: true);
    });

    var document = const CanvasDocument(frames: 50, frameRate: 25, elements: [
      AudioElement(ElementBase(id: "a"),
          clip: MediaClip(
              playlist: [MediaSource(assetId: "tone", name: "tone", length: 2)],
              timed: true)),
    ]);

    for (var (format, codec, rate) in [
      (AudioFormat.wav, "pcm_s24le", "44100 Hz"),
      (AudioFormat.flac, "flac", "44100 Hz"),
      (AudioFormat.mp3, "mp3", "44100 Hz"),
      (AudioFormat.aac, "aac", "44100 Hz"),
      (AudioFormat.opus, "opus", "48000 Hz"),
    ]) {
      test("as ${format.label}", () async {
        if (!ready) {
          markTestSkipped("ffmpeg is not installed");
          return;
        }
        var made = await renderAudio(document,
            options: AudioOptions(format: format, sampleRate: 44100),
            locate: (kind, id) async => tone);
        expect(made, isNotNull);
        expect(made!.mime, format.mime);
        var file = path.join(dir.path, "out${format.extension}");
        await File(file).writeAsBytes(made.data);
        var said = await Process.run("ffmpeg", ["-hide_banner", "-i", file]);
        expect("${said.stderr}", contains("Audio: $codec"));
        expect("${said.stderr}", contains(rate));
        expect("${said.stderr}", contains("00:00:02"),
            reason: "as long as the timeline");
      });
    }

    test("and nothing on the timeline is nothing to write", () async {
      if (!ready) {
        markTestSkipped("ffmpeg is not installed");
        return;
      }
      expect(await renderAudio(const CanvasDocument(frames: 25)), isNull);
    });
  });

  group("the sheet", () {
    Future<void> open(WidgetTester tester) async {
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
                    document: const CanvasDocument(frames: 12),
                    images: null,
                    frame: 0,
                    name: "Plan"),
                child: const Text("open"),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
    }

    Future<void> pick<T>(WidgetTester tester, String option) async {
      await tester.tap(find.byType(DropdownButton<T>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets("Audio asks the format, and says when there is nothing to hear",
        (tester) async {
      await open(tester);
      await pick<PublishAs>(tester, "Audio");
      expect(find.byType(DropdownButton<AudioFormat>), findsOneWidget);
      expect(find.textContaining("Nothing is on the timeline"), findsOneWidget);
      expect(find.text("Bit depth"), findsOneWidget, reason: "WAV is lossless");
      await pick<AudioFormat>(tester, "MP3");
      expect(find.text("Bit depth"), findsNothing);
      expect(find.text("Sample rate"), findsOneWidget);
      await pick<AudioFormat>(tester, "Opus");
      expect(find.text("Sample rate"), findsNothing,
          reason: "Opus has one rate, said instead");
    });

    testWidgets("a video's sound has its settings, and so does a book's",
        (tester) async {
      await open(tester);
      await pick<PublishAs>(tester, "Video");
      expect(find.text("SOUND"), findsOneWidget);
      expect(find.byType(DropdownButton<AudioFormat>), findsNothing,
          reason: "a video's codec is its container's");
      await tester.tap(find.byKey(const ValueKey("publishToTarget")));
      await tester.pumpAndSettle();
      expect(find.text("Loudness"), findsOneWidget);
      await pick<PublishAs>(tester, "Document");
      expect(find.text("Sound quality"), findsNothing,
          reason: "a PDF has no sound");
      await pick<DocumentAs>(tester, "Interactive EPUB");
      expect(find.text("Sound quality"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
