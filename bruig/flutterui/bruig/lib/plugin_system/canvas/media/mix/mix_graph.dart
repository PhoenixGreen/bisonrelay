import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';

// mix_graph.dart is how the sound gets from the channels to the speakers:
// each channel through its strip; from each, what its sends ask for into the
// returns -- before the fader or after it, as each return says -- each return
// through its devices and its own strip; and all of it into the master.
//
// The one routing there is. The editor's mixer (mix_core.dart) and an
// export's render (mix_render.dart) both fill the channels' inputs a block at
// a time and ask this for the master, so a send heard while editing is the
// send in the file.
//
// Where each channel lands among the speakers is a gain for each speaker
// from each of its two sides -- see _Pan. In stereo, its left to the left
// and its right to the right, as it always was. In surround, its sides are
// spread about its SurroundPan's angle; and a placed sound (SoundPlacement)
// is one point at the angle the picture puts it, as loud as its distance.
// The gains glide from block to block, so a sound moving round the room
// does not click as it goes.
//
// A surround mix's master runs a pair of speakers at a time; the LFE is
// filtered below 120Hz. The editor hears the speakers folded down to two
// (foldDown); an export takes them whole, from [speakers].

class _Bus {
  Float32List l, r;
  _Bus(int n)
      : l = Float32List(n),
        r = Float32List(n);

  void grow(int n) {
    if (l.length >= n) return;
    l = Float32List(n);
    r = Float32List(n);
  }

  void clear(int n) {
    l.fillRange(0, math.min(n, l.length), 0);
    r.fillRange(0, math.min(n, r.length), 0);
  }

  void addScaled(_Bus from, int n, double g) {
    if (g == 0) return;
    for (var i = 0; i < n; i++) {
      l[i] += from.l[i] * g;
      r[i] += from.r[i] * g;
    }
  }
}

class _Return {
  final ReturnChannel spec;
  final List<DeviceProcessor> devices;
  final StripProcessor strip;
  final _Bus bus;
  _Return(this.spec, int n)
      : devices = [
          for (var d in spec.devices)
            if (DeviceProcessor.of(d) case var p?) p,
        ],
        strip = StripProcessor(spec.mix),
        bus = _Bus(n);
}

/// _Pan is a channel's way to the speakers: the gain to each speaker from
/// its left side and from its right, now and where it is going.
class _Pan {
  Float64List fromL, fromR;
  _Pan(int speakers)
      : fromL = Float64List(speakers),
        fromR = Float64List(speakers);
}

class MixGraph {
  /// speakersLayout is what the mix is for: see setSpeakers.
  SpeakerLayout get speakersLayout => _layout;
  SpeakerLayout _layout = SpeakerLayout.stereo;

  /// speakers is the last block of each speaker, in the layout's order --
  /// what an export writes.
  List<Float32List> get speakers => _out;
  List<Float32List> _out = [Float32List(1024), Float32List(1024)];

  List<MasterProcessor> _masters = [];
  Biquad? _lfeFilter;
  Float32List _silent = Float32List(1024);

  final Map<String, Heard> _placed = {};
  final Map<String, _Pan> _pans = {};

  final Map<String, StripProcessor> _strips = {};
  final Map<String, String> _signatures = {};
  final Map<String, _Bus> _inputs = {};
  final _Bus _direct = _Bus(1024);
  List<_Return> _returns = [];
  String _returnsSignature = "";
  MasterProcessor _master = MasterProcessor(const MasterMix(limiter: false));
  String _masterSignature = "";

  final Map<String, (double, double)> _levels = {};
  (double, double) _masterLevels = (0, 0);

  /// heard is each channel's and each return's last block, after its strip,
  /// by key -- for a spectrum.
  final Map<String, (Float32List, Float32List)> heard = {};

  bool has(String key) => _strips.containsKey(key);

  /// setChannel makes or changes a channel. A strip set again unchanged
  /// keeps its processors, and so what is in them.
  void setChannel(String key, ChannelMix mix) {
    var signature = mix.toJson().toString();
    if (_signatures[key] == signature) return;
    _signatures[key] = signature;
    _strips[key] = StripProcessor(mix);
  }

  void setReturns(List<ReturnChannel> returns) {
    var signature = [for (var r in returns) r.toKey()].join("|");
    if (signature == _returnsSignature) return;
    _returnsSignature = signature;
    _returns = [for (var r in returns) _Return(r, 1024)];
  }

