import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraOf;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// position_group.dart is the place-and-size group every element's Layout
// section starts with (see elementPanel): where it is, how big, its turn,
// slant and anchor, and what it does on each page shape.

/// positionGroup is what every element has: place, size, turn, and whether
/// it can be touched. Its keyframes are the Chain's to make and ease.
Widget positionGroup(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  // No lock, hide or bring-to-front here: they belong to the layer, and the
  // layers list shows them on the element's row, usable unselected.
  var p = _Placing(controller, e, write, begin, commit);
  var document = controller.document;
  return CanvasControlGroup(
      label: e.kind.label,
      // The settings are already headed with the element's name.
      hideCaption: true,
      children: [
        ..._placeRows(p),
        ..._skewRow(p),
        // Distance from the scene's Camera, for depth of field and parallax.
        if (e is! CameraElement && cameraOf(document) != null) ..._depthRow(p),
        // What this element does on this page shape, for a document laid out
        // for several; a canvas made for one shape has one design.
        if (document.targets.length > 1) ..._pageShapeRow(p),
      ]);
}

/// opacityField is the element's opacity as the position group sets it, as
/// a pose while animating: for a panel that stands in for the group, as
/// words riding a line do.
Widget opacityField(CanvasController controller, CanvasElement e,
        SettingsWrite write, VoidCallback begin, VoidCallback commit) =>
    _opacityField(_Placing(controller, e, write, begin, commit));

/// _Placing is what the group's rows share: the element, how a change is
/// written, and where the element is seen on the frame shown.
class _Placing {
  final CanvasController controller;
  final CanvasElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  final int frame;
  final Keyframe pose;
  final Rect box;

  /// posing is whether these fields edit a keyframe, not the resting place:
  /// the stage's question for a drag, so typing and dragging agree.
  final bool posing;

  _Placing(this.controller, this.e, this.write, this.begin, this.commit)
      : frame = controller.frame,
        pose = e.poseAt(controller.frame),
        box = e.boundsAt(controller.frame),
        posing = controller.posesRatherThanMoves(e);

  /// track is the element's keyframes, with one at the frame shown.
  ElementTrack get track => (e.track ?? ElementTrack.empty).seededFor(frame);

  /// moveTo writes a position, as a pose while animating, else the resting
  /// position; the fields show the posed value, where the element is seen.
  void moveTo({double? x, double? y}) {
    begin();
    if (!posing) {
      write(e.withBase(x: x, y: y));
      return;
    }
    // The location keyed here, and nothing else (see ElementTrack.posed).
    write(e.withBase(
      track: track.posed(
          frame,
          const [KeyProp.location],
          (at) => at.copyWith(
                dx: x == null ? at.dx : x - e.x,
                dy: y == null ? at.dy : y - e.y,
              )),
    ));
  }

  /// resize writes width or height, keeping proportions where they are held
  /// (CanvasElement.keepsAspect) by scaling the other side. Fields show the
  /// posed size but edit the resting one: a pose scales evenly.
  void resize({double? width, double? height}) {
    // The undo step, as moveTo opens one.
    begin();
    var scale = pose.scale == 0 ? 1.0 : pose.scale;
    if (!e.keepsAspect) {
      write(e.withBase(
        width: width == null ? null : width / scale,
        height: height == null ? null : height / scale,
      ));
      return;
    }

    // The edited side's factor applied to both, guarding a zero side.
    var by = width != null
        ? (box.width <= 0 ? 1 : width / box.width)
        : (box.height <= 0 ? 1 : height! / box.height);
    if (!by.isFinite || by <= 0) return;

    write(e.withBase(
      width: box.width * by / scale,
      height: box.height * by / scale,
    ));
  }

  /// turnTo writes the angle, as a pose while animating.
  void turnTo(double v) {
    begin();
    if (!posing) {
      // About its anchor, which stays where it is.
      write(e.turnedTo(v));
      return;
    }
    write(e.withBase(
        track: track.posed(frame, const [KeyProp.rotation],
            (at) => at.copyWith(rotate: v - e.rotation))));
  }

