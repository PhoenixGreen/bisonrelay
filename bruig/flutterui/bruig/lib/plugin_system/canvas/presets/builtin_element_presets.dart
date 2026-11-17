import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';

// builtin_element_presets.dart is the designs that ship with the app: so
// far a Code panel's examples (code_starters.dart). A shipped preset cannot
// be renamed or deleted (ElementPreset.builtIn), and must carry the page it
// was designed on, or it is not scaled.

List<ElementPreset> get builtinElementPresets =>
    _builtin ??= [...codeExamplePresets];
List<ElementPreset>? _builtin;
