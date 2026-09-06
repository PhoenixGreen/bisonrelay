import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// team settings.dart is a team's settings.

/// teamSettings is a whole team's controls.
///
/// Ordered the way a team is actually set up: which game, what shape, who is
/// in it, what colour they are, and how big the dots are. The squad list is
/// behind an expander because eleven rows of four fields is more than every
/// other element's settings put together, and somebody opening a team is
/// usually there for the formation or the kit.
List<Widget> teamSettings(TeamElement e, SettingsWrite write,
    VoidCallback begin, VoidCallback commit) {
  /// now is a change made in one go -- a dropdown, a colour, a switch -- which
  /// is its own undo step.
  void now(TeamElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    // No caption: the panel header says "Team settings" already, and a
    // group called Team directly under it was the word twice.
    CanvasControlGroup(label: "Team", hideCaption: true, children: [
      CanvasDropdown<TeamSport>(
        label: "Sport",
        value: e.sport,
        width: 104,
        options: [for (var s in TeamSport.values) (s, s.label)],
        // Changing the sport re-lays the squad out, since a formation belongs
        // to one game and the squad size changes with it.
        onChanged: (v) =>
            now(e.copyWith(sport: v).withFormation(v.formations.first)),
      ),
      CanvasDropdown<TeamFormation>(
        label: "Formation",
        value: e.sport.formations.contains(e.formation)
            ? e.formation
            : e.sport.formations.first,
        width: 118,
        options: [for (var f in e.sport.formations) (f, f.label)],
        onChanged: (v) => now(e.withFormation(v)),
      ),
      CanvasDropdown<FormationSpread>(
        label: "Spread",
        value: e.spread,
        width: 108,
        options: [for (var v in FormationSpread.values) (v, v.label)],
        // The same eleven positions, two pictures: the shape at kick-off sits
        // inside its own half, the shape in possession has its forwards over
        // the halfway line. See FormationSpread.
        onChanged: (v) => now(e.withFormation(e.formation, spread: v)),
      ),
      CanvasToggle(
        label: "Attack left",
        value: e.mirrored,
        // Turning the team round re-lays it out, which is how the away side
        // faces the home side rather than both running at the same goal.
        onChanged: (v) => now(e.withFormation(e.formation, mirror: v)),
      ),
      CanvasIconButton(
        icon: e.frameLocked ? Icons.lock : Icons.lock_open,
        tooltip: e.frameLocked
            ? "The team's box is pinned — players still move"
            : "Pin the team's box so only players move",
        active: e.frameLocked,
        onPressed: () => now(e.copyWith(frameLocked: !e.frameLocked)),
      ),
      CanvasIconButton(
        icon: Icons.refresh,
        tooltip: "Put everybody back in formation",
        onPressed: () => now(e.withFormation(e.formation)),
      ),
    ]),
    _squadList(e, write, begin, commit, now),
    CanvasControlGroup(label: "Colours", children: [
      CanvasColorButton(
        label: "Keeper",
        color: e.keeperColor,
        onChanged: (c) => now(e.copyWith(keeperColor: c)),
      ),
      CanvasColorButton(
        label: "Players",
        color: e.playerColor,
        onChanged: (c) => now(e.copyWith(playerColor: c)),
      ),
      CanvasColorButton(
        label: "Outline",
        color: e.outlineColor,
        onChanged: (c) => now(e.copyWith(outlineColor: c)),
      ),
      // The element's own opacity rather than a second one of the team's. Two
      // opacities multiplying together is a control that appears not to work
      // whenever the other one is down.
      CanvasNumberField(
        label: "Opacity",
        decimals: 2,
        width: 62,
        value: e.opacity,
        min: 0,
        max: 1,
        onChanged: (v) {
          begin();
          write(e.withBase(opacity: v));
        },
        onCommit: commit,
      ),
    ]),
    CanvasControlGroup(label: "Dots", children: [
      CanvasNumberField(
        key: const ValueKey("teamDotWidth"),
        label: "Width",
        value: e.dotWidth,
        min: 4,
        max: 400,
        width: 56,
        onChanged: (v) {
          begin();
          // Locked, the two move together, which is what keeps a player marker
          // a circle. An oval is almost always somebody having dragged one
          // field without meaning to.
          write(e.copyWith(
              dotWidth: v, dotHeight: e.lockDotAspect ? v : e.dotHeight));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        key: const ValueKey("teamDotHeight"),
        label: "Height",
        value: e.dotHeight,
        min: 4,
        max: 400,
        width: 56,
        onChanged: (v) {
          begin();
          write(e.copyWith(
              dotHeight: v, dotWidth: e.lockDotAspect ? v : e.dotWidth));
        },
        onCommit: commit,
      ),
      CanvasIconButton(
        icon: e.lockDotAspect ? Icons.link : Icons.link_off,
        tooltip: e.lockDotAspect
            ? "Width and height move together"
            : "Width and height are independent",
        active: e.lockDotAspect,
        onPressed: () => now(e.copyWith(
            lockDotAspect: !e.lockDotAspect,
            dotHeight: e.lockDotAspect ? e.dotHeight : e.dotWidth)),
      ),
      CanvasNumberField(
        label: "Ring",
        value: e.ringWidth,
        min: 0,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(ringWidth: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Angle",
        value: e.rotation,
        min: -180,
        max: 180,
        width: 56,
        suffix: "°",
        onChanged: (v) {
          begin();
          write(e.withBase(rotation: v));
        },
        onCommit: commit,
      ),
    ]),
    // One set of type for the number and the name. They were two identical
    // panels, and the two drifted -- a team's names ended up in a different
    // face from its numbers without anybody having chosen that.
    ...typeGroups(
      e.labelSpec,
      (spec) {
        begin();
        write(e.copyWith(labelSpec: spec));
      },
      begin,
      commit,
      label: "Numbers and names",
    ),
    CanvasControlGroup(label: "Labels", children: [
      CanvasToggle(
        label: "Numbers",
        value: e.showNumbers,
        onChanged: (v) => now(e.copyWith(showNumbers: v)),
      ),
      CanvasToggle(
        label: "Names",
        value: e.showNames,
        onChanged: (v) => now(e.copyWith(showNames: v)),
      ),
      CanvasDropdown<LabelPosition>(
        label: "Name at",
        value: e.namePosition,
        width: 92,
        options: [for (var p in LabelPosition.values) (p, p.label)],
        onChanged: (v) => now(e.copyWith(namePosition: v)),
      ),
      CanvasNumberField(
        label: "Gap",
        value: e.nameGap,
        min: 0,
        max: 80,
        decimals: 1,
        width: 50,
        onChanged: (v) {
          begin();
          write(e.copyWith(nameGap: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Turn",
        value: e.labelRotation,
        min: -180,
        max: 180,
        width: 56,
        suffix: "°",
        onChanged: (v) {
          begin();
          write(e.copyWith(labelRotation: v));
        },
        onCommit: commit,
      ),
    ]),
  ];
}

/// _squadList is the team sheet: one row per player, goalkeeper first.
///
/// The coordinates are shown and edited in canvas units rather than as the
/// fractions they are stored as, because "where is he" is a question about the
/// pitch, not about the element's box.

/// _squadList is the team sheet: one row per player, goalkeeper first.
///
/// The coordinates are shown and edited in canvas units rather than as the
/// fractions they are stored as, because "where is he" is a question about the
/// pitch, not about the element's box.
Widget _squadList(TeamElement e, SettingsWrite write, VoidCallback begin,
        VoidCallback commit, void Function(TeamElement) now) =>
    CanvasExpander(
      label: "Players",
      trailing: "${e.players.length}",
      children: [
        for (var i = 0; i < e.players.length; i++)
          _PlayerRow(
            key: ValueKey("player-$i-${e.id}"),
            team: e,
            index: i,
            write: write,
            begin: begin,
            commit: commit,
            now: now,
          ),
      ],
    );

/// _PlayerRow is one line of the team sheet.
///
/// A widget rather than a function so each row's fields keep their own state
/// across the rebuild that every keystroke causes; as plain builders, typing
/// in one player's name rebuilt all eleven and moved the caret.

/// _PlayerRow is one line of the team sheet.
///
/// A widget rather than a function so each row's fields keep their own state
/// across the rebuild that every keystroke causes; as plain builders, typing
/// in one player's name rebuilt all eleven and moved the caret.
class _PlayerRow extends StatelessWidget {
  final TeamElement team;
  final int index;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  final void Function(TeamElement) now;

  const _PlayerRow({
    required this.team,
    required this.index,
    required this.write,
    required this.begin,
    required this.commit,
    required this.now,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var spot = team.players[index];
    var centre = team.centreOf(spot);

    void set(PlayerSpot next) {
      begin();
      write(team.withPlayer(index, next));
    }

    /// moveTo writes a canvas coordinate back as the fraction it is stored as.
    void moveTo({double? x, double? y}) {
      var w = team.width == 0 ? 1 : team.width;
      var h = team.height == 0 ? 1 : team.height;
      set(spot.copyWith(
        dx: x == null ? spot.dx : (x - team.x) / w,
        dy: y == null ? spot.dy : (y - team.y) / h,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        CanvasTextField(
          key: ValueKey("num-$index-${team.id}"),
          label: index == 0 ? "GK" : "No.",
          value: spot.number,
          width: 42,
          onChanged: (v) => set(spot.copyWith(number: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          key: ValueKey("name-$index-${team.id}"),
          label: "Name",
          value: spot.name,
          width: 104,
          onChanged: (v) => set(spot.copyWith(name: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("x-$index-${team.id}"),
          label: "X",
          value: centre.dx,
          min: -100000,
          max: 100000,
          width: 54,
          onChanged: (v) => moveTo(x: v),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("y-$index-${team.id}"),
          label: "Y",
          value: centre.dy,
          min: -100000,
          max: 100000,
          width: 54,
          onChanged: (v) => moveTo(y: v),
          onCommit: commit,
        ),
        CanvasIconButton(
          icon: spot.locked ? Icons.lock : Icons.lock_open,
          tooltip: spot.locked ? "Unlock" : "Lock in place",
          active: spot.locked,
          onPressed: () =>
              now(team.withPlayer(index, spot.copyWith(locked: !spot.locked))),
        ),
        CanvasIconButton(
          icon: spot.hidden ? Icons.visibility_off : Icons.visibility,
          tooltip: spot.hidden ? "Show" : "Hide",
          active: spot.hidden,
          onPressed: () =>
              now(team.withPlayer(index, spot.copyWith(hidden: !spot.hidden))),
        ),
        CanvasIconButton(
          icon: Icons.arrow_upward,
          tooltip: "Bring forward",
          onPressed: index >= team.players.length - 1
              ? null
              : () => now(team.movePlayer(index, index + 1)),
        ),
        CanvasIconButton(
          icon: Icons.arrow_downward,
          tooltip: "Send to back",
          onPressed:
              index <= 0 ? null : () => now(team.movePlayer(index, index - 1)),
        ),
      ]),
    );
  }
}

/// _pathSettings is a curve, and what travels along it.
///
/// The follower is chosen from a flat list of everything on the canvas plus
/// every player of every team, because "which player runs this" is the
/// question this feature exists to answer and making it a two-step choice --
/// pick a team, then pick a row -- would be two dropdowns for one decision.
