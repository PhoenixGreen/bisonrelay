import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:bruig/plugin_system/canvas/media/push_surface.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show MidiControl;

// midi_input.dart is a MIDI keyboard plugged in: the ones there are, the one
// chosen, and its notes handed to whichever canvas is open -- which plays
// them on an instrument, and records them while Record is on.
//
// One for the whole app, since there is one keyboard on the desk. USB and
// the system's own MIDI only: Bluetooth MIDI would ask for Bluetooth, and
// nothing here needs it.

class MidiInput extends ChangeNotifier {
  static final MidiInput shared = MidiInput();

  MidiCommand? _command;
  StreamSubscription<MidiPacket>? _packets;

  List<MidiDevice> _devices = const [];
  MidiDevice? _device;
  bool _unavailable = false;

  /// devices are the MIDI devices there are, as last looked.
  List<MidiDevice> get devices => _devices;

  /// device is the one notes are taken from, or null for none.
  MidiDevice? get device => _device;

  /// unavailable is set where the system's MIDI could not be reached.
  bool get unavailable => _unavailable;

  /// onNote is handed every key pressed, and let go -- at a velocity of
  /// nought -- on the chosen device. Set by the canvas that is open.
  void Function(int key, int velocity)? onNote;

  /// onSustain is handed the sustain pedal, down or up.
  void Function(bool down)? onSustain;

  /// onControl is handed the other controllers a keyboard sends -- the mod
  /// wheel, the pitch bend, an expression pedal, volume, pan -- nought to
  /// one.
  void Function(MidiControl control, double value)? onControl;

  /// onPlay and onRecord are a controller's transport buttons: a Push's.
  void Function()? onPlay;
  void Function()? onRecord;

  /// onClip and clipAt are a Push's Session mode: a slot's pad pressed, at
  /// its velocity, or let go; and how a slot is doing, to light it.
  void Function(int column, int row, int velocity)? onClip;
  PadClip Function(int column, int row)? clipAt;

  /// push is the Push being played, where the device chosen is one -- see
  /// push_surface.dart -- or null.
  PushSurface? get push => _push;
  PushSurface? _push;

  /// usePush plays [surface] as a Push: its pads, buttons and encoders
  /// read through it before anything else. Public for tests.
  @visibleForTesting
  void usePush(PushSurface? surface) {
    _push = surface;
    if (surface == null) return;
    surface.onNote = (key, velocity) => onNote?.call(key, velocity);
    surface.onControl = (c, v) => onControl?.call(c, v);
    surface.onPlay = () => onPlay?.call();
    surface.onRecord = () => onRecord?.call();
    surface.onClip = (column, row, v) => onClip?.call(column, row, v);
    surface.clipAt =
        (column, row) => clipAt?.call(column, row) ?? PadClip.empty;
    surface.start();
  }

  MidiCommand get _midi => _command ??= MidiCommand();

  /// refresh looks again for the devices there are.
  Future<void> refresh() async {
    try {
      _devices = await _midi.devices ?? const [];
      _unavailable = false;
    } catch (exception) {
      debugPrint("MIDI is not available: $exception");
      _devices = const [];
      _unavailable = true;
    }
    notifyListeners();
  }

  /// use takes notes from [device] -- or, null, from none.
  Future<bool> use(MidiDevice? device) async {
    if (_device case var was?) {
      try {
        _midi.disconnectDevice(was);
      } catch (_) {}
    }
    _device = null;
    _push = null;
    await _packets?.cancel();
    _packets = null;
    // A Push is played on its User port, whichever of its ports was picked.
    if (device != null && isPush(device.name)) {
      var port = pushPort([for (var d in _devices) d.name]);
      device = _devices.where((d) => d.name == port).firstOrNull ?? device;
    }
    if (device == null) {
      notifyListeners();
      return true;
    }
    try {
      await _midi.connectToDevice(device);
      _device = device;
      var id = device.id;
      _packets = _midi.onMidiPacketReceived?.listen((p) {
        if (p.device.id != id) return;
        handle(p.data);
      });
      if (isPush(device.name)) {
        usePush(PushSurface(
            model: PushModel.of(device.name),
            send: (data) {
              try {
                _midi.sendData(data, deviceId: id);
              } catch (_) {}
            }));
      }
      notifyListeners();
      return true;
    } catch (exception) {
      debugPrint("Unable to use ${device.name}: $exception");
      notifyListeners();
      return false;
    }
  }

  /// handle reads one MIDI message: a key pressed or let go, on any
  /// channel, goes to [onNote]; the rest is let pass.
  @visibleForTesting
  void handle(Uint8List data) {
    if (data.length < 3) return;
    // A Push's pads, buttons and encoders are its own; its touch strip and
    // anything else are read as any keyboard's.
    if (_push?.handle(data) ?? false) return;
    var kind = data[0] & 0xF0;
    var key = data[1] & 0x7F, velocity = data[2] & 0x7F;
    if (kind == 0x90) {
      onNote?.call(key, velocity);
    } else if (kind == 0x80) {
      onNote?.call(key, 0);
    } else if (kind == 0xB0 && key == 64) {
      // Control change 64: the sustain pedal, down from 64.
      onSustain?.call(velocity >= 64);
    } else if (kind == 0xB0) {
      if (MidiControl.ofCc(key) case var c?) onControl?.call(c, velocity / 127);
    } else if (kind == 0xE0) {
      // Pitch bend: fourteen bits, low seven first; 8192 the middle.
      onControl?.call(MidiControl.pitchBend, (velocity << 7 | key) / 16383);
    }
  }
}
