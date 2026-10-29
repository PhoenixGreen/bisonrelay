import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// canvas_returns_test.dart is returns and sends: a channel sending some of
// itself to a return -- before its fader or after -- and the return's reverb
// or delay, heard while editing and in the export alike.

Float32List block(int n, [double v = 0]) => Float32List(n)..fillRange(0, n, v);

double energy(Float32List x, [int from = 0, int? to]) {
  var sum = 0.0;
  for (var i = from; i < (to ?? x.length); i++) {
    sum += x[i] * x[i];
  }
  return sum;
}

void main() {
  group("the model", () {
    test("a document starts with a reverb and a delay, and keeps changes", () {
      expect(const CanvasDocument().returns, defaultReturns);
      expect(const CanvasDocument().toJson().containsKey("returns"), isFalse,
          reason: "the defaults take no room in the file");
      var changed = [
        defaultReturns[0].copyWith(
            pre: true,
            devices: [
              const MixDevice(DeviceKind.reverb, values: {"size": 0.9})
            ]),
        const ReturnChannel("returnC", name: "Room"),
      ];
      var back = CanvasDocument.fromJson(
          const CanvasDocument().copyWith(returns: changed).toJson());
      expect([for (var r in back.returns) r.toKey()],
          [for (var r in changed) r.toKey()]);
      expect(back.returns.first.devices.single.value("size"), 0.9);
      expect(back.returns.first.devices.single.value("damping"), 0.4,
          reason: "a setting not changed is its default");
      expect(returnLetter(2), "C");
    });

    test("a send is saved, and nothing sent is nothing written", () {
      var mix = const ChannelMix().withSend("returnA", -12);
      expect(ChannelMix.fromJson(mix.toJson()).sendDb("returnA"), -12);
      expect(mix.withSend("returnA", null).isDefault, isTrue);
      expect(mix.withSend("returnA", -200).sends, isEmpty);
    });
  });

  group("the devices", () {
    test("a reverb leaves a tail that dies away, and at no mix is dry", () {
      var r = Reverb(const MixDevice(DeviceKind.reverb));
      var l = block(48000), rr = block(48000);
      l[0] = rr[0] = 1;
      r.process(l, rr, 48000);
      expect(energy(l, 4800, 9600), greaterThan(0),
          reason: "still sounding a tenth of a second on");
      expect(energy(l, 4800, 9600), greaterThan(energy(l, 38400, 43200)),
          reason: "and quieter later");
      expect(energy(l, 2400, 4800), isNot(energy(rr, 2400, 4800)),
          reason: "the two sides differ: it is wide");
      var dry = Reverb(const MixDevice(DeviceKind.reverb, values: {"mix": 0}));
      var a = block(512, 0.5), b = block(512, 0.5);
      dry.process(a, b, 512);
      expect(a.every((v) => v == 0.5), isTrue);
    });

    test("a delay repeats at its time, quieter; ping-pong crosses over", () {
      var d = Delay(const MixDevice(DeviceKind.delay,
          values: {"time": 100, "feedback": 0.5, "tone": 18000}));
      var l = block(20000), r = block(20000);
      l[0] = 1;
      d.process(l, r, 20000);
      expect(l[4800], closeTo(1, 0.05), reason: "first repeat at 100ms");
      expect(l[9600], closeTo(0.5, 0.05), reason: "the next, half as loud");
      expect(r[4800], 0, reason: "not ping-pong: the left stays left");
      var p = Delay(const MixDevice(DeviceKind.delay,
          values: {"time": 100, "feedback": 0.5, "pingpong": 1}));
      var pl = block(20000), pr = block(20000);
      pl[0] = 1;
      p.process(pl, pr, 20000);
      expect(pr[9600].abs(), greaterThan(0.2),
          reason: "the second repeat comes back on the right");
    });
  });

  group("the routing", () {
    MixGraph graph(ChannelMix mix, {bool pre = false, ChannelMix ret = const ChannelMix()}) =>
        MixGraph()
          ..setMaster(const MasterMix(limiter: false))
          ..setReturns([ReturnChannel("fx", pre: pre, mix: ret)])
          ..setChannel("a", mix);

    double run(MixGraph g, double level) {
      g.begin(256);
      var (l, r) = g.input("a", 256);
      l.fillRange(0, 256, level);
      r.fillRange(0, 256, level);
      var ol = Float32List(256), or = Float32List(256);
      g.finish(ol, or, 256);
      return ol[100];
    }

    test("after the fader, a send follows it", () {
      var g = graph(const ChannelMix(gainDb: -6).withSend("fx", -6));
      var out = run(g, 0.5);
      var post = 0.5 * dbToGain(-6);
      expect(out, closeTo(post + post * dbToGain(-6), 1e-6),
          reason: "the channel, and its send through an empty return");
      expect(g.levels("fx").$1, closeTo(post * dbToGain(-6), 1e-6));
    });

    test("before the fader, the fader does not change the send", () {
      var g = graph(const ChannelMix(gainDb: -60).withSend("fx", 0), pre: true);
      run(g, 0.5);
      expect(g.levels("fx").$1, closeTo(0.5, 1e-6));
    });

    test("a muted channel sends nothing; a return has its own strip", () {
      var g = graph(const ChannelMix(mute: true).withSend("fx", 0));
      run(g, 0.5);
      expect(g.levels("fx"), (0.0, 0.0));
      var h = graph(const ChannelMix().withSend("fx", 0),
          ret: const ChannelMix(gainDb: -6));
      run(h, 0.5);
      expect(h.levels("fx").$1, closeTo(0.5 * dbToGain(-6), 1e-6));
    });
  });

  test("an export carries a send's reverb past the end of the sound",
      () async {
    var which = await Process.run("which", ["ffmpeg"]);
    if (which.exitCode != 0) {
      markTestSkipped("ffmpeg is not installed");
      return;
    }
    var dir = await Directory.systemTemp.createTemp("canvas-returns");
    addTearDown(() => dir.delete(recursive: true));
    var tone = path.join(dir.path, "tone.wav");
    await Process.run("ffmpeg", [
      "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", tone //
    ]);
    Future<Float32List> render(ChannelMix mix) async {
      var out = path.join(dir.path, "mix-${mix.sends.length}.wav");
      expect(
          await renderMixWav([
            ExportSound(
                path: tone, at: 0, from: 0, length: 1, channel: "a", mix: mix),
          ], const MasterMix(limiter: false),
              seconds: 3, ffmpeg: "ffmpeg", out: out, returns: defaultReturns),
          isTrue);
      var bytes = await File(out).readAsBytes();
      var pcm = bytes.buffer.asFloat32List(44);
      return Float32List.fromList(
          [for (var i = 0; i < pcm.length ~/ 2; i++) pcm[i * 2]]);
    }

    var dry = await render(const ChannelMix());
    var wet = await render(const ChannelMix().withSend("returnA", 0));
    var after = (1.2 * 48000).round(), until = (2 * 48000).round();
    expect(energy(dry, after, until), 0, reason: "dry, it stops with the sound");
    expect(energy(wet, after, until), greaterThan(1e-4),
        reason: "sent to the reverb, its tail rings on");
    expect(math.sqrt(energy(wet, 0, 48000) / 48000),
        greaterThan(math.sqrt(energy(dry, 0, 48000) / 48000)));
  });
}