  /// fadeTo writes the opacity, 0 to 1, as a pose while animating.
  void fadeTo(double v) {
    begin();
    if (!posing) {
      write(e.withBase(opacity: v));
      return;
    }
    write(e.withBase(
        track: track.posed(
            frame,
            const [KeyProp.opacity],
            (at) => at.copyWith(
                opacity:
                    e.opacity == 0 ? v : (v / e.opacity).clamp(0.0, 1.0)))));
  }
}

/// _placeRows are place and turn on one line, size and opacity on the next,
/// then whether the proportions are held, and the anchor.
List<Widget> _placeRows(_Placing p) {
  var box = p.box;
  var xField = CanvasStepper(
    key: const ValueKey("elementX"),
    label: "X",
    // Two to a line (across beside down, wide beside high), held so by the
    // breaks, not the width, which only leaves the arrows room.
    width: 104,
    value: box.left,
    onChanged: (v) => p.moveTo(x: v),
    onCommit: p.commit,
  );
  var yField = CanvasStepper(
    key: const ValueKey("elementY"),
    label: "Y",
    width: 104,
    value: box.top,
    onChanged: (v) => p.moveTo(y: v),
    onCommit: p.commit,
  );
  var wField = CanvasStepper(
    key: const ValueKey("elementW"),
    label: "W",
    width: 104,
    value: box.width,
    min: 1,
    onChanged: (v) => p.resize(width: v),
    onCommit: p.commit,
  );
  var hField = CanvasStepper(
    key: const ValueKey("elementH"),
    label: "H",
    width: 104,
    value: box.height,
    min: 1,
    onChanged: (v) => p.resize(height: v),
    onCommit: p.commit,
  );
  var turnField = CanvasStepper(
    key: const ValueKey("elementAngle"),
    label: "Angle",
    value: p.e.rotationAt(p.frame),
    min: -3600,
    max: 3600,
    // X's least width, so Angle and Opacity line up under X and Y.
    width: 104,
    step: 15,
    dragStep: 1,
    defaultValue: 0,
    suffix: "°",
    onChanged: p.turnTo,
    onCommit: p.commit,
  );
  return [
    panelRow([cell(xField), cell(yField), cell(turnField)]),
    panelRow([cell(wField), cell(hField), cell(_opacityField(p))]),
    _lockButton(p),
    _anchorButtons(p),
  ];
}

/// _opacityField is the element's opacity in percent.
Widget _opacityField(_Placing p) => CanvasStepper(
      key: const ValueKey("elementOpacity"),
      label: "Opacity",
      min: 0,
      max: 100,
      step: 5,
      dragStep: 1,
      suffix: "%",
      defaultValue: 100,
      width: 104,
      value: p.e.opacityAt(p.frame) * 100,
      onChanged: (percent) => p.fadeTo(percent / 100),
      onCommit: p.commit,
    );

/// _lockButton holds the width and height together, or lets them go. What
/// keeps them by its kind (a square or a circle) is held whatever it says,
/// so on one it is the other thing the person's hold does: whether a resize
/// scales its outline, corners, padding and words (see the stage's resize),
/// said in its icon, its tooltip and the words beside it.
Widget _lockButton(_Placing p) {
  var byKind = p.e.keepsAspectByKind;
  var own = p.e.base.lockAspect;
  var held = byKind || own;
  void toggle() {
    p.begin();
    p.write(p.e.withProportionsKept(!own));
    p.commit();
  }

  if (!byKind) {
    return CanvasIconButton(
      icon: held ? Icons.link : Icons.link_off,
      tooltip: held
          ? "Proportions are held — the width and the height move together"
          : "Width and height are free of each other",
      active: held,
      onPressed: toggle,
    );
  }
  return Row(mainAxisSize: MainAxisSize.min, children: [
    CanvasIconButton(
      icon: own ? Icons.open_in_full : Icons.link,
      tooltip: own
          ? "Always square, and a resize scales its outline, corners, "
              "padding and words with it. Press to leave them their size."
          : "Always square, and a resize leaves its outline, corners, "
              "padding and words their size. Press to scale them with it.",
      active: true,
      onPressed: toggle,
    ),
    // Level with the button, which sits below its neighbours' captions,
    // and on two lines where the line is short.
    Flexible(
        child: Builder(
            builder: (context) => Padding(
                  padding: EdgeInsets.only(top: nudgeIn(context)),
                  child: Text(own ? "Inside scales" : "Inside stays",
                      style: TextStyle(
                          fontSize: 12,
                          color: ThemeNotifier.of(context)
                              .colors
                              .onSurfaceVariant)),
                ))),
  ]);
}

