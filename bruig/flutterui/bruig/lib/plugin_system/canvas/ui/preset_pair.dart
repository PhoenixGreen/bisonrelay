import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown;
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:flutter/widgets.dart';

// preset_pair.dart is an arrival's, a leaving's or a loop's preset chosen
// in two steps (Ken, 2026-11-12): "Preset" its family -- Fade, Slide,
// Scale -- and "Kind" which of them -- Fade up. The list is a lot shorter
// and grouped as the presets are. The same two, in the Chain and in the
// settings panel.

/// PresetOption is one preset, by its value, name and family.
class PresetOption<T> {
  final T value;
  final String label;
  final String family;
  const PresetOption(this.value, this.label, this.family);
}

/// textPresetOptions are a text's arrivals and leavings.
List<PresetOption<TextAnimationPreset>> textPresetOptions() => [
      for (var p in TextAnimationPreset.values)
        if (p != TextAnimationPreset.none)
          PresetOption(p, p.label, p.family.label),
    ];

/// elementPresetOptions are a shape's or a picture's.
List<PresetOption<ElementAnimationPreset>> elementPresetOptions() => [
      for (var p in ElementAnimationPreset.values)
        if (p != ElementAnimationPreset.none)
          PresetOption(p, p.label, p.family.label),
    ];

/// loopPresetOptions are the loops; the drifts only for a picture.
List<PresetOption<LoopPreset>> loopPresetOptions({bool drifts = true}) => [
      for (var p in LoopPreset.values)
        if (p != LoopPreset.none && (drifts || p.family != LoopFamily.drift))
          PresetOption(p, p.label, p.family.label),
    ];

/// PresetPair is [value] split into its family and kind, and what choosing
/// either makes it.
class PresetPair<T> {
  final List<PresetOption<T>> options;
  final T value;

  /// none is "no preset": the family "None".
  final T none;
  const PresetPair(this.options, this.value, this.none);

  List<String> get families => [
        for (var o in options) o.family,
      ].toSet().toList();

  /// family is [value]'s family, or "" for none.
  String get family =>
      options.where((o) => o.value == value).firstOrNull?.family ?? "";

  /// kinds are the presets of [value]'s family.
  List<PresetOption<T>> get kinds => [
        for (var o in options)
          if (o.family == family) o,
      ];

  /// inFamily is what choosing family [f] makes it: as it is where it is
  /// one of them already, else the family's first; none for "".
  T inFamily(String f) {
    if (f.isEmpty) return none;
    if (family == f) return value;
    return options.firstWhere((o) => o.family == f).value;
  }
}

/// studioPresetPair is the pair as the Chain's selects: the family keyed
/// "[key]Family", the kind [key].
List<Widget> studioPresetPair<T>({
  required String key,
  required PresetPair<T> pair,
  required ValueChanged<T> onChanged,
  String familyLabel = "Preset",
  String kindLabel = "Kind",
  String noneLabel = "None",
  double width = 150,
}) =>
    [
      StudioDrop<String>(
        key: ValueKey("${key}Family"),
        label: familyLabel,
        value: pair.family,
        width: width,
        options: [
          ("", noneLabel),
          for (var f in pair.families) (f, f),
        ],
        onChanged: (f) => onChanged(pair.inFamily(f)),
      ),
      if (pair.family.isNotEmpty)
        StudioDrop<T>(
          key: ValueKey(key),
          label: kindLabel,
          value: pair.value,
          width: width,
          options: [for (var o in pair.kinds) (o.value, o.label)],
          onChanged: onChanged,
        ),
    ];

/// canvasPresetPair is the pair as the settings panel's selects.
List<Widget> canvasPresetPair<T>({
  required String key,
  required PresetPair<T> pair,
  required ValueChanged<T> onChanged,
  String familyLabel = "Preset",
  String kindLabel = "Kind",
  String noneLabel = "None",
}) =>
    [
      CanvasDropdown<String>(
        key: ValueKey("${key}Family"),
        label: familyLabel,
        value: pair.family,
        width: 80,
        options: [
          ("", noneLabel),
          for (var f in pair.families) (f, f),
        ],
        onChanged: (f) => onChanged(pair.inFamily(f)),
      ),
      CanvasDropdown<T>(
        key: ValueKey(key),
        label: kindLabel,
        value: pair.value,
        width: 80,
        enabled: pair.family.isNotEmpty,
        options: pair.family.isEmpty
            ? [(pair.none, "—")]
            : [for (var o in pair.kinds) (o.value, o.label)],
        onChanged: onChanged,
      ),
    ];
