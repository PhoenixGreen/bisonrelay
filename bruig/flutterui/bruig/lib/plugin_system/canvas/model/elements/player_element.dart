import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// player_element.dart is a whole team on the pitch, not one player.
//
// It started as one dot per element and that was the wrong grain. Setting up a
// match meant adding twenty-two elements, typing twenty-two numbers, and then
// changing the shirt colour twenty-two times -- and the layer list was
// twenty-two rows deep before anything else had been drawn. Worse, the one
// thing anybody actually wants to say ("play a 4-3-3") could not be said at
// all, because no element knew about any other.
//
// One element per team turns all of that into one control each: a sport, a
// formation, one set of colours, one dot size. The players inside it are rows
// in a list rather than elements in the document, so a team drags, rotates,
// scales and animates as a unit, and a player is still individually movable,
// nameable, hideable and orderable within it.

/// TeamSport is which game the team is set up for.
///
/// It decides the squad size and which formations are on offer. Only football
/// is wired up; the enum exists so that adding basketball is a table of
/// formations rather than a second element that duplicates all of this.
enum TeamSport {
  football("Football", 11);

  final String label;

  /// squadSize includes the goalkeeper, who is always the first player.
  final int squadSize;

  const TeamSport(this.label, this.squadSize);

  static TeamSport fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => TeamSport.football);

  List<TeamFormation> get formations =>
      TeamFormation.values.where((f) => f.sport == this).toList();
}

/// _pitchHalfLength and _pitchWidth are the half a team lines up in, in metres.
///
/// Formations below are written in metres against these, for the same reason
/// the pitch itself is drawn to scale: a back four sitting exactly on the edge
/// of its own penalty area is the whole point of having drawn the box
/// correctly, and a formation in fractions of the canvas drifts off the
/// markings the moment the canvas changes shape.
const double _pitchHalfLength = 52.5;
const double _pitchWidth = 68;

/// FormationSpread is how far up the pitch a formation is drawn.
///
/// The same eleven positions mean two different pictures. A tactics board
/// showing a shape at kick-off wants the whole team inside its own half; one
/// showing the shape in possession wants the front players over the halfway
/// line, where they would actually be. Both are drawn from the same table --
/// the difference is only what the metres are divided by.
enum FormationSpread {
  /// attacking uses the real metres, so a 4-4-2's strikers stand about
  /// fifteen metres inside the opposition half. Positions run past 1.
  attacking("Attacking", "Forwards push into the other half"),

  /// ownHalf compresses the same shape to fit between the goal line and the
  /// halfway line, keeping the spacing between the lines proportional.
  ownHalf("Own half", "The whole team fits in its own half");

  final String label;
  final String description;
  const FormationSpread(this.label, this.description);

  static FormationSpread fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => FormationSpread.attacking,
      );
}

/// TeamFormation is a starting shape.
///
/// The positions are (metres up the pitch from the team's own goal line,
/// metres across from the near touchline), goalkeeper first. They are
/// converted to fractions of the element's own box when applied, so a team
/// element sized to its half of the pitch puts everybody on the right line.
enum TeamFormation {
  f442("4-4-2", TeamSport.football, [
    (5.5, 34),
    (20, 12), (18, 26), (18, 42), (20, 56),
    (42, 12), (38, 27), (38, 41), (42, 56),
    (62, 27), (62, 41),
  ]),
  f433("4-3-3", TeamSport.football, [
    (5.5, 34),
    (20, 12), (18, 26), (18, 42), (20, 56),
    (40, 20), (36, 34), (40, 48),
    (64, 14), (66, 34), (64, 54),
  ]),
  f4231("4-2-3-1", TeamSport.football, [
    (5.5, 34),
    (20, 12), (18, 26), (18, 42), (20, 56),
    (34, 26), (34, 42),
    (52, 13), (50, 34), (52, 55),
    (68, 34),
  ]),
  f352("3-5-2", TeamSport.football, [
    (5.5, 34),
    (18, 20), (16, 34), (18, 48),
    (40, 6), (36, 22), (34, 34), (36, 46), (40, 62),
    (62, 27), (62, 41),
  ]),
  f532("5-3-2", TeamSport.football, [
    (5.5, 34),
    (20, 8), (16, 21), (14, 34), (16, 47), (20, 60),
    (38, 22), (36, 34), (38, 46),
    (60, 27), (60, 41),
  ]),
  f4141("4-1-4-1", TeamSport.football, [
    (5.5, 34),
    (20, 12), (18, 26), (18, 42), (20, 56),
    (32, 34),
    (48, 12), (46, 27), (46, 41), (48, 56),
    (66, 34),
  ]),
  f4141Diamond("4-4-2 diamond", TeamSport.football, [
    (5.5, 34),
    (20, 12), (18, 26), (18, 42), (20, 56),
    (34, 34), (44, 18), (44, 50), (54, 34),
    (66, 27), (66, 41),
  ]),

