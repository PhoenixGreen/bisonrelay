import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';

// patch_voice.dart plays a synth patch (see model/synth_patch.dart): each
// note a voice that works every module the speaker hears through, a sample
// at a time, sources first -- the keyboard's pitch and gate, oscillators and
// noise, envelopes and LFOs, the filter, the amp, the mixer, the speaker.
//
// What a module does with what is patched into it follows the prototype the
// patch was designed in (sheet-music-prototype/index.html): an envelope
// only moves anything once the keyboard's gate is patched into it; an amp
// with nothing in its gain is on while the key is held; a cable into a
// filter's cutoff opens it by up to its amount, in octaves; one into an
// oscillator's mod bends it by up to its mod, in semitones.

/// PatchGraph is a patch made ready to play: its modules in the order a
/// voice works them out, each input as the place of the module it comes
/// from and that module's output.
class PatchGraph {
  final SynthPatch patch;
  final List<SynthModule> nodes;

  /// inputs are, for each node, each input's source as (node, output), or
  /// null where nothing is patched in.
  final List<Map<String, (int, int)>> inputs;

  /// gated are the envelopes the keyboard's gate is patched into.
  final Set<int> gated;

  /// releases is how long, after a key is let go, a voice can still be
  /// heard: its longest gated envelope's release.
  final double release;

  /// tail is how long its echoes and rooms ring on after that: the
  /// longest delay's repeats dying away, the largest reverb's tail.
  final double tail;

  PatchGraph._(
      this.patch, this.nodes, this.inputs, this.gated, this.release, this.tail);

  factory PatchGraph(SynthPatch patch) {
    var nodes = patch.heard;
    var at = {for (var (i, m) in nodes.indexed) m.id: i};
    var inputs = <Map<String, (int, int)>>[];
    for (var m in nodes) {
      var ins = <String, (int, int)>{};
      for (var MapEntry(key: port, value: plug) in m.inputs.entries) {
        var from = at[plug.module];
        if (from == null) continue;
        var kind = nodes[from].kind;
        var out = kind.outs.indexWhere((o) => o.name == plug.port);
        var into = m.kind.input(port);
        if (out < 0 || into == null) continue;
        if (!synthPlugFits(kind.outs[out], into)) continue;
        ins[port] = (from, out);
      }
      inputs.add(ins);
    }
    var gated = <int>{};
    var release = 0.0;
    for (var (i, m) in nodes.indexed) {
      if (m.kind != SynthModuleKind.env) continue;
      var g = inputs[i]["gate"];
      if (g != null && nodes[g.$1].kind == SynthModuleKind.keys) {
        gated.add(i);
        release = math.max(release, m.value("r"));
      }
    }
    var tail = 0.0;
    for (var m in nodes) {
      if (m.kind == SynthModuleKind.delay) {
        // Repeats until a thousandth of the first: time × ln(0.001)/ln(fb).
        var fb = m.value("feedback").clamp(0.0, 0.95);
        var t = fb <= 0.001
            ? m.value("time")
            : m.value("time") * math.log(0.001) / math.log(fb);
        tail = math.max(tail, math.min(8.0, t + 0.1));
      } else if (m.kind == SynthModuleKind.reverb) {
        tail = math.max(tail, 1 + 4 * m.value("size").clamp(0.0, 1.0));
      }
    }
    return PatchGraph._(patch, nodes, inputs, gated, release, tail);
  }

  /// wiring is its patch's: see SynthPatch.wiring.
  String get wiring => patch.wiring;
}

/// PatchVoice is a note played on a patch.
class PatchVoice extends Voice {
  /// graph is what it plays: changed for one wired alike as a setting
  /// changes, it goes on in that.
  PatchGraph graph;
  final double _f0, _velocity;
  final math.Random _random;

  /// _out is each node's outputs this sample; _phase each oscillator's and
  /// LFO's; _env each envelope's level and stage; _z each filter's state.
  final List<Float64List> _out;
  final Float64List _phase, _level, _z1, _z2;
  final Int8List _stage; // 0 attack, 1 decay, 2 sustain, 3 release, 4 done
  double _sinceRelease = 0;

  /// _echoes and _rooms are each delay's and reverb's state, made as it is
  /// first heard.
  final Map<int, _Echo> _echoes = {};
  final Map<int, _Room> _rooms = {};

  /// onSample is told of every node's outputs each sample, for a screen to
  /// show what a module is putting out (see patchScopes).
  void Function(List<Float64List> outs)? onSample;

