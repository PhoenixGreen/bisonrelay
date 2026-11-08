import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_dsp.dart'
    show Follower, Gate;
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/split_dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';

// mix_graph.dart is the routing from channels to speakers: each channel
// through its strip, its sends (pre- or post-fader, as each return says)
// into the returns, each return through its devices and strip, and all of
// it into the master. The editor (mix_core.dart) and exports (mix_render.dart)
// both use it, so a send heard while editing is the send in the file.
//
// Each channel reaches the speakers as a gain per speaker from each of its
// two sides (_Pan): left to left and right to right in stereo; spread about
// its SurroundPan's angle in surround; or, for a placed sound, one point at
// its [Heard] angle and gain. The gains ramp over each block so a moving
// sound does not click.
//
// A surround master runs a pair of speakers at a time and the LFE is
// filtered below 120Hz. The editor hears the speakers folded down to two;
// an export takes them whole from [speakers].

/// limitKey is the master limiter's turn-down among a graph's levels: see
/// MixGraph._publishMaster.
const String limitKey = "@limit";

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

  /// addRamped adds [from] at a gain moving from [was] to [g] over the
  /// block, so a send turned (or automated) does not step.
  void addRamped(_Bus from, int n, double was, double g) {
    if (was == g) return addScaled(from, n, g);
    var d = (g - was) / n;
    for (var i = 0; i < n; i++) {
      var k = was + d * (i + 1);
      l[i] += from.l[i] * k;
      r[i] += from.r[i] * k;
    }
  }
}

/// _Return is a return as it runs: a channel's strip over its devices,
/// EQ and compressor in the order they were put (ReturnChannel.chainMix),
/// fed from its bus of what was sent to it.
class _Return {
  final ReturnChannel spec;
  final StripProcessor strip;
  final _Bus bus;

  /// structure is what its strip was built from, but for settings it can
  /// be retuned to (see MixGraph._structureOf).
  final String structure;

  _Return(this.spec, this.strip, this.bus, this.structure);
}

/// masterTapKey is the master's key among MixGraph.tapped: the empty
/// string, as the worker's snapshots name it.
const String masterTapKey = "";

/// _Pan is the gain to each speaker from a channel's left and right sides,
/// as the last block ended.
class _Pan {
  Float64List fromL, fromR;

  /// made is what [fromL] and [fromR] were worked out from -- the layout,
  /// where it is heard from, its surround pan -- so a block with none of
  /// them changed uses them again rather than making them anew.
  Object? made;
  _Pan(int speakers)
      : fromL = Float64List(speakers),
        fromR = Float64List(speakers);
}

class MixGraph {
  SpeakerLayout _layout = SpeakerLayout.stereo;

  /// speakers is the last block of each speaker, in the layout's order,
  /// for an export to write.
  List<Float32List> get speakers => _out;
  List<Float32List> _out = [Float32List(1024), Float32List(1024)];

  List<MasterProcessor> _masters = [];
  Biquad? _lfeFilter;
  Float32List _silent = Float32List(1024);

  final Map<String, Heard> _placed = {};
  final Map<String, _Pan> _pans = {};

  final Map<String, StripProcessor> _strips = {};
  final Map<String, String> _signatures = {};
  final Map<String, String> _structures = {};
  final Map<String, _Bus> _inputs = {};
  final _Bus _direct = _Bus(1024);
  List<_Return> _returns = [];
  String _returnsSignature = "";
  MasterProcessor _master = MasterProcessor(const MasterMix(limiter: false));
  String _masterSignature = "";

  final Map<String, (double, double)> _levels = {};

  /// _loudness measures what leaves the master, kept while its settings
  /// change, so the whole song's reading is not lost to a turned knob.
  LoudnessTap _loudness = LoudnessTap();

