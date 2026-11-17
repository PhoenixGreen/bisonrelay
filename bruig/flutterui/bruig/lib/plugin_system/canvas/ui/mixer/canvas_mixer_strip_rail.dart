part of 'canvas_mixer.dart';

// The band rail on the mixer's left, with its bands and their pickers, and the
// tab folding the All group's strips. Part of canvas_mixer.dart.

/// _AllFold is the tab before the All group's strips (the master canvas's,
/// in every scene) that folds them away and back: "All scenes", their count
/// and the arrow, sharing its fold with CanvasController.allFolded.
class _AllFold extends StatelessWidget {
  final CanvasController controller;
  final MixerLook theme;
  final int count;
  const _AllFold(
      {required this.controller, required this.theme, required this.count});

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    var folded = controller.allFolded;
    return Material(
      color: theme.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: const ValueKey("mixerAllFold"),
        borderRadius: BorderRadius.circular(6),
        onTap: () => controller.allFolded = !folded,
        child: SizedBox(
          width: 22,
          child: Column(children: [
            const SizedBox(height: 6),
            Icon(folded ? Icons.chevron_right : Icons.chevron_left,
                size: 14, color: studio.muted),
            const SizedBox(height: 4),
            Text("$count",
                style: TextStyle(fontSize: 9.5, color: studio.muted)),
            const SizedBox(height: 6),
            Expanded(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text("All scenes",
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: studio.text)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// _RailBand is one of the rail's bands: Motion slots (the slot rows'
/// motion parts) or one of the mixer's sections.
class _RailBand {
  final String key;
  final String label;
  final IconData icon;
  final BandState state;
  final bool canMinimise;
  final ValueChanged<BandState> onChoose;

  /// auto is it stepped down for room, below what was chosen: lit amber.
  final bool auto;
  const _RailBand(this.key, this.label, this.icon, this.state, this.onChoose,
      {this.canMinimise = true, this.auto = false});
}

/// _railWidth is the rail open; _railFoldedWidth folded to its strip.
const double _railWidth = 50;

const double _railFoldedWidth = 14;

/// _BandRail is the rail on the mixer's left: a button for each band, its
/// icon and name over three bars of how it shows (three shown, one
/// minimised, none hidden), pressed for Show, Minimise or Hide; under a
/// line, the returns and every column narrow; a "?" at the foot. Its top
/// arrow folds it to a thin strip. Short of height, the names go.
class _BandRail extends StatelessWidget {
  final List<_RailBand> bands;
  final MixerLook theme;
  final bool folded;
  final VoidCallback onFold;
  final bool returnsShown;
  final VoidCallback onReturns;
  final bool allNarrow;
  final VoidCallback onNarrowAll;

  const _BandRail({
    required this.bands,
    required this.theme,
    required this.folded,
    required this.onFold,
    required this.returnsShown,
    required this.onReturns,
    required this.allNarrow,
    required this.onNarrowAll,
  });

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    if (folded) {
      return SizedBox(
        key: const ValueKey("mixerRail"),
        width: _railFoldedWidth,
        child: Align(
          alignment: Alignment.topCenter,
          child: InkWell(
            key: const ValueKey("railFold"),
            onTap: onFold,
            child: SizedBox(
                width: _railFoldedWidth,
                height: 22,
                child:
                    Icon(Icons.chevron_right, size: 12, color: studio.muted)),
          ),
        ),
      );
    }
    return SizedBox(
      key: const ValueKey("mixerRail"),
      width: _railWidth,
      child: LayoutBuilder(builder: (context, box) {
        var named = box.maxHeight >= 330;
        return SingleChildScrollView(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                key: const ValueKey("railFold"),
                onTap: onFold,
                child: SizedBox(
                    width: 22,
                    height: 20,
                    child: Icon(Icons.chevron_left,
                        size: 12, color: studio.muted)),
              ),
            ),
            for (var b in bands) _bandButton(b, named),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1, color: studio.edge),
            ),
            _toggle(
                key: const ValueKey("showReturns"),
                icon: Icons.call_split,
                label: "Returns",
                on: returnsShown,
                named: named,
                onTap: onReturns),
            _toggle(
                key: const ValueKey("narrowAll"),
                icon: Icons.compress,
                label: "Narrow",
                on: allNarrow,
                named: named,
                onTap: onNarrowAll),
            const SizedBox(height: 4),
            const HelpNote(
              id: "mixerRail",
              size: 14,
              title: "What the strips show",
              paragraphs: [
                "These buttons choose what every strip shows, top to bottom: "
                    "the motion slots, the sound slots, the devices, the sends "
                    "and the mixer.",
                "Press one to choose Show, Minimise or Hide. The bars under "
                    "each show which: three for shown, one for minimised, "
                    "none for hidden.",
                "Under the line, Returns shows the return channels beside "
                    "the master, and Narrow makes every strip narrow. The "
                    "arrow at the top folds this column away.",
              ],
            ),
          ]),
        );
      }),
    );
  }

  Widget _bandButton(_RailBand b, bool named) {
    var studio = theme.studio;
    var lit = b.state != BandState.hidden;
    var ink = lit ? studio.text : studio.muted;
    var bars = switch (b.state) {
      BandState.shown => 3,
      BandState.minimised => 1,
      BandState.hidden => 0,
    };
    // A picture of each choice (a strip in small, the band whole, a sliver
    // or gone) and a word on what it does.
    Widget choice(BandState s, String label) => MenuItemButton(
          key: ValueKey("section-${b.key}-${s.name}"),
          style: MenuItemButton.styleFrom(
              padding: const EdgeInsets.all(4),
              backgroundColor: b.state == s ? studio.raised : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                      color: b.state == s ? studio.on : studio.edge))),
          onPressed: () => b.onChoose(s),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
                size: const Size(54, 34),
                painter: _BandPicture(b.key, s, studio)),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: b.state == s ? studio.text : studio.muted)),
          ]),
        );
    var states = [
      (BandState.shown, "Show"),
      if (b.canMinimise) (BandState.minimised, "Minimise"),
      (BandState.hidden, "Hide"),
    ];
    return MenuAnchor(
      style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(studio.panel),
          side: WidgetStatePropertyAll(BorderSide(color: studio.edge))),
      menuChildren: [
        Padding(
          key: ValueKey("railPicker-${b.key}"),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: SizedBox(
            width: 230,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(b.label.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                              color: studio.muted)),
                    ),
                    Builder(
                      builder: (context) => InkResponse(
                        key: ValueKey("railPickerClose-${b.key}"),
                        radius: 12,
                        onTap: () => MenuController.maybeOf(context)?.close(),
                        child: Icon(Icons.close, size: 13, color: studio.muted),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (var (i, (s, label)) in states.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: choice(s, label)),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Text(_bandAbout(b.key),
                      style: TextStyle(
                          fontSize: 11, height: 1.4, color: studio.text)),
                  if (b.auto) ...[
                    const SizedBox(height: 6),
                    Text(
                        key: ValueKey("railPickerAuto-${b.key}"),
                        "Short of height, it shows less for now. It shows as "
                        "chosen again when the mixer is taller.",
                        style: const TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Color(0xFFF6C46A))),
                  ],
                ]),
          ),
        ),
      ],
      builder: (context, menu, _) => InkWell(
        key: ValueKey("section-${b.key}"),
        borderRadius: BorderRadius.circular(4),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(children: [
            Icon(b.icon, size: 14, color: ink),
            if (named)
              Text(b.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  // Stepped down for room: its name amber, as its bars.
                  style: TextStyle(
                      fontSize: 8.5,
                      color: b.auto ? const Color(0xFFF2A33D) : ink)),
            const SizedBox(height: 2),
            Row(
                key: b.auto ? ValueKey("railAuto-${b.key}") : null,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 8,
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      color: i < bars
                          ? (b.auto ? const Color(0xFFF2A33D) : studio.on)
                          : b.auto
                              ? const Color(0x66F2A33D)
                              : studio.edge,
                    ),
                ]),
          ]),
        ),
      ),
    );
  }

  Widget _toggle(
      {required Key key,
      required IconData icon,
      required String label,
      required bool on,
      required bool named,
      required VoidCallback onTap}) {
    var studio = theme.studio;
    var ink = on ? studio.on : studio.muted;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(children: [
          Icon(icon, size: 13, color: ink),
          if (named)
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontSize: 8.5, color: ink)),
        ]),
      ),
    );
  }
}

