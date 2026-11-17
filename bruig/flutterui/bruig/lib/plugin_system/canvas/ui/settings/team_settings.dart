import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/team_photo_editor.dart';

// team_settings.dart is a team's settings.

/// teamSettings is a team's controls in setup order; the squad list sits
/// in an expander, as eleven rows of four fields outweigh the rest.
List<Widget> teamSettings(
    BuildContext context,
    CanvasController controller,
    TeamElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  /// now is a one-go change (a dropdown, colour or switch), its own undo
  /// step.
  void now(TeamElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    section(e, "team",
        icon: Icons.groups_outlined,
        title: "Team",
        summary: "${e.sport.label} · ${e.formation.label}"
            "${e.ball != null ? " · ball" : ""}",
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
              label: "Team",
              hideCaption: true,
              rule: false,
              children: [
                // The team's pitch: linked, it follows the pitch and keeps
                // players in its metres. See team_painter.dart.
                _pitchDropdown(controller, e, now),
                CanvasDropdown<TeamSport>(
                  key: const ValueKey("teamSport"),
                  label: "Sport",
                  value: e.sport,
                  width: 138,
                  options: [for (var s in TeamSport.values) (s, s.label)],
                  // Changing sport re-lays and renumbers the squad: a
                  // formation belongs to one game, and squad size changes.
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
                  // The same eleven positions at kick-off (own half) or in
                  // possession (forwards past halfway). See FormationSpread.
                  onChanged: (v) =>
                      now(e.withFormation(e.formation, spread: v)),
                ),
                CanvasToggle(
                  label: "Attack left",
                  value: e.mirrored,
                  // Turning the team round re-lays it, so the away side faces
                  // the home side rather than both attacking one goal.
                  onChanged: (v) =>
                      now(e.withFormation(e.formation, mirror: v)),
                ),
                if (!e.linked)
                  CanvasIconButton(
                    icon: e.frameLocked ? Icons.lock : Icons.lock_open,
                    tooltip: e.frameLocked
                        ? "The team's box is pinned — players still move"
                        : "Pin the team's box so only players move",
                    active: e.frameLocked,
                    onPressed: () =>
                        now(e.copyWith(frameLocked: !e.frameLocked)),
                  ),
                CanvasIconButton(
                  icon: Icons.refresh,
                  tooltip: "Reset formation",
                  onPressed: () => now(e.withFormation(e.formation)),
                ),
                // The ball: one more thing on the pitch moving as a player does
                // (dragged, keyframed, or sent along a path).
                CanvasToggle(
                  key: const ValueKey("teamBall"),
                  label: "Ball",
                  value: e.ball != null,
                  onChanged: (v) => now(e.withBall(v)),
                ),
                // Positions instead of names, as a switch: the names are kept
                // and return when it is off.
                CanvasIconButton(
                  key: const ValueKey("teamNameByPosition"),
                  icon: Icons.badge_outlined,
                  tooltip: e.namesByPosition ? "Show names" : "Show positions",
                  active: e.namesByPosition,
                  onPressed: () =>
                      now(e.copyWith(namesByPosition: !e.namesByPosition)),
                ),
              ]),
          if (e.ball != null) _ballGroup(e, now, begin, write, commit),
        ]),
    section(e, "players",
        icon: Icons.person_outline,
        title: "Players",
        summary: e.ball == null
            ? "${e.players.length} players"
            : "${e.players.length - 1} players + ball",
        children: [
          _squadList(context, controller, e, write, begin, commit, now),
        ]),
    section(e, "look",
        icon: Icons.palette_outlined,
        title: "Look",
        summary: e.tokenStyle.label,
        children: [
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
            // The element's own opacity, not a second: two multiplying make a
            // control that seems broken whenever the other is down.
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
                // Locked, the two move together, keeping a marker circular.
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
        ]),
    section(e, "labels",
        icon: Icons.badge_outlined,
        title: "Numbers and names",
        summary: [
          if (e.showNumbers) "Numbers",
          if (e.showNames) "names",
          typeSummary(e.labelSpec),
        ].join(" · "),
        children: [
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
        ]),
  ];
}

/// _squadList is the team sheet: a row per player, goalkeeper first, in
/// canvas units rather than the stored fractions.
Widget _squadList(
        BuildContext context,
        CanvasController controller,
        TeamElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit,
        void Function(TeamElement) now) =>
    // Boxed like every element's sections: shut, a heading in a box, not a
    // line of text running into the settings below.
    boxed(
        context,
        CanvasExpander(
          label: "Players",
          remember: "team.players",
          // In its own section, which is its heading.
          flat: true,
          trailing: e.ball == null
              ? "${e.players.length}"
              : "${e.players.length - 1} + ball",
          children: [
            _teamPhotoRow(context, e, now),
            if (e.teamPhoto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TeamPhotoEditor(
                  key: ValueKey("teamPhoto-${e.id}"),
                  team: e,
                  begin: begin,
                  write: write,
                  commit: commit,
                ),
              ),
            // At the ordinary size, as a cell grid is: card-sized, a player
            // took three ragged lines.
            for (var i = 0; i < e.players.length; i++)
              CanvasCards.none(_PlayerRow(
                key: ValueKey("player-$i-${e.id}"),
                controller: controller,
                team: e,
                index: i,
                write: write,
                begin: begin,
                commit: commit,
                now: now,
              )),
          ],
        ));

