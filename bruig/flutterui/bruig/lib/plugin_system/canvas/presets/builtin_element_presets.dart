import 'package:bruig/plugin_system/canvas/model/element_preset.dart';

// builtin_element_presets.dart is the designs that ship with the app. There
// are none at present; the list and ElementPreset.builtIn (a shipped preset
// cannot be renamed or deleted) are kept ready for the next one. A shipped
// preset must carry the page it was designed on, or it is not scaled.

/// builtinElementPresets are the presets everybody has.
List<ElementPreset> get builtinElementPresets => const [];
