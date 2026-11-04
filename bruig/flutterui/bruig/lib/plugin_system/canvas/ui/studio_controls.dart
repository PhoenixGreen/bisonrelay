import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// studio_controls.dart is the Character Studio's controls, in the look of its
// prototype: small capital headings, rows of pills, sliders with their value
// beside them, and round colour swatches, coloured from the app's theme.

/// StudioLabel is a heading over a group of controls.
class StudioLabel extends StatelessWidget {
  final String text;
  const StudioLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 7),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant)),
    );
  }
}

/// StudioPill is one rounded button, outlined in the theme's main colour
/// when it is the one chosen.
class StudioPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// filled is the page's main action ("Next", "Done").
  final bool filled;
  final String tooltip;
  const StudioPill(
      {required this.label,
      this.selected = false,
      this.onTap,
      this.filled = false,
      this.tooltip = "",
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final enabled = onTap != null;
    final fill = filled
        ? colors.primary
        : selected
            ? colors.primary.withValues(alpha: 0.16)
            : colors.surfaceContainerHigh;
    final ink = filled
        ? colors.onPrimary
        : enabled
            ? colors.onSurface
            : colors.onSurfaceVariant.withValues(alpha: 0.5);
    final pill = Material(
      color: fill,
      shape: StadiumBorder(
          side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: ink)),
        ),
      ),
    );
    return tooltip.isEmpty ? pill : Tooltip(message: tooltip, child: pill);
  }
}

/// StudioPills is a heading and a choice among a few, as a row of pills.
class StudioPills<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// id names the pills for tests: `studioPill-<id>-<value>`.
  final String id;
  const StudioPills(
      {required this.id,
      required this.label,
      required this.value,
      required this.options,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StudioLabel(label),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, name) in options)
            StudioPill(
              key: ValueKey("studioPill-$id-$v"),
              label: name,
              selected: v == value,
              onTap: () => onChanged(v),
            ),
        ]),
      ]);
}

/// StudioSlider is a setting as a slider: its name, the slider, and its
/// value. Changed, it has a dot beside it; clicking the dot, or its name,
/// puts it back.
class StudioSlider extends StatelessWidget {
  final String label;
  final double value, min, max;

  /// rest is what it goes back to.
  final double rest;

  /// format writes the value: by default -100 to +100 for a slider either
  /// side of nought, and a percentage for one from nought.
  final String Function(double)? format;
  final ValueChanged<double> onChanged;
  const StudioSlider(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.min = -1,
      this.max = 1,
      this.rest = 0,
      this.format,
      super.key});

  String _text(double v) {
    final f = format;
    if (f != null) return f(v);
    if (min >= 0) return "${(v * 100).round()}%";
    final n = (v * 100).round();
    return n > 0 ? "+$n" : "$n";
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final changed = (value - rest).abs() > 1e-6;
    return SizedBox(
      height: 36,
      child: Row(children: [
        SizedBox(
          width: 104,
          child: InkWell(
            onTap: changed ? () => onChanged(rest) : null,
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.onSurface)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.outlineVariant,
              thumbColor: colors.primary,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(_text(value),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colors.onSurfaceVariant)),
        ),
        SizedBox(
          width: 18,
          child: changed
              ? Tooltip(
                  message: "Put it back",
                  child: InkWell(
                    key: const ValueKey("studioSliderReset"),
                    customBorder: const CircleBorder(),
                    onTap: () => onChanged(rest),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: colors.primary, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ]),
    );
  }
}

/// StudioSwatches is a heading and a row of colours, as 0xRRGGBB, the one in
/// use ringed. With [asMade], the first swatch is "as it was made" (null).
class StudioSwatches extends StatelessWidget {
  final String id, label;
  final List<int> palette;
  final int? value;
  final bool asMade;
  final ValueChanged<int?> onPick;
  const StudioSwatches(
      {required this.id,
      required this.label,
      required this.palette,
      required this.value,
      required this.onPick,
      this.asMade = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    Widget swatch(int? c) {
      final on = c == value;
      final name = c == null ? "made" : c.toRadixString(16).padLeft(6, '0');
      return InkWell(
        key: ValueKey("$id-$name"),
        customBorder: const CircleBorder(),
        onTap: () => onPick(c),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c == null ? null : Color(0xff000000 | c),
            gradient: c == null
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [0.5, 0.5],
                    colors: [Color(0xfff4f1ea), Color(0xff6b6f7a)])
                : null,
            border: Border.all(
                color: on ? colors.primary : colors.outlineVariant,
                width: on ? 2.5 : 1),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StudioLabel(label),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (asMade) swatch(null),
        for (final c in palette) swatch(c),
      ]),
    ]);
  }
}

/// StudioPanelHead is a part's name and what it changes, at the top of
/// the settings, with a way back to as made when anything is changed.
class StudioPanelHead extends StatelessWidget {
  final String title, says;
  final String resetLabel;
  final VoidCallback? onReset;
  const StudioPanelHead(
      {required this.title,
      required this.says,
      this.resetLabel = "As made",
      this.onReset,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface)),
        ),
        if (onReset != null)
          StudioPill(
              key: const ValueKey("studioPartReset"),
              label: resetLabel,
              onTap: onReset),
      ]),
      const SizedBox(height: 4),
      Text(says,
          style: TextStyle(
              fontSize: 12.5, height: 1.45, color: colors.onSurfaceVariant)),
    ]);
  }
}

/// StudioPartHeading heads a group in a Studio step's list of parts.
class StudioPartHeading extends StatelessWidget {
  final String text;

  /// first is whether it is the list's first, nearer the top.
  final bool first;
  const StudioPartHeading(this.text, {this.first = false, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 14 : 20, 16, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant)),
    );
  }
}

/// StudioPartRow is one part in a Studio step's list: its name, marked
/// once it is changed, picked to open its settings. The mark puts the part
/// back as it was, clicked.
class StudioPartRow extends StatelessWidget {
  final String id, name;
  final bool changed, selected;
  final VoidCallback onTap;

  /// onReset puts the part back; null for a mark that only marks.
  final VoidCallback? onReset;

  /// keyPrefix names its keys: `<keyPrefix>-<id>`, and the mark
  /// `<keyPrefix minus Part>Changed-<id>`.
  final String keyPrefix;
  const StudioPartRow(
      {required this.id,
      required this.name,
      required this.changed,
      required this.selected,
      required this.onTap,
      this.onReset,
      this.keyPrefix = "shapePart",
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final on = selected;
    final mark = "${keyPrefix.replaceAll("Part", "")}Changed-$id";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: on ? colors.primary.withValues(alpha: 0.14) : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(
                color: on ? colors.primary : Colors.transparent, width: 1.2)),
        child: InkWell(
          key: ValueKey("$keyPrefix-$id"),
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface)),
              ),
              if (changed)
                Tooltip(
                  message: onReset == null ? "" : "Put it back",
                  child: InkWell(
                    key: ValueKey(mark),
                    customBorder: const CircleBorder(),
                    onTap: onReset,
                    // A dot to see, a finger's width to click.
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: colors.primary, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
