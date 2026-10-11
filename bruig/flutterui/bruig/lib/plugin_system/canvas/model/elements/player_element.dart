import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
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
/// It decides the squad size, which formations are on offer, whether the
/// first player is a goalkeeper in a different shirt, and the size of the
/// half a formation is laid out in -- in metres, from the sport's own laws,
/// like the pitches. The names are what documents saved.
enum TeamSport {
  football("Football", 11, true, 52.5, 68),
  futsal("Futsal", 5, true, 20, 20),
  basketball("Basketball", 5, false, 14, 15),
  tennis("Tennis doubles", 2, false, 11.885, 10.97),
  hockey("Field hockey", 11, true, 45.7, 55),
  iceHockey("Ice hockey", 6, true, 30.48, 25.91),
  rugbyUnion("Rugby union", 15, false, 50, 70),
  rugbyLeague("Rugby league", 13, false, 50, 68),
  americanFootball("American football", 11, false, 54.864, 48.768);

  final String label;

  /// squadSize includes the goalkeeper, where there is one, who is always
  /// the first player.
  final int squadSize;

  /// hasKeeper is whether the first player is a goalkeeper, drawn in the
  /// keeper's colour.
  final bool hasKeeper;

  /// halfLength and width are the half a team lines up in, in metres: from
  /// its own goal line, end line or baseline to halfway, and across.
  final double halfLength;
  final double width;

  const TeamSport(
      this.label, this.squadSize, this.hasKeeper, this.halfLength, this.width);

  static TeamSport fromName(String? name) => values
      .firstWhere((s) => s.name == name, orElse: () => TeamSport.football);

  /// tokenMetres is how big a player's token is drawn on a pitch of this
  /// sport, in metres: big enough to read, small enough not to cover the
  /// markings round it.
  double get tokenMetres => switch (this) {
        football || rugbyUnion || rugbyLeague => 3.2,
        hockey => 2.8,
        americanFootball => 2.4,
        futsal => 1.5,
        iceHockey => 1.7,
        basketball => 1.0,
        tennis => 0.9,
      };

  /// ballSize is the ball against a player's token: drawn larger than life,
  /// as a diagram's ball always is, or it is a speck nobody can find.
  double get ballSize => switch (this) {
        tennis => 0.4,
        hockey => 0.36,
        iceHockey => 0.42,
        basketball => 0.58,
        rugbyUnion || rugbyLeague || americanFootball => 0.6,
        football || futsal => 0.52,
      };

  /// forPitch is the team sport played on [pitch].
  static TeamSport forPitch(PitchSport pitch) => switch (pitch) {
        PitchSport.football || PitchSport.blank => football,
        PitchSport.futsal => futsal,
        PitchSport.basketball || PitchSport.basketballNba => basketball,
        PitchSport.tennis => tennis,
        PitchSport.hockey => hockey,
        PitchSport.iceHockey => iceHockey,
        PitchSport.rugby => rugbyUnion,
        PitchSport.rugbyLeague => rugbyLeague,
        PitchSport.americanFootball => americanFootball,
      };

  List<TeamFormation> get formations => [
        ...TeamFormation.values
            .where((f) => f.sport == this && f != TeamFormation.custom),
        TeamFormation.custom,
      ];
}

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

const _f442Roles = [
  "GK",
  "RB",
  "CB",
  "CB",
  "LB",
  "RM",
  "CM",
  "CM",
  "LM",
  "ST",
  "ST"
];

