part of 'mixer_plugins.dart';

// DeviceFrame, one device in the chain with its bar, body and folding, and the
// power switch and arrows on its bar. Part of mixer_plugins.dart.

/// DeviceFrame is one device in the chain: a bar along the top with its
/// fold arrow, its power switch and its name, and under it the device -- or,
/// folded, its name down the side and [folded], a meter or a reading.
class DeviceFrame extends StatelessWidget {
  /// id names the device in keys: device-[id], deviceFold-[id].
  final String id;
  final String title;
  final DeviceSkin skin;

  /// on is whether it is switched on, or null for a device with no switch.
  final bool? on;
  final ValueChanged<bool>? onPower;
  final Key? powerKey;
  final bool folded;
  final VoidCallback onFold;

  /// width is the device's width open, before scaling; height the room the
  /// chain gives it; drawnHeight the height it is drawn at and scaled from
  /// (deviceHeight for a unit, whose dials keep their places; the room
  /// itself for a form, which keeps its text's size and scrolls).
  final double width;
  final double height;
  final double drawnHeight;
  final Widget body;
  final Widget foldedBody;
  final List<Widget> actions;

  /// controls, given, lays the device out for its height rather than
  /// scaling it (see DeviceTier): [display] over its knobs -- the knobs
  /// [controls] gives for the tier -- with [footer] under them when tall,
  /// and only [summary] when short. [body] is then not used.
  final List<Widget> Function(DeviceTier tier)? controls;

  /// lead is what comes first on the card, over its screen: what the rest
  /// of it is about (the Motion clips card's own arrival, loop and leaving).
  final List<Widget> lead;

  /// display is what the device is doing, over its knobs in the height left.
  final Widget? display;
  final List<Widget> footer;
  final String summary;

  /// icon and accent are its family's mark: see deviceGroupLook.
  final IconData? icon;
  final Color? accent;

  /// help is what it does, behind a "?" at the right of its bar, read when
  /// clicked: the Chain shows no tips on hover. Empty for none.
  final String help;

  /// glows is whether it makes the sound (an instrument, the Generator):
  /// its edge and a glow in its colour.
  final bool glows;

  /// onDuplicate and onReset, given, are its ⋯ menu's Duplicate (a copy
  /// after it) and Reset every setting (its settings as a new one's).
  final VoidCallback? onDuplicate;
  final VoidCallback? onReset;

  /// onSavePreset, given, is its ⋯ menu's Save as a preset.
  final VoidCallback? onSavePreset;

  /// onAB, given, is its bar's A|B: its settings swapped with a second set
  /// to compare by ear; [showingB] which is heard.
  final VoidCallback? onAB;
  final bool showingB;

  /// extraMenu are more of its ⋯ menu's items, after Reset: its own
  /// settings that are not knobs (Oversample, Works on, Listens to).
  final List<Widget> Function(MixerLook look)? extraMenu;

  /// barExtras sit on its bar before A|B: its preset and its level change.
  final List<Widget> barExtras;

  /// frozen is whether it is in the part of its chain frozen into the
  /// channel's sounds (see CanvasController.freezeChain): shown as frozen,
  /// and not to be changed until unfrozen. onFreeze, given, freezes the
  /// chain up to it; onUnfreeze puts the chain back.
  final bool frozen;
  final VoidCallback? onFreeze;
  final VoidCallback? onUnfreeze;

  /// besideDisplay, given, is how wide its display is on a short card
  /// (beside its settings, the full height), and besideSettings how wide
  /// those settings are, packed rather than in one row that scrolls.
  final double? besideDisplay;
  final double besideSettings;

  /// displayBeside puts [display] beside the settings at every height but
  /// the strip, not only a short one's: a list, which wants height more
  /// than width (the Instances card's copies).
  final bool displayBeside;

