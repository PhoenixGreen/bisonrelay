part of 'canvas_mixer.dart';

// canvas_mixer_strips.dart is the mixer's columns: one for each channel,
// return and the master, all the same shape, in bands top to bottom as in
// Ableton's session mixer: clips (a channel's slots; the master's scenes),
// devices (effects as slots), sends (dials), and the mixer (pan, on, solo
// and arm beside the fader). Each band is one height across every column
// (_Bands), so the faders line up; the rail (MixerSection) shows or hides it.

/// _headH, _bandGap and the rest are the columns' measures, at the desk's
/// own size (see _CanvasMixerState.build).
const double _headH = 22;
const double _bandGap = 6;
const double _slotH = 20;
const double _slotGap = 4;
const double _clipH = 20;
const double _clipGap = 3;
const double _stopH = 16;

/// _clipRowsWanted is the most clip slots the clips band is made tall
/// enough for, room allowing (fewer while fewer show); more scroll.
const int _clipRowsWanted = 4;

/// _clipsLeast is the least a clips band is given: one slot and its stop.
const double _clipsLeast = _clipH + _clipGap + _slotGap + _stopH;

/// _mixerMinH is the least a mixer band is given (its left column and a
/// fader still worth dragging), and _mixerCapH the most before the room
/// left goes to the clips. Both include the sound half's label, pan and
/// switch rows over the fader, so the fader keeps its room.
const double _mixerMinH = 120 + _soundRowsH;
const double _mixerCapH = 230 + _soundRowsH;
const double _soundRowsH = 30;

const double _buttonW = 18;
const double _buttonH = 12;

/// _wideW and _narrowW are a column's widths: wide, with names and a numbered
/// fader, or narrow, each column or all (CanvasController.narrowStrips).
const double _wideW = 116;
const double _narrowW = 62;

/// _sendRow is a row of send dials; a narrow column's are smaller, two a row.
const double _sendRow = 35;
const double _narrowSendRow = 29;

double _slotsHeight(int n) => n <= 0 ? 0 : n * _slotH + (n - 1) * _slotGap;

/// sendsHeight is the send dials' band for [returns] returns: rows of
/// three, or of two in a narrow column; nought with none.
double sendsHeight(int returns, {bool narrow = false}) {
  if (returns == 0) return 0;
  var rows = (returns / (narrow ? 2 : 3)).ceil();
  return rows * (narrow ? _narrowSendRow : _sendRow) + (rows - 1) * 2;
}

/// _Bands is how tall every column's clips and devices bands are (null for
/// one hidden), and whether the mixer band, taking what is left, shows.
class _Bands {
  final double? clips;
  final double? devices;

  /// sends is the send dials' band height; null when hidden or no returns.
  final double? sends;

  /// mixer is whether the mixer band shows whole, taking what is left;
  /// miniMixer whether it shows minimised, [_miniMixerH] high.
  final bool mixer;
  final bool miniMixer;

  /// bare is the mixer at its smallest: no column has its head.
  final bool bare;

  /// motion is the room every column's motion half takes over its sound
  /// half, and motionClip each slot row's motion part over its sound part:
  /// nought where no element has a strip, so the sound halves share a line.
  final double motion;
  final double motionClip;

  /// devicesMini is whether the devices band is minimised to a count.
  final bool devicesMini;
  const _Bands(this.clips, this.devices, this.mixer,
      {this.miniMixer = false,
      this.devicesMini = false,
      this.sends,
      this.bare = false,
      this.motion = 0,
      this.motionClip = 0});