/// TeamFormation is a starting shape.
///
/// The positions are (metres up the pitch from the team's own goal line,
/// metres across from the near touchline), goalkeeper first. They are
/// converted to fractions of the element's own box when applied, so a team
/// element sized to its half of the pitch puts everybody on the right line.
enum TeamFormation {
  f442("4-4-2", TeamSport.football, roles: _f442Roles, [
    (5.5, 34),
    (20, 12),
    (18, 26),
    (18, 42),
    (20, 56),
    (42, 12),
    (38, 27),
    (38, 41),
    (42, 56),
    (62, 27),
    (62, 41),
  ]),
  f433("4-3-3", TeamSport.football, roles: [
    "GK",
    "RB",
    "CB",
    "CB",
    "LB",
    "CM",
    "DM",
    "CM",
    "RW",
    "ST",
    "LW"
  ], [
    (5.5, 34),
    (20, 12),
    (18, 26),
    (18, 42),
    (20, 56),
    (40, 20),
    (36, 34),
    (40, 48),
    (64, 14),
    (66, 34),
    (64, 54),
  ]),
  f4231("4-2-3-1", TeamSport.football, roles: [
    "GK",
    "RB",
    "CB",
    "CB",
    "LB",
    "DM",
    "DM",
    "RW",
    "AM",
    "LW",
    "ST"
  ], [
    (5.5, 34),
    (20, 12),
    (18, 26),
    (18, 42),
    (20, 56),
    (34, 26),
    (34, 42),
    (52, 13),
    (50, 34),
    (52, 55),
    (68, 34),
  ]),
  f352("3-5-2", TeamSport.football, roles: [
    "GK",
    "CB",
    "CB",
    "CB",
    "RWB",
    "CM",
    "DM",
    "CM",
    "LWB",
    "ST",
    "ST"
  ], [
    (5.5, 34),
    (18, 20),
    (16, 34),
    (18, 48),
    (40, 6),
    (36, 22),
    (34, 34),
    (36, 46),
    (40, 62),
    (62, 27),
    (62, 41),
  ]),
  f532("5-3-2", TeamSport.football, roles: [
    "GK",
    "RWB",
    "CB",
    "CB",
    "CB",
    "LWB",
    "CM",
    "CM",
    "CM",
    "ST",
    "ST"
  ], [
    (5.5, 34),
    (20, 8),
    (16, 21),
    (14, 34),
    (16, 47),
    (20, 60),
    (38, 22),
    (36, 34),
    (38, 46),
    (60, 27),
    (60, 41),
  ]),
  f4141("4-1-4-1", TeamSport.football, roles: [
    "GK",
    "RB",
    "CB",
    "CB",
    "LB",
    "DM",
    "RM",
    "CM",
    "CM",
    "LM",
    "ST"
  ], [
    (5.5, 34),
    (20, 12),
    (18, 26),
    (18, 42),
    (20, 56),
    (32, 34),
    (48, 12),
    (46, 27),
    (46, 41),
    (48, 56),
    (66, 34),
  ]),
  f4141Diamond("4-4-2 diamond", TeamSport.football, roles: [
    "GK",
    "RB",
    "CB",
    "CB",
    "LB",
    "DM",
    "RM",
    "LM",
    "AM",
    "ST",
    "ST"
  ], [
    (5.5, 34),
    (20, 12),
    (18, 26),
    (18, 42),
    (20, 56),
    (34, 34),
    (44, 18),
    (44, 50),
    (54, 34),
    (66, 27),
    (66, 41),
  ]),

  // Futsal: a 40 by 20 metre court, five a side.
  futsalDiamond("1-2-1 diamond", TeamSport.futsal, [
    (1, 10),
    (6, 10),
    (11, 4),
    (11, 16),
    (17, 10),
  ], roles: [
    "GK",
    "Fixo",
    "Ala",
    "Ala",
    "Pivot"
  ]),
  futsal22("2-2", TeamSport.futsal, [
    (1, 10),
    (7, 6),
    (7, 14),
    (15, 6),
    (15, 14),
  ], roles: [
    "GK",
    "Def",
    "Def",
    "Ala",
    "Ala"
  ]),
  futsal31("3-1", TeamSport.futsal, [
    (1, 10),
    (8, 4),
    (6, 10),
    (8, 16),
    (16, 10),
  ], roles: [
    "GK",
    "Ala",
    "Fixo",
    "Ala",
    "Pivot"
  ]),
  futsal40("4-0", TeamSport.futsal, [
    (1, 10),
    (12, 3),
    (12, 8),
    (12, 12),
    (12, 17),
  ], roles: [
    "GK",
    "Ala",
    "Def",
    "Def",
    "Ala"
  ]),

