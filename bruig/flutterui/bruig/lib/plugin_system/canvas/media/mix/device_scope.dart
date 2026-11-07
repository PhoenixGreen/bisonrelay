import 'dart:math' as math;
import 'dart:typed_data';

// device_scope.dart is what a device's screen shows of the real sound while
// its display is on (Ken, 2026-11-08: "the Gate visual doesn't show real
// audio signal"; displays start off, to save the work): the sound going
// into the device and coming out of it -- the last few milliseconds as a
// wave, and the last few seconds as peaks -- and, for a device that keeps
// one, a reading of its own (a vocoder's bands, a gate's opening).

/// ScopeReading is a device's sound in and out, oldest first: [inWave] and
/// [outWave] the latest samples (both sides mixed), [inPeaks] and
/// [outPeaks] the loudest of every [DeviceScope.chunk] samples over the
/// last few seconds, and [own] the device's reading, or null.
typedef ScopeReading = ({
  Float32List inWave,
  Float32List outWave,
  Float32List inPeaks,
  Float32List outPeaks,
  Float32List? own,
});

/// Readable is a device with a reading of its own for its screen.
abstract class Readable {
  /// reading is what it last did, as its screen draws it: a vocoder's
  /// bands' levels, a gate's gain.
  Float32List get reading;
}

/// DeviceScope keeps what passes one device: see [ScopeReading].
class DeviceScope {
  /// waveLength is how many samples of wave are kept: about 40 ms.
  static const int waveLength = 2048;

  /// chunk is how many samples a peak is taken over: 5 ms at 48 kHz.
  static const int chunk = 240;

  /// historyLength is how many peaks are kept: three seconds.
  static const int historyLength = 600;

  final Float32List _inWave = Float32List(waveLength),
      _outWave = Float32List(waveLength);
  final Float32List _inPeaks = Float32List(historyLength),
      _outPeaks = Float32List(historyLength);
  int _w = 0, _start = 0, _h = 0, _filled = 0;
  double _pin = 0, _pout = 0;
  Float32List? _own;

  /// before is a stretch of [n] about to go into the device.
  void before(Float32List l, Float32List r, int n) {
    _start = _w;
    var at = _w;
    for (var i = 0; i < n; i++) {
      _inWave[at] = (l[i] + r[i]) * 0.5;
      if (++at == waveLength) at = 0;
    }
  }

  /// after is that stretch come out of it, [device] what ran it.
  void after(Float32List l, Float32List r, int n, Object? device) {
    var at = _start;
    for (var i = 0; i < n; i++) {
      var o = (l[i] + r[i]) * 0.5;
      _outWave[at] = o;
      _pin = math.max(_pin, _inWave[at].abs());
      _pout = math.max(_pout, o.abs());
      if (++_filled >= chunk) {
        _inPeaks[_h] = _pin;
        _outPeaks[_h] = _pout;
        if (++_h == historyLength) _h = 0;
        _pin = _pout = 0;
        _filled = 0;
      }
      if (++at == waveLength) at = 0;
    }
    _w = at;
    if (device is Readable) _own = device.reading;
  }

  /// reading is what it has kept, oldest first: copies, to be sent on.
  ScopeReading get reading {
    Float32List from(Float32List ring, int at) {
      var out = Float32List(ring.length);
      out.setRange(0, ring.length - at, ring, at);
      out.setRange(ring.length - at, ring.length, ring);
      return out;
    }

    return (
      inWave: from(_inWave, _w),
      outWave: from(_outWave, _w),
      inPeaks: from(_inPeaks, _h),
      outPeaks: from(_outPeaks, _h),
      own: _own == null ? null : Float32List.fromList(_own!),
    );
  }
}
