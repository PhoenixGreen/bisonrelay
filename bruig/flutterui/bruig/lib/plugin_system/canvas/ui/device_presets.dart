import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/model/strip_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/widgets.dart';

// device_presets.dart keeps a sound's devices as presets, as the prototype's
// "Save as a preset…" does: one device, or a whole chain, with its settings.
// They are kept with the canvas's other presets (Presets › Sound), one file
// each, and brought back from a chain's "+" or from the Presets sidebar.

/// devicePresets is where they are kept.
SavedPresetStore get devicePresets => SavedPresetStore.devices;

/// presetDevices are a preset's sound devices, each with no id yet: added
/// to a chain, it is given one of its own.
List<MixDevice> presetDevices(Map<String, dynamic> data) => [
      if (data["devices"] case List list)
        for (var d in list)
          if (MixDevice.fromJson(d) case var device?) device.withId(""),
    ];

/// presetMidi are a preset's MIDI effects.
List<MidiEffect> presetMidi(Map<String, dynamic> data) => [
      if (data["midi"] case List list)
        for (var m in list)
          if (MidiEffect.fromJson(m) case var effect?) effect,
    ];

/// stripPresetOf is a preset of one of a strip's own cards -- which, and its
/// settings as written -- or null for one of devices.
(StripPart, Map<String, dynamic>)? stripPresetOf(Map<String, dynamic> data) =>
    switch ((StripPart.fromName(data["strip"]), data["value"])) {
      (var part?, Map<String, dynamic> value) => (part, value),
      _ => null,
    };

/// motionPresetOf is a preset of one motion device -- its kind, and its
/// settings as written -- or null for any other.
MotionDevice? motionPresetOf(Map<String, dynamic> data) =>
    MotionDevice.fromJson(data["motion"]);

/// saveMotionPreset keeps motion device [d]'s settings as a preset, named
/// for its kind, as saveDevicePreset keeps a sound's device.
Future<void> saveMotionPreset(BuildContext context, MotionDevice d) async {
  SnackBarModel? snack;
  try {
    snack = SnackBarModel.of(context);
  } catch (_) {}
  await devicePresets.load();
  var named = freshPresetName(
      d.kind.label, {for (var p in devicePresets.presets) p.name});
  var saved = await devicePresets.save(named, {"motion": d.toJson()});
  if (saved == null) {
    snack?.error("The preset could not be kept");
    return;
  }
  snack?.success("Kept as the preset \"$named\" (Presets › Sound)");
}

/// saveStripPreset keeps [value] -- an EQ's, a compressor's, a limiter's or
/// a Ducker's settings as written -- as a preset of [part], as
/// saveDevicePreset keeps a device.
Future<void> saveStripPreset(
    BuildContext context, StripPart part, Map<String, dynamic> value) async {
  SnackBarModel? snack;
  try {
    snack = SnackBarModel.of(context);
  } catch (_) {}
  await devicePresets.load();
  var named = freshPresetName(
      part.label, {for (var p in devicePresets.presets) p.name});
  var saved =
      await devicePresets.save(named, {"strip": part.name, "value": value});
  if (saved == null) {
    snack?.error("The preset could not be kept");
    return;
  }
  snack?.success("Kept as the preset \"$named\" (Presets › Sound)");
}

/// freshPresetName is [name], or "[name] 2", "[name] 3"… where [taken]
/// has it.
String freshPresetName(String name, Set<String> taken) {
  var named = name;
  for (var n = 2; taken.contains(named); n++) {
    named = "$name $n";
  }
  return named;
}

/// saveDevicePreset keeps [devices] and [midi] as a preset named for
/// [name] -- "Chorus", or "Chorus 2" where that is taken -- and says where
/// it went. Nothing is asked: it can be renamed in the Presets sidebar.
Future<void> saveDevicePreset(BuildContext context, String name,
    {List<MixDevice> devices = const [],
    List<MidiEffect> midi = const []}) async {
  SnackBarModel? snack;
  try {
    snack = SnackBarModel.of(context);
  } catch (_) {
    // No snack bar where it was asked from: kept all the same.
  }
  await devicePresets.load();
  var named =
      freshPresetName(name, {for (var p in devicePresets.presets) p.name});
  var saved = await devicePresets.save(named, {
    if (devices.isNotEmpty)
      "devices": [for (var d in devices) d.withId("").toJson()],
    if (midi.isNotEmpty) "midi": [for (var m in midi) m.toJson()],
  });
  if (saved == null) {
    snack?.error("The preset could not be kept");
    return;
  }
  snack?.success("Kept as the preset \"$named\" (Presets › Sound)");
}

/// useDevicePreset adds [preset]'s devices to the end of [owner]'s chain
/// -- and its MIDI effects to a MIDI channel's -- as one undo step.
/// Answers whether there was anything it could add there.
bool useDevicePreset(
    CanvasController c, String owner, Map<String, dynamic> preset) {
  // One of a strip's own cards: put on this strip's, where it has one.
  if (stripPresetOf(preset) case (var part, var value)) {
    switch (part) {
      case StripPart.eq:
        c.writeStripPart(owner, eq: Eq.fromJson(value));
      case StripPart.comp:
        c.writeStripPart(owner, comp: Dynamics.fromJson(value));
      case StripPart.duck:
        if (c.timelineChannels.every((l) => l.key != owner)) return false;
        c.writeStripPart(owner, duck: Ducking.fromJson(value));
      case StripPart.limiter:
        if (owner != mixerMasterKey) return false;
        var m = c.document.masterMix;
        c.beginInteraction();
        c.setMasterMix(
            m.copyWith(
                ceilingDb: (value["ceiling"] as num?)?.toDouble(),
                limiterAheadMs: (value["ahead"] as num?)?.toDouble(),
                limiterReleaseMs: (value["release"] as num?)?.toDouble()),
            transient: true);
        c.endInteraction();
    }
    return true;
  }
  var devices = presetDevices(preset);
  var midi = c.instrumentChannel(owner) ? presetMidi(preset) : const [];
  if (devices.isEmpty && midi.isEmpty) return false;
  c.beginInteraction();
  if (devices.isNotEmpty) {
    c.setDevicesOf(owner, withDeviceIds([...c.devicesOf(owner), ...devices]));
  }
  if (midi.isNotEmpty) {
    c.setChannelPart(
        owner, (p) => p.copyWith(effects: [...p.effects, ...midi]));
  }
  c.endInteraction();
  return true;
}

/// presetHolds is whether [p] has sound devices, or -- with [midi] --
/// MIDI effects.
bool presetHolds(SavedPreset p, {bool midi = false}) =>
    midi ? presetMidi(p.data).isNotEmpty : presetDevices(p.data).isNotEmpty;
