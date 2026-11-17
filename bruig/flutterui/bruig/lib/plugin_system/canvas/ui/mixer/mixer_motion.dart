part of 'mixer_plugins.dart';

// mixer_motion.dart is the Motion view's own cards: a motion device, the slot to add one, the joins between them, and what a modulator moves: part of mixer_plugins.dart, split from it to keep
// that file readable (Ken, 2026-11-12). Its imports are the library's.

// ---- The motion chain

/// MotionDeviceCard is one device of an element's motion chain (see
/// motion_devices.dart) in the Chain's Motion view, as a sound's devices
/// are in its Sound view: its switch, its knobs, a screen of what it does,
/// arrows to move it along its side of the drawing, and a way to take it
/// out.
class MotionDeviceCard extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final String device;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const MotionDeviceCard({
    required this.controller,
    required this.element,
    required this.device,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var all = controller.motionDevicesOf(element);
    var d = all.where((x) => x.id == device).firstOrNull;
    if (d == null) return const SizedBox.shrink();
    var side = [
      for (var x in all)
        if (x.side == d.side) x.id
    ];
    var at = side.indexOf(d.id);
    void write(MotionDevice next, {bool transient = false}) {
      var now = controller.motionDevicesOf(element);
      controller.beginInteraction();
      controller.setMotionDevices(
          element, [for (var x in now) x.id == next.id ? next : x],
          transient: true);
      if (!transient) controller.endInteraction();
    }

    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var pose = d.side == MotionDeviceSide.pose;
    // Which of its knobs an LFO in the chain moves.
    var moved = {
      for (var l in all)
        if (l.on && l.modulates)
          for (var m in l.mods)
            if (m.device == d.id) m.param,
    };
    var accent = pose ? const Color(0xFF6FA8FF) : const Color(0xFFE59BFF);
    // Right-click: move it with a modulator of the element's chain.
    List<(String, VoidCallback)> modMenu(DeviceParam p) {
      if (d.modulates) return const [];
      void moveWith(MotionDevice m, ModTarget t) {
        if (m.mods.any((x) =>
            x.device == t.device && x.param == t.param && x.from == t.from)) {
          return;
        }
        var now = controller.motionDevicesOf(element);
        controller.beginInteraction();
        controller.setMotionDevices(element, [
          for (var x in now) x.id == m.id ? x.withMods([...x.mods, t]) : x
        ]);
        controller.endInteraction();
      }

      // A modulator of its own, made for it, as a sound knob's menu has.
      void added(MotionDeviceKind kind, ModTarget t) {
        var now = controller.motionDevicesOf(element);
        controller.beginInteraction();
        controller.setMotionDevices(
            element,
            motionDevicesInOrder(withMotionDeviceIds(
                [...now, MotionDevice(kind).withMods([t])])));
        controller.endInteraction();
      }

      var macro =
          all.where((m) => m.kind == MotionDeviceKind.macro).firstOrNull;
      return [
        for (var m in all)
          if (m.id != d.id && m.modulates)
            if (m.kind == MotionDeviceKind.macro)
              for (var k = 0; k < macroKnobs; k++)
                (
                  "Turn with ${m.kind.label}'s M${k + 1}",
                  () => moveWith(m, ModTarget(d.id, p.id, 0.5, k))
                )
            else
              (
                "Move with ${m.kind.label}",
                () => moveWith(m, ModTarget(d.id, p.id))
              ),
        if (!p.isChoice) ...[
          (
            "Move it with a new LFO",
            () => added(MotionDeviceKind.lfo, ModTarget(d.id, p.id))
          ),
          (
            "Add it to a macro",
            () {
              if (macro == null) {
                return added(
                    MotionDeviceKind.macro, ModTarget(d.id, p.id, 0.5, 0));
              }
              var used = {for (var t in macro.mods) t.from};
              var k = [for (var k = 0; k < macroKnobs; k++) k]
                      .where((k) => !used.contains(k))
                      .firstOrNull ??
                  0;
              moveWith(macro, ModTarget(d.id, p.id, 0.5, k));
            }
          ),
        ],
        ("Reset", () => write(d.withValue(p.id, p.initial))),
      ];
    }

    var reused = controller.motionOf(element).instances != null;
    // A look on a text can be on one layer of it: see MotionDevice.layer.
    var text = controller.document.elementById(element);
    var layers = d.side == MotionDeviceSide.look && text is TextElement
        ? textLayerChoices(text)
        : null;
    // With copies picked, a knob is theirs: their own value, or the shared
    // one, and turned it becomes their own (Ken, 2026-11-08).
    var copies = controller.copiesPicked(element);
    (double, bool) knobAt(DeviceParam p) =>
        controller.deviceKnob(element, d.id, p.id, d.value(p.id));
    void set(DeviceParam p, double v, {bool transient = false}) {
      // Animated, a turn is a key at the playhead (MotionDevice.keys).
      if (!copies && d.keyed(p.id)) {
        return write(
            d.withKey(p.id, controller.playheadSeconds, v,
                spans: controller.phaseSpansFor(element)),
            transient: transient);
      }
      if (!copies) return write(d.withValue(p.id, v), transient: transient);
      controller.beginInteraction();
      controller.setCopyOwn(element, deviceOwnKey(d.id, p.id), v,
          transient: true);
      if (!transient) controller.endInteraction();
    }

    // A keyed setting is shown as it is at the playhead.
    double shownAt(DeviceParam p) => d.keyed(p.id)
        ? controller.deviceValueNow(element, d, p.id)
        : knobAt(p).$1;

    List<(String, VoidCallback)> keyMenu(DeviceParam p) {
      var t = controller.playheadSeconds;
      return [
        (
          d.keyAt(p.id, t, spans: controller.phaseSpansFor(element))
              ? "Take the key here away"
              : "Key it here",
          () => controller.toggleDeviceKey(element, d.id, p.id)
        ),
        if (d.keyed(p.id))
          (
            "Stop animating it",
            () => controller.stopAnimatingDevice(element, d.id, p.id)
          ),
      ];
    }

    List<(String, VoidCallback)> ownMenu(DeviceParam p) => [
          if (copies && knobAt(p).$2)
            (
              "Back to the shared value",
              () {
                controller.beginInteraction();
                controller.setCopyOwn(element, deviceOwnKey(d.id, p.id), null);
                controller.endInteraction();
              }
            ),
        ];
    List<Widget> knobs(DeviceTier tier) => [
          for (var p in d.kind.params)
            if (!p.isChoice && motionParamShown(d, p, reused: reused))
              // A diamond on its corner keys it at the playhead, or takes
              // the key there away, as the prototype's (Ken, 2026-11-11):
              // keyframing is done here, in the Chain.
              Stack(clipBehavior: Clip.none, children: [
              _Knob(
                key: ValueKey("mdev-${d.id}-${p.id}"),
                modulated: moved.contains(p.id),
                own: knobAt(p).$2,
                // Keyed, it shows the dot a lane's setting does.
                automated: d.keyed(p.id),
                menu: [...keyMenu(p), ...ownMenu(p), ...modMenu(p)],
                label: p.label,
                text: p.reading(shownAt(p)),
                value: shownAt(p),
                initial: p.initial,
                range: _Range(p.min, p.max),
                step: paramStep(p),
                size: switch (tier) {
                  DeviceTier.large => 46,
                  DeviceTier.medium => 38,
                  _ => 30,
                },
                reading: true,
                accent: accent,
                ink: skin.ink,
                bipolar: p.min < 0 && p.max > 0,
                onChanged: (v, {transient = false}) =>
                    set(p, v, transient: transient),
                onCommit: controller.endInteraction,
              ),
              Positioned(
                top: -2,
                right: -2,
                child: GestureDetector(
                  key: ValueKey("mdevKey-${d.id}-${p.id}"),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => controller.toggleDeviceKey(element, d.id, p.id),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: IconTheme(
                      data: IconThemeData(
                          color: d.keyed(p.id)
                              ? const Color(0xFFF2C14E)
                              : skin.ink.withValues(alpha: 0.45)),
                      child: KeyDiamond(
                          filled: d.keyAt(p.id, controller.playheadSeconds,
                              spans: controller.phaseSpansFor(element)),
                          size: 10),
                    ),
                  ),
                ),
              ),
              ]),
          // What an LFO moves: any knob of the element's other devices.
          if (d.modulates)
            ModTargets(
              key: ValueKey("mdevMods-${d.id}"),
              mods: d.mods,
              sources: d.kind == MotionDeviceKind.macro
                  ? [for (var i = 1; i <= macroKnobs; i++) "M$i"]
                  : const [],
              knobs: [
                for (var x in all)
                  if (x.id != d.id && !x.modulates)
                    for (var p in x.kind.params)
                      if (!p.isChoice)
                        (x.id, p.id, "${x.kind.label} · ${p.label}"),
              ],
              ink: skin.ink,
              onChanged: (mods, {transient = false}) =>
                  write(d.withMods(mods), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // Its choices, and what it follows or looks at: dropdowns side by
          // side under its knobs, as the prototype's Seed and Follows.
          if (d.takesTarget ||
              layers != null ||
              d.kind.params.any(
                  (p) => p.isChoice && motionParamShown(d, p, reused: reused)))
            DevicePack(key: ValueKey("mdevPack-${d.id}"), children: [
              // What of a text it is laid on: all of it, its words, or one
              // piece (MotionDevice.layer).
              if (layers != null)
                StudioDrop<String>(
                  key: ValueKey("mdevLayer-${d.id}"),
                  label: "On",
                  value: layers.any((l) => l.$1 == d.layer) ? d.layer : "",
                  options: layers,
                  onChanged: (v) => write(d.withLayer(v)),
                ),
              for (var p in d.kind.params)
                if (p.isChoice && motionParamShown(d, p, reused: reused))
                  StudioDrop<int>(
                    key: ValueKey("mdev-${d.id}-${p.id}"),
                    label: knobAt(p).$2 ? "${p.label} · its own" : p.label,
                    value: knobAt(p).$1.round(),
                    options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                    onChanged: (i) => set(p, i.toDouble()),
                  ),
              if (d.takesTarget)
                StudioDrop<String>(
                  key: ValueKey("mdevTarget-${d.id}"),
                  label: switch (d.kind) {
                    MotionDeviceKind.followPath => "Path",
                    MotionDeviceKind.followSound ||
                    MotionDeviceKind.follower =>
                      "Channel",
                    MotionDeviceKind.spring => "Chases",
                    _ => "Looks at",
                  },
                  value: d.target,
                  options: [
                    ("", "Nothing"),
                    // Facing the camera, wherever it is pointed.
                    if (d.kind == MotionDeviceKind.lookAt) ...[
                      (lookAtCamera, "The camera"),
                      (lookAtPointer, "The pointer"),
                    ],
                    // A sound follows a channel's loudness.
                    if (d.kind == MotionDeviceKind.followSound ||
                        d.kind == MotionDeviceKind.follower)
                      for (var ch in controller.timelineChannels)
                        (ch.key, ch.name)
                    else
                      for (var x in controller.document.elements)
                        if (x.id != element &&
                            (d.kind != MotionDeviceKind.followPath ||
                                x is PathElement ||
                                x is LineElement))
                          (x.id, x.name.isEmpty ? x.id : x.name),
                  ],
                  onChanged: (v) => write(d.withTarget(v)),
                ),
            ]),
          if (d.side == MotionDeviceSide.look &&
              d.kind != MotionDeviceKind.colour &&
              d.kind != MotionDeviceKind.blur)
            _LookColour(
                key: ValueKey("mdevColour-${d.id}"),
                colour: d.colour,
                ink: skin.ink,
                onPick: (c) => write(d.withColour(c))),
        ];
    return DeviceFrame(
      id: "mdev:${d.id}",
      title: d.kind.label,
      help: motionAbout(d.kind),
      // Its presets, as a sound device's: Default, those saved of its
      // kind, and Save -- a preset's knobs put on, its target kept.
      barExtras: [
        _StripPresetPicker(
          key: ValueKey("mdevPreset-${d.id}"),
          label: d.kind.label,
          kept: () => [
            for (var p in devicePresets.presets)
              if (motionPresetOf(p.data) case var m? when m.kind == d.kind)
                (p.name, p.data["motion"] as Map<String, dynamic>),
          ],
          name: controller.presetNameOf(element, "mdev:${d.id}"),
          builtIn: const [],
          onPick: (name, value) {
            var m = MotionDevice.fromJson(value);
            if (m == null) return;
            var next = d;
            for (var p in d.kind.params) {
              next = next.withValue(p.id, m.value(p.id));
            }
            write(next);
            controller.setPresetName(element, "mdev:${d.id}", name);
          },
          onDefault: () {
            write(MotionDevice(d.kind, on: d.on)
                .withId(d.id)
                .withTarget(d.target)
                .withLayer(d.layer)
                .withMods(d.mods));
            controller.setPresetName(element, "mdev:${d.id}", null);
          },
          onSave: () => saveMotionPreset(context, d),
        ),
      ],
      onSavePreset: () => saveMotionPreset(context, d),
      // A copy beside it, and its settings back as they began.
      onDuplicate: () {
        var now = controller.motionDevicesOf(element);
        var i = now.indexWhere((x) => x.id == d.id);
        if (i < 0) return;
        controller.beginInteraction();
        controller.setMotionDevices(
            element, withMotionDeviceIds([...now]..insert(i + 1, d.withId(""))));
        controller.endInteraction();
      },
      onReset: () {
        var fresh = MotionDevice(d.kind, on: d.on).withId(d.id);
        controller.beginInteraction();
        controller.setMotionDevices(element, [
          for (var x in controller.motionDevicesOf(element))
            x.id == d.id
                ? fresh.withTarget(d.target).withLayer(d.layer).withMods(d.mods)
                : x
        ]);
        controller.endInteraction();
      },
      // A second set of its knobs to compare, as a sound device's A|B.
      onAB: () => controller.toggleABOf("$element|mdev:${d.id}", d,
          (o) => write((o as MotionDevice).switched(d.on).withTarget(d.target),
              transient: true)),
      showingB: controller.showingBOf("$element|mdev:${d.id}"),
      // What it does made keys, for an EPUB, and it switched off.
      extraMenu: pose &&
              d.on &&
              !d.modulates &&
              d.kind != MotionDeviceKind.follower
          ? (look) => [
                chainMenuItem(look,
                    key: ValueKey("mdevBake-${d.id}"),
                    text: "Bake into keys",
                    hint: "for EPUB", onPressed: () {
                  var why = controller.bakeMotionDevice(element, d.id);
                  try {
                    var snack = SnackBarModel.of(context);
                    why == null
                        ? snack.success("Baked: the ${d.kind.label} is keys "
                            "in a clip now, and switched off")
                        : snack.error(why);
                  } catch (_) {}
                }),
              ]
          : null,
      skin: skin,
      on: d.on,
      onPower: (v) => write(d.switched(v)),
      powerKey: ValueKey("mdevPower-${d.id}"),
      folded: folded,
      onFold: onFold,
      // As wide as its knobs on one row, and room for two dropdowns.
      // Wide enough for its presets' mark beside its name and its A|B.
      width: math.max(
          280.0,
          16.0 +
              58 *
                  d.kind.params.where((p) => !p.isChoice).length *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5)),
      height: height,
      icon: pose ? Icons.timer_outlined : Icons.auto_awesome,
      accent: accent,
      besideDisplay: 250,
      besideSettings: 200,
      actions: [
        DeviceMove(
            id: "mdev-${d.id}",
            canLeft: at > 0,
            canRight: at < side.length - 1,
            onMove: (by) => controller.moveMotionDevice(element, d.id, by),
            ink: _headerInkLight),
        IconButton(
          key: ValueKey("mdevRemove-${d.id}"),
          tooltip: "Take the ${d.kind.label.toLowerCase()} off",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: _headerInkLight),
          onPressed: () => controller.removeMotionDevice(element, d.id),
        ),
      ],
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: knobs,
      // A screen where there is something to show without the element:
      // a look on a square, Time's curve, a wave's shape.
      // Every kind has one now (Ken, 2026-11-08: the motion chain as
      // usable as the sound's): its settings drawn.
      display: SizedBox.expand(
        child: CustomPaint(
            key: ValueKey("mdevScreen-${d.id}"),
            painter: _MotionScreen(d, look.studio.display, accent)),
      ),
      summary: [
        for (var p in d.kind.params.take(2))
          "${p.label} ${p.reading(d.value(p.id))}"
      ].join(" · "),
    );
  }
}

