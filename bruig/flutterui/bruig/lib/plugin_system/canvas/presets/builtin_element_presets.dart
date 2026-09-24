import 'package:bruig/plugin_system/canvas/model/element_preset.dart';

// builtin_element_presets.dart is the designs that ship with the app.
//
// There are none. There was one -- a football league table, kept as the
// element's own JSON -- and it was taken out on 2026-09-24: a preset now
// carries the page it was designed on and is sized to the page it is dropped
// on, and that one had no page to carry, so it arrived at whatever size it
// happened to have been saved at. Saving it again from a canvas gives it one.
//
// The list stays, and so does ElementPreset.builtIn: a design that ships with
// the app is one nobody can rename or throw away, and that rule is worth
// keeping ready for the next one rather than being written again.

/// builtinElementPresets are the presets everybody has.
List<ElementPreset> get builtinElementPresets => const [];