  /// custom is what any formation becomes once a player has been moved. It
  /// holds no positions of its own -- choosing it changes nothing, which is
  /// the point: it is a label for "these are yours now", not an instruction.
  custom("Custom", TeamSport.football, []);

  final String label;
  final TeamSport sport;

  /// metres is (up the pitch, across it), goalkeeper first.
  final List<(double, double)> metres;

  const TeamFormation(this.label, this.sport, this.metres);

  static TeamFormation fromName(String? name) => values.firstWhere(
        (f) => f.name == name,
        orElse: () => TeamFormation.f442,
      );

  /// spots places this formation, as fractions of a team's own box.
  ///
  /// [mirrored] turns the team round to attack the other way, which is how the
  /// away side ends up facing the home side rather than both running at the
  /// same goal.
  ///
  /// Both axes flip, not just the one along the pitch. Turning a team round is
  /// a half turn, and flipping only the length leaves the right back on the
  /// left touchline -- a shape that is a 4-4-2 in outline and wrong in every
  /// detail anybody would notice.
  ///
  /// [spread] chooses the denominator, and nothing else. Two pictures of one
  /// shape; see [FormationSpread].
  List<(double, double)> spots({
    bool mirrored = false,
    FormationSpread spread = FormationSpread.attacking,
  }) {
    var along = spread == FormationSpread.ownHalf ? _deepest * 1.06 : _pitchHalfLength;
    return [
      for (var (up, across) in metres)
        mirrored
            ? (1 - up / along, 1 - across / _pitchWidth)
            : (up / along, across / _pitchWidth),
    ];
  }

  /// _deepest is how far up the pitch this formation's furthest player stands,
  /// which is what [FormationSpread.ownHalf] scales against. The 6% on top
  /// keeps that player off the halfway line rather than standing on it.
  double get _deepest =>
      metres.fold(0.0, (most, m) => m.$1 > most ? m.$1 : most);
}

/// defaultSquadNumbers is 1 for the keeper and 2..11 out, which is what a
/// blank team sheet has on it before anybody has been named.
const List<String> defaultSquadNumbers = [
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11",
];

/// PlayerSpot is one player: who they are, where they stand, and the two
/// switches every layer has.
///
/// Positions are fractions of the team element's box rather than canvas
/// coordinates, which is what makes the team a real transform: moving it moves
/// everybody, and resizing it spreads or compresses the shape without anybody
/// having to be dragged.
class PlayerSpot {
  final String number;
  final String name;

  /// dx and dy are 0..1 within the team's box. Not clamped -- a player pulled
  /// slightly outside the box is a player who has made a run, and snapping
  /// them back to the edge would be the tool arguing with the diagram.
  final double dx;
  final double dy;

  /// locked keeps a player where they are while the rest of the team is being
  /// arranged. hidden takes them off without losing their number and name.
  final bool locked;
  final bool hidden;

  /// track is this player's own animation, or null when they do not move.
  ///
  /// Per player, not per team, because that is the whole point of a tactics
  /// diagram: the ball goes wide, the full back overlaps, the winger comes
  /// inside and everybody else holds their line. A team-wide track can only
  /// move all eleven together, which is the one movement no move ever is.
  ///
  /// The same [ElementTrack] an element uses, so a player's keyframes ease,
  /// interpolate and export exactly as everything else does. Its dx and dy are
  /// in design units on top of the player's resting position, the same as an
  /// element's are on top of its own.
  final ElementTrack? track;