  // Basketball: offence is set up in the half being attacked, so its
  // metres run past halfway; a zone defends the team's own basket.
  basketball122("1-2-2 offence", TeamSport.basketball, [
    (18.5, 7.5),
    (21, 2.5),
    (21, 12.5),
    (25.5, 4),
    (25.5, 11),
  ], roles: [
    "PG",
    "SG",
    "SF",
    "PF",
    "C"
  ]),
  basketball131("1-3-1 offence", TeamSport.basketball, [
    (18.5, 7.5),
    (22, 1.5),
    (22.5, 7.5),
    (22, 13.5),
    (26.5, 7.5),
  ], roles: [
    "PG",
    "SG",
    "PF",
    "SF",
    "C"
  ]),
  basketballHorns("Horns", TeamSport.basketball, [
    (18.5, 7.5),
    (27, 1),
    (27, 14),
    (22.2, 5),
    (22.2, 10),
  ], roles: [
    "PG",
    "SG",
    "SF",
    "PF",
    "C"
  ]),
  basketballZone23("2-3 zone", TeamSport.basketball, [
    (5, 5),
    (5, 10),
    (1.8, 2.5),
    (1.5, 7.5),
    (1.8, 12.5),
  ], roles: [
    "PG",
    "SG",
    "SF",
    "C",
    "PF"
  ]),

  // Tennis doubles, on the team's own half of the court.
  tennisUpBack("Up and back", TeamSport.tennis, [
    (-0.5, 2.7),
    (8.5, 8.2),
  ], roles: [
    "Server",
    "Net"
  ]),
  tennisBack("Both back", TeamSport.tennis, [
    (-0.5, 2.7),
    (-0.5, 8.2),
  ], roles: [
    "Deuce",
    "Ad"
  ]),
  tennisNet("Both at net", TeamSport.tennis, [
    (8.5, 2.7),
    (8.5, 8.2),
  ], roles: [
    "Deuce",
    "Ad"
  ]),

  // Field hockey: a 91.4 by 55 metre pitch.
  hockey433("4-3-3", TeamSport.hockey, [
    (2, 27.5),
    (16, 8),
    (13, 21),
    (13, 34),
    (16, 47),
    (30, 14),
    (28, 27.5),
    (30, 41),
    (43, 10),
    (45, 27.5),
    (43, 45),
  ], roles: [
    "GK",
    "RB",
    "CB",
    "CB",
    "LB",
    "RM",
    "CM",
    "LM",
    "RF",
    "CF",
    "LF"
  ]),
  hockey343("3-4-3", TeamSport.hockey, [
    (2, 27.5),
    (14, 14),
    (12, 27.5),
    (14, 41),
    (28, 6),
    (27, 20),
    (27, 35),
    (28, 49),
    (43, 12),
    (45, 27.5),
    (43, 43),
  ], roles: [
    "GK",
    "RB",
    "CB",
    "LB",
    "RM",
    "CM",
    "CM",
    "LM",
    "RF",
    "CF",
    "LF"
  ]),