  /// need is the least [states] take of a column's height, as fit gives it.
  static double need(Map<MixerSection, BandState> states,
      {required double devicesWanted,
      required double devicesCap,
      double sendsH = 0,
      bool bare = false,
      bool motion = false,
      BandState motionSlots = BandState.shown}) {
    var mc = !motion
        ? 0.0
        : switch (motionSlots) {
            BandState.shown => _motionClipH + _motionClipGap,
            BandState.minimised => _motionClipMini + _motionClipGap,
            BandState.hidden => 0.0,
          };
    var mh = motion ? motionHalfHeight + _motionGap : 0.0;
    var total = bare ? 0.0 : _headH;
    for (var s in MixerSection.values) {
      var st = states[s]!;
      if (st == BandState.hidden) continue;
      if (s == MixerSection.sends && sendsH <= 0) continue;
      total += _bandGap;
      total += switch (s) {
        MixerSection.clips => _clipsLeast + mc,
        MixerSection.devices =>
          st == BandState.shown ? math.min(devicesWanted, devicesCap) : _slotH,
        MixerSection.sends => sendsH,
        MixerSection.mixer => st == BandState.shown
            ? _mixerMinH + mh
            : bare
                ? _bareMixerH
                : _miniMixerH + (motion ? _motionLineH : 0),
      };
    }
    return total;
  }

  /// _Bands.fit shares [inner], a column's height inside its frame, among the
  /// bands as [states] says. A minimised band has its least; the whole ones
  /// share the rest: the mixer its least, each other what it wants, the mixer
  /// more up to [_mixerCapH], then the clips the rest. Short of room, clips
  /// and devices share it as they want it, and scroll. The devices want no
  /// more than [devicesCap] while clips and mixer both show whole, so a long
  /// chain scrolls rather than squeezing them.
  factory _Bands.fit(double inner, Map<MixerSection, BandState> states,
      double devicesWanted, double devicesCap,
      {double sendsH = 0,
      bool bare = false,
      int clipRows = _clipRowsWanted,
      bool motion = false,
      BandState motionSlots = BandState.shown}) {
    var mh = motion ? motionHalfHeight + _motionGap : 0.0;
    var mc = !motion
        ? 0.0
        : switch (motionSlots) {
            BandState.shown => _motionClipH + _motionClipGap,
            BandState.minimised => _motionClipMini + _motionClipGap,
            BandState.hidden => 0.0,
          };
    var mixerLeast = _mixerMinH + mh;
    var mixerMost = _mixerCapH + mh;
    bool whole(MixerSection s) => states[s] == BandState.shown;
    bool mini(MixerSection s) => states[s] == BandState.minimised;
    var clips = whole(MixerSection.clips);
    var devices = whole(MixerSection.devices);
    var mixer = whole(MixerSection.mixer);
    var sends = states[MixerSection.sends] != BandState.hidden && sendsH > 0
        ? sendsH
        : null;
    var showing = MixerSection.values
        .where((s) =>
            states[s] != BandState.hidden &&
            (s != MixerSection.sends || sends != null))
        .length;
    var avail = math.max(0.0, inner - (bare ? 0 : _headH) - _bandGap * showing);
    double? c, d;
    var fixed = sends ?? 0.0;
    if (mini(MixerSection.clips)) {
      c = _clipsLeast + mc;
      fixed += c;
    }
    if (mini(MixerSection.devices)) {
      d = _slotH;
      fixed += d;
    }
    if (mini(MixerSection.mixer)) {
      fixed += bare ? _bareMixerH : _miniMixerH + (motion ? _motionLineH : 0);
    }
    // Too short for each band's least with the motion parts: they go first.
    if (motion && fixed > avail) {
      return _Bands.fit(inner, states, devicesWanted, devicesCap,
          sendsH: sendsH, bare: bare, clipRows: clipRows);
    }
    var free = math.max(0.0, avail - fixed);
    var want =
        clips && mixer ? math.min(devicesWanted, devicesCap) : devicesWanted;
    var clipsWanted =
        math.min(clipRows, _clipRowsWanted) * (_clipH + _clipGap + mc) -
            _clipGap +
            _slotGap +
            _stopH;
    if (!mixer) {
      if (clips && devices) {
        d = math.min(want, math.max(0.0, free - _clipsLeast - mc));
        c = free - d;
      } else if (clips) {
        c = free;
      } else if (devices) {
        d = free;
      }
      return _Bands(c, d, false,
          miniMixer: mini(MixerSection.mixer),
          devicesMini: mini(MixerSection.devices),
          sends: sends,
          bare: bare,
          motion: mh,
          motionClip: mc);
    }
    var wanted = (clips ? clipsWanted : 0) + (devices ? want : 0);
    var forMixer = free - wanted;
    double mixerH;
    if (forMixer < mixerLeast) {
      mixerH = math.min(mixerLeast, free);
    } else if (clips) {
      mixerH = math.min(forMixer, mixerMost);
    } else {
      mixerH = forMixer;
    }
    var rest = math.max(0.0, free - mixerH);
    if (devices && clips) {
      d = rest >= wanted ? want : rest * want / wanted;
      c = rest - d;
      // At least a slot and its stop, taken from the devices, which scroll:
      // shared by want, a long chain would leave the clips a sliver.
      if (c < _clipsLeast + mc && rest > _clipsLeast + mc) {
        c = _clipsLeast + mc;
        d = rest - c;
      }
    } else if (devices) {
      d = math.min(rest, want);
    } else if (clips) {
      c = rest;
    }
    return _Bands(c, d, true,
        sends: sends,
        bare: bare,
        motion: mh,
        motionClip: mc,
        devicesMini: mini(MixerSection.devices));
  }
}

