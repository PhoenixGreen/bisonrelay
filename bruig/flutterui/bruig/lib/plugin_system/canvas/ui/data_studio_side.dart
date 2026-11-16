import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart' as pp;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_studio_side.dart is the Data Studio's sidebars' one shape (Ken,
// 2026-11-17, the sidebar prototype approved: "The prototype is great,
// let's build it"): a header saying what is being changed, with the way
// back up; a quick strip of what is changed most; then sections that fold,
// each saying what is set in it while shut. Built from the canvas panel's
// own kit (CanvasSection, CanvasStepper, CanvasSegmented...) inside
// CanvasDense, so the Studio and the element panel look alike. The Sheet,
// Table and Charts tabs all build on this.
//
// The keys the Studio's tests have long found things by are kept: a choice
// is still `studioPill-<id>-<value>`, a colour's swatches `<id>-<rrggbb>`.

/// StudioSide is a sidebar: its [header], then the [quick] strip and the
/// [body]'s sections, scrolled.
class StudioSide extends StatelessWidget {
  final Widget header;
  final List<Widget> quick;
  final List<Widget> body;

  /// scrollKey names the scroll, by what is picked, so it starts at the top
  /// when the pick changes.
  final Key? scrollKey;
  const StudioSide(
      {required this.header,
      this.quick = const [],
      required this.body,
      this.scrollKey,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Container(
      color: colors.surfaceContainerLow,
      child: CanvasDense(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              key: scrollKey,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (quick.isNotEmpty) pp.CanvasQuickStrip(children: quick),
                  ...body,
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// StudioSideHeader says what the sidebar is changing: a picture of its
/// kind, the way to it (Table › Column · Pts), each step clickable, its
/// name, and a button up a level.
class StudioSideHeader extends StatelessWidget {
  final IconData icon;

  /// crumbs are the steps to what is picked, the last being it; a step
  /// with a press goes back to it.
  final List<(String, VoidCallback?)> crumbs;
  final String title;
  final VoidCallback? onUp;

  /// titleKey names the title for the tests.
  final Key? titleKey;

  /// crumbKey names each step: `<crumbKey>-<i>`.
  final String crumbKey;
  const StudioSideHeader(
      {required this.icon,
      this.crumbKey = "studioCrumb",
      required this.crumbs,
      required this.title,
      this.onUp,
      this.titleKey,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var muted = colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colors.surfaceContainerHighest,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Icon(icon, size: 18, color: muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (var (i, (name, go)) in crumbs.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text("›",
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                  i == crumbs.length - 1 || go == null
                      ? Text(name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == crumbs.length - 1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == crumbs.length - 1
                                  ? colors.onSurface
                                  : muted))
                      : InkWell(
                          key: ValueKey("$crumbKey-$i"),
                          borderRadius: BorderRadius.circular(5),
                          onTap: go,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 1),
                            child: Text(name,
                                style: TextStyle(fontSize: 12, color: muted)),
                          ),
                        ),
                ],
              ]),
              const SizedBox(height: 1),
              Text(title,
                  key: titleKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface)),
            ],
          ),
        ),
        if (onUp != null)
          Tooltip(
            message: "Up a level (Esc)",
            child: InkWell(
              key: const ValueKey("studioUp"),
              borderRadius: BorderRadius.circular(8),
              onTap: onUp,
              child: Container(
                width: 32,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Icon(Icons.arrow_upward, size: 16, color: muted),
              ),
            ),
          ),
      ]),
    );
  }
}

/// studioSection is a fold of the sidebar, remembered as `studio.<remember>`.
Widget studioSection(
        {required String remember,
        required IconData icon,
        required String title,
        String summary = "",
        bool open = false,
        int? count,
        Widget? action,
        required List<Widget> children}) =>
    CanvasSection(
        key: ValueKey("studioSection-$remember"),
        remember: "studio.$remember",
        icon: icon,
        title: count == null ? title : "$title · $count",
        summary: summary,
        initiallyOpen: open,
        action: action,
        children: _lifted(children));