/// _teamPhotoRow is the squad's photo: add, swap or remove. Adding one shows
/// portraits, the only token that draws a face.
Widget _teamPhotoRow(
    BuildContext context, TeamElement e, void Function(TeamElement) now) {
  TeamElement withPhoto(String id) => e.copyWith(
      teamPhoto: id,
      tokenStyle: id.isEmpty ? e.tokenStyle : TokenStyle.portrait);
  return CanvasWrap(children: [
    CanvasIconButton(
      key: const ValueKey("teamPhotoAdd"),
      icon: e.teamPhoto.isEmpty ? Icons.groups_outlined : Icons.groups,
      tooltip: e.teamPhoto.isEmpty ? "Team photo" : "Change team photo",
      active: e.teamPhoto.isNotEmpty,
      onPressed: () async {
        var id = await pickCanvasImage(context);
        if (id == null) return;
        now(withPhoto(id));
      },
    ),
    CanvasIconButton(
      key: const ValueKey("teamPhotoLibrary"),
      icon: Icons.photo_library_outlined,
      tooltip: "Team photo from library",
      onPressed: () async {
        var id = await showRecentPictures(context);
        if (id == null) return;
        now(withPhoto(id));
      },
    ),
    if (e.teamPhoto.isNotEmpty)
      CanvasIconButton(
        key: const ValueKey("teamPhotoRemove"),
        icon: Icons.no_photography_outlined,
        tooltip: "Remove team photo",
        onPressed: () => now(withPhoto("")),
      ),
    const CanvasHint("One photo of the whole squad. Each player without a "
        "photo of their own shows the circle marked for them on it: tap a "
        "circle to choose it, drag it to move, the square to size it and the "
        "round handle to turn it."),
  ]);
}

/// _ballGroup is the ball's design, where the team has one.
Widget _ballGroup(TeamElement e, void Function(TeamElement) now,
    VoidCallback begin, SettingsWrite write, VoidCallback commit) {
  var look = e.ballLook;
  void set(BallLook next) => now(e.copyWith(ballLook: next));
  var designed = look.style != BallStyle.auto;
  return CanvasControlGroup(label: "Ball", rule: false, children: [
    CanvasDropdown<BallStyle>(
      key: const ValueKey("teamBallStyle"),
      label: "Style",
      value: look.style,
      width: 124,
      options: [for (var s in BallStyle.values) (s, s.label)],
      onChanged: (v) => set(look.copyWith(style: v)),
    ),
    if (designed || look.trail)
      CanvasColorButton(
        key: const ValueKey("teamBallColour"),
        label: "Main",
        color: look.color,
        onChanged: (c) => set(look.copyWith(color: c)),
      ),
    if (designed && look.style != BallStyle.plain)
      CanvasColorButton(
        key: const ValueKey("teamBallSecond"),
        label: "Second",
        color: look.second,
        onChanged: (c) => set(look.copyWith(second: c)),
      ),
    CanvasNumberField(
      key: const ValueKey("teamBallSize"),
      label: "Size",
      value: look.size,
      min: 0.3,
      max: 4,
      decimals: 2,
      width: 54,
      onChanged: (v) {
        begin();
        write(e.copyWith(ballLook: look.copyWith(size: v)));
      },
      onCommit: commit,
    ),
    CanvasToggle(
      key: const ValueKey("teamBallShadow"),
      label: "Shadow",
      value: look.shadow,
      onChanged: (v) => set(look.copyWith(shadow: v)),
    ),
    CanvasToggle(
      key: const ValueKey("teamBallOutline"),
      label: "Outline",
      value: look.outline,
      onChanged: (v) => set(look.copyWith(outline: v)),
    ),
    CanvasToggle(
      key: const ValueKey("teamBallTrail"),
      label: "Trail",
      value: look.trail,
      onChanged: (v) => set(look.copyWith(trail: v)),
    ),
  ]);
}

/// _PlayerRow is one team sheet line: a widget, so its fields keep state
/// (and the caret) across the rebuild each keystroke causes.
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
    // On a pitch, position is in its metres (from the left end and bottom
    // touchline), the same whatever the pitch is doing.
    var ground = teamGround(controller.document, team, controller.frame);
    var field =
        ground == null ? null : teamFieldPoint(team, spot, ground.place);

    void set(PlayerSpot next) {
      begin();
      write(team.withPlayer(index, next));
    }

    /// moveTo writes a canvas coordinate back as its stored fraction.
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

    // Half a group apart, so each player's two lines read as one entry.
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
        // A portrait photo from a file or the canvas's pictures, and
        // removal. Not for the ball.
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