  void setMaster(MasterMix mix, {double normaliseDb = 0}) {
    var signature = "${mix.toJson()}|$normaliseDb";
    if (signature == _masterSignature) return;
    _masterSignature = signature;
    _masterMix = mix;
    _normaliseDb = normaliseDb;
    _master = MasterProcessor(mix, normaliseDb: normaliseDb);
    _buildMasters();
  }

  MasterMix _masterMix = const MasterMix(limiter: false);
  double _normaliseDb = 0;

  /// setSpeakers is what the mix is for: stereo, or surround.
  void setSpeakers(SpeakerLayout layout) {
    if (layout == _layout) return;
    _layout = layout;
    _out = [for (var i = 0; i < layout.channels; i++) Float32List(1024)];
    _pans.clear();
    _buildMasters();
  }

  void _buildMasters() {
    _masters = _layout.isSurround
        ? [
            for (var k = 0; k < (_layout.channels + 1) ~/ 2; k++)
              MasterProcessor(_masterMix, normaliseDb: _normaliseDb)
          ]
        : [];
    _lfeFilter = _layout.lfe == null ? null : Biquad(lowPass(120));
  }

  /// setPlacement is where the sound on channel [key] is heard from, taken
  /// from the picture -- or null, the channel's own pan.
  void setPlacement(String key, Heard? heard) {
    if (heard == null) {
      _placed.remove(key);
    } else {
      _placed[key] = heard;
    }
  }

  /// _targets is where [mix]'s two sides go now: a gain to each speaker
  /// from each side.
  (Float64List, Float64List) _targets(String key, ChannelMix mix) {
    var count = _layout.channels;
    var l = Float64List(count), r = Float64List(count);
    if (_placed[key] case var heard?) {
      // One point: the two sides together, as loud at a speaker as the
      // channel was on its own side.
      var g = panGains(_layout, heard.angle);
      var k = math.sqrt2 / 2 * heard.gain;
      for (var c = 0; c < count; c++) {
        l[c] = g[c] * k;
        r[c] = g[c] * k;
      }
      return (l, r);
    }
    var pan = _layout.isSurround ? mix.surround : null;
    if (pan == null) {
      l[0] = 1;
      r[1] = 1;
      return (l, r);
    }
    // Spread about the angle; drawn together to a point, each side half
    // as much again, so a point is as loud as the pair.
    var near = 1 / math.sqrt2;
    var k = near + (1 - near) * (pan.width / 60).clamp(0.0, 1.0);
    var gl = panGains(_layout, pan.angle - pan.width / 2);
    var gr = panGains(_layout, pan.angle + pan.width / 2);
    for (var c = 0; c < count; c++) {
      l[c] = gl[c] * k;
      r[c] = gr[c] * k;
    }
    return (l, r);
  }

  /// _land adds [b], a channel's block, to the speakers through its pan --
  /// gliding from where it was to where it is now over the block -- and to
  /// the LFE as its strip asks.
  void _land(String key, ChannelMix mix, _Bus b, int n) {
    var count = _layout.channels;
    var (tl, tr) = _targets(key, mix);
    var pan = _pans[key];
    if (pan == null) {
      pan = _Pan(count)
        ..fromL = tl
        ..fromR = tr;
      _pans[key] = pan;
    }
    for (var c = 0; c < count; c++) {
      var a = pan.fromL[c], b2 = pan.fromR[c];
      var da = (tl[c] - a) / n, db = (tr[c] - b2) / n;
      if (a == 0 && b2 == 0 && da == 0 && db == 0) continue;
      var out = _out[c];
      if (da == 0 && db == 0) {
        for (var i = 0; i < n; i++) {
          out[i] += b.l[i] * a + b.r[i] * b2;
        }
      } else {
        for (var i = 0; i < n; i++) {
          a += da;
          b2 += db;
          out[i] += b.l[i] * a + b.r[i] * b2;
        }
      }
    }
    pan
      ..fromL = tl
      ..fromR = tr;
    var lfe = _layout.lfe;
    if (lfe != null && mix.lfeDb != null) {
      var g = dbToGain(mix.lfeDb!) / 2;
      var out = _out[lfe];
      for (var i = 0; i < n; i++) {
        out[i] += (b.l[i] + b.r[i]) * g;
      }
    }
  }

  (double, double) levels([String? key]) =>
      key == null ? _masterLevels : (_levels[key] ?? (0, 0));