/// _lifted is a section's [children] with what an unnamed group is for
/// moved up to the section's own "?": a "?" alone on a line under the
/// controls reads as stray.
List<Widget> _lifted(List<Widget> children) {
  var out = <Widget>[];
  var helps = <String>[];
  for (var c in children) {
    if (c is CanvasControlGroup &&
        c.label.isEmpty &&
        (c.help ?? "").isNotEmpty) {
      helps.add(c.help!);
      out.add(CanvasControlGroup(
          key: c.key,
          label: c.label,
          hideCaption: c.hideCaption,
          rule: c.rule,
          below: c.below,
          children: c.children));
    } else {
      out.add(c);
    }
  }
  return [...out, for (var h in helps) CanvasHint(h)];
}

/// studioGroup is a few controls under one small-capital name (none for
/// [label] empty), [help] behind its "?".
Widget studioGroup(String label, List<Widget> children, {String? help}) =>
    CanvasControlGroup(
        label: label,
        hideCaption: label.isEmpty,
        rule: false,
        help: help,
        children: children);

/// studioRow is controls side by side across the line.
Widget studioRow(List<Widget> cells, {List<int>? flex}) => pp.panelRow([
      for (var (i, c) in cells.indexed)
        pp.cell(c, flex: flex == null ? 1 : flex[i], min: 96),
    ]);

/// studioSeg is a choice among a few, side by side in one box; its options
/// keyed `studioPill-<id>-<value>` as the pills they replace were.
Widget studioSeg<T>(
        {required String id,
        String label = "",
        required T value,
        required List<(T, String)> options,
        required ValueChanged<T> onChanged}) =>
    SizedBox(
      width: double.infinity,
      child: CanvasSegmented<T>(
          key: ValueKey("studioSeg-$id"),
          label: label,
          value: value,
          options: options,
          keyOf: (v) => "studioPill-$id-$v",
          onChanged: onChanged),
    );

/// studioDrop is a choice among many, as a list that drops down.
Widget studioDrop<T>(
        {required Key key,
        String label = "",
        required T value,
        required List<(T, String)> options,
        required ValueChanged<T> onChanged}) =>
    CanvasDropdown<T>(
        key: key,
        label: label,
        value: value,
        options: options,
        width: 96,
        onChanged: onChanged);

/// studioStepper is a number with an arrow either side ([percent] shows a
/// fraction as a percentage), set back to [rest] by its ↺.
Widget studioStepper(
    {required Key key,
    required String label,
    required double value,
    required double min,
    required double max,
    double? rest,
    int decimals = 0,
    double? step,
    String suffix = "",
    bool percent = false,
    required ValueChanged<double> onChanged,
    VoidCallback? onCommit}) {
  var k = percent ? 100.0 : 1.0;
  return CanvasStepper(
      key: key,
      label: label,
      value: value * k,
      min: min * k,
      max: max * k,
      decimals: decimals,
      step: step == null ? null : step * k,
      suffix: percent ? "%" : suffix,
      defaultValue: rest == null ? null : rest * k,
      width: 96,
      onChanged: (v) => onChanged(v / k),
      onCommit: onCommit);
}

/// studioText is a line of words to type.
Widget studioText(
        {required Key key,
        String label = "",
        required String value,
        String hint = "",
        required ValueChanged<String> onChanged}) =>
    CanvasTextField(
        key: key,
        label: label,
        value: value,
        hint: hint,
        width: 120,
        onChanged: onChanged);