/// _anchorButtons are the anchor point: shown on stage to drag, or hidden;
/// while shown, locked or re-centred. See ElementBase.anchorX.
Widget _anchorButtons(_Placing p) {
  var controller = p.controller;
  var e = p.e;
  var shown = controller.anchorShown(e.id);
  var locked = e.base.anchorLocked;
  // One cluster: three buttons about one thing, kept together.
  return Row(
      key: const ValueKey("elementAnchor"),
      mainAxisSize: MainAxisSize.min,
      children: [
        CanvasIconButton(
          key: const ValueKey("elementAnchorShow"),
          icon: shown ? Icons.gps_fixed : Icons.gps_not_fixed,
          tooltip: shown ? "Hide anchor" : "Show anchor",
          active: shown,
          onPressed: () => controller.showAnchor(e.id, !shown),
        ),
        if (shown) ...[
          CanvasIconButton(
            key: const ValueKey("elementAnchorLock"),
            icon: locked ? Icons.lock_outline : Icons.lock_open,
            tooltip: locked ? "Unlock anchor" : "Lock anchor",
            active: locked,
            onPressed: () {
              p.begin();
              p.write(e.withBase(anchorLocked: !locked));
              p.commit();
            },
          ),
          CanvasIconButton(
            key: const ValueKey("elementAnchorReset"),
            icon: Icons.center_focus_strong_outlined,
            tooltip: "Centre anchor",
            onPressed: e.anchorCentred
                ? null
                : () {
                    p.begin();
                    p.write(e.withBase(anchorX: 0.5, anchorY: 0.5));
                    p.commit();
                  },
          ),
        ],
      ]);
}

/// _skewRow is slant after turn, and the switch making side handles slant
/// it, for a screen with no keys to hold.
List<Widget> _skewRow(_Placing p) => [
      const CanvasLineBreak(),
      for (var (key, label, value, across) in [
        ("elementSkewX", "Skew X", p.e.base.skewX, true),
        ("elementSkewY", "Skew Y", p.e.base.skewY, false),
      ])
        CanvasStepper(
          key: ValueKey(key),
          label: label,
          value: value,
          min: -maxSkew,
          max: maxSkew,
          width: 104,
          step: 5,
          dragStep: 1,
          defaultValue: 0,
          suffix: "°",
          onChanged: (v) {
            p.begin();
            p.write(across ? p.e.withBase(skewX: v) : p.e.withBase(skewY: v));
          },
          onCommit: p.commit,
        ),
      CanvasToggle(
        key: const ValueKey("elementSkewHandles"),
        label: "Skew",
        value: p.controller.skewHandles,
        onChanged: (v) => p.controller.skewHandles = v,
      ),
      const CanvasHint("Skew X leans the sides, Skew Y the top and bottom. "
          "On the canvas, hold Command and drag a side handle -- or switch "
          "Skew on and drag one without a key."),
    ];