  const PlayerSpot({
    this.number = "",
    this.name = "",
    this.dx = 0.5,
    this.dy = 0.5,
    this.locked = false,
    this.hidden = false,
    this.track,
  });

  PlayerSpot copyWith({
    String? number,
    String? name,
    double? dx,
    double? dy,
    bool? locked,
    bool? hidden,
    ElementTrack? track,
    bool clearTrack = false,
  }) =>
      PlayerSpot(
        number: number ?? this.number,
        name: name ?? this.name,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        locked: locked ?? this.locked,
        hidden: hidden ?? this.hidden,
        track: clearTrack ? null : (track ?? this.track),
      );

  Map<String, dynamic> toJson() => {
        "n": number,
        if (name.isNotEmpty) "name": name,
        "dx": dx,
        "dy": dy,
        if (locked) "locked": true,
        if (hidden) "hidden": true,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
      };

  factory PlayerSpot.fromJson(Map<String, dynamic> json) {
    var track = json["track"];
    return PlayerSpot(
      number: jsonString(json["n"], ""),
      name: jsonString(json["name"], ""),
      dx: jsonDouble(json["dx"], 0.5),
      dy: jsonDouble(json["dy"], 0.5),
      locked: jsonBool(json["locked"], false),
      hidden: jsonBool(json["hidden"], false),
      track: track is Map<String, dynamic> ? ElementTrack.fromJson(track) : null,
    );
  }
}

/// LabelPosition is where a player's name sits relative to the dot.
///
/// Four sides plus off. It is one setting for the whole team: on a pitch of
/// twenty-two, per-player label sides were twenty-two controls to answer a
/// question almost nobody asks differently for one player than for the next.
enum LabelPosition {
  above("Above"),
  below("Below"),
  left("Left"),
  right("Right"),
  none("Hidden");

  final String label;
  const LabelPosition(this.label);

  static LabelPosition fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => LabelPosition.below,
      );
}

/// TeamElement is a team of numbered dots.
class TeamElement extends CanvasElement {
  final TeamSport sport;
  final TeamFormation formation;

  /// mirrored turns the team round. Kept as a field rather than baked into the
  /// positions so that changing formation on an away side stays mirrored
  /// instead of turning them round to attack their own goal.
  final bool mirrored;

  /// spread is how far up the pitch the formation is drawn. Kept for the same
  /// reason as [mirrored]: changing the shape must not quietly change which of
  /// the two pictures is being shown.
  final FormationSpread spread;

  /// players is the squad, goalkeeper first and then in the formation's own
  /// order. The list order is also the paint order, which is what Bring
  /// forward and Send to back move a player through.
  final List<PlayerSpot> players;

  /// keeperColor fills the first player; playerColor fills the rest. One
  /// exception rather than a per-player colour, because the keeper being in a
  /// different shirt is a rule of the game and everything else is a team kit.
  final Color keeperColor;
  final Color playerColor;

  /// outlineColor rings every dot, keeper included. A team of one colour on a
  /// green pitch needs the ring to read at all, and two teams in similar kits
  /// need it more.
  final Color outlineColor;

  final double dotWidth;
  final double dotHeight;

  /// lockDotAspect keeps the two above equal, which is on to begin with: a
  /// player marker is a circle, and an oval is almost always somebody having
  /// dragged one field without meaning to.
  final bool lockDotAspect;

  final double ringWidth;

  /// labelSpec is the type for the number *and* the name.
  ///
  /// One spec, deliberately. They were two, and every change to a team's
  /// lettering had to be made twice in two panels that looked identical -- and
  /// the two drifted, so a team's names ended up in a different face from its
  /// numbers without anybody having chosen that.
  final TextSpec labelSpec;

  final LabelPosition namePosition;

  /// nameGap is how far the name sits from the dot's edge, in design units, so
  /// it stays the same distance whatever the dot's size.
  final double nameGap;