/// StudioSwitchRow is a setting that is on or off: its words, and a switch.
class StudioSwitchRow extends StatelessWidget {
  final String label;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;
  const StudioSwitchRow(
      {required this.label,
      this.note = "",
      required this.value,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return SizedBox(
      width: double.infinity,
      height: 30,
      // The whole line is the switch: words are easier to hit.
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!value),
        child: Row(children: [
          Expanded(
            child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  if (note.isNotEmpty)
                    TextSpan(
                        text: " · $note",
                        style: TextStyle(color: colors.onSurfaceVariant)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.onSurface)),
          ),
          CanvasSwitch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// StudioColourField is a colour as one row -- the colour and its name --
/// whose palette opens under it when pressed (the prototype's: a dropdown,
/// not a popup; Ken's settings rule): the style's own colours first, then
/// the theme's, then any colour, and "as made" where it can have none.
class StudioColourField extends StatefulWidget {
  /// id keys the field and each swatch: `<id>-<rrggbb>`, `<id>-made`.
  final String id;
  final String label;
  final Color value;

  /// styleColours are the colours the table's or chart's style is made of.
  final List<Color> styleColours;

  /// palette is the theme's colours, as 0xRRGGBB.
  final List<int> palette;

  /// asMade offers "as made": none of its own.
  final bool asMade;
  final ValueChanged<Color> onPick;
  const StudioColourField(
      {required this.id,
      required this.label,
      required this.value,
      this.styleColours = const [],
      required this.palette,
      this.asMade = true,
      required this.onPick,
      super.key});

  @override
  State<StudioColourField> createState() => _StudioColourFieldState();
}

String _hex(Color c) =>
    (c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0');

class _StudioColourFieldState extends State<StudioColourField> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var none = widget.value.a == 0;
    Widget dot(Color c, String name) {
      var on = !none && _hex(c) == _hex(widget.value);
      return InkWell(
        key: ValueKey("${widget.id}-$name"),
        borderRadius: BorderRadius.circular(5),
        onTap: () {
          widget.onPick(c);
          setState(() => _open = false);
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: c,
            border: Border.all(
                color: on ? colors.primary : colors.outlineVariant,
                width: on ? 2.5 : 1),
          ),
        ),
      );
    }

    Widget caption(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(s.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.onSurfaceVariant)),
        );
    var swatch = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: none ? null : widget.value.withValues(alpha: 1),
        gradient: none
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.5, 0.5],
                colors: [Color(0xfff4f1ea), Color(0xff6b6f7a)])
            : null,
        border: Border.all(color: colors.outlineVariant),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: colors.onSurfaceVariant)),
            ),
          Material(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
                side: BorderSide(
                    color: _open ? colors.primary : colors.outlineVariant)),
            child: InkWell(
              key: ValueKey(widget.id),
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: 30,
                child: Row(children: [
                  const SizedBox(width: 4),
                  swatch,
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                        none
                            ? "As made"
                            : "#${_hex(widget.value).toUpperCase()}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontFamily: "monospace",
                            color: colors.onSurfaceVariant)),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                ]),
              ),
            ),
          ),
          if (_open)
            Container(
              key: ValueKey("${widget.id}-palette"),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: colors.surfaceContainerLowest,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.styleColours.isNotEmpty) ...[
                    caption("This style"),
                    Wrap(spacing: 5, runSpacing: 5, children: [
                      for (var c in {
                        for (var s in widget.styleColours) _hex(s): s
                      }.entries)
                        dot(c.value.withValues(alpha: 1), "style-${c.key}"),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  caption("Theme"),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    for (var c in widget.palette)
                      dot(Color(0xff000000 | c),
                          c.toRadixString(16).padLeft(6, '0')),
                  ]),
                  const SizedBox(height: 8),
                  // Wrapping: the field may be half a line wide.
                  Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Held to its own size: a row cell's fill would
                        // stretch it across a line it has no width in.
                        Tooltip(
                          message: "Any colour",
                          child: SizedBox(
                            width: 44,
                            child: CanvasColorButton(
                              key: ValueKey("${widget.id}-any"),
                              color:
                                  none ? const Color(0xffffffff) : widget.value,
                              allowAlpha: false,
                              onChanged: widget.onPick,
                            ),
                          ),
                        ),
                        if (widget.asMade)
                          SizedBox(
                            width: 84,
                            child: CanvasTextButton(
                                key: ValueKey("${widget.id}-made"),
                                label: "As made",
                                grow: false,
                                onPressed: () {
                                  widget.onPick(const Color(0x00000000));
                                  setState(() => _open = false);
                                }),
                          ),
                      ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// StudioItem is one of a list -- a style on a table, a highlight, a note,
/// a view of a sheet: its mark, its name and what it reaches, an eye to
/// switch it off, and a press to open it. Hovered, it says so, for the
/// stage to light what it reaches.
class StudioItem extends StatelessWidget {
  final Widget mark;
  final String title, subtitle;
  final bool off;

  /// tag is a warning beside it ("does nothing").
  final String? tag;
  final Key? tagKey;
  final VoidCallback? onTap;
  final VoidCallback? onEye;
  final Key? eyeKey;
  final bool lit;
  final ValueChanged<bool>? onHover;

  /// trailing goes before its chevron: a button of its own.
  final Widget? trailing;
  const StudioItem(
      {required this.mark,
      required this.title,
      this.subtitle = "",
      this.off = false,
      this.tag,
      this.tagKey,
      this.onTap,
      this.onEye,
      this.eyeKey,
      this.lit = false,
      this.onHover,
      this.trailing,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var muted = colors.onSurfaceVariant;
    var row = Material(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side:
              BorderSide(color: lit ? colors.primary : colors.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
          child: Row(children: [
            mark,
            const SizedBox(width: 8),
            Expanded(
              child: Opacity(
                opacity: off ? 0.45 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: muted)),
                  ],
                ),
              ),
            ),
            if (tag != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(tag!,
                    key: tagKey,
                    style: const TextStyle(
                        fontSize: 10.5, color: Color(0xFFF2B33D))),
              ),
            if (trailing != null) trailing!,
            if (onEye != null)
              IconButton(
                key: eyeKey,
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: off ? "Switch on" : "Switch off",
                icon: Icon(
                    off
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: off ? muted : colors.primary),
                onPressed: onEye,
              ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: muted),
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        width: double.infinity,
        child: onHover == null
            ? row
            : MouseRegion(
                onEnter: (_) => onHover!(true),
                onExit: (_) => onHover!(false),
                child: row),
      ),
    );
  }
}