  // Ice hockey: three forwards, two defence and the goalie.
  iceFaceoff("Centre faceoff", TeamSport.iceHockey, [
    (4.5, 12.95),
    (24, 8.5),
    (24, 17.4),
    (29.6, 6.2),
    (30, 12.95),
    (29.6, 19.7),
  ], roles: [
    "G",
    "LD",
    "RD",
    "LW",
    "C",
    "RW"
  ], numbers: [
    "30",
    "4",
    "44",
    "17",
    "19",
    "88"
  ]),
  iceDefence("Defensive zone", TeamSport.iceHockey, [
    (4.2, 12.95),
    (6.5, 9),
    (6.5, 17),
    (9.5, 12.95),
    (14, 5),
    (14, 21),
  ], roles: [
    "G",
    "LD",
    "RD",
    "C",
    "LW",
    "RW"
  ], numbers: [
    "30",
    "4",
    "44",
    "19",
    "17",
    "88"
  ]),

  // Rugby union: fifteen, numbered by position.
  unionReceive("Kick-off receive", TeamSport.rugbyUnion, [
    (40, 30),
    (40, 35),
    (40, 40),
    (37, 32),
    (37, 38),
    (38, 24),
    (38, 46),
    (35, 35),
    (31, 28),
    (26, 22),
    (14, 6),
    (24, 16),
    (21, 10),
    (14, 64),
    (6, 35),
  ], roles: [
    "Loosehead",
    "Hooker",
    "Tighthead",
    "Lock",
    "Lock",
    "Flanker",
    "Flanker",
    "No. 8",
    "Scrum-half",
    "Fly-half",
    "Wing",
    "Centre",
    "Centre",
    "Wing",
    "Full-back"
  ]),
  unionScrum("Attacking scrum", TeamSport.rugbyUnion, [
    (48, 31.5),
    (48, 35),
    (48, 38.5),
    (46.3, 33.2),
    (46.3, 36.8),
    (46.5, 30),
    (46.5, 40),
    (44.6, 35),
    (48.5, 28),
    (41, 24),
    (35, 4),
    (39, 17),
    (37, 10),
    (35, 66),
    (25, 35),
  ], roles: [
    "Loosehead",
    "Hooker",
    "Tighthead",
    "Lock",
    "Lock",
    "Flanker",
    "Flanker",
    "No. 8",
    "Scrum-half",
    "Fly-half",
    "Wing",
    "Centre",
    "Centre",
    "Wing",
    "Full-back"
  ]),

  // Rugby league: thirteen.
  leagueStandard("Standard", TeamSport.rugbyLeague, [
    (10, 34),
    (30, 4),
    (28, 14),
    (28, 54),
    (30, 64),
    (32, 26),
    (34, 40),
    (45, 30),
    (44, 34),
    (45, 38),
    (42, 22),
    (42, 46),
    (40, 34),
  ], roles: [
    "Full-back",
    "Wing",
    "Centre",
    "Centre",
    "Wing",
    "Stand-off",
    "Half-back",
    "Prop",
    "Hooker",
    "Prop",
    "Second row",
    "Second row",
    "Loose forward"
  ]),

