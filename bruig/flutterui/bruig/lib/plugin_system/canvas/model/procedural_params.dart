// procedural_params.dart is the settings a background style has of its own,
// beyond the ones every style shares. Each style lists its own (see
// procedural_style_params.dart) and the settings panel draws whatever is
// listed.
//
// A table rather than a class per style (only the rings and the metal have
// one), so the panel, saving and looks handle every style the same way.

/// StyleParam is one setting a style has of its own.
///
/// Every value is a number, so looks and documents carry them as one map: a
/// choice is the index chosen, a switch is nought or one.
class StyleParam {
  /// id is what it is saved under. Styles with the same setting share an id,
  /// so the value survives switching between them.
  final String id;
  final String label;
  final double min;
  final double max;
  final double initial;
  final int decimals;

  /// choices makes it a dropdown of these, its value the index of one.
  final List<String> choices;

  /// toggle makes it a switch.
  final bool toggle;

  /// group is the heading it is shown under, or null for the style's own
  /// first group.
  final String? group;

  /// onlyWhen hides it unless each setting named is one of the values
  /// listed for it: a cube's depth means nothing when the blocks are flat.
  final Map<String, List<int>> onlyWhen;

  /// sets is, for a choice, the other settings each answer puts in place
  /// when chosen, as a starting point.
  final Map<int, Map<String, double>> sets;

  const StyleParam(
    this.id,
    this.label, {
    this.min = 0,
    this.max = 1,
    this.initial = 0.5,
    this.decimals = 2,
    this.group,
    this.onlyWhen = const {},
  })  : choices = const [],
        toggle = false,
        sets = const {};

  const StyleParam.choice(
    this.id,
    this.label,
    this.choices, {
    int initial = 0,
    this.group,
    this.onlyWhen = const {},
    this.sets = const {},
  })  : min = 0,
        max = 1000,
        initial = initial + 0.0,
        decimals = 0,
        toggle = false;

  const StyleParam.toggle(
    this.id,
    this.label, {
    bool initial = false,
    this.group,
    this.onlyWhen = const {},
  })  : min = 0,
        max = 1,
        initial = initial ? 1.0 : 0.0,
        decimals = 0,
        choices = const [],
        sets = const {},
        toggle = true;

  bool get isChoice => choices.isNotEmpty;

  /// clamped is [v] held inside what this setting can be.
  double clamped(double v) {
    if (isChoice) return v.round().clamp(0, choices.length - 1).toDouble();
    if (toggle) return v >= 0.5 ? 1 : 0;
    return v.clamp(min, max);
  }
}
