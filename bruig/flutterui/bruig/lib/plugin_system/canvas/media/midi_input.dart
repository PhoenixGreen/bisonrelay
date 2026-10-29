import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

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
    await _packets?.cancel();
    _packets = null;
    if (device == null) {
      notifyListeners();
      return true;
    }
    try {
      await _midi.connectToDevice(device);
      _device = device;
      _packets = _midi.onMidiPacketReceived?.listen((p) {
        if (p.device.id != device.id) return;
        handle(p.data);
      });
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
    var kind = data[0] & 0xF0;
    var key = data[1] & 0x7F, velocity = data[2] & 0x7F;
    if (kind == 0x90) {
      onNote?.call(key, velocity);
    } else if (kind == 0x80) {
      onNote?.call(key, 0);
    }
  }
}
