// procedural_params.dart is the settings a background style has of its own.
//
// Six numbers shared by twenty styles was the trouble with them: "density"
// and "size" are not what anybody wants to say about a circuit board or a
// chain of blocks. The questions worth asking are the style's own -- how
// thick the traces are, whether the blocks are cubes -- so each style lists
// its own here, and the settings panel draws whatever is listed.
//
// A table rather than a class per style, which is what the pitch, the rings
// and the metal have. Those are big enough to be worth one; most styles have
// four or five numbers and a choice, and a table is what lets the panel, the
// saving and the looks all handle every one of them the same way.

/// StyleParam is one setting a style has of its own.
///
/// Every value is held as a number, choices and switches too: a choice is
/// the index of what was chosen, and a switch is nought or one. That is what
/// lets a look be written as a map of numbers and a document carry them as
/// one.
class StyleParam {
  /// id is what it is saved under. Styles that ask the same question use the
  /// same one -- a line's weight is a line's weight -- so it survives moving
  /// between them.
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
        toggle = false;

  const StyleParam.choice(
    this.id,
    this.label,
    this.choices, {
    int initial = 0,
    this.group,
    this.onlyWhen = const {},
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
        toggle = true;

  bool get isChoice => choices.isNotEmpty;

  /// clamped is [v] held inside what this setting can be.
  double clamped(double v) {
    if (isChoice) return v.round().clamp(0, choices.length - 1).toDouble();
    if (toggle) return v >= 0.5 ? 1 : 0;
    return v.clamp(min, max);
  }
}
