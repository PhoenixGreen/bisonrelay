import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
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
List<Widget> teamSettings(
    BuildContext context,
    CanvasController controller,
    TeamElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
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
    CanvasControlGroup(
        label: "Team",
        hideCaption: true,
        rule: false,
        children: [
          // The pitch the team stands on. Linked, it goes wherever the pitch
          // goes -- moved, turned, zoomed or tilted -- and its players are
          // kept in the pitch's own metres. See team_painter.dart.
          _pitchDropdown(controller, e, now),
          CanvasDropdown<TeamSport>(
            key: const ValueKey("teamSport"),
            label: "Sport",
            value: e.sport,
            width: 138,
            options: [for (var s in TeamSport.values) (s, s.label)],
            // Changing the sport re-lays the squad out and numbers it afresh,
            // since a formation belongs to one game and the squad size changes
            // with it.
            onChanged: (v) => now(e.withSport(v)),
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
          if (!e.linked)
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
            tooltip: "Reset formation",
            onPressed: () => now(e.withFormation(e.formation)),
          ),
          // The ball: one more thing on the pitch that moves the way a player
          // does -- dragged, keyframed, or sent along a path.
          CanvasToggle(
            key: const ValueKey("teamBall"),
            label: "Ball",
            value: e.ball != null,
            onChanged: (v) => now(e.withBall(v)),
          ),
          if (e.formation.roles.isNotEmpty)
            CanvasIconButton(
              key: const ValueKey("teamNameByPosition"),
              icon: Icons.badge_outlined,
              tooltip: "Name by position",
              onPressed: () => now(e.namedByPosition()),
            ),
        ]),
    _squadList(context, controller, e, write, begin, commit, now),
    // What the players look like: a dot, a shirt or a portrait, the kit's
    // pattern, faces, and the finishing.
    CanvasControlGroup(label: "Design", rule: false, children: [
      CanvasDropdown<TokenStyle>(
        key: const ValueKey("teamToken"),
        label: "Players as",
        value: e.tokenStyle,
        width: 104,
        options: [for (var t in TokenStyle.values) (t, t.label)],
        onChanged: (v) => now(e.copyWith(tokenStyle: v)),
      ),
      CanvasDropdown<KitPattern>(
        key: const ValueKey("teamKit"),
        label: "Kit",
        value: e.kitPattern,
        width: 104,
        options: [for (var k in KitPattern.values) (k, k.label)],
        onChanged: (v) => now(e.copyWith(kitPattern: v)),
      ),
      CanvasDropdown<NameStyle>(
        key: const ValueKey("teamNameStyle"),
        label: "Names",
        value: e.nameStyle,
        width: 90,
        options: [for (var n in NameStyle.values) (n, n.label)],
        onChanged: (v) => now(e.copyWith(nameStyle: v)),
      ),
      if (e.tokenStyle == TokenStyle.portrait)
        CanvasToggle(
          key: const ValueKey("teamFaces"),
          label: "Faces",
          value: e.faces,
          onChanged: (v) => now(e.copyWith(faces: v)),
        ),
      CanvasToggle(
        key: const ValueKey("teamShadow"),
        label: "Shadow",
        value: e.shadow,
        onChanged: (v) => now(e.copyWith(shadow: v)),
      ),
      CanvasToggle(
        key: const ValueKey("teamRuns"),
        label: "Runs",
        value: e.showRuns,
        onChanged: (v) => now(e.copyWith(showRuns: v)),
      ),
    ]),
    CanvasControlGroup(label: "Colours", rule: false, children: [
      if (e.sport.hasKeeper)
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
        key: const ValueKey("teamSecond"),
        label: "Second",
        color: e.secondaryColor,
        onChanged: (c) => now(e.copyWith(secondaryColor: c)),
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
    CanvasControlGroup(label: "Dots", rule: false, children: [
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
      if (!e.linked)
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
      remember: "team",
      rule: false,
    ),
    CanvasControlGroup(label: "Labels", rule: false, children: [
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
Widget _squadList(
        BuildContext context,
        CanvasController controller,
        TeamElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit,
        void Function(TeamElement) now) =>
    CanvasExpander(
      label: "Players",
      trailing: e.ball == null
          ? "${e.players.length}"
          : "${e.players.length - 1} + ball",
      children: [
        for (var i = 0; i < e.players.length; i++)
          _PlayerRow(
            key: ValueKey("player-$i-${e.id}"),
            controller: controller,
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
class _PlayerRow extends StatelessWidget {
  final CanvasController controller;
  final TeamElement team;
  final int index;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  final void Function(TeamElement) now;

  const _PlayerRow({
    required this.controller,
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
    // On a pitch, where they stand is said in its metres -- along the
    // field from the left end and across it from the bottom touchline --
    // which is a position that means the same whatever the pitch is doing.
    var ground = teamGround(controller.document, team, controller.frame);
    var field =
        ground == null ? null : teamFieldPoint(team, spot, ground.place);

    void set(PlayerSpot next) {
      begin();
      write(team.withPlayer(index, next));
    }

    /// moveTo writes a canvas coordinate back as the fraction it is stored as.
    void moveTo({double? x, double? y}) {
      if (ground != null && field != null) {
        var (dx, dy) = spotFromField(
            team, Offset(x ?? field.dx, y ?? field.dy), ground.place);
        set(spot.copyWith(dx: dx, dy: dy));
        return;
      }
      var w = team.width == 0 ? 1 : team.width;
      var h = team.height == 0 ? 1 : team.height;
      set(spot.copyWith(
        dx: x == null ? spot.dx : (x - team.x) / w,
        dy: y == null ? spot.dy : (y - team.y) / h,
      ));
    }

    // Half a group apart, so each player's two lines read as one entry
    // rather than running into the next player's.
    return Padding(
      padding: const EdgeInsets.only(bottom: canvasGroupGap / 2),
      child: CanvasWrap(children: [
        if (!spot.ball)
          CanvasTextField(
            key: ValueKey("num-$index-${team.id}"),
            label: index == 0 && team.sport.hasKeeper ? "GK" : "No.",
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
          label: field == null ? "X" : "Along",
          decimals: field == null ? 0 : 1,
          value: field?.dx ?? centre.dx,
          min: -100000,
          max: 100000,
          width: 54,
          onChanged: (v) => moveTo(x: v),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("y-$index-${team.id}"),
          label: field == null ? "Y" : "Across",
          decimals: field == null ? 0 : 1,
          value: field?.dy ?? centre.dy,
          min: -100000,
          max: 100000,
          width: 54,
          onChanged: (v) => moveTo(y: v),
          onCommit: commit,
        ),
        // A photo for the portrait, from a file or from the pictures the
        // canvas already has -- and taken off again. Not for the ball.
        if (!spot.ball) ...[
          CanvasIconButton(
            key: ValueKey("photo-$index-${team.id}"),
            icon: spot.photo.isEmpty
                ? Icons.add_a_photo_outlined
                : Icons.account_circle,
            tooltip: spot.photo.isEmpty ? "Add photo" : "Change photo",
            active: spot.photo.isNotEmpty,
            onPressed: () async {
              var id = await pickCanvasImage(context);
              if (id == null) return;
              now(team.withPlayer(index, spot.copyWith(photo: id)));
            },
          ),
          CanvasIconButton(
            icon: Icons.photo_library_outlined,
            tooltip: "Photo from library",
            onPressed: () async {
              var id = await showRecentPictures(context);
              if (id == null) return;
              now(team.withPlayer(index, spot.copyWith(photo: id)));
            },
          ),
          if (spot.photo.isNotEmpty)
            CanvasIconButton(
              icon: Icons.no_photography_outlined,
              tooltip: "Remove photo",
              onPressed: () =>
                  now(team.withPlayer(index, spot.copyWith(photo: ""))),
            ),
          CanvasIconButton(
            key: ValueKey("captain-$index-${team.id}"),
            icon: Icons.copyright,
            tooltip: "Captain",
            active: spot.captain,
            onPressed: () => now(
                team.withPlayer(index, spot.copyWith(captain: !spot.captain))),
          ),
        ],
        CanvasIconButton(
          key: ValueKey("highlight-$index-${team.id}"),
          icon: Icons.highlight,
          tooltip: "Highlight",
          active: spot.highlight,
          onPressed: () => now(team.withPlayer(
              index, spot.copyWith(highlight: !spot.highlight))),
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
        if (!spot.ball)
          CanvasIconButton(
            icon: Icons.arrow_upward,
            tooltip: "Bring forward",
            onPressed: index >= team.players.length - 1
                ? null
                : () => now(team.movePlayer(index, index + 1)),
          ),
        if (!spot.ball)
          CanvasIconButton(
            icon: Icons.arrow_downward,
            tooltip: "Send to back",
            onPressed: index <= 0
                ? null
                : () => now(team.movePlayer(index, index - 1)),
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

/// _pitchDropdown is which pitch the team stands on: none, the canvas's
/// background where it is a pitch, or a pitch background element.
Widget _pitchDropdown(CanvasController controller, TeamElement e,
    void Function(TeamElement) now) {
  var choices = pitchChoices(controller.document);
  var known = e.link.isEmpty || choices.any((c) => c.link == e.link);
  return CanvasDropdown<String>(
    key: const ValueKey("teamPitch"),
    label: "Pitch",
    value: known ? e.link : "?",
    width: 150,
    options: [
      ("", "Not linked"),
      if (!known) ("?", "Missing pitch"),
      for (var c in choices) (c.link, c.label),
    ],
    onChanged: (link) {
      if (link == "?") return;
      if (link.isEmpty) {
        now(e.copyWith(link: ""));
        return;
      }
      var c = choices.firstWhere((c) => c.link == link);
      now(e.linkedTo(link,
          pitch: c.sport, reference: c.reference, area: c.area));
    },
  );
}
