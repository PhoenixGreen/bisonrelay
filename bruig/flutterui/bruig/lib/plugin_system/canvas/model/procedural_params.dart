// procedural_params.dart is the settings a background style has beyond the
// shared ones. Each style lists its own (procedural_style_params.dart) and
// the panel draws whatever is listed. A table, not a class per style, so
// the panel, saving and looks treat every style the same way.

/// StyleParam is one setting a style has of its own. Every value is a
/// number, so looks and documents carry them as one map: a choice is its
/// index, a switch nought or one.
class StyleParam {
  /// id is what it is saved under. Styles with the same setting share an id,
  /// so the value survives switching between them.
  final String id;
  final String label;
  final double min;
  final double max;
  final double initial;
  final int decimals;

  /// choices makes it a dropdown, its value the chosen index.
  final List<String> choices;

  final bool toggle;

  /// group is the heading it is shown under, or null for the style's first.
  final String? group;

  /// onlyWhen hides it unless each named setting has one of the values
  /// listed: a cube's depth means nothing when the blocks are flat.
  final Map<String, List<int>> onlyWhen;

  /// sets is, for a choice, the other settings each answer puts in place as
  /// a starting point.
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

  /// clamped is [v] held inside this setting's range.
  double clamped(double v) {
    if (isChoice) return v.round().clamp(0, choices.length - 1).toDouble();
    if (toggle) return v >= 0.5 ? 1 : 0;
    return v.clamp(min, max);
  }
}