  const DeviceFrame({
    required this.id,
    required this.title,
    required this.skin,
    required this.folded,
    required this.onFold,
    required this.width,
    required this.height,
    required this.body,
    required this.foldedBody,
    this.drawnHeight = deviceHeight,
    this.on,
    this.onPower,
    this.powerKey,
    this.actions = const [],
    this.controls,
    this.lead = const [],
    this.display,
    this.footer = const [],
    this.summary = "",
    this.icon,
    this.accent,
    this.glows = false,
    this.help = "",
    this.onDuplicate,
    this.onReset,
    this.onSavePreset,
    this.onAB,
    this.showingB = false,
    this.extraMenu,
    this.barExtras = const [],
    this.frozen = false,
    this.onFreeze,
    this.onUnfreeze,
    this.besideDisplay,
    this.besideSettings = 220,
    this.displayBeside = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (controls != null) return _tiered(context);
    // The bar as every card's, at its own size; only what is under it is
    // drawn at the device's size and scaled to the room.
    var tier = DeviceTier.of(height);
    var barHeight = ChainPanelStyle.on(context)
        ? 40.0
        : tier == DeviceTier.small || tier == DeviceTier.strip
            ? 24.0
            : 28.0;
    var header = _bar(context,
        height: barHeight, short: false, full: true, cardWidth: width);
    if (folded) {
      return SizedBox(
        key: ValueKey("device-$id"),
        width: deviceFoldedWidth,
        height: height,
        child: _card(context, header, _foldedInside(context)),
      );
    }
    var drawn = drawnHeight - 28;
    var scale = ((height - barHeight) / drawn).clamp(0.5, 1.5);
    // Never narrower than its bar needs; what is under the bar keeps its
    // shape, scaled to fit.
    return SizedBox(
      key: ValueKey("device-$id"),
      width: math.max(width * scale, 120),
      height: height,
      child: _card(
        context,
        header,
        FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, height: drawn, child: body),
        ),
      ),
    );
  }

  /// _card is the Chain's card round [header] and [inside]: raised, a line
  /// round it, its family's colour on top, faded while switched off.
  Widget _card(BuildContext context, Widget header, Widget inside) {
    var studio = MixerLook.of(context).studio;
    var off = on == false;
    if (ChainPanelStyle.on(context)) {
      // As the settings panel's cards: plain, outlined, faded while off.
      var group = ChainGroupColour.of(context);
      return Container(
        decoration: BoxDecoration(
          color: studio.strip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: studio.edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            if (group != null)
              Container(
                  key: const ValueKey("chainGroupLine"),
                  height: 3,
                  color: group),
            header,
            Expanded(
                child: IgnorePointer(
                    ignoring: frozen,
                    child: Opacity(opacity: off ? 0.5 : 1, child: inside))),
          ]),
        ),
      );
    }
    // The line round it and the colour along its top are drawn over it,
    // taking none of the room its insides had.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [
              0,
              0.14
            ],
            colors: [
              Color.lerp(studio.raised, Colors.white, 0.03)!,
              studio.raised
            ]),
        borderRadius: BorderRadius.circular(9),
        boxShadow: glows && accent != null
            ? [
                BoxShadow(
                    color: accent!.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -6)
              ]
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
            color: glows && accent != null
                ? Color.lerp(accent!, studio.edge, 0.3)!
                : studio.edge),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Column(children: [
            header,
            Expanded(
                child: IgnorePointer(
                    ignoring: frozen,
                    child: Opacity(opacity: off ? 0.55 : 1, child: inside))),
          ]),
          if (frozen && !folded)
            Positioned(
              right: 8,
              bottom: 6,
              child: IgnorePointer(
                child: Container(
                  key: ValueKey("deviceFrozen-$id"),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5AB4E6).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFF5AB4E6).withValues(alpha: 0.6)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.ac_unit, size: 11, color: Color(0xFF9FD4F2)),
                    SizedBox(width: 3),
                    Text("FROZEN",
                        style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: Color(0xFF9FD4F2))),
                  ]),
                ),
              ),
            ),
          if (!folded)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 2,
              child: IgnorePointer(
                child: ColoredBox(
                    color: (accent ?? studio.muted)
                        .withValues(alpha: off ? 0.3 : 0.9)),
              ),
            ),
        ]),
      ),
    );
  }

  /// _inMenu is whether [w] goes behind the bar's ⋯ rather than on it: the
  /// arrows that move a device along the chain, and what takes it out.
  static bool _inMenu(Widget w) {
    if (w is DeviceMove) return true;
    var key = w.key;
    if (key is! ValueKey<String>) return false;
    var k = key.value;
    return k.startsWith("deviceLeft-") ||
        k.startsWith("deviceRight-") ||
        k.startsWith("menu-") ||
        k.contains("Remove");
  }

  /// _menuItems are its ⋯ menu: its name; moving it, a copy and its
  /// settings reset; what else [actions] keeps there; what it does; and,
  /// last, taking it out. The actions keep their keys.
  List<Widget> _menuItems(MixerLook look) {
    var moves = <Widget>[], others = <Widget>[], removes = <Widget>[];
    String? hintOf(VoidCallback? onPressed, bool left) =>
        onPressed != null ? null : (left ? "first" : "last");
    for (var w in actions.where(_inMenu)) {
      if (w is DeviceMove) {
        for (var (left, can) in [(true, w.canLeft), (false, w.canRight)]) {
          VoidCallback? go = !can ? null : () => w.onMove(left ? -1 : 1);
          moves.add(chainMenuItem(look,
              key: ValueKey("deviceMove${left ? "Left" : "Right"}-${w.id}"),
              text: left ? "Move left" : "Move right",
              hint: hintOf(go, left),
              onPressed: go));
        }
      } else if (w is IconButton) {
        var k =
            w.key is ValueKey<String> ? (w.key as ValueKey<String>).value : "";
        var left = k.startsWith("deviceLeft-");
        if (left || k.startsWith("deviceRight-")) {
          moves.add(chainMenuItem(look,
              key: w.key,
              text: left ? "Move left" : "Move right",
              hint: hintOf(w.onPressed, left),
              onPressed: w.onPressed));
        } else if (k.contains("Remove")) {
          removes.add(chainMenuItem(look,
              key: w.key, text: "Remove", onPressed: w.onPressed));
        } else {
          others.add(chainMenuItem(look,
              key: w.key, text: w.tooltip ?? "", onPressed: w.onPressed));
        }
      }
    }
    var top = [
      ...moves,
      if (onDuplicate != null)
        chainMenuItem(look,
            key: ValueKey("deviceDuplicate-$id"),
            text: "Duplicate",
            onPressed: onDuplicate),
      if (onReset != null)
        chainMenuItem(look,
            key: ValueKey("deviceReset-$id"),
            text: "Reset every setting",
            onPressed: onReset),
      ...others,
      ...?extraMenu?.call(look),
    ];
    if (top.isEmpty &&
        removes.isEmpty &&
        onSavePreset == null &&
        onFreeze == null &&
        onUnfreeze == null) {
      return const [];
    }
    return [
      chainMenuHeading(look, title),
      ...top,
      if (help.isNotEmpty ||
          onSavePreset != null ||
          onFreeze != null ||
          onUnfreeze != null)
        chainMenuDivider(look),
      if (onUnfreeze != null)
        chainMenuItem(look,
            key: ValueKey("deviceUnfreeze-$id"),
            text: "Unfreeze the chain",
            onPressed: onUnfreeze)
      else if (onFreeze != null)
        chainMenuItem(look,
            key: ValueKey("deviceFreeze-$id"),
            text: "Freeze the chain up to here",
            hint: "plays a copy",
            onPressed: onFreeze),
      if (onSavePreset != null)
        chainMenuItem(look,
            key: ValueKey("deviceSavePreset-$id"),
            text: "Save as a preset",
            onPressed: onSavePreset),
      if (help.isNotEmpty) ...[
        SubmenuButton(
          key: ValueKey("deviceAbout-$id"),
          style: chainMenuItemStyle(look),
          menuStyle: chainMenuStyle(look),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 240,
                child: Text(help,
                    style: TextStyle(
                        fontSize: 11.5, height: 1.4, color: look.studio.text)),
              ),
            ),
          ],
          child: const Text("What it does"),
        ),
      ],
      if (removes.isNotEmpty) ...[chainMenuDivider(look), ...removes],
    ];
  }

  /// _barRoom is what the bar has room for beside its switch, its mark, a
  /// short name, its A|B, its [buttons] and its ⋯ ([more]) -- measured,
  /// each button its tap target's 48 -- given out in order: a reading (a
  /// gain badge comes and goes with the sound, so its room is kept), the
  /// presets whole or as their mark, then the help, which the ⋯ also says.
  ({bool badges, bool preset, bool compactPreset, bool help}) _barRoom(
      BuildContext context, int buttons, bool more, double cardWidth) {
    var scale = MediaQuery.textScalerOf(context).scale(1);
    var badges = barExtras.where((w) => w is _GainBadge || w is _ReadingBadge);
    var pickers =
        barExtras.where((w) => w is _PresetPicker || w is _StripPresetPicker);
    // Anything else it has there -- a latency, a mark -- always shown.
    var others = barExtras.length - badges.length - pickers.length;
    var room = cardWidth -
        (72 * scale * others +
            10 +
            (on != null ? 25 : 0) +
            (icon != null ? 20 : 0) +
            52 * scale +
            (onAB != null ? 36 : 0) +
            48 * (buttons + (more ? 1 : 0)));
    bool take(double w) {
      if (room < w) return false;
      room -= w;
      return true;
    }

    var hasBadges = badges.isEmpty || take(badges.length * 44 * scale);
    var whole = pickers.isNotEmpty && take(86 * scale);
    var compact = !whole && pickers.isNotEmpty && take(23);
    var help = take(48);
    return (
      badges: hasBadges && badges.isNotEmpty,
      preset: whole,
      compactPreset: compact,
      help: help,
    );
  }

  Widget _bar(BuildContext context,
      {required double height,
      required bool short,
      required bool full,
      double cardWidth = double.infinity}) {
    var studio = MixerLook.of(context).studio;
    var shown = [
      for (var a in actions)
        if (!_inMenu(a)) a
    ];
    var look = MixerLook.of(context);
    var menu = _menuItems(look);
    var bar = _barRoom(context, shown.length, menu.isNotEmpty, cardWidth);
    Widget small(Widget child) => IconButtonTheme(
          data: IconButtonThemeData(
              style: IconButton.styleFrom(
                  foregroundColor: studio.muted,
                  minimumSize: const Size(21, 21),
                  maximumSize: const Size(28, 28),
                  padding: EdgeInsets.zero,
                  iconSize: 14)),
          child: child,
        );
    var panel = ChainPanelStyle.on(context);
    if (folded) {
      return Container(
        height: height,
        alignment: Alignment.center,
        child: on == null
            ? null
            : _Power(on: on!, onPower: onPower!, powerKey: powerKey),
      );
    }
    return Container(
      height: height,
      padding: panel
          ? const EdgeInsets.fromLTRB(10, 0, 4, 0)
          : const EdgeInsets.fromLTRB(8, 0, 2, 0),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: studio.edge.withValues(alpha: 0.7)))),
      child: Row(children: [
        if (on != null) ...[
          _Power(on: on!, onPower: onPower!, powerKey: powerKey),
          const SizedBox(width: 7),
        ],
        if (icon != null && full && !panel) ...[
          chainIconOr(icon!, size: 14, color: accent ?? studio.muted),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Tooltip(
            message: "Fold $title",
            child: GestureDetector(
              key: ValueKey("deviceFold-$id"),
              behavior: HitTestBehavior.opaque,
              onTap: onFold,
              child: Text(panel ? _titled(title) : title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: panel ? 13 : 10.5,
                      letterSpacing: panel ? 0 : 0.6,
                      fontWeight: FontWeight.w600,
                      color: studio.text)),
            ),
          ),
        ),
        // A strip is too narrow for its buttons: they are for a taller panel.
        if (full) ...[
          // Its reading, its presets and A|B; what the bar has no room for
          // left off, in this order: the help (its ⋯ says what it does),
          // then the presets as their mark alone, then the reading.
          ...[
            for (var w in barExtras)
              if (w is _GainBadge || w is _ReadingBadge)
                if (bar.badges) w else const SizedBox.shrink()
              else if (w is _PresetPicker || w is _StripPresetPicker)
                if (bar.preset)
                  w
                else if (bar.compactPreset)
                  _PresetCompact(child: w)
                else
                  const SizedBox.shrink()
              else
                w,
            if (onAB != null)
              _ABSwitch(
                  key: ValueKey("deviceAB-$id"), b: showingB, onTap: onAB!),
          ],
          for (var a in shown) small(a),
          if (help.isNotEmpty && bar.help)
            MenuAnchor(
              style: chainMenuStyle(look),
              builder: (context, controller, _) => small(IconButton(
                key: ValueKey("deviceHelp-$id"),
                icon: const Icon(Icons.help_outline),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              )),
              menuChildren: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 240,
                    child: Text(help,
                        key: ValueKey("deviceHelpText-$id"),
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: look.studio.text)),
                  ),
                ),
              ],
            ),
          if (menu.isNotEmpty)
            MenuAnchor(
              style: chainMenuStyle(look),
              builder: (context, controller, _) => small(IconButton(
                key: ValueKey("deviceMore-$id"),
                tooltip: "Move or remove",
                icon: const Icon(Icons.more_horiz),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              )),
              menuChildren: menu,
            ),
        ],
      ]),
    );
  }

  /// _foldedInside is a folded card: mark and name down a slim column.
  Widget _foldedInside(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    return Tooltip(
      message: "Open $title",
      child: GestureDetector(
        key: ValueKey("deviceFold-$id"),
        behavior: HitTestBehavior.opaque,
        onTap: onFold,
        // What it shows folded (a meter, a curve) at its foot: as much of the
        // card as is left over its name, up to 90. Measured from the card
        // itself: a LayoutBuilder in the column is told nothing of its height.
        child: LayoutBuilder(builder: (context, box) {
          var room = box.maxHeight.isFinite ? box.maxHeight : 200.0;
          var fixed = (icon != null ? 18.0 : 0) + 8 + 6;
          var foot = math.min(
              math.min(90.0, room * 0.4), math.max(0.0, room - fixed - 30));
          return Column(children: [
            if (icon != null) ...[
              const SizedBox(height: 4),
              chainIconOr(icon!, size: 14, color: accent ?? studio.muted),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: studio.text)),
              ),
            ),
            SizedBox(
              width: 26,
              height: math.max(0.0, foot),
              child: ClipRect(child: foldedBody),
            ),
            const SizedBox(height: 6),
          ]);
        }),
      ),
    );
  }

  static bool _isKnob(Widget w) => w is _Knob || w is DeviceKnob;

  /// _isCell is whether [w] takes a cell of a ChainPanelStyle card: a knob,
  /// alone or with its key's diamond on its corner.
  static bool _isCell(Widget w) =>
      _isKnob(w) ||
      (w is Stack && w.children.isNotEmpty && _isKnob(w.children.first));

  /// _besideDisplay is how wide a short card's display is, beside its knobs.
  static const double _besideDisplay = 170;

  /// _titled is a card's name as the settings panel writes one: its first
  /// letter a capital, the rest as given ("MOTION CLIPS" -> "Motion clips").
  static String _titled(String t) {
    if (t.isEmpty || t != t.toUpperCase()) return t;
    var lower = t.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  /// _panelLaid is the device in ChainPanelStyle: its screen, kept small,
  /// over its settings, two or three to a row -- the knobs as steppers,
  /// each a cell; anything else a row of its own.
  Widget _panelLaid(BuildContext context) {
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var tier = DeviceTier.of(height);
    var items = folded
        ? const <Widget>[]
        : controls!(tier == DeviceTier.strip ? DeviceTier.small : tier);
    var leading = folded ? const <Widget>[] : lead;
    var cells = items.where(_isCell).length;
    var columns = cells > 4 ? 3 : 2;
    var cell = 104.0 * scale;
    // A list (its copies, its parts) keeps a column of its own beside the
    // settings, its full height: it is used, not looked at.
    var list = displayBeside && display != null && !folded;
    var listWidth = list ? (besideDisplay ?? 220.0) : 0.0;
    var w = folded
        ? deviceFoldedWidth
        : math.max(math.max(236.0 * scale, width),
                22 + columns * cell + (columns - 1) * 8) +
            (list ? listWidth + 8 : 0);
    var header = _bar(context, height: 40, short: false, full: true, cardWidth: w);
    Widget inside;
    if (folded) {
      inside = _foldedInside(context);
    } else {
      var studio = MixerLook.of(context).studio;
      var room = w - 22 - (list ? listWidth + 8 : 0);
      var each = ((room - (columns - 1) * 8) / columns).floorToDouble();
      inside = LayoutBuilder(builder: (context, box) {
        var settings = SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var k in items)
              SizedBox(width: _isCell(k) ? each : room, child: k),
          ]),
        );
        if (list) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
              child: SizedBox(
                width: listWidth,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: studio.edge),
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(6), child: display),
                ),
              ),
            ),
            Expanded(child: settings),
          ]);
        }
        var screen = display == null
            ? null
            : SizedBox(
                height: math.min(96.0, box.maxHeight * 0.35),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: studio.edge),
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(6), child: display),
                ),
              );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var w in leading) ...[w, const SizedBox(height: 8)],
                if (screen != null) ...[screen, const SizedBox(height: 8)],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var k in items)
                    SizedBox(width: _isCell(k) ? each : room, child: k),
                ]),
                if (footer.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: footer),
                ],
              ]),
        );
      });
    }
    return SizedBox(
      key: ValueKey("device-$id"),
      width: w,
      height: height,
      child: _card(context, header, inside),
    );
  }

  Widget _tiered(BuildContext context) {
    if (ChainPanelStyle.on(context)) return _panelLaid(context);
    var tier = DeviceTier.of(height);
    var short = tier == DeviceTier.small || tier == DeviceTier.strip;
    var barHeight = short ? 24.0 : 28.0;
    // Wider rather than taller: as wide as its knobs need to sit on one row
    // -- the chain scrolls sideways, and has more room across than down.
    var knobCount = folded || tier == DeviceTier.strip
        ? 0
        : controls!(tier).where(_isKnob).length;
    var oneRow = 14.0 + 58 * math.min(knobCount, 9);
    // Short, its display goes beside its knobs, not over them.
    var beside = display != null &&
        (tier == DeviceTier.small ||
            (displayBeside && tier != DeviceTier.strip));
    var packed = beside && besideDisplay != null;
    var textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var w = folded
        ? deviceFoldedWidth
        : tier == DeviceTier.strip
            ? math.min(width, 170.0)
            : packed
                ? besideDisplay! + besideSettings * textScale + 21
                : beside
                    ? math.max(width, _besideDisplay + 50.0 * knobCount + 24)
                    : math.max(width, oneRow);
    var header = _bar(context,
        height: barHeight,
        short: short,
        full: tier != DeviceTier.strip,
        cardWidth: w);
    var studio = MixerLook.of(context).studio;
    Widget inside;
    if (folded) {
      inside = _foldedInside(context);
    } else if (tier == DeviceTier.strip) {
      inside = Padding(
        key: ValueKey("deviceSummary-$id"),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Text(summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: studio.muted)),
      );
    } else {
      var knobs = [...lead, ...controls!(tier)];
      inside = LayoutBuilder(builder: (context, box) {
        // The knobs on an even grid, a column for every 55 pixels of the
        // card (three to seven), each other setting a row of its own; one
        // row of them on a small card, scrolled where it is too long.
        Widget grid;
        if (packed) {
          // Beside a wide display: a knob a cell, the rest the settings'
          // width, wrapping down rather than scrolling along.
          grid = Wrap(spacing: 4, runSpacing: 6, children: [
            for (var k in knobs)
              SizedBox(
                  width: _isKnob(k)
                      ? 50.0 * textScale
                      : besideSettings * textScale - 14,
                  child: k),
          ]);
        } else if (tier == DeviceTier.small) {
          grid = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var (i, k) in knobs.indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    // A knob a cell; any other setting as wide as it
                    // needs, in a row that scrolls.
                    _isKnob(k)
                        ? SizedBox(width: 50, child: k)
                        : SizedBox(
                            width: k is SplitBranches
                                ? SplitBranches.width - 16
                                : 170,
                            child: k),
                  ],
                ]),
          );
        } else {
          var count = knobs.where(_isKnob).length;
          var columns = math.max(((box.maxWidth - 14) / 55).floor().clamp(3, 9),
              math.min(count, 9));
          var rows = <Widget>[];
          var run = <Widget>[];
          void flush() {
            if (run.isEmpty) return;
            rows.add(
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var k in run) Expanded(child: k),
              for (var i = run.length; i < columns; i++)
                const Expanded(child: SizedBox()),
            ]));
            run = [];
          }

          for (var k in knobs) {
            if (_isKnob(k)) {
              run.add(k);
              if (run.length == columns) flush();
            } else {
              flush();
              rows.add(Align(alignment: Alignment.centerLeft, child: k));
            }
          }
          flush();
          grid = Column(mainAxisSize: MainAxisSize.min, children: [
            for (var (i, r) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: 7),
              r,
            ],
          ]);
        }
        // The knobs, as much of them as fits under the display's least;
        // they scroll rather than spill where even that is too much.
        var most = math.max(0.0, box.maxHeight - (display == null ? 0 : 40));
        var below = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: most),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(7, short ? 5 : 8, 7, short ? 5 : 5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                grid,
                if (tier == DeviceTier.large && footer.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: footer),
                ],
              ]),
            ),
          ),
        );
        Widget? screen = display == null
            ? null
            : Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: studio.edge.withValues(alpha: 0.8)),
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(5), child: display),
              );
        if (beside) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 5, 0, 6),
              child: SizedBox(
                  width: besideDisplay ?? _besideDisplay, child: screen),
            ),
            Expanded(
              child: Align(
                // Beside a list, from its top; beside a picture, centred.
                alignment:
                    displayBeside ? Alignment.topLeft : Alignment.centerLeft,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                    child: grid,
                  ),
                ),
              ),
            ),
          ]);
        }
        return Column(children: [
          if (screen != null)
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(7, short ? 5 : 7, 7, 0),
                child: screen,
              ),
            ),
          below,
          if (display == null) const Spacer(),
        ]);
      });
    }
    return SizedBox(
      key: ValueKey("device-$id"),
      width: w,
      height: height,
      child: _card(context, header, inside),
    );
  }

}