  // American football: the line of scrimmage at midfield, each side
  // measured from its own end line.
  nflI("I formation", TeamSport.americanFootball, [
    (53.9, 24.38),
    (53.9, 23.3),
    (53.9, 25.46),
    (53.9, 22.2),
    (53.9, 26.56),
    (53.9, 27.7),
    (53.9, 6),
    (53.4, 42.8),
    (52.9, 24.38),
    (50.3, 24.38),
    (48.0, 24.38),
  ], roles: [
    "C",
    "LG",
    "RG",
    "LT",
    "RT",
    "TE",
    "WR",
    "WR",
    "QB",
    "FB",
    "RB"
  ], numbers: [
    "55",
    "66",
    "77",
    "71",
    "76",
    "87",
    "11",
    "81",
    "12",
    "44",
    "28"
  ]),
  nflShotgun("Shotgun", TeamSport.americanFootball, [
    (53.9, 24.38),
    (53.9, 23.3),
    (53.9, 25.46),
    (53.9, 22.2),
    (53.9, 26.56),
    (53.9, 5),
    (53.4, 10),
    (53.4, 38.7),
    (49.4, 24.38),
    (49.4, 22.6),
    (53.9, 43.8),
  ], roles: [
    "C",
    "LG",
    "RG",
    "LT",
    "RT",
    "WR",
    "WR",
    "WR",
    "QB",
    "RB",
    "WR"
  ], numbers: [
    "55",
    "66",
    "77",
    "71",
    "76",
    "11",
    "13",
    "81",
    "12",
    "28",
    "84"
  ]),
  nfl43("4-3 defence", TeamSport.americanFootball, [
    (53.9, 21.3),
    (53.9, 23.3),
    (53.9, 25.46),
    (53.9, 27.5),
    (49.8, 19.8),
    (49.3, 24.38),
    (49.8, 29),
    (53, 6),
    (53, 42.8),
    (43.5, 16),
    (43.5, 32.8),
  ], roles: [
    "DE",
    "DT",
    "DT",
    "DE",
    "OLB",
    "MLB",
    "OLB",
    "CB",
    "CB",
    "FS",
    "SS"
  ], numbers: [
    "91",
    "93",
    "97",
    "99",
    "52",
    "54",
    "56",
    "24",
    "21",
    "29",
    "31"
  ]),
  nfl34("3-4 defence", TeamSport.americanFootball, [
    (53.9, 22.4),
    (53.9, 24.38),
    (53.9, 26.4),
    (53.4, 18.8),
    (49.8, 21.8),
    (49.8, 27),
    (53.4, 30),
    (53, 6),
    (53, 42.8),
    (43.5, 16),
    (43.5, 32.8),
  ], roles: [
    "DE",
    "NT",
    "DE",
    "OLB",
    "ILB",
    "ILB",
    "OLB",
    "CB",
    "CB",
    "FS",
    "SS"
  ], numbers: [
    "94",
    "92",
    "98",
    "55",
    "50",
    "54",
    "58",
    "24",
    "21",
    "29",
    "31"
  ]),

  /// custom is what any formation becomes once a player has been moved. It
  /// holds no positions of its own -- choosing it changes nothing, which is
  /// the point: it is a label for "these are yours now", not an instruction.
  custom("Custom", TeamSport.football, []);

  final String label;
  final TeamSport sport;

  /// metres is (up the pitch, across it), goalkeeper first.
  final List<(double, double)> metres;

  /// roles names each position, for naming a squad by where they play.
  /// Empty where the sport's own names are not worth more than a number.
  final List<String> roles;

  /// numbers are the shirt numbers that go with the positions, where the
  /// sport numbers by position or a blank sheet would look wrong with 1 to
  /// 11. Empty for one to however many.
  final List<String> numbers;