  /// labelRotation turns the number and the name together, in degrees.
  final double labelRotation;

  final bool showNumbers;
  final bool showNames;

  const TeamElement(
    super.base, {
    this.sport = TeamSport.football,
    this.formation = TeamFormation.f442,
    this.mirrored = false,
    this.spread = FormationSpread.attacking,
    this.players = const [],
    this.keeperColor = const Color(0xFFF2C230),
    this.playerColor = const Color(0xFFE8362F),
    this.outlineColor = const Color(0xFFFFFFFF),
    this.dotWidth = 34,
    this.dotHeight = 34,
    this.lockDotAspect = true,
    this.ringWidth = 2.4,
    this.labelSpec = const TextSpec(fontSize: 15, weight: 700),
    this.namePosition = LabelPosition.below,
    this.nameGap = 5,
    this.labelRotation = 0,
    this.showNumbers = true,
    this.showNames = true,
  });

  @override
  ElementKind get kind => ElementKind.player;

  /// dotRadius is half the smaller side, so a team whose dots have been pulled
  /// out of square still draws circles rather than eggs.
  double get dotRadius => (dotWidth < dotHeight ? dotWidth : dotHeight) / 2;

  /// centreOf is where a player stands at rest, in document coordinates.
  Offset centreOf(PlayerSpot spot) =>
      Offset(x + spot.dx * width, y + spot.dy * height);

  /// centreAt is where a player is on [frame], which is their resting position
  /// plus whatever their own track says.
  ///
  /// The renderer, the hit test and the settings all ask this rather than
  /// working it out again, so a player being dragged, a player being drawn and
  /// a player being clicked can never disagree about where they are.
  Offset centreAt(PlayerSpot spot, int frame) {
    var rest = centreOf(spot);
    var track = spot.track;
    if (track == null || track.isEmpty) return rest;
    var pose = track.at(frame);
    return rest.translate(pose.dx, pose.dy);
  }

  /// withFormation lays the squad out in [next], keeping each player's number
  /// and name.
  ///
  /// Keeping them is the whole reason this is not "delete the team and make a
  /// new one": a manager trying 4-3-3 against 4-4-2 is moving the same eleven
  /// people, and losing their names on the way would make the comparison
  /// useless.
  TeamElement withFormation(TeamFormation next,
      {bool? mirror, FormationSpread? spread}) {
    var flip = mirror ?? mirrored;
    var how = spread ?? this.spread;
    if (next.metres.isEmpty) {
      return copyWith(formation: next, mirrored: flip, spread: how);
    }
    var spots = next.spots(mirrored: flip, spread: how);
    return copyWith(
      formation: next,
      mirrored: flip,
      spread: how,
      players: [
        for (var i = 0; i < spots.length; i++)
          (i < players.length ? players[i] : PlayerSpot(number: _defaultNumber(i)))
              .copyWith(dx: spots[i].$1, dy: spots[i].$2, locked: false),
      ],
    );
  }

  static String _defaultNumber(int i) =>
      i < defaultSquadNumbers.length ? defaultSquadNumbers[i] : "${i + 1}";

  /// withPlayer replaces one row.
  TeamElement withPlayer(int index, PlayerSpot spot) {
    if (index < 0 || index >= players.length) return this;
    var next = [...players]..[index] = spot;
    return copyWith(players: next);
  }

  /// movePlayer reorders one player, which is what Bring forward and Send to
  /// back do -- the list order is the paint order, so a player moved to the
  /// end is drawn over everybody they overlap.
  TeamElement movePlayer(int from, int to) {
    if (from < 0 || from >= players.length) return this;
    var clamped = to.clamp(0, players.length - 1);
    if (clamped == from) return this;
    var next = [...players];
    next.insert(clamped, next.removeAt(from));
    return copyWith(players: next);
  }

