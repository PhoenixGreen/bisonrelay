// character_views.dart is the views a sketched character is drawn from.
// It starts with three -- front, side and back -- and has others added
// only as they are wanted: three-quarters, from above, from below, from
// the top. However it is turned, it is drawn from the nearest view it has;
// a view turned the other way -- the left side for the right -- is its
// mirror, until it is drawn itself.
//
// A view is one of the panels of CharacterPose.inPanel: turned a multiple
// of 45 degrees, from one of its four heights. Drawings, face rigs and
// garment drawings are kept by a view's panel, so nothing about them
// changes when views come and go.

/// CharacterView is one view a character is drawn from: [turn] round it,
/// 0 to 180, the other way being its mirror, and [tilt] from below to the
/// top.
class CharacterView {
  final double turn;
  final double tilt;
  const CharacterView(this.turn, this.tilt);

  static const CharacterView front = CharacterView(0, 0);
  static const CharacterView side = CharacterView(90, 0);
  static const CharacterView back = CharacterView(180, 0);

  /// start is the views a character starts with.
  static const List<CharacterView> start = [front, side, back];

  /// turns and tilts are where views can be: round the character every 45
  /// degrees, and from below, level, above and the top.
  static const List<double> turns = [0, 45, 90, 135, 180];
  static const List<double> tilts = [0, -45, 45, 85];

  /// all is every view a character can have.
  static List<CharacterView> get all => [
        for (var tilt in tilts)
          for (var turn in turns) CharacterView(turn, tilt),
      ];

  String get label => viewLabel(turn, tilt);

  @override
  bool operator ==(Object other) =>
      other is CharacterView && other.turn == turn && other.tilt == tilt;

  @override
  int get hashCode => Object.hash(turn, tilt);

  List<double> toJson() => [turn, tilt];

  static CharacterView? fromJson(Object? json) {
    if (json is! List || json.length != 2 || json[0] is! num || json[1] is! num) {
      return null;
    }
    return CharacterView.of((json[0] as num).toDouble(), (json[1] as num).toDouble());
  }

  /// of is the view a panel turned [turn] and tilted [tilt] is: turned
  /// the way round its mirror is not.
  factory CharacterView.of(double turn, double tilt) {
    var t = ((turn % 360) + 360) % 360;
    if (t > 180) t = 360 - t;
    return CharacterView((t / 45).round() * 45.0, tilts.reduce(
        (a, b) => (tilt - a).abs() <= (tilt - b).abs() ? a : b));
  }
}

/// viewLabel is a view's name: Front, ¾ front, Side, ¾ back, Back, and how
/// it is seen from where it is not level.
String viewLabel(double turn, double tilt) {
  var t = turn.abs().round();
  var side = switch (t) {
    0 => "Front",
    45 => "¾ front",
    90 => "Side",
    135 => "¾ back",
    180 => "Back",
    _ => "$t°",
  };
  var height = switch (tilt.round()) {
    -45 => " from below",
    45 => " from above",
    85 => " from the top",
    _ => "",
  };
  return "$side$height";
}

/// nearestView is the panel -- turn and tilt -- of [views] nearest a
/// character turned [turn] and tilted [tilt]: one of them, or its mirror.
(double, double) nearestView(List<CharacterView> views, double turn, double tilt) {
  if (views.isEmpty) return (0, 0);
  var t = ((turn % 360) + 360) % 360;
  if (t > 180) t -= 360;
  double apart(double a, double b) {
    var d = ((a - b) % 360 + 360) % 360;
    return d > 180 ? 360 - d : d;
  }

  var best = (views.first.turn, views.first.tilt);
  var bestD = double.infinity;
  for (var v in views) {
    for (var sign in v.turn == 0 || v.turn == 180 ? const [1.0] : const [1.0, -1.0]) {
      var vt = v.turn * sign;
      var d = apart(t, vt) + (tilt - v.tilt).abs();
      if (d < bestD) {
        bestD = d;
        best = (vt, v.tilt);
      }
    }
  }
  return best;
}