  const TeamFormation(this.label, this.sport, this.metres,
      {this.roles = const [], this.numbers = const []});

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
    var along =
        spread == FormationSpread.ownHalf ? _deepest * 1.06 : sport.halfLength;
    var wide = sport.width;
    return [
      for (var (up, across) in metres)
        mirrored
            ? (1 - up / along, 1 - across / wide)
            : (up / along, across / wide),
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
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "10",
  "11",
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

  /// photo is a picture of the player, by asset, shown in the token where
  /// the team shows faces; empty for a drawn face.
  final String photo;

  /// captain wears the armband; highlight picks the player out with a glow,
  /// for the one a diagram is about.
  final bool captain;
  final bool highlight;

  /// ball makes this the ball rather than a player: the same in every way a
  /// player can be moved -- dragged, keyframed, sent along a path -- and left
  /// out of formations, numbering and names. Kept last in the list, so it is
  /// drawn over the players and the keeper is still the first of them.
  final bool ball;

  const PlayerSpot({
    this.number = "",
    this.name = "",
    this.dx = 0.5,
    this.dy = 0.5,
    this.locked = false,
    this.hidden = false,
    this.track,
    this.photo = "",
    this.captain = false,
    this.highlight = false,
    this.ball = false,
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
    String? photo,
    bool? captain,
    bool? highlight,
    bool? ball,
  }) =>
      PlayerSpot(
        number: number ?? this.number,
        name: name ?? this.name,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        locked: locked ?? this.locked,
        hidden: hidden ?? this.hidden,
        track: clearTrack ? null : (track ?? this.track),
        photo: photo ?? this.photo,
        captain: captain ?? this.captain,
        highlight: highlight ?? this.highlight,
        ball: ball ?? this.ball,
      );

  Map<String, dynamic> toJson() => {
        "n": number,
        if (name.isNotEmpty) "name": name,
        "dx": dx,
        "dy": dy,
        if (locked) "locked": true,
        if (hidden) "hidden": true,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
        if (photo.isNotEmpty) "photo": photo,
        if (captain) "captain": true,
        if (highlight) "highlight": true,
        if (ball) "ball": true,
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
      track:
          track is Map<String, dynamic> ? ElementTrack.fromJson(track) : null,
      photo: jsonString(json["photo"], ""),
      captain: jsonBool(json["captain"], false),
      highlight: jsonBool(json["highlight"], false),
      ball: jsonBool(json["ball"], false),
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

/// TokenStyle is what a player is drawn as.
enum TokenStyle {
  dot("Dot"),
  shirt("Shirt"),
  portrait("Portrait");

  final String label;
  const TokenStyle(this.label);

  static TokenStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => TokenStyle.dot);
}

/// KitPattern is how a team's two kit colours are laid out on a shirt.
enum KitPattern {
  plain("Plain"),
  stripes("Stripes"),
  hoops("Hoops"),
  halves("Halves"),
  sash("Sash"),
  quarters("Quarters");

  final String label;
  const KitPattern(this.label);

  static KitPattern fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => KitPattern.plain);
}

/// NameStyle is how a player's name is set.
enum NameStyle {
  plain("Plain"),
  plate("Plate");

  final String label;
  const NameStyle(this.label);

  static NameStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => NameStyle.plain);
}

