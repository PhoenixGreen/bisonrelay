import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:bruig/plugin_system/canvas/media/push_surface.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show MidiControl;

// midi_input.dart is the plugged-in MIDI keyboards, the chosen one, and its
// notes handed to the open canvas. One for the app, as there is one desk.
// USB and system MIDI only: Bluetooth MIDI would ask for Bluetooth access.

/// MidiInput is the app's one MIDI keyboard connection.
class MidiInput extends ChangeNotifier {
  static final MidiInput shared = MidiInput();

  MidiCommand? _command;
  StreamSubscription<MidiPacket>? _packets;

  List<MidiDevice> _devices = const [];
  MidiDevice? _device;
  bool _unavailable = false;

  /// devices are the MIDI devices as last looked.
  List<MidiDevice> get devices => _devices;

  /// device is the one notes are taken from, or null for none.
  MidiDevice? get device => _device;

  /// unavailable is set where the system's MIDI could not be reached.
  bool get unavailable => _unavailable;

  /// onNote is handed every key pressed and let go (velocity nought) on the
  /// chosen device. Set by the open canvas.
  void Function(int key, int velocity)? onNote;

  /// onControl is handed the other controllers (mod wheel, pitch bend,
  /// expression, volume, pan), nought to one.
  void Function(MidiControl control, double value)? onControl;

  /// onCc is handed every control change by number, nought to one, before
  /// it is read as a known controller (see CanvasController.midiCc).
  void Function(int cc, double value)? onCc;

  /// onPlay and onRecord are a controller's transport buttons: a Push's.
  void Function()? onPlay;
  void Function()? onRecord;

  /// onClip and clipAt are a Push's Session mode: a slot's pad pressed (at
  /// its velocity) or let go, and a slot's state, to light it.
  void Function(int column, int row, int velocity)? onClip;
  PadClip Function(int column, int row)? clipAt;

  /// push is the Push being played (see push_surface.dart), or null.
  PushSurface? get push => _push;
  PushSurface? _push;

  /// usePush plays [surface] as a Push: its pads, buttons and encoders are
  /// read through it first.
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

  /// use takes notes from [device], or none with null.
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

  /// handle reads one MIDI message on any channel: keys to [onNote],
  /// controllers and pitch bend to [onControl]; the rest is ignored.
  @visibleForTesting
  void handle(Uint8List data) {
    if (data.length < 3) return;
    // A Push's pads, buttons and encoders are its own; its touch strip and
    // the rest read as any keyboard's.
    if (_push?.handle(data) ?? false) return;
    var kind = data[0] & 0xF0;
    var key = data[1] & 0x7F, velocity = data[2] & 0x7F;
    if (kind == 0x90) {
      onNote?.call(key, velocity);
    } else if (kind == 0x80) {
      onNote?.call(key, 0);
    } else if (kind == 0xB0) {
      onCc?.call(key, velocity / 127);
      if (MidiControl.ofCc(key) case var c?) onControl?.call(c, velocity / 127);
    } else if (kind == 0xE0) {
      // Pitch bend: fourteen bits, low seven first; 8192 the middle.
      onControl?.call(MidiControl.pitchBend, (velocity << 7 | key) / 16383);
    }
  }
}