/// _miniMixerH is the mixer band minimised: a row of its buttons over a
/// meter on its side, which is the fader too.
const double _miniMixerH = 34;

/// _motionGap is under the motion half; _motionClipH a slot row's motion
/// part, _motionClipGap under it; _motionLineH the line over a mini mixer.
const double _motionGap = 4;
const double _motionClipH = 14;
const double _motionClipMini = 4;
const double _motionClipGap = 2;
const double _motionLineH = 18;

/// _bareMixerH is it at the mixer's smallest: the meter alone.
const double _bareMixerH = 12;

/// _StripFrame is a column: its frame, head and bands at shared heights.
class _StripFrame extends StatelessWidget {
  final double width;
  final bool selected;
  final bool master;
  final MixerLook theme;
  final _Bands bands;
  final Widget head;
  final Widget Function() clips;
  final Widget Function() devices;
  final Widget Function() mixer;

  /// sends are its send dials, in the sends band; nothing in a column
  /// without, which keeps the band's room so the faders line up.
  final Widget Function()? sends;

  final Widget Function() miniMixer;

  /// motion is the motion half over the sound half, where the column has
  /// one (an element's), and motionLine it over a minimised mixer; without
  /// one, a well saying [noMotion] keeps the sound halves on one line.
  final Widget Function()? motion;
  final Widget Function()? motionLine;
  final String noMotion;

  /// narrow is whether the column is narrow, and onNarrow (the arrow in its
  /// head, keyed [narrowKey]) makes it the other.
  final bool narrow;
  final VoidCallback? onNarrow;
  final Key? narrowKey;

  /// badges go after its name, where it is wide: see stripBadges.
  final List<Widget> badges;

  /// rowColour is a bar along the top of its head; none on buses or master.
  final Color? rowColour;

  /// deviceCount is how many devices it has, motion and sound, for the
  /// devices band minimised; null where it has nothing to count.
  final int? deviceCount;