/// _depthRow is how far the element is from the scene's Camera.
List<Widget> _depthRow(_Placing p) => [
      const CanvasLineBreak(gap: 8),
      CanvasStepper(
        key: const ValueKey("elementDepth"),
        label: "Depth",
        value: p.e.base.depth * 100,
        min: -100,
        max: 100,
        width: 104,
        step: 10,
        dragStep: 1,
        defaultValue: 0,
        onChanged: (v) {
          p.begin();
          p.write(p.e.withBase(depth: v / 100));
        },
        onCommit: p.commit,
      ),
      const CanvasHint("Depth is how far behind the page it is, to 100, or "
          "in front of it, to -100, as the Camera sees it: its depth of "
          "field blurs what is away from its focus, and its parallax moves "
          "the far less and the near more."),
    ];

/// _pageShapeRow is what the element does on the page shape shown: how big
/// its contents are, and whether it keeps a design of its own there.
List<Widget> _pageShapeRow(_Placing p) {
  var e = p.e;
  var shape = shapeKey(p.controller.document.size);
  return [
    // Air, not just a break: what follows is about this ratio.
    const CanvasLineBreak(gap: 8),
    // How big the contents are on this shape: the box stays and type,
    // spacing and padding scale, as a banner headline is a feed line
    // (ElementBase.typeScale). Offered where something inside is measured
    // apart from the box (scalesInside): words, a table's type and padding,
    // a shape's outline, corners, padding and label, a stroke's width and
    // dash. A picture is drawn to its box.
    if (e.scalesInside) ...[
      CanvasStepper(
        key: const ValueKey("elementTypeScale"),
        label: "Scale inside",
        value: e.base.typeScale,
        min: 0.05,
        max: 10,
        decimals: 2,
        step: 0.05,
        defaultValue: 1,
        width: 104,
        onChanged: (v) {
          if (v <= 0 || e.base.typeScale <= 0) return;
          p.begin();
          p.write(e.scaledBy(v / e.base.typeScale).withBase(
                x: e.x,
                y: e.y,
                width: e.width,
                height: e.height,
                typeScale: v,
              ));
        },
        onCommit: p.commit,
      ),
      CanvasHint(_scaleInsideHint(e)),
    ],
    // And the way out of sharing, for an element it cannot carry.
    CanvasToggle(
      key: const ValueKey("elementOwnDesign"),
      label: "Own on ${shapeShort(shape)}",
      value: e.base.ownDesign,
      onChanged: (v) {
        p.begin();
        // The shared design is kept aside while detached.
        p.write(v ? detachedHere(e) : sharedAgain(e));
        p.commit();
      },
    ),
    CanvasHint(e.base.ownDesign
        ? "This element is its own on ${shapeLabel(shape)}: "
            "nothing done to it on another ratio reaches it here, and "
            "nothing done here reaches them. Switch it off and it goes "
            "back to the design the ratios share, laid out for this one."
        : "Give this element its own settings on "
            "${shapeLabel(shape)} alone. "
            "Everything an element *is* — its words, its colours, its "
            "data, its settings — is shared by every ratio; only where "
            "it sits and how big it is belong to one. Switch this on "
            "and this ratio gets a copy of the element to change "
            "freely, and the shared one is kept for the others."),
  ];
}

/// _scaleInsideHint is what Scale inside sizes on [e], in the words of what
/// [e] has inside it.
String _scaleInsideHint(CanvasElement e) => switch (e) {
      ShapeElement() => "Everything inside the box at once, on the shape of "
          "page you are on: the words, the outline, the corners and the "
          "padding. The box itself stays where you put it, and the shape is "
          "drawn to it. Type size on its own is the Label type group's Size "
          "— this is that and the room round it together, which is what "
          "keeps a design looking like itself at another size.",
      StrokedElement() => "The stroke's weight, on the shape of page you are "
          "on: its width and its dashes, and the marks on its ends with "
          "them. Where it runs stays where you put it.",
      _ => "Everything inside the box at once, on the shape of page you "
          "are on: the type, the line spacing, the padding, the corners "
          "and the rules. The box itself stays where you put it. Type "
          "size on its own is the Type group's Size — this is that and "
          "the room round it together, which is what keeps a design "
          "looking like itself at another size.",
    };