/// _LookColour is the colour a look draws in: its own (none chosen), or
/// one of a few.
class _LookColour extends StatelessWidget {
  final int? colour;
  final Color ink;
  final ValueChanged<int?> onPick;
  const _LookColour(
      {required this.colour,
      required this.ink,
      required this.onPick,
      super.key});

  static const _choices = <int?>[
    null,
    0xFF000000,
    0xFFFFFFFF,
    0xFFFFD54F,
    0xFFFF5252,
    0xFF40C4FF,
    0xFF69F0AE,
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 92,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Colour", style: TextStyle(fontSize: 11, color: ink)),
          const SizedBox(height: 4),
          Wrap(spacing: 3, runSpacing: 3, children: [
            for (var c in _choices)
              Tooltip(
                message: c == null ? "Its own" : "",
                child: InkWell(
                  key: ValueKey("lookColour-${c ?? "own"}"),
                  onTap: () => onPick(c),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: c == null ? null : Color(c),
                      gradient: c == null
                          ? const SweepGradient(colors: [
                              Color(0xFFFF5252),
                              Color(0xFFFFD54F),
                              Color(0xFF69F0AE),
                              Color(0xFF40C4FF),
                              Color(0xFFFF5252),
                            ])
                          : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: colour == c ? ink : ink.withValues(alpha: 0.3),
                          width: colour == c ? 2 : 1),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );
}

/// _MotionScreen is a motion device's screen: a look drawn on a square, as
/// it would be on the element; Time, the moment it asks for against the
/// moment it is.
class _MotionScreen extends CustomPainter {
  final MotionDevice device;
  final Color back, accent;
  _MotionScreen(this.device, this.back, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    if (size.width < 8 || size.height < 8) return;
    if (device.kind == MotionDeviceKind.wiggle ||
        device.kind == MotionDeviceKind.oscillate) {
      // Four seconds of what it adds, across.
      var path = Path();
      var amount = device.value("amount");
      double at(double t) => device.kind == MotionDeviceKind.oscillate
          ? math.sin(
              2 * math.pi * (device.value("rate") * t + device.value("phase")))
          : (math.sin(t * device.value("speed") * 2.1) * 0.5 +
              math.sin(t * device.value("speed") * 4.7 + 1.3) * 0.3 +
              math.sin(t * device.value("speed") * 9.3 + 2.1) * 0.2);
      var reach = amount <= 0 ? 0.0 : 0.42;
      for (var i = 0; i <= 160; i++) {
        var x = size.width * i / 160;
        var y = size.height * (0.5 - at(4.0 * i / 160) * reach);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = device.on ? accent : accent.withValues(alpha: 0.4));
      return;
    }
    var ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = device.on ? accent : accent.withValues(alpha: 0.4);
    var faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.2);
    var w = size.width, h = size.height;
    Path curve(double Function(double u) y, {int steps = 120}) {
      var path = Path();
      for (var i = 0; i <= steps; i++) {
        var u = i / steps;
        i == 0 ? path.moveTo(u * w, y(u)) : path.lineTo(u * w, y(u));
      }
      return path;
    }

    switch (device.kind) {
      case MotionDeviceKind.spring:
        // A step: where its keys go (the dashed line), and it overshooting
        // and settling there.
        var k = device.value("stiffness"), damp = device.value("damping");
        var top = h * 0.25, bottom = h * 0.82;
        canvas.drawLine(Offset(0, top), Offset(w, top), faint);
        canvas.drawPath(
            curve((u) {
              var t = u * 2.5;
              var settle = 1 -
                  math.exp(-t * damp * k * 0.5) * math.cos(t * k * 0.9);
              return bottom - (bottom - top) * settle;
            }),
            ink);
        return;
      case MotionDeviceKind.squash:
        // A ball as it lands: squashed by Amount, more the faster.
        var a = device.value("amount") * (0.4 + 0.6 * device.value("bySpeed"));
        var r = math.min(w, h) * 0.22;
        var floor = h * 0.85;
        canvas.drawLine(Offset(8, floor), Offset(w - 8, floor), faint);
        for (var (i, sq) in [0.0, a * 0.5, a].indexed) {
          var cx = w * (0.22 + 0.28 * i);
          var rw = r * (1 + sq * 0.6), rh = r * (1 - sq * 0.5);
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(cx, floor - rh), width: rw * 2, height: rh * 2),
              ink..style = i == 2 ? PaintingStyle.fill : PaintingStyle.stroke);
        }
        return;
      case MotionDeviceKind.followPath:
        // A path, and where along it it starts.
        Offset at(double u) => Offset(
            w * (0.1 + 0.8 * u), h * (0.5 - math.sin(u * 2 * math.pi) * 0.3));
        var path = Path()..moveTo(at(0).dx, at(0).dy);
        for (var i = 1; i <= 60; i++) {
          path.lineTo(at(i / 60).dx, at(i / 60).dy);
        }
        canvas.drawPath(path, faint..strokeWidth = 2);
        var start = at(device.value("start"));
        canvas.drawCircle(start, 6,
            Paint()..color = device.on ? accent : accent.withValues(alpha: 0.4));
        if (device.target.isEmpty) _say(canvas, size, "Pick a path below");
        return;
      case MotionDeviceKind.lookAt:
        // It, turned to face what it looks at, with its offset.
        var me = Offset(w * 0.3, h * 0.6), them = Offset(w * 0.78, h * 0.3);
        canvas.drawCircle(them, 5, Paint()..color = accent.withValues(alpha: 0.5));
        var a = math.atan2(them.dy - me.dy, them.dx - me.dx) +
            device.value("offset") * math.pi / 180;
        var tip = me + Offset(math.cos(a), math.sin(a)) * math.min(w, h) * 0.3;
        canvas.drawLine(me, tip, ink);
        canvas.drawCircle(me, 7, ink..style = PaintingStyle.fill);
        if (device.target.isEmpty) _say(canvas, size, "Pick what it looks at");
        return;
      case MotionDeviceKind.followSound || MotionDeviceKind.follower:
        // A sound coming and going (faint) and it rising after it,
        // smoothed as set.
        var smooth = device.value("smooth");
        double loud(double u) =>
            (math.sin(u * 19) * 0.5 + 0.5) * (u % 0.33 < 0.2 ? 1 : 0.15);
        canvas.drawPath(curve((u) => h * 0.9 - loud(u) * h * 0.7), faint);
        var env = 0.0, k = 1 - smooth * 0.95;
        canvas.drawPath(
            curve((u) {
              env += (loud(u) - env) * k * 0.25;
              return h * 0.9 - env * h * 0.7;
            }),
            ink);
        if (device.target.isEmpty) _say(canvas, size, "Pick a channel below");
        return;
      case MotionDeviceKind.lfo:
        // Two of its cycles in its shape.
        var shape = device.value("shape").round(),
            phase = device.value("phase");
        canvas.drawPath(
            curve((u) => h / 2 - lfoValue(shape, 2 * u + phase) * (h / 2 - 6)),
            ink);
        return;
      case MotionDeviceKind.macro:
        // Its knobs as bars, as far as each is turned.
        var bar = (w - 10) / macroKnobs;
        for (var i = 0; i < macroKnobs; i++) {
          var full = Rect.fromLTWH(5 + i * bar + 3, 8, bar - 6, h - 16);
          canvas.drawRect(full, Paint()..color = accent.withValues(alpha: 0.15));
          var up = device.value("m${i + 1}");
          canvas.drawRect(
              Rect.fromLTRB(full.left, full.bottom - full.height * up,
                  full.right, full.bottom),
              Paint()..color = accent);
        }
        return;
      default:
        break;
    }
    if (device.kind == MotionDeviceKind.time) {
      // Eight seconds along; the moment asked for, up the side.
      const span = 8.0;
      var grid = Paint()..color = accent.withValues(alpha: 0.15);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), grid);
      var path = Path();
      for (var i = 0; i <= 120; i++) {
        var t = span * i / 120;
        var y = size.height -
            (retimed(device, t) / span).clamp(0.0, 1.0) * size.height;
        var x = size.width * i / 120;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = device.on ? accent : accent.withValues(alpha: 0.4));
      return;
    }
    // A look is shown on a page, as it would mostly be seen: a shadow in its
    // own black would vanish on the dark screen.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE9E6DF));
    var side = math.min(size.width, size.height) * 0.42;
    var box = Rect.fromCenter(
        center: size.center(Offset.zero), width: side, height: side);
    void square() => canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(side * 0.12)),
        Paint()..color = accent);
    if (!device.on) return square();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintWithLooks(canvas, box, [device],
        (on) => on.drawRRect(
            RRect.fromRectAndRadius(box, Radius.circular(side * 0.12)),
            Paint()..color = accent));
    canvas.restore();
  }

  /// _say writes [text] small at the foot: what it is waiting for.
  void _say(Canvas canvas, Size size, String text) {
    var tp = TextPainter(
        text: TextSpan(
            text: text,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8E8A9C))),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: size.width - 12);
    tp.paint(canvas, Offset(6, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(_MotionScreen old) =>
      old.device != device || old.back != back || old.accent != accent;
}

/// AddMotionDeviceSlot puts a move (or a look, by [side]) on [element]'s
/// motion chain: the chain's "+".
class AddMotionDeviceSlot extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final MotionDeviceSide side;
  final double height;
  const AddMotionDeviceSlot(
      {required this.controller,
      required this.element,
      required this.side,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var pose = side == MotionDeviceSide.pose;
    return AddSlot(
      id: pose ? "addMoveOpen" : "addLookOpen",
      title: pose ? "Add a move" : "Add a look",
      height: height,
      // By family, as the sound chain's "+" lists them.
      groups: [
        for (var family in {
          for (var k in MotionDeviceKind.on(side)) motionFamily(k),
        })
          (
            family,
            [
              for (var k in MotionDeviceKind.on(side))
                if (motionFamily(k) == family)
                  (
                    "addMotion-${k.name}",
                    k.label,
                    () {
                      controller.beginInteraction();
                      controller.addMotionDevice(element, k);
                      controller.endInteraction();
                    }
                  ),
            ]
          ),
      ],
    );
  }
}

/// MotionJoin is the join after the first [upto] pose devices of
/// [element]'s motion chain -- after its clips, for nought: how fast it is
/// going there, as a bar and in its tooltip with its pose; clicked, the
/// stage shows the element as the chain leaves it there ("Preview from
/// here"), and clicked again, whole.
class MotionJoin extends StatefulWidget {
  final CanvasController controller;
  final String element;
  final int upto;
  final double height;
  const MotionJoin(
      {required this.controller,
      required this.element,
      required this.upto,
      required this.height,
      super.key});

  @override
  State<MotionJoin> createState() => _MotionJoinState();
}

class _MotionJoinState extends State<MotionJoin>
    with SingleTickerProviderStateMixin, _Metered {
  @override
  CanvasController get meteredBy => widget.controller;

  double _speed = 0;
  Keyframe _pose = Keyframe.rest;

  @override
  void tick() {
    var c = widget.controller;
    var e = c.document.elementById(widget.element);
    if (e == null) return;
    var (speed, pose) = motionSpeedAt(e, c.frame, c.document,
        upto: widget.upto, live: c.liveMotion);
    _speed = speed;
    _pose = pose;
  }

  /// _hover is whether the pointer is on it: only then is it wide, its
  /// eye shown -- thin between the cards otherwise (Ken, 2026-11-12).
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Read again on every build too -- a frame scrubbed to, the chain
    // changed -- as the ticker rests while nothing plays.
    tick();
    var c = widget.controller;
    var look = MixerLook.of(context);
    var on = c.motionPreview == (widget.element, widget.upto);
    // A thousand pixels a second fills it; slower is more than its share,
    // so a drift still shows.
    var fill = (math.log(1 + _speed) / math.log(1001)).clamp(0.0, 1.0);
    return Tooltip(
      message: "x ${_pose.dx.round()} · y ${_pose.dy.round()} · "
          "size ${_pose.scale.toStringAsFixed(2)} · turn ${_pose.rotate.round()}° · "
          "${_speed.round()} px/s\n"
          "${on ? "Showing it as it is here. Click to show it whole." : "Click to show it on the stage as it is here."}",
      // A right click: preview from here, or with its trail on the stage
      // as well, as the prototype's join menu.
      child: MenuAnchor(
        style: chainMenuStyle(look),
        menuChildren: [
          chainMenuItem(look,
              key: ValueKey("motionJoinPreview-${widget.upto}"),
              text: on ? "Show the whole chain again" : "Preview from here",
              hint: "on the canvas",
              onPressed: () =>
                  c.previewMotionFrom(widget.element, on ? null : widget.upto)),
          chainMenuItem(look,
              key: ValueKey("motionJoinTrail-${widget.upto}"),
              text: "Preview from here, with its trail", onPressed: () {
            c.motionTrail = true;
            c.previewMotionFrom(widget.element, widget.upto);
          }),
        ],
        builder: (context, menu, _) => GestureDetector(
          onSecondaryTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: InkWell(
            key: ValueKey("motionJoin-${widget.upto}"),
            onTap: () =>
                c.previewMotionFrom(widget.element, on ? null : widget.upto),
            child: Container(
              width: on || _hover ? 22 : 10,
              height: widget.height,
              padding: EdgeInsets.symmetric(
                  vertical: 8, horizontal: on || _hover ? 6 : 3),
              decoration: BoxDecoration(
                color: on ? look.colors.primary.withValues(alpha: 0.25) : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(children: [
                if (on || _hover) ...[
                  Icon(on ? Icons.visibility : Icons.visibility_outlined,
                      size: 11,
                      color: on ? look.colors.primary : look.studio.muted),
                  const SizedBox(height: 4),
                ],
                Expanded(
                  child: Container(
                    width: on || _hover ? 6 : 4,
                    alignment: Alignment.bottomCenter,
                    decoration: BoxDecoration(
                      color: look.studio.display,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      key: ValueKey("motionJoinBar-${widget.upto}"),
                      heightFactor: fill,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF6FA8FF),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// modulationColour marks what a modulator moves: a knob's ring.
const Color modulationColour = Color(0xFFFF6FB5);

/// ownColour marks a copy's own value: a knob's arc and its dot.
const Color ownColour = Color(0xFFE2B04A);

/// ModTargets is what a modulator moves: each knob, by its device and its
/// name, with how far it moves it and a way to take it off, and a way to
/// add another of [knobs] -- (device id, setting, name) each.
class ModTargets extends StatelessWidget {
  final List<ModTarget> mods;
  final List<(String, String, String)> knobs;

  /// sources are a macro's knobs, by name, each target turned by one;
  /// empty for a modulator of one.
  final List<String> sources;
  final Color ink;
  final void Function(List<ModTarget> mods, {bool transient}) onChanged;
  final VoidCallback onCommit;
  const ModTargets(
      {required this.mods,
      required this.knobs,
      required this.ink,
      required this.onChanged,
      required this.onCommit,
      this.sources = const [],
      super.key});

  @override
  Widget build(BuildContext context) {
    var style = TextStyle(fontSize: 11, color: ink);
    String nameOf(ModTarget m) =>
        knobs
            .where((k) => k.$1 == m.device && k.$2 == m.param)
            .firstOrNull
            ?.$3 ??
        "Gone";
    var free = [
      for (var k in knobs)
        if (!mods.any((m) => m.device == k.$1 && m.param == k.$2)) k,
    ];
    return SizedBox(
      width: 230,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Moves", style: style.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (var (i, m) in mods.indexed)
              Row(key: ValueKey("modTarget-$i"), children: [
                Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: const BoxDecoration(
                        color: modulationColour, shape: BoxShape.circle)),
                // Which of a macro's knobs turns it.
                if (sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: CanvasDropdown<int>(
                      key: ValueKey("modFrom-$i"),
                      label: "",
                      value: m.from.clamp(0, sources.length - 1),
                      width: 64,
                      grow: false,
                      tight: true,
                      options: [
                        for (var (k, name) in sources.indexed) (k, name)
                      ],
                      onChanged: (k) =>
                          onChanged([...mods]..[i] = m.withFrom(k)),
                    ),
                  ),
                Expanded(
                  child: Text(nameOf(m),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style),
                ),
                _Knob(
                  key: ValueKey("modDepth-$i"),
                  label: "",
                  text: "${(m.depth * 100).round()}%",
                  value: m.depth,
                  initial: 0.5,
                  range: const _Range(-1, 1),
                  size: 22,
                  reading: false,
                  accent: modulationColour,
                  ink: ink,
                  bipolar: true,
                  onChanged: (v, {transient = false}) => onChanged(
                      [...mods]..[i] = m.withDepth(v),
                      transient: transient),
                  onCommit: onCommit,
                ),
                IconButton(
                  key: ValueKey("modRemove-$i"),
                  tooltip: "Stop moving it",
                  iconSize: 13,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: ink),
                  onPressed: () => onChanged([...mods]..removeAt(i)),
                ),
              ]),
            if (free.isNotEmpty)
              CanvasDropdown<String>(
                key: const ValueKey("modAdd"),
                label: "Add",
                value: "",
                width: 200,
                grow: false,
                options: [
                  ("", "Move a knob…"),
                  for (var k in free) ("${k.$1}|${k.$2}", k.$3),
                ],
                onChanged: (v) {
                  if (v.isEmpty) return;
                  var cut = v.indexOf("|");
                  onChanged([
                    ...mods,
                    ModTarget(v.substring(0, cut), v.substring(cut + 1)),
                  ]);
                },
              )
            else if (knobs.isEmpty)
              Text("Nothing in the chain to move yet", style: style),
          ]),
    );
  }
}