  const _StripFrame({
    this.rowColour,
    this.badges = const [],
    this.deviceCount,
    this.width = _wideW,
    this.master = false,
    this.narrow = false,
    this.onNarrow,
    this.narrowKey,
    required this.selected,
    required this.theme,
    required this.bands,
    required this.head,
    required this.clips,
    required this.devices,
    required this.mixer,
    required this.miniMixer,
    this.sends,
    this.motion,
    this.motionLine,
    this.noMotion = "No motion",
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var studio = theme.studio;
    var withMotion = bands.motion > 0;
    return Container(
      width: narrow ? _narrowW : width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: master ? colors.outline : colors.outlineVariant),
      ),
      // Picked: drawn over the frame, not thickening it, which would move its
      // bands off the others' line. Always there, clear when not picked: one
      // that comes and goes changes the tree, losing a reading being typed.
      foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? colors.primary : const Color(0x00000000),
              width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!bands.bare)
          SizedBox(
            height: _headH,
            child: Stack(clipBehavior: Clip.none, children: [
              // Its row's colour along the top, in the frame's own padding,
              // so nothing under it moves.
              if (rowColour case var colour?)
                Positioned(
                  key: const ValueKey("stripColour"),
                  left: -5,
                  right: -5,
                  top: -5,
                  height: 2,
                  child: ColoredBox(color: colour),
                ),
              Positioned.fill(
                child: Row(children: [
                  Expanded(child: ClipRect(child: head)),
                  if (!narrow)
                    for (var b in badges) ...[const SizedBox(width: 3), b],
                  if (onNarrow case var toggle?)
                    Tooltip(
                      message: narrow ? "Make it wide" : "Make it narrow",
                      child: InkWell(
                        key: narrowKey,
                        onTap: toggle,
                        child: Icon(
                            narrow ? Icons.chevron_right : Icons.chevron_left,
                            size: 12,
                            color: studio.muted),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        if (bands.clips case var h?) ...[
          const SizedBox(height: _bandGap),
          SizedBox(height: h, child: clips()),
        ],
        if (bands.devices case var h?) ...[
          const SizedBox(height: _bandGap),
          SizedBox(
              height: h,
              child: ClipRect(
                  child: bands.devicesMini && deviceCount != null
                      ? _DevicesCount(deviceCount!, theme)
                      : devices())),
        ],
        if (bands.sends case var h?) ...[
          const SizedBox(height: _bandGap),
          SizedBox(
              key: const ValueKey("sendsBand"),
              height: h,
              child: ClipRect(child: sends?.call() ?? const SizedBox())),
        ],
        if (bands.mixer) ...[
          const SizedBox(height: _bandGap),
          // Short of room, the motion half goes first, then the sound half
          // is drawn smaller rather than overflowing.
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              var sound = box.maxHeight;
              var both = withMotion &&
                  box.maxHeight >= motionHalfHeight + _motionGap + _soundLeast;
              if (both) sound -= motionHalfHeight + _motionGap;
              Widget half = sound >= _soundLeast
                  ? mixer()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                          width: box.maxWidth,
                          height: _soundLeast,
                          child: mixer()));
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (both) ...[
                      SizedBox(
                          height: motionHalfHeight,
                          child: motion?.call() ?? _Well(noMotion, theme)),
                      const SizedBox(height: _motionGap),
                    ],
                    Expanded(child: half),
                  ]);
            }),
          ),
        ],
        if (bands.miniMixer) ...[
          const Spacer(),
          const SizedBox(height: _bandGap),
          if (withMotion && !bands.bare)
            SizedBox(
                height: _motionLineH,
                child: motionLine?.call() ?? const SizedBox()),
          SizedBox(
              height: bands.bare ? _bareMixerH : _miniMixerH,
              child: miniMixer()),
        ],
      ]),
    );
  }
}

/// _Well is a recessed well saying what a half of a strip has not: "No
/// motion", "No sound", or nothing (the returns and the master).
class _Well extends StatelessWidget {
  final String text;
  final MixerLook theme;
  const _Well(this.text, this.theme);

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: theme.studio.inset, borderRadius: BorderRadius.circular(4)),
        child: text.isEmpty
            ? null
            : Text(text,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontSize: 9.5, color: theme.studio.muted)),
      );
}

/// _band is [children] in a band, scrolled where the band is shorter.
Widget _band(List<Widget> children) => ListView(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: children,
    );

List<Widget> _slots(List<Widget> slots) => [
      for (var (i, s) in slots.indexed) ...[
        if (i > 0) const SizedBox(height: _slotGap),
        SizedBox(height: _slotH, child: s),
      ],
    ];