  /// _publishMaster notes what the master's cards read: the limiter's
  /// turn-down among the levels ([limitKey], as a gain), and what leaves
  /// it measured for the Loudness card (see loudnessOf).
  void _publishMaster(Float32List l, Float32List r, int n) {
    // In surround, the most any pair's limiter turned down.
    var g = _layout.isSurround
        ? _masters.fold(1.0, (least, m) => math.min(least, m.limited))
        : _master.limited;
    _levels[limitKey] = (g, g);
    _loudness.process(l, r, n);
  }
  (double, double) _masterLevels = (0, 0);

  /// The scene's bus (see CanvasScene.bus): the channels in [_sceneKeys]
  /// land on [_sceneOut], speaker by speaker as they would on the master,
  /// so their pans and places are kept; each pair of speakers then runs
  /// through a strip of the scene's settings, and on to the master. Null
  /// strips -- a bus at its defaults -- and they land on the master.
  List<StripProcessor>? _scene;
  String _sceneSignature = "";
  ChannelMix _sceneMix = const ChannelMix();
  Set<String> _sceneKeys = const {};
  List<Float32List> _sceneOut = [Float32List(1024), Float32List(1024)];

  /// heard is each channel's and return's last block after its strip, by
  /// key, for a spectrum.
  final Map<String, (Float32List, Float32List)> heard = {};

  bool has(String key) => _strips.containsKey(key);

  /// setChannel makes or changes a channel, keeping its processors' state
  /// where it can.
  /// removeChannel stops running channel [key]'s strip: gone from the
  /// canvas, its sounds go to the master.
  void removeChannel(String key) {
    _strips.remove(key);
    _signatures.remove(key);
    _structures.remove(key);
    // Its input too: a gate or a vocoder listening to it then hears it
    // gone, as an export (which never had it) does, not silence.
    _inputs.remove(key);
    _sending.remove(key);
    _sendsMet.removeWhere((id) => id.startsWith("$key>"));
    _sendGains.removeWhere((id, _) => id.startsWith("$key>"));
    _pans.remove(key);
    _placed.remove(key);
    _levels.remove(key);
  }

  void setChannel(String key, ChannelMix mix) {
    var json = _soundOf(mix);
    var signature = json.toString();
    if (_signatures[key] == signature) return;
    _signatures[key] = signature;
    var structure = _structureOf(mix, json);
    var strip = _strips[key];
    if (strip != null && _structures[key] == structure) {
      strip.retune(mix);
      return;
    }
    _structures[key] = structure;
    _strips[key] = StripProcessor(mix, carry: strip);
  }

  /// _soundOf is [mix]'s settings that change its sound here. Speech and
  /// vocaliser settings do not, and automation arrives already applied, so
  /// none of them resets a strip -- a channel's, a return's or a bus's.
  static Map<String, dynamic> _soundOf(ChannelMix mix) => mix.toJson()
    ..remove("speech")
    ..remove("vocaliser")
    ..remove("automation");

  /// _structureOf is [mix] -- as [json], its settings that change the
  /// sound -- but for what a running strip can be retuned to: a strip
  /// differing only in levels, sends and device settings (as when
  /// automation plays) is retuned, so reverb tails and the like carry on.
  static String _structureOf(ChannelMix mix, Map<String, dynamic> json) =>
      (Map.of(json)
            ..remove("gain")
            ..remove("balance")
            ..remove("sends")
            // Read as it runs (MixGraph.finish, StripProcessor.level): a
            // mute, a solo, its place round the room, where it goes.
            ..remove("mute")
            ..remove("surround")
            ..remove("lfe")
            ..remove("duck")
            ..remove("output")
            ..["devices"] = [
              for (var (i, d) in mix.devices.indexed)
                [deviceIdAt(mix.devices, i), d.kind.name, d.on, d.source]
            ])
          .toString();