  PatchVoice(super.key, int velocity, this.graph)
      : _f0 = 440 * math.pow(2, (key - 69) / 12).toDouble(),
        _velocity = math.pow(velocity.clamp(1, 127) / 127, 1.2).toDouble(),
        _random = math.Random(key * 7919 + velocity),
        _out = [
          for (var m in graph.nodes)
            Float64List(math.max(1, m.kind.outs.length))
        ],
        _phase = Float64List(graph.nodes.length),
        _level = Float64List(graph.nodes.length),
        _z1 = Float64List(graph.nodes.length),
        _z2 = Float64List(graph.nodes.length),
        _stage = Int8List(graph.nodes.length);

  double _in(int node, String port, double otherwise) {
    var src = graph.inputs[node][port];
    if (src == null) return otherwise;
    // An envelope the gate is not patched into moves nothing.
    var from = graph.nodes[src.$1];
    if (from.kind == SynthModuleKind.env && !graph.gated.contains(src.$1)) {
      return otherwise;
    }
    return _out[src.$1][src.$2];
  }

  bool _patched(int node, String port) {
    var src = graph.inputs[node][port];
    if (src == null) return false;
    var from = graph.nodes[src.$1];
    return from.kind != SynthModuleKind.env || graph.gated.contains(src.$1);
  }

  static double _blep(double t, double dt) {
    if (t < dt) {
      t /= dt;
      return t + t - t * t - 1;
    }
    if (t > 1 - dt) {
      t = (t - 1) / dt;
      return t * t + t + t + 1;
    }
    return 0;
  }

  static double _wave(String shape, double ph, double dt) => switch (shape) {
        "sine" => math.sin(2 * math.pi * ph),
        "triangle" => 1 - 4 * (ph - 0.5).abs(),
        "sawtooth" => 2 * ph - 1 - _blep(ph, dt),
        "square" =>
          (ph < 0.5 ? 1.0 : -1.0) + _blep(ph, dt) - _blep((ph + 0.5) % 1, dt),
        _ => math.sin(2 * math.pi * ph),
      };

  @override
  void render(Float32List l, Float32List r, int n) {
    var nodes = graph.nodes;
    var dtSample = 1 / mixRate;
    for (var i = 0; i < n; i++) {
      var gate = released ? 0.0 : 1.0;
      if (released) _sinceRelease += dtSample;
      double heard = 0;
      for (var k = 0; k < nodes.length; k++) {
        var m = nodes[k];
        var out = _out[k];
        switch (m.kind) {
          case SynthModuleKind.keys:
            out[0] = gate;
            out[1] = _f0 * pitch;
          case SynthModuleKind.osc:
            // Not keyed, an oscillator drones on the A below middle C.
            var f = _in(k, "pitch", 220) *
                math.pow(
                    2,
                    m.value("octave") +
                        m.value("detune") / 1200 +
                        _in(k, "mod", 0) * m.value("mod") / 12);
            var dt = (f / mixRate).clamp(0.0, 0.45);
            out[0] = m.value("level") * _wave(m.choice("wave"), _phase[k], dt);
            _phase[k] = (_phase[k] + dt) % 1;
          case SynthModuleKind.noise:
            out[0] = m.value("level") * (_random.nextDouble() * 2 - 1);
          case SynthModuleKind.env:
            out[0] = _envelope(k, m, _in(k, "gate", 0) > 0.5);
          case SynthModuleKind.lfo:
            var rate = m.value("rate");
            out[0] = m.value("depth") *
                _wave(m.choice("shape"), _phase[k], rate / mixRate);
            _phase[k] = (_phase[k] + rate / mixRate) % 1;
          case SynthModuleKind.filter:
            out[0] = _filter(k, m, _in(k, "in", 0));
          case SynthModuleKind.amp:
            var gain = _patched(k, "gain")
                ? _gainOf(k)
                // Nothing in its gain: on while the key is, off quickly
                // once it is let go.
                : (released ? math.max(0, 1 - _sinceRelease / 0.03) : 1.0);
            out[0] = _in(k, "in", 0) * m.value("level") * gain;
          case SynthModuleKind.mixer:
            out[0] = _in(k, "a", 0) * m.value("a") +
                _in(k, "b", 0) * m.value("b") +
                _in(k, "c", 0) * m.value("c");
          case SynthModuleKind.delay:
            var time = (m.value("time") * (1 + 0.5 * _in(k, "time", 0)))
                .clamp(0.01, 1.0);
            out[0] = (_echoes[k] ??= _Echo()).step(_in(k, "in", 0), time,
                m.value("feedback").clamp(0.0, 0.95), m.value("mix"));
          case SynthModuleKind.reverb:
            out[0] = (_rooms[k] ??= _Room()).step(_in(k, "in", 0),
                m.value("size"), m.value("damp"), m.value("mix"));
          case SynthModuleKind.scope:
            out[0] = _in(k, "in", 0);
          case SynthModuleKind.out:
            if (m.id == graph.patch.speaker) {
              heard = _in(k, "in", 0) * m.value("volume");
            }
        }
      }
      onSample?.call(_out);
      var v = heard * _velocity * 0.5;
      l[i] += v;
      r[i] += v;
      if (released && _sinceRelease > graph.release + graph.tail + 0.06) {
        done = true;
        return;
      }
    }
  }