  @override
  CanvasElement rebase(ElementBase base) => TeamElement(base,
      sport: sport,
      formation: formation,
      mirrored: mirrored,
      spread: spread,
      players: players,
      keeperColor: keeperColor,
      playerColor: playerColor,
      outlineColor: outlineColor,
      dotWidth: dotWidth,
      dotHeight: dotHeight,
      lockDotAspect: lockDotAspect,
      ringWidth: ringWidth,
      labelSpec: labelSpec,
      namePosition: namePosition,
      nameGap: nameGap,
      labelRotation: labelRotation,
      showNumbers: showNumbers,
      showNames: showNames);

  TeamElement copyWith({
    TeamSport? sport,
    TeamFormation? formation,
    bool? mirrored,
    FormationSpread? spread,
    List<PlayerSpot>? players,
    Color? keeperColor,
    Color? playerColor,
    Color? outlineColor,
    double? dotWidth,
    double? dotHeight,
    bool? lockDotAspect,
    double? ringWidth,
    TextSpec? labelSpec,
    LabelPosition? namePosition,
    double? nameGap,
    double? labelRotation,
    bool? showNumbers,
    bool? showNames,
  }) =>
      TeamElement(base,
          sport: sport ?? this.sport,
          formation: formation ?? this.formation,
          mirrored: mirrored ?? this.mirrored,
          spread: spread ?? this.spread,
          players: players ?? this.players,
          keeperColor: keeperColor ?? this.keeperColor,
          playerColor: playerColor ?? this.playerColor,
          outlineColor: outlineColor ?? this.outlineColor,
          dotWidth: dotWidth ?? this.dotWidth,
          dotHeight: dotHeight ?? this.dotHeight,
          lockDotAspect: lockDotAspect ?? this.lockDotAspect,
          ringWidth: ringWidth ?? this.ringWidth,
          labelSpec: labelSpec ?? this.labelSpec,
          namePosition: namePosition ?? this.namePosition,
          nameGap: nameGap ?? this.nameGap,
          labelRotation: labelRotation ?? this.labelRotation,
          showNumbers: showNumbers ?? this.showNumbers,
          showNames: showNames ?? this.showNames);

  @override
  Map<String, dynamic> props() => {
        "sport": sport.name,
        "formation": formation.name,
        if (mirrored) "mirrored": true,
        "spread": spread.name,
        "players": [for (var p in players) p.toJson()],
        "keeper": colorToJson(keeperColor),
        "player": colorToJson(playerColor),
        "outline": colorToJson(outlineColor),
        "dotW": dotWidth,
        "dotH": dotHeight,
        if (!lockDotAspect) "lockDot": false,
        "ring": ringWidth,
        "labelSpec": labelSpec.toJson(),
        "namePos": namePosition.name,
        "nameGap": nameGap,
        if (labelRotation != 0) "labelRot": labelRotation,
        if (!showNumbers) "showNumbers": false,
        if (!showNames) "showNames": false,
      };

  factory TeamElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["players"];
    return TeamElement(b,
        sport: TeamSport.fromName(json["sport"] as String?),
        formation: TeamFormation.fromName(json["formation"] as String?),
        mirrored: jsonBool(json["mirrored"], false),
        spread: FormationSpread.fromName(json["spread"] as String?),
        players: [
          if (raw is List)
            for (var p in raw)
              if (p is Map<String, dynamic>) PlayerSpot.fromJson(p),
        ],
        keeperColor: colorFromJson(json["keeper"], const Color(0xFFF2C230)),
        playerColor: colorFromJson(json["player"], const Color(0xFFE8362F)),
        outlineColor: colorFromJson(json["outline"]),
        dotWidth: jsonDouble(json["dotW"], 34),
        dotHeight: jsonDouble(json["dotH"], 34),
        lockDotAspect: jsonBool(json["lockDot"], true),
        ringWidth: jsonDouble(json["ring"], 2.4),
        labelSpec: jsonSpec(json["labelSpec"], TextSpec.fromJson,
            const TextSpec(fontSize: 15, weight: 700)),
        namePosition: LabelPosition.fromName(json["namePos"] as String?),
        nameGap: jsonDouble(json["nameGap"], 5),
        labelRotation: jsonDouble(json["labelRot"], 0),
        showNumbers: jsonBool(json["showNumbers"], true),
        showNames: jsonBool(json["showNames"], true));
  }
}