class _Power extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onPower;
  final Key? powerKey;
  const _Power({required this.on, required this.onPower, this.powerKey});

  @override
  Widget build(BuildContext context) => ChainPanelStyle.on(context)
      ? Padding(
          padding: const EdgeInsets.only(right: 1),
          child: CanvasSwitch(key: powerKey, value: on, onChanged: onPower))
      : Tooltip(
        message: on ? "On: click to bypass" : "Bypassed: click to switch on",
        child: GestureDetector(
          key: powerKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => onPower(!on),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on
                    ? const RadialGradient(
                        center: Alignment(-0.3, -0.3),
                        colors: [Color(0xFF9BF0A6), Color(0xFF5BC46B)])
                    : null,
                color: on ? null : const Color(0xFF4A4658),
                border: Border.all(color: const Color(0xFF110F22), width: 2),
                boxShadow: on
                    ? const [BoxShadow(color: Color(0x885BC46B), blurRadius: 6)]
                    : null,
              ),
            ),
          ),
        ),
      );
}

/// DeviceMove is a device's arrows moving it along its chain.
class DeviceMove extends StatelessWidget {
  final bool canLeft, canRight;
  final Color ink;
  final String id;

  /// onMove moves it a place along the chain, minus one to the left.
  final void Function(int by) onMove;

  const DeviceMove(
      {required this.id,
      required this.canLeft,
      required this.canRight,
      required this.onMove,
      required this.ink,
      super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var (left, can) in [(true, canLeft), (false, canRight)])
          Tooltip(
            message: left ? "Move earlier in the chain" : "Move later",
            child: GestureDetector(
              key: ValueKey("deviceMove${left ? "Left" : "Right"}-$id"),
              onTap: !can ? null : () => onMove(left ? -1 : 1),
              child: Icon(left ? Icons.chevron_left : Icons.chevron_right,
                  size: 18, color: can ? ink : ink.withValues(alpha: 0.25)),
            ),
          ),
      ]);
}