  /// setScene sets the bus of the scene playing, and [channels], the
  /// channels heard through it -- the scene's own, not the master's.
  void setScene(ChannelMix bus, Set<String> channels) {
    _sceneKeys = channels;
    if (identical(bus, _sceneMix)) return;
    // As for a channel (see setChannel): differing only in its fader and
    // its devices' settings, the same strips are retuned, and the fader
    // ramps.
    var signature = bus.isDefault ? "" : _structureOf(bus, _soundOf(bus));
    if (signature == _sceneSignature) {
      if (_scene case var strips?) {
        for (var s in strips) {
          s.retune(bus);
        }
      }
      _sceneMix = bus;
      return;
    }
    var was = _scene;
    _sceneSignature = signature;
    _sceneMix = bus;
    _buildScene(carry: was);
  }

  void _buildScene({List<StripProcessor>? carry}) {
    if (_sceneSignature.isEmpty) {
      _scene = null;
      return;
    }
    var pairs = (_layout.channels + 1) ~/ 2;
    _scene = [
      for (var k = 0; k < pairs; k++)
        StripProcessor(_sceneMix,
            carry: carry != null && k < carry.length ? carry[k] : null)
    ];
  }

  void setReturns(List<ReturnChannel> returns) {
    var signature = [for (var r in returns) r.toKey()].join("|");
    if (signature == _returnsSignature) return;
    _returnsSignature = signature;
    // Each retuned or rebuilt as a channel's strip is (see setChannel), so
    // a knob turned on a return's reverb does not cut its tail.
    var was = {for (var r in _returns) r.spec.id: r};
    _returns = [
      for (var r in returns)
        () {
          var mix = r.chainMix;
          var structure = _structureOf(mix, _soundOf(mix));
          var old = was[r.id];
          if (old != null && old.structure == structure) {
            old.strip.retune(mix);
            return _Return(r, old.strip, old.bus, structure);
          }
          return _Return(r, StripProcessor(mix, carry: old?.strip),
              old?.bus ?? _Bus(1024), structure);
        }(),
    ];
  }

  void setMaster(MasterMix mix, {double normaliseDb = 0}) {
    var signature = "${mix.toJson()}|$normaliseDb";
    if (signature == _masterSignature) return;
    _masterSignature = signature;
    _masterMix = mix;
    _normaliseDb = normaliseDb;
    _master = MasterProcessor(mix, normaliseDb: normaliseDb, carry: _master);
    _buildMasters();
  }

  MasterMix _masterMix = const MasterMix(limiter: false);
  double _normaliseDb = 0;

  /// hear is which speakers the editor hears on its two (see SpeakerGroup):
  /// only the folded l and r change; [speakers] are as mixed.
  SpeakerGroup hear = SpeakerGroup.all;

  /// setSpeakers sets the speaker layout the mix is for.
  void setSpeakers(SpeakerLayout layout) {
    if (layout == _layout) return;
    _layout = layout;
    _out = [for (var i = 0; i < layout.channels; i++) Float32List(1024)];
    _pans.clear();
    _buildMasters();
    _buildScene();
  }

  void _buildMasters() {
    // Each pair carried on from the one it replaces, as the stereo master
    // is (see setMaster).
    var was = _masters;
    _masters = _layout.isSurround
        ? [
            for (var k = 0; k < (_layout.channels + 1) ~/ 2; k++)
              MasterProcessor(_masterMix,
                  normaliseDb: _normaliseDb,
                  carry: k < was.length ? was[k] : null)
          ]
        : [];
    _lfeFilter = _layout.lfe == null ? null : Biquad(lowPass(120));
  }

  /// setPlacement is where the sound on channel [key] is heard from, taken
  /// from the picture; null for the channel's own pan.
  void setPlacement(String key, Heard? heard) {
    if (heard == null) {
      _placed.remove(key);
    } else {
      _placed[key] = heard;
    }
  }