/// _bandAbout is what a rail band's choice does, said in its picker.
String _bandAbout(String band) => switch (band) {
      "motion" => "Minimised, each motion slot is a thin coloured line over "
          "its sound slot: still pressable, nothing written.",
      "clips" => "Minimised, the slots are short and show only the colour "
          "and the triangle.",
      "devices" => "Minimised, a strip shows how many devices it has, in one "
          "line.",
      "sends" => "The send dials, one per return.",
      _ => "Minimised, the fader is one bar you drag sideways, with the "
          "meter in it.",
    };

/// _BandPicture is a strip in small, for a rail band's picker: [band] shown
/// whole, minimised to a sliver, or gone.
class _BandPicture extends CustomPainter {
  final String band;
  final BandState state;
  final StudioColors studio;
  _BandPicture(this.band, this.state, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var sx = size.width / 54, sy = size.height / 34;
    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy);
    var colour = switch (band) {
      "motion" => const Color(0xFF3FB08D),
      "clips" => const Color(0xFF4F8FD6),
      "devices" => const Color(0xFF9A92EA),
      "sends" => const Color(0xFF8E6BD1),
      _ => const Color(0xFFCFCBDF),
    };
    canvas.drawRRect(
        RRect.fromRectAndRadius(r(1, 1, 52, 32), const Radius.circular(4)),
        Paint()..color = studio.inset);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r(1, 1, 52, 32), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = studio.edge);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r(5, 5, 44, 4), const Radius.circular(1)),
        Paint()..color = studio.edge);
    var h = switch (state) {
      BandState.shown => 14.0,
      BandState.minimised => 4.0,
      BandState.hidden => 0.0,
    };
    if (h > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r(5, 11, 44, h), const Radius.circular(1.5)),
          Paint()..color = colour.withValues(alpha: 0.85));
    } else {
      var dash = Paint()
        ..color = colour.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = 5.0; x < 49; x += 4) {
        canvas.drawLine(
            Offset(x * sx, 12 * sy), Offset((x + 2) * sx, 12 * sy), dash);
      }
    }
    var restTop = h > 0 ? 13 + h : 15.0;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            r(5, restTop, 44, 29 - restTop), const Radius.circular(1)),
        Paint()..color = studio.raised);
  }

  @override
  bool shouldRepaint(_BandPicture old) =>
      old.band != band || old.state != state || old.studio != studio;
}