  /// begin clears every input for a block of [n].
  void begin(int n) {
    _direct
      ..grow(n)
      ..clear(n);
    if (_out[0].length < n) {
      _out = [for (var i = 0; i < _layout.channels; i++) Float32List(n)];
      _silent = Float32List(n);
    } else {
      for (var o in _out) {
        o.fillRange(0, n, 0);
      }
    }
    for (var b in _inputs.values) {
      b
        ..grow(n)
        ..clear(n);
    }
    for (var r in _returns) {
      r.bus
        ..grow(n)
        ..clear(n);
    }
  }

  /// input is where a sound on channel [key] is added for this block: its
  /// channel's input, or -- for a sound on no channel there is -- straight
  /// into the master.
  (Float32List, Float32List) input(String? key, int n) {
    if (key == null || !_strips.containsKey(key)) return (_direct.l, _direct.r);
    var b = _inputs[key];
    if (b == null) {
      b = _Bus(math.max(n, 1024));
      _inputs[key] = b;
    }
    b.grow(n);
    return (b.l, b.r);
  }

  /// finish routes the block and leaves the master in [l] and [r]. The
  /// limiter only when [limit]: the first of an export's two passes measures
  /// the mix before it.
  void finish(Float32List l, Float32List r, int n, {bool limit = true}) {
    // What is on no channel, to the front pair.
    for (var i = 0; i < n; i++) {
      _out[0][i] += _direct.l[i];
      _out[1][i] += _direct.r[i];
    }
    for (var entry in _strips.entries) {
      var b = _inputs[entry.key];
      if (b == null) {
        b = _Bus(math.max(n, 1024));
        _inputs[entry.key] = b;
      }
      b.grow(n);
      var strip = entry.value;
      strip.shape(b.l, b.r, n);
      _send(strip.mix, b, n, pre: true);
      strip.level(b.l, b.r, n);
      _send(strip.mix, b, n, pre: false);
      _levels[entry.key] = _peaks(b.l, b.r, n);
      heard[entry.key] = (b.l, b.r);
      _land(entry.key, strip.mix, b, n);
    }
    for (var ret in _returns) {
      var b = ret.bus;
      for (var d in ret.devices) {
        d.process(b.l, b.r, n);
      }
      ret.strip.process(b.l, b.r, n);
      _levels[ret.spec.id] = _peaks(b.l, b.r, n);
      heard[ret.spec.id] = (b.l, b.r);
      _land(ret.spec.id, ret.spec.mix, b, n);
    }
    if (!_layout.isSurround) {
      l.setRange(0, n, _out[0]);
      r.setRange(0, n, _out[1]);
      _master.process(l, r, n, limit: limit);
      _out[0].setRange(0, n, l);
      _out[1].setRange(0, n, r);
      _masterLevels = _peaks(l, r, n);
      return;
    }
    if ((_layout.lfe, _lfeFilter) case (var lfe?, var filter?)) {
      _silent.fillRange(0, n, 0);
      filter.process(_out[lfe], _silent, n);
    }
    for (var k = 0; k < _masters.length; k++) {
      var a = _out[2 * k];
      var b = 2 * k + 1 < _out.length ? _out[2 * k + 1] : _silent;
      _masters[k].process(a, b, n, limit: limit);
    }
    // Heard on two speakers: folded down.
    l.fillRange(0, n, 0);
    r.fillRange(0, n, 0);
    for (var (c, (gl, gr)) in foldDown(_layout).indexed) {
      var o = _out[c];
      for (var i = 0; i < n; i++) {
        l[i] += o[i] * gl;
        r[i] += o[i] * gr;
      }
    }
    _masterLevels = _peaks(l, r, n);
  }

  /// _send adds what [mix]'s sends ask for, from [from], into the returns
  /// that take their sends at this point -- before the fader or after it.
  void _send(ChannelMix mix, _Bus from, int n, {required bool pre}) {
    if (mix.sends.isEmpty || mix.mute) return;
    for (var ret in _returns) {
      if (ret.spec.pre != pre) continue;
      var db = mix.sends[ret.spec.id];
      if (db == null) continue;
      ret.bus.addScaled(from, n, dbToGain(db));
    }
  }

  static (double, double) _peaks(Float32List l, Float32List r, int n) {
    var pl = 0.0, pr = 0.0;
    for (var i = 0; i < n; i++) {
      var a = l[i].abs(), b = r[i].abs();
      if (a > pl) pl = a;
      if (b > pr) pr = b;
    }
    return (pl, pr);
  }
}