/// teamLinkBackground is [TeamElement.link] for a team standing on the
/// canvas's own background.
const String teamLinkBackground = "background";

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

  /// frameLocked pins the team's own box while leaving the players free.
  ///
  /// Separate from the layer lock, which stops everything. A pitch is set up
  /// once and then worked on for an hour, and in that hour every drag is a
  /// player -- but a drag that starts a few pixels off a dot takes hold of the
  /// team instead and slides all eleven, which is both easy to do and easy not
  /// to notice until the shape is wrong. Locking the frame makes that
  /// impossible without giving up the ability to move anybody.
  final bool frameLocked;

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

  /// link is the pitch the team stands on: [teamLinkBackground] for the
  /// canvas's own background, a background element's id, or empty for none.
  ///
  /// Linked, the players are kept in the pitch's own metres -- the team's
  /// half of it -- and drawn wherever the pitch puts them, so moving,
  /// turning, zooming or tilting the pitch carries the team with it. The
  /// team's own box then means nothing and is not dragged.
  final String link;

  /// secondaryColor is the kit's second colour, and kitPattern how the two
  /// are laid out.
  final Color secondaryColor;
  final KitPattern kitPattern;

  final TokenStyle tokenStyle;

  /// faces draws a face for every player in a portrait who has no photo.
  final bool faces;

  /// shadow puts a soft shadow under every player.
  final bool shadow;

  final NameStyle nameStyle;

  /// showRuns draws where each player with keyframes goes, as a dashed line
  /// to an arrow.
  final bool showRuns;

  const TeamElement(
    super.base, {
    this.sport = TeamSport.football,
    this.formation = TeamFormation.f442,
    this.mirrored = false,
    this.spread = FormationSpread.attacking,
    this.frameLocked = false,
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
    this.link = "",
    this.secondaryColor = const Color(0xFFFFFFFF),
    this.kitPattern = KitPattern.plain,
    this.tokenStyle = TokenStyle.dot,
    this.faces = true,
    this.shadow = false,
    this.nameStyle = NameStyle.plain,
    this.showRuns = false,
  });

  /// linked is whether the team stands on a pitch.
  bool get linked => link.isNotEmpty;

  /// frameFixed is whether the team's own box stays where it is: pinned, or
  /// not the team's to move because it stands on a pitch.
  bool get frameFixed => frameLocked || linked;

  @override
  ElementKind get kind => ElementKind.player;

  /// radiusOf is how big [spot]'s token is: the ball smaller than a player.
  double radiusOf(PlayerSpot spot) =>
      spot.ball ? dotRadius * sport.ballSize : dotRadius;

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
      {bool? mirror, FormationSpread? spread, bool fresh = false}) {
    var flip = mirror ?? mirrored;
    var how = spread ?? this.spread;
    if (next.metres.isEmpty) {
      return copyWith(formation: next, mirrored: flip, spread: how);
    }
    var spots = next.spots(mirrored: flip, spread: how);
    // The ball is not in the formation: it keeps its place, and its place at
    // the end of the list.
    var people = [
      for (var p in players)
        if (!p.ball) p
    ];
    return copyWith(
      formation: next,
      mirrored: flip,
      spread: how,
      players: [
        for (var i = 0; i < spots.length; i++)
          (i < people.length && !fresh
                  ? people[i]
                  : PlayerSpot(number: _defaultNumber(next, i)))
              .copyWith(dx: spots[i].$1, dy: spots[i].$2, locked: false),
        ...players.where((p) => p.ball),
      ],
    );
  }

  /// ball is the team's ball, or null where it has none.
  PlayerSpot? get ball => players.where((p) => p.ball).firstOrNull;

  /// withBall is the team with a ball -- on the centre spot, which is the
  /// edge of the team's own half nearest the other -- or without one.
  TeamElement withBall(bool on) {
    var without = [
      for (var p in players)
        if (!p.ball) p
    ];
    if (!on) return copyWith(players: without);
    if (ball != null) return this;
    return copyWith(players: [
      ...without,
      PlayerSpot(name: "Ball", dx: mirrored ? 0 : 1, dy: 0.5, ball: true),
    ]);
  }

  /// withSport is the team set up for [next]: its first formation, with
  /// the squad numbered afresh -- a rugby fifteen is not a football eleven
  /// with four more.
  ///
  /// A team turned round to attack the other way starts in the sport's
  /// defensive shape where it has one -- a zone, a defence -- so two sides
  /// set up for the same game face each other rather than both attacking.
  TeamElement withSport(TeamSport next) {
    var forms = next.formations;
    var start = mirrored
        ? forms.firstWhere(
            (f) =>
                f.label.toLowerCase().contains("defen") ||
                f.label.toLowerCase().contains("zone"),
            orElse: () => forms.first)
        : forms.first;
    return copyWith(sport: next).withFormation(start, fresh: true);
  }

  /// linkedTo is the team standing on a pitch of [pitch]: linked by
  /// [link], set up for the sport played on it if it was set up for another,
  /// and its tokens sized for it -- [reference] being how many pixels a
  /// metre is on that pitch drawn flat.
  TeamElement linkedTo(String link,
      {required PitchSport pitch, required double reference, Rect? area}) {
    var game = TeamSport.forPitch(pitch);
    var team = sport == game ? this : withSport(game);
    var dot = game.tokenMetres * reference;
    // Its box is the pitch's, with no turn of its own: nothing draws by it
    // any more, but whatever asks where the team is -- an export laying the
    // page out element by element -- asks it.
    if (area != null) {
      team = team.withBase(
          x: area.left,
          y: area.top,
          width: area.width,
          height: area.height,
          rotation: 0) as TeamElement;
    }
    return team.copyWith(
      link: link,
      dotWidth: dot,
      dotHeight: dot,
      ringWidth: dot * 0.07,
      nameGap: dot * 0.18,
      labelSpec:
          labelSpec.copyWith(fontSize: dot * 0.46, outlineWidth: dot * 0.035),
    );
  }

  /// namedByPosition is the squad named after the positions they play in
  /// the formation, where it names them.
  TeamElement namedByPosition() {
    var roles = formation.roles;
    if (roles.isEmpty) return this;
    return copyWith(players: [
      for (var (i, p) in players.indexed)
        i < roles.length && !p.ball ? p.copyWith(name: roles[i]) : p,
    ]);
  }

  static String _defaultNumber(TeamFormation f, int i) =>
      i < f.numbers.length ? f.numbers[i] : "${i + 1}";

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
      frameLocked: frameLocked,
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
      showNames: showNames,
      link: link,
      secondaryColor: secondaryColor,
      kitPattern: kitPattern,
      tokenStyle: tokenStyle,
      faces: faces,
      shadow: shadow,
      nameStyle: nameStyle,
      showRuns: showRuns);

  TeamElement copyWith({
    TeamSport? sport,
    TeamFormation? formation,
    bool? mirrored,
    FormationSpread? spread,
    bool? frameLocked,
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
    String? link,
    Color? secondaryColor,
    KitPattern? kitPattern,
    TokenStyle? tokenStyle,
    bool? faces,
    bool? shadow,
    NameStyle? nameStyle,
    bool? showRuns,
  }) =>
      TeamElement(base,
          sport: sport ?? this.sport,
          formation: formation ?? this.formation,
          mirrored: mirrored ?? this.mirrored,
          spread: spread ?? this.spread,
          frameLocked: frameLocked ?? this.frameLocked,
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
          showNames: showNames ?? this.showNames,
          link: link ?? this.link,
          secondaryColor: secondaryColor ?? this.secondaryColor,
          kitPattern: kitPattern ?? this.kitPattern,
          tokenStyle: tokenStyle ?? this.tokenStyle,
          faces: faces ?? this.faces,
          shadow: shadow ?? this.shadow,
          nameStyle: nameStyle ?? this.nameStyle,
          showRuns: showRuns ?? this.showRuns);

  @override
  Map<String, dynamic> props() => {
        "sport": sport.name,
        "formation": formation.name,
        if (mirrored) "mirrored": true,
        "spread": spread.name,
        if (frameLocked) "frameLocked": true,
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
        if (link.isNotEmpty) "link": link,
        "secondary": colorToJson(secondaryColor),
        if (kitPattern != KitPattern.plain) "kit": kitPattern.name,
        if (tokenStyle != TokenStyle.dot) "token": tokenStyle.name,
        if (!faces) "faces": false,
        if (shadow) "shadow": true,
        if (nameStyle != NameStyle.plain) "nameStyle": nameStyle.name,
        if (showRuns) "runs": true,
      };

  factory TeamElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["players"];
    return TeamElement(b,
        sport: TeamSport.fromName(json["sport"] as String?),
        formation: TeamFormation.fromName(json["formation"] as String?),
        mirrored: jsonBool(json["mirrored"], false),
        spread: FormationSpread.fromName(json["spread"] as String?),
        frameLocked: jsonBool(json["frameLocked"], false),
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
        showNames: jsonBool(json["showNames"], true),
        link: jsonString(json["link"], ""),
        secondaryColor:
            colorFromJson(json["secondary"], const Color(0xFFFFFFFF)),
        kitPattern: KitPattern.fromName(json["kit"] as String?),
        tokenStyle: TokenStyle.fromName(json["token"] as String?),
        faces: jsonBool(json["faces"], true),
        shadow: jsonBool(json["shadow"], false),
        nameStyle: NameStyle.fromName(json["nameStyle"] as String?),
        showRuns: jsonBool(json["runs"], false));
  }
}
