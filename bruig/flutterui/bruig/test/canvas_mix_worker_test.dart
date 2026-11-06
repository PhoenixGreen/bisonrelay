// SoLoud's own error type, which the worker is handed but the package does
// not export: see the first test.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/mix_worker.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show wav16;
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter_soloud/src/enums.dart' show PlayerErrors;
import 'package:flutter_test/flutter_test.dart';

// The mix in its own isolate: what the editor sends arrives, plain data
// crossing between the two, and what it reports comes back. No sound card
// here, so nothing is pushed; the worker still opens, plays and meters.

void main() {
  test("SoLoud's answer of no error lets the worker push to the stream", () {
    // Its own type, as the worker is given it: its text is not its name,
    // which once sent every mix back to the UI's isolate.
    expect(streamAnswered(PlayerErrors.noError), isTrue);
    expect(PlayerErrors.noError.toString(), isNot(endsWith("noError")));
    expect(streamAnswered(PlayerErrors.invalidParameter), isFalse);
  });

  test("the worker opens, plays, meters and reports", () async {
    var dir = await Directory.systemTemp.createTemp("mix_worker");
    addTearDown(() => dir.delete(recursive: true));
    var tone = Float32List(4800);
    for (var i = 0; i < tone.length; i++) {
      tone[i] = (i % 100) / 100 - 0.5;
    }
    var file = File("${dir.path}/tone.wav");
    await file.writeAsBytes(wav16(tone, tone));

    var from = ReceivePort();
    var isolate = await Isolate.spawn(mixWorkerMain, from.sendPort);
    addTearDown(() {
      isolate.kill();
      from.close();
    });
    var replies = StreamController<List>.broadcast();
    var to = Completer<SendPort>();
    from.listen((m) {
      if (m is SendPort) {
        to.complete(m);
      } else if (m is List) {
        replies.add(m);
      }
    });
    var send = await to.future;

    Future<List> next(String kind) =>
        replies.stream.firstWhere((m) => m.first == kind);

    // A file is answered, never left waiting: unreadable where the app's
    // decoder is not to hand (a test alone), or read whole where it is (as
    // when tests that set it up ran first, bundled).
    send.send(["open", 1, file.path, null]);
    expect((await next("opened"))[2], anyOf(isNull, 4800));

    // A metronome needs no decoder: made in the worker, and played.
    send.send(["click", 2, 0.5, 4, 48000]);
    send.send(["channel", "a", const ChannelMix(gainDb: -3)]);
    send.send(["play", 7, 2, 1.0, 0.0, "a", 0.0, null]);
    send.send(["watch", "levels", "a"]);
    send.send(["noteOn", "keys", const InstrumentPart(), 60, 100, false]);
    // The first report after all of that has arrived.
    var snap = (await replies.stream
        .where((m) => m.first == "snapshot")
        .map((m) => m[1] as MixSnapshot)
        .firstWhere((s) => s.voices.containsKey(7))
        .timeout(const Duration(seconds: 5)));
    expect(snap.voices[7]!.$3, isTrue, reason: "alive");
    expect(snap.levels.keys, contains("a"));
    send.send(const ["dispose"]);
  });

  test("with nothing to be heard it rests -- no reports -- until told",
      () async {
    var from = ReceivePort();
    var isolate = await Isolate.spawn(mixWorkerMain, from.sendPort);
    addTearDown(() {
      isolate.kill();
      from.close();
    });
    var to = Completer<SendPort>();
    var reports = <int>[];
    var watch = Stopwatch()..start();
    from.listen((m) {
      if (m is SendPort) {
        to.complete(m);
      } else if (m is List && m.first == "snapshot") {
        reports.add(watch.elapsedMilliseconds);
      }
    });
    var send = await to.future;
    // Settled: no report for half a second. Under a loaded machine (the
    // whole suite) that can take longer than it does alone.
    var settling = Stopwatch()..start();
    var seen = -1;
    while (settling.elapsedMilliseconds < 6000) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (reports.length == seen) break;
      seen = reports.length;
    }
    var resting = reports.length;
    expect(resting, lessThan(100), reason: "not fifty a second for ever");
    await Future.delayed(const Duration(milliseconds: 800));
    expect(reports.length, resting, reason: "at rest, nothing is sent");
    // Anything said to it wakes it.
    send.send(["watch", "levels", "a"]);
    await Future.delayed(const Duration(milliseconds: 300));
    expect(reports.length, greaterThan(resting));
    send.send(const ["dispose"]);
  });
}