/// studioDot is an item's mark: a small square of its colour.
Widget studioDot(Color c) => Container(
      width: 12,
      height: 12,
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
    );

/// studioChips is a line of dashed "+ something" chips: things to add.
Widget studioChips(List<(String, Key, VoidCallback)> chips) => SizedBox(
      width: double.infinity,
      child: Wrap(children: [
        for (var (label, key, go) in chips)
          pp.CanvasChip(label, key: key, onPressed: go),
      ]),
    );

/// studioButtons is a line of the kit's buttons, wrapping.
Widget studioButtons(List<Widget> buttons) => SizedBox(
      width: double.infinity,
      child: Wrap(spacing: 6, runSpacing: 6, children: buttons),
    );

/// studioButton is one of the kit's buttons, sized to its words.
Widget studioButton(String label,
        {required Key key,
        VoidCallback? onPressed,
        IconData? icon,
        bool primary = false,
        String tooltip = ""}) =>
    CanvasTextButton(
        key: key,
        label: label,
        icon: icon,
        tooltip: tooltip,
        primary: primary,
        grow: false,
        onPressed: onPressed);

/// studioNote is a line of plain words: what a list holds, where none.
class StudioNote extends StatelessWidget {
  final String text;
  final Color? colour;
  const StudioNote(this.text, {this.colour, super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: colour ??
                    ThemeNotifier.of(context).colors.onSurfaceVariant)),
      );
}

/// StudioPartButton is one of a chart's parts, to go to it: its name and
/// what it is set to.
class StudioPartButton extends StatelessWidget {
  final String label, says;
  final VoidCallback onTap;
  const StudioPartButton(
      {required this.label,
      required this.says,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          // Its name over what it is set to: both whole at any width.
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                    Text(says,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                  ]),
            ),
            Icon(Icons.chevron_right, size: 16, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// studioParts is [parts] two to a line.
Widget studioParts(List<Widget> parts) => SizedBox(
      width: double.infinity,
      child: LayoutBuilder(builder: (context, room) {
        var w = (room.maxWidth - 4) / 2;
        return Wrap(spacing: 4, runSpacing: 4, children: [
          for (var p in parts) SizedBox(width: w, child: p),
        ]);
      }),
    );