/// _chainSlots is a strip's devices, EQ and compressor as slots, in the
/// order its chain runs them, as the Chain shows them. [devicePrefix],
/// [eqKey] and [compKey] are each strip's own keys.
List<Widget> _chainSlots(
  MixerLook theme, {
  required List<String> chain,
  required List<MixDevice> devices,
  required Eq eq,
  required Dynamics comp,
  required String devicePrefix,
  required String eqKey,
  required String compKey,
  String compLabel = "Comp",
  required VoidCallback onEq,
  required VoidCallback onComp,
  required void Function(String key) onDevice,
  void Function(String key)? onRemove,
}) {
  var colors = theme.colors;
  return [
    for (var step in chain)
      if (step == chainEq)
        _slot(
            theme,
            "EQ",
            eq.on,
            CustomPaint(
                size: const Size(40, 14), painter: _MiniCurve(eq, colors)),
            onEq,
            key: ValueKey(eqKey))
      else if (step == chainComp)
        _slot(
            theme,
            compLabel,
            comp.on,
            Icon(Icons.circle,
                size: 7, color: comp.on ? theme.studio.on : colors.outline),
            onComp,
            key: ValueKey(compKey))
      else if (deviceIndexOf(devices, step) case var i when i >= 0)
        _slot(
            theme,
            devices[i].kind.label,
            devices[i].on,
            Icon(Icons.circle,
                size: 7,
                color: devices[i].on ? theme.studio.on : colors.outline),
            () => onDevice(deviceKey(step)),
            onRemove: onRemove == null ? null : () => onRemove(deviceKey(step)),
            key: ValueKey("$devicePrefix-$i")),
  ];
}

/// stripBadges are a strip's badges, as the timeline's row has them: ×N in
/// amber where [element] is reused N times, and All for a sound on the
/// master canvas, there in every scene.
List<Widget> stripBadges(MixerLook theme, String key,
    {CanvasElement? element, bool all = false}) {
  var studio = theme.studio;
  var copies = element?.base.motion.instances?.count ?? 1;
  Widget chip(Key k, String text, Color ink,
          {bool mono = false, bool raised = false}) =>
      Container(
        key: k,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            color: raised ? studio.raised : studio.inset,
            border: Border.all(color: studio.edge),
            borderRadius: BorderRadius.circular(7)),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                fontSize: mono ? 9.5 : 8.5,
                height: 1.35,
                letterSpacing: mono ? 0 : 0.5,
                fontFeatures:
                    mono ? const [FontFeature.tabularFigures()] : null,
                color: ink)),
      );
  return [
    if (copies > 1)
      chip(ValueKey("stripCopies-$key"), "×$copies", studio.on, mono: true),
    if (all) chip(ValueKey("stripAll-$key"), "All", studio.text, raised: true),
  ];
}

/// _DevicesCount is a minimised devices band: how many devices there are.
class _DevicesCount extends StatelessWidget {
  final int count;
  final MixerLook theme;
  const _DevicesCount(this.count, this.theme);

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey("devicesCount"),
        height: _slotH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: theme.studio.raised, borderRadius: BorderRadius.circular(4)),
        child: Text("$count device${count == 1 ? "" : "s"}",
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(fontSize: 10, color: theme.studio.muted)),
      );
}

/// _MiniNote is a line said small in a strip's minimised band: the Scenes
/// strip's "◆ N transitions" over its mixer, "no sound" where an element has
/// none, "not in cues" under the Scenes strip's slots.
class _MiniNote extends StatelessWidget {
  final String text;
  final MixerLook theme;
  final bool diamond;
  final bool faint;
  const _MiniNote(this.text, this.theme,
      {this.diamond = false, this.faint = false, super.key});

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return Row(
        mainAxisAlignment:
            diamond ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          if (diamond) ...[
            const Icon(Icons.diamond, size: 9, color: motionColour),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                    fontSize: 9.5, color: faint ? studio.edge : studio.muted)),
          ),
        ]);
  }
}

/// _chainCount is how many devices a chain has, as _chainSlots shows them.
int _chainCount(List<String> chain, List<MixDevice> devices) => chain
    .where(
        (s) => s == chainEq || s == chainComp || deviceIndexOf(devices, s) >= 0)
    .length;