  /// _targets is the gain to each speaker from each of [mix]'s sides now.
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
    // Spread about the angle. As the width narrows to a point each side is
    // scaled down to 1/sqrt2, so the point is as loud as the pair.
    var near = 1 / math.sqrt2;
    var k = near + (1 - near) * (pan.width / 60).clamp(0.0, 1.0);
    var gl = panGains(_layout, pan.angle - pan.width / 2, centre: pan.centre);
    var gr = panGains(_layout, pan.angle + pan.width / 2, centre: pan.centre);
    for (var c = 0; c < count; c++) {
      l[c] = gl[c] * k;
      r[c] = gr[c] * k;
    }
    return (l, r);
  }

  /// _land adds [b], a channel's block, to the speakers through its pan
  /// (ramped over the block) and to the LFE as its strip asks.
  void _land(String key, ChannelMix mix, _Bus b, int n,
      {List<Float32List>? into}) {
    var speakers = into ?? _out;
    var count = _layout.channels;
    var pan = _pans[key];
    // Worked out again only when what they come from has changed: every
    // channel's, at every block, before (Ken's systems review, 2026-11-08).
    var made =
        (_layout, _placed[key], _layout.isSurround ? mix.surround : null);
    var (tl, tr) = pan != null && pan.made == made
        ? (pan.fromL, pan.fromR)
        : _targets(key, mix);
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
      var out = speakers[c];
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
      ..fromR = tr
      ..made = made;
    var lfe = _layout.lfe;
    if (lfe != null && mix.lfeDb != null) {
      var g = dbToGain(mix.lfeDb!) / 2;
      var out = speakers[lfe];
      for (var i = 0; i < n; i++) {
        out[i] += (b.l[i] + b.r[i]) * g;
      }
    }
  }

  /// _runScene runs the scene's bus over what landed on it, a pair of
  /// speakers at a time, and adds it to the master's.
  void _runScene(int n) {
    var strips = _scene;
    if (strips == null) return;
    for (var (k, strip) in strips.indexed) {
      var a = _sceneOut[2 * k];
      var b = 2 * k + 1 < _sceneOut.length ? _sceneOut[2 * k + 1] : null;
      // An odd speaker out -- none in the layouts there are -- runs alone.
      b ??= Float32List(n);
      strip.tapping = k == 0 && tapped.contains(sceneBusKey);
      // Every pair listened to at the same point, so a 5.1 scene bus is
      // heard from one place.
      strip.listenAt = listenAt[sceneBusKey];
      strip.scopes = k == 0 ? scoped[sceneBusKey] ?? const {} : const {};
      strip.process(a, b, n);
      if (k == 0) {
        _levels[sceneBusKey] = _peaks(a, b, n);
        heard[sceneBusKey] = (a, b);
      }
      var oa = _out[2 * k];
      for (var i = 0; i < n; i++) {
        oa[i] += a[i];
      }
      if (2 * k + 1 < _out.length) {
        var ob = _out[2 * k + 1];
        for (var i = 0; i < n; i++) {
          ob[i] += b[i];
        }
      }
    }
  }

  /// _shownMaster is the master whose devices its cards read: in surround,
  /// the front pair's, the one that runs (the stereo master does not).
  MasterProcessor get _shownMaster =>
      _layout.isSurround && _masters.isNotEmpty ? _masters.first : _master;

  /// pitchOf is the pitch heard by strip [key]'s first tuner or Auto-tune
  /// (the master's with no key), or null.
  PitchReading? pitchOf([String? key]) {
    var devices = key == null
        ? _shownMaster.devices
        : _stripOf(key)?.devices ?? const <DeviceProcessor>[];
    for (var d in devices) {
      if (d case PitchListener l when l.pitch) {
        // Read: it goes on listening (see PitchListener.asked).
        l.asked();
        return l.heard;
      }
      if (d case AutoTune a) return a.heard;
    }
    return null;
  }

  /// _devicesOf are strip [key]'s processors (the master's with no key).
  List<DeviceProcessor> _devicesOf(String? key) => key == null
      ? _shownMaster.devices
      : _stripOf(key)?.devices ?? const <DeviceProcessor>[];

  /// waveOf is what strip [key]'s first analyser of [kind] (a Scope or a
  /// Stereo Image) last heard, or null with none.
  Wave? waveOf(String? key, DeviceKind kind) {
    for (var d in _devicesOf(key)) {
      if (d case WaveTap t when t.kind == kind) return t.wave;
    }
    return null;
  }

  /// loudnessOf is strip [key]'s first Loudness's reading, or null.
  LoudnessReading? loudnessOf([String? key]) {
    for (var d in _devicesOf(key)) {
      if (d case LoudnessTap t) return t.reading;
    }
    // The master always measures what leaves it, for its Loudness card.
    return key == null ? _loudness.reading : null;
  }

  /// resetLoudness starts strip [key]'s Loudness measuring again -- the
  /// master's, its own meter too.
  void resetLoudness([String? key]) {
    for (var d in _devicesOf(key)) {
      if (d case LoudnessTap t) t.reset();
    }
    if (key == null) _loudness.reset();
  }

  /// scoped are the devices whose screens show the real sound, by strip
  /// (as [tapped] names them) and then by step: see device_scope.dart.
  final Map<String, Map<String, DeviceScope>> scoped = {};

  /// listenAt is, by channel, the step of its chain heard in place of its
  /// end: see StripProcessor.listenAt.
  final Map<String, int> listenAt = {};

  /// scope starts or stops keeping what passes device [id] of strip [key].
  void scope(String key, String id, bool on) {
    if (on) {
      (scoped[key] ??= {}).putIfAbsent(id, DeviceScope.new);
    } else {
      scoped[key]?.remove(id);
      if (scoped[key]?.isEmpty ?? false) scoped.remove(key);
    }
  }

  /// scopeOf is what device [id] of strip [key] has passed, or null where
  /// it is not [scope]d.
  ScopeReading? scopeOf(String key, String id) => scoped[key]?[id]?.reading;

  /// tapped are the channels whose meters between devices are on screen:
  /// their strips measure each step (see StripProcessor.taps).
  final Set<String> tapped = {};

  /// tapsOf is channel [key]'s levels at each step of its strip, as last
  /// played: see StripProcessor.taps. Empty until [tapped] has it.
  List<(double, double)> tapsOf(String key) {
    if (key == masterTapKey) {
      return _layout.isSurround
          ? _masters.firstOrNull?.taps ?? const []
          : _master.taps;
    }
    return _stripOf(key)?.taps ?? const [];
  }

  /// _stripOf is channel [key]'s strip, a return's, or the scene bus's
  /// front pair's.
  StripProcessor? _stripOf(String key) =>
      _strips[key] ??
      (key == sceneBusKey
          ? _scene?.firstOrNull
          : _returns.where((r) => r.spec.id == key).firstOrNull?.strip);

  /// reductionOf is how many decibels channel [key]'s compressor is taking
  /// off now, or 0 with none.
  double reductionOf(String key) => _stripOf(key)?.compressor?.reductionDb ?? 0;

  /// ringing is whether what leaves the master can still be heard -- a
  /// reverb's or a delay's tail after its sound has stopped -- over about
  /// −90 dB: not to be cut off by resting (see the mix engine's _fill).
  bool get ringing => math.max(_masterLevels.$1, _masterLevels.$2) > 3e-5;

  (double, double) levels([String? key]) =>
      key == null ? _masterLevels : (_levels[key] ?? (0, 0));

  /// quiet sets every meter to silence: each strip's level, the master's,
  /// and the levels between devices -- as the mix rests, so what is read
  /// while it renders nothing is not the last moment it heard (Ken's meters
  /// stood where they were when he pressed stop).
  void quiet() {
    _levels.updateAll((key, level) => (0.0, 0.0));
    _masterLevels = (0, 0);
    List<(double, double)> zero(List<(double, double)> taps) =>
        [for (var _ in taps) (0.0, 0.0)];
    for (var s in _strips.values) {
      s.taps = zero(s.taps);
    }
    for (var s in _scene ?? const <StripProcessor>[]) {
      s.taps = zero(s.taps);
    }
    for (var r in _returns) {
      r.strip.taps = zero(r.strip.taps);
    }
    _master.taps = zero(_master.taps);
    for (var m in _masters) {
      m.taps = zero(m.taps);
    }
  }

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
    if (_scene != null) {
      if (_sceneOut.length != _layout.channels || _sceneOut[0].length < n) {
        _sceneOut = [
          for (var i = 0; i < _layout.channels; i++)
            Float32List(math.max(n, 1024))
        ];
      } else {
        for (var o in _sceneOut) {
          o.fillRange(0, n, 0);
        }
      }
    }
    for (var r in _returns) {
      r.bus
        ..grow(n)
        ..clear(n);
    }
  }

  /// input is where a sound on channel [key] is added for this block: its
  /// channel's input, or straight into the master for an unknown channel.
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
  /// limiter runs only when [limit] (see [MasterProcessor.process]).
  void finish(Float32List l, Float32List r, int n, {bool limit = true}) {
    // What is on no channel, to the front pair.
    for (var i = 0; i < n; i++) {
      _out[0][i] += _direct.l[i];
      _out[1][i] += _direct.r[i];
    }
    // A vocoder's carrier channel, as it came in -- before its own strip,
    // so a muted carrier still carries.
    var everyStrip = [
      ..._strips.values,
      for (var ret in _returns) ret.strip,
      ...?_scene,
    ];
    for (var devices in [
      for (var strip in everyStrip) strip.devices,
      // And those in a split's branches.
      for (var strip in everyStrip)
        for (var split in strip.devices.whereType<SplitProcessor>())
          split.inner.toList(),
    ]) {
      for (var d in devices) {
        if (d is! Sidechained) continue;
        var from = _inputs[d.source];
        if (from != null) {
          d.feed(from.l, from.r, n);
        } else if (_strips.containsKey(d.source)) {
          if (d is Gate) d.silence(n);
          if (d is Follower) d.silence(n);
        }
      }
    }
    // A compressor listening to another channel: a channel there but
    // silent this block is listened to as silence; one gone, not at all.
    for (var comp in [for (var strip in everyStrip) strip.compressor]) {
      var source = comp?.source;
      if (comp == null || source == null) continue;
      var from = _inputs[source];
      if (from != null) {
        comp.key.feed(from.l, from.r, n);
      } else if (_strips.containsKey(source)) {
        comp.key.silence(n);
      }
    }
    for (var entry in _strips.entries) {
      var b = _inputs[entry.key];
      if (b == null) {
        b = _Bus(math.max(n, 1024));
        _inputs[entry.key] = b;
      }
      b.grow(n);
      var strip = entry.value;
      strip.tapping = tapped.contains(entry.key);
      strip.scopes = scoped[entry.key] ?? const {};
      strip.listenAt = listenAt[entry.key];
      strip.shape(b.l, b.r, n);
      _send(entry.key, strip.mix, b, n, pre: true);
      strip.level(b.l, b.r, n);
      _send(entry.key, strip.mix, b, n, pre: false);
      _levels[entry.key] = _peaks(b.l, b.r, n);
      heard[entry.key] = (b.l, b.r);
      // Out into a return, as a group bus, rather than to the master.
      var bus = strip.mix.output.isEmpty
          ? null
          : _returns.where((r) => r.spec.id == strip.mix.output).firstOrNull;
      if (bus != null) {
        if (!strip.mix.mute) bus.bus.addScaled(b, n, 1);
        continue;
      }
      _land(entry.key, strip.mix, b, n,
          into: _scene != null && _sceneKeys.contains(entry.key)
              ? _sceneOut
              : null);
    }
    _runScene(n);
    for (var ret in _returns) {
      var b = ret.bus;
      // Measured, screened and listened to as a channel's strip is.
      ret.strip
        ..tapping = tapped.contains(ret.spec.id)
        ..scopes = scoped[ret.spec.id] ?? const {}
        ..listenAt = listenAt[ret.spec.id]
        ..process(b.l, b.r, n);
      _levels[ret.spec.id] = _peaks(b.l, b.r, n);
      heard[ret.spec.id] = (b.l, b.r);
      _land(ret.spec.id, ret.spec.mix, b, n);
    }
    if (!_layout.isSurround) {
      l.setRange(0, n, _out[0]);
      r.setRange(0, n, _out[1]);
      _master.tapping = tapped.contains(masterTapKey);
      _master.listenAt = listenAt[masterTapKey];
      _master.scopes = scoped[masterTapKey] ?? const {};
      _master.process(l, r, n, limit: limit);
      _publishMaster(l, r, n);
      _out[0].setRange(0, n, l);
      _out[1].setRange(0, n, r);
      _masterLevels = _peaks(l, r, n);
      _levels[speakerLevelKey(0)] = (_masterLevels.$1, _masterLevels.$1);
      _levels[speakerLevelKey(1)] = (_masterLevels.$2, _masterLevels.$2);
      return;
    }
    if ((_layout.lfe, _lfeFilter) case (var lfe?, var filter?)) {
      _silent.fillRange(0, n, 0);
      filter.process(_out[lfe], _silent, n);
    }
    for (var k = 0; k < _masters.length; k++) {
      var a = _out[2 * k];
      var b = 2 * k + 1 < _out.length ? _out[2 * k + 1] : _silent;
      // The front pair's measured between its devices, as a stereo
      // master's is.
      _masters[k].tapping = k == 0 && tapped.contains(masterTapKey);
      _masters[k].listenAt = listenAt[masterTapKey];
      _masters[k].scopes =
          k == 0 ? scoped[masterTapKey] ?? const {} : const {};
      _masters[k].process(a, b, n, limit: limit);
    }
    // Each speaker's peak, for its meter.
    for (var c = 0; c < _out.length; c++) {
      var p = _peaks(_out[c], _out[c], n).$1;
      _levels[speakerLevelKey(c)] = (p, p);
    }
    // Heard on two speakers: folded down, or the group listened to.
    l.fillRange(0, n, 0);
    r.fillRange(0, n, 0);
    for (var (c, (gl, gr)) in hearFold(_layout, hear).indexed) {
      if (gl == 0 && gr == 0) continue;
      var o = _out[c];
      for (var i = 0; i < n; i++) {
        l[i] += o[i] * gl;
        r[i] += o[i] * gr;
      }
    }
    // Its cards' readings, as a stereo master's: the limiting, and the
    // loudness of what is heard.
    _publishMaster(l, r, n);
    _masterLevels = _peaks(l, r, n);
  }

  /// _send adds [mix]'s sends from [from] into the returns that take them
  /// at this point, [pre] or post fader.
  ///
  /// Each from where the last block left it, ramped -- a send turned, or
  /// moved by a lane, or the channel muted -- as a fader is (Ken's systems
  /// review, 2026-11-08: a send stepped at each block).
  void _send(String key, ChannelMix mix, _Bus from, int n,
      {required bool pre}) {
    if (mix.sends.isEmpty && !_sending.contains(key)) return;
    var any = false;
    for (var ret in _returns) {
      if (ret.spec.pre != pre) continue;
      var id = "$key>${ret.spec.id}";
      var db = mix.sends[ret.spec.id];
      var g = db == null || mix.mute ? 0.0 : dbToGain(db);
      // A send's first block starts it where it is set; after that, one
      // not sounding before rises from silence.
      var was = _sendGains[id] ?? (_sendsMet.add(id) ? g : 0.0);
      if (was == 0 && g == 0) {
        _sendGains.remove(id);
        continue;
      }
      any = true;
      ret.bus.addRamped(from, n, was, g);
      _sendGains[id] = g;
    }
    any ? _sending.add(key) : _sending.remove(key);
  }

  /// _sendGains are each send's gain as the last block ended, by
  /// "channel>return"; _sending the channels with one still sounding.
  final Map<String, double> _sendGains = {};
  final Set<String> _sending = {}, _sendsMet = {};

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