  /// _gainOf is what is patched into an amp's gain as a level, nought to
  /// one: an envelope as it is, an LFO swung about the middle.
  double _gainOf(int k) {
    var src = graph.inputs[k]["gain"]!;
    var v = _out[src.$1][src.$2];
    var from = graph.nodes[src.$1].kind;
    return (from == SynthModuleKind.lfo ? 0.5 + 0.5 * v : v).clamp(0.0, 1.0);
  }

  /// _envelope is envelope [k] a sample on: up to one over its attack, down
  /// to its sustain over its decay, held, and down to nought over its
  /// release once its gate goes.
  double _envelope(int k, SynthModule m, bool gate) {
    var a = math.max(0.0005, m.value("a"));
    var d = math.max(0.001, m.value("d"));
    var s = m.value("s").clamp(0.0, 1.0);
    var rel = math.max(0.001, m.value("r"));
    var step = 1 / mixRate;
    var level = _level[k];
    if (!gate && _stage[k] < 3) _stage[k] = 3;
    switch (_stage[k]) {
      case 0:
        level += step / a;
        if (level >= 1) {
          level = 1;
          _stage[k] = 1;
        }
      case 1:
        level -= step / d * (1 - s);
        if (level <= s) {
          level = s;
          _stage[k] = 2;
        }
      case 2:
        level = s;
      case 3:
        level -= step / rel;
        if (level <= 0) {
          level = 0;
          _stage[k] = 4;
        }
      default:
        level = 0;
    }
    _level[k] = level;
    return level;
  }

  /// _filter is filter [k] taking [x]: a state-variable filter (as
  /// Zavalishin's), its cutoff opened by what is patched into it, its
  /// resonance a peak at the cutoff.
  double _filter(int k, SynthModule m, double x) {
    var cutoff = m.value("cutoff") *
        math.pow(2, _in(k, "cutoff", 0) * m.value("amount"));
    cutoff = cutoff.clamp(20.0, mixRate * 0.45);
    var g = math.tan(math.pi * cutoff / mixRate);
    // Resonance 0.1 to 20, as the prototype's: a Q from about 0.7 to 20.
    var q = 0.7 + m.value("res").clamp(0.0, 20.0) * 0.97;
    var kk = 1 / q;
    var a1 = 1 / (1 + g * (g + kk));
    var a2 = g * a1;
    var a3 = g * a2;
    var v3 = x - _z2[k];
    var v1 = a1 * _z1[k] + a2 * v3;
    var v2 = _z2[k] + a2 * _z1[k] + a3 * v3;
    _z1[k] = 2 * v1 - _z1[k];
    _z2[k] = 2 * v2 - _z2[k];
    return switch (m.choice("type")) {
      "highpass" => x - kk * v1 - v2,
      "bandpass" => v1,
      _ => v2,
    };
  }
}

/// _Echo is a delay line a second long, read between samples.
class _Echo {
  final Float32List _line = Float32List(mixRate + 2);
  int _at = 0;

  double step(double x, double time, double feedback, double mix) {
    var n = _line.length;
    var back = time * mixRate;
    var r = _at - back;
    while (r < 0) {
      r += n;
    }
    var i = r.floor() % n, f = r - r.floor();
    var y = _line[i] * (1 - f) + _line[(i + 1) % n] * f;
    _line[_at] = x + y * feedback;
    _at = (_at + 1) % n;
    return x * (1 - mix) + y * mix;
  }
}

/// _Room is a small Schroeder-Moorer reverb, as Freeverb's: four damped
/// combs side by side, then two allpasses.
class _Room {
  static const _combs = [1116, 1188, 1277, 1356];
  static const _passes = [556, 441];
  final List<Float32List> _comb = [
    for (var n in _combs) Float32List((n * mixRate / 44100).round())
  ];
  final List<Float32List> _pass = [
    for (var n in _passes) Float32List((n * mixRate / 44100).round())
  ];
  final List<int> _ci = [0, 0, 0, 0], _pi = [0, 0];
  final List<double> _low = [0, 0, 0, 0];

  double step(double x, double size, double damp, double mix) {
    var fb = 0.7 + 0.28 * size.clamp(0.0, 1.0);
    var d = damp.clamp(0.0, 1.0) * 0.4;
    var input = x * 0.15;
    var wet = 0.0;
    for (var c = 0; c < 4; c++) {
      var line = _comb[c];
      var y = line[_ci[c]];
      _low[c] = y * (1 - d) + _low[c] * d;
      line[_ci[c]] = input + _low[c] * fb;
      _ci[c] = (_ci[c] + 1) % line.length;
      wet += y;
    }
    for (var a = 0; a < 2; a++) {
      var line = _pass[a];
      var b = line[_pi[a]];
      line[_pi[a]] = wet + b * 0.5;
      wet = b - wet;
      _pi[a] = (_pi[a] + 1) % line.length;
    }
    return x * (1 - mix) + wet * mix;
  }
}

/// PatchWatch is a note played on a patch to be looked at rather than
/// heard: a voice kept going alongside the one heard, a stretch at a time,
/// each module's latest output kept -- for its screen to show its real
/// sound, its meter its real level, its envelope where it is.
class PatchWatch {
  final int key;
  PatchVoice _voice;
  final int _keep;
  final Map<String, Float32List> _rings = {};
  int _at = 0, _filled = 0;
  Float32List _l = Float32List(0), _r = Float32List(0);

  PatchWatch(SynthPatch patch, this.key, {int keep = 1024})
      : _keep = keep,
        _voice = PatchVoice(key, 100, PatchGraph(patch)) {
    _watch();
  }

  void _watch() {
    _rings.clear();
    var nodes = _voice.graph.nodes;
    for (var m in nodes) {
      _rings[m.id] = Float32List(_keep);
    }
    var speaker = _voice.graph.patch.speaker;
    _voice.onSample = (outs) {
      for (var (k, m) in nodes.indexed) {
        if (m.id == speaker) continue;
        _rings[m.id]![_at] = outs[k][0];
      }
    };
  }

  SynthPatch get patch => _voice.graph.patch;

  /// patch set to one wired alike goes on in it; otherwise the note starts
  /// again in the new one.
  set patch(SynthPatch p) {
    var next = PatchGraph(p);
    if (next.wiring == _voice.graph.wiring) {
      _voice.graph = next;
      return;
    }
    var wasReleased = _voice.released;
    _voice = PatchVoice(key, 100, next);
    if (wasReleased) _voice.release();
    _at = _filled = 0;
    _watch();
  }

  bool get released => _voice.released;
  bool get done => _voice.done;
  void release() => _voice.release();

  /// has is whether module [id] is in what is watched.
  bool has(String id) => _rings.containsKey(id);

  /// advance plays [samples] more of it.
  void advance(int samples) {
    if (_voice.done) return;
    if (_l.length < samples) {
      _l = Float32List(samples);
      _r = Float32List(samples);
    }
    var speaker = _rings[_voice.graph.patch.speaker];
    for (var i = 0; i < samples; i++) {
      _l[0] = 0;
      _r[0] = 0;
      _voice.render(_l, _r, 1);
      speaker?[_at] = _l[0];
      _at = (_at + 1) % _keep;
      if (_filled < _keep) _filled++;
      if (_voice.done) break;
    }
  }

  /// waveOf is module [id]'s latest output, oldest first.
  Float32List? waveOf(String id) {
    var ring = _rings[id];
    if (ring == null) return null;
    var out = Float32List(_filled);
    for (var i = 0; i < _filled; i++) {
      out[i] = ring[(_at - _filled + i + _keep) % _keep];
    }
    return out;
  }

  /// levelOf is how loud module [id] is now, its output's RMS.
  double levelOf(String id) {
    var ring = _rings[id];
    if (ring == null || _filled == 0) return 0;
    var s = 0.0;
    for (var i = 0; i < _filled; i++) {
      var v = ring[(_at - 1 - i + _keep) % _keep];
      s += v * v;
    }
    return math.sqrt(s / _filled);
  }

  /// valueOf is module [id]'s output this moment: where an envelope is.
  double valueOf(String id) {
    var ring = _rings[id];
    if (ring == null || _filled == 0) return 0;
    return ring[(_at - 1 + _keep) % _keep];
  }
}
