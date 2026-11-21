part of 'controls.dart';

// Buttons and switches: the text button, segmented choice, chip, toggle and
// switch, the read-out, the icon button, the keyframe dot, and the grid cell.
// Part of controls.dart.

/// CanvasTextButton is a button that says what it does in words ("Flip
/// across", "Clear mask"), sharing the room on its line with its neighbours.
class CanvasTextButton extends StatelessWidget implements CanvasGrowable {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// primary fills it with the accent: the one thing a card is for.
  final bool primary;

  @override
  final bool grow;

  /// least fits its words and icon, so a line wraps before any is cut short.
  @override
  double get least =>
      (label.isEmpty ? 0 : 26 + label.length * 7.2) +
      (icon == null ? 0 : (label.isEmpty ? 40 : 22));

  /// tooltip says what an icon alone does, on hover. Words need none.
  final String tooltip;

  const CanvasTextButton(
      {required this.label,
      required this.onPressed,
      this.tooltip = "",
      this.icon,
      this.primary = false,
      this.grow = true,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var enabled = onPressed != null;
    var ink = !enabled
        ? theme.colors.onSurfaceVariant.withValues(alpha: 0.4)
        : primary
            ? theme.colors.onPrimary
            : theme.colors.onSurface;
    Widget button(Widget child) =>
        tooltip.isEmpty ? child : CanvasTip(message: tooltip, child: child);
    return Padding(
      padding: EdgeInsets.only(
          right: card ? cardGapIn(context) : canvasControlGap),
      child: canvasSized(
        context,
        min: least,
        height: heightIn(context),
        grow: grow,
        child: button(Material(
          color: primary && enabled ? theme.colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(card ? 10 : 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(card ? 10 : 4),
            onTap: onPressed,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 2 : 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(card ? 10 : 4),
                border: Border.all(
                    color: primary && enabled
                        ? theme.colors.primary
                        : theme.colors.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: label.isEmpty ? 18 : 16, color: ink),
                  if (label.isNotEmpty) const SizedBox(width: 6),
                ],
                if (label.isNotEmpty)
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: card ? 12 : 11,
                            fontWeight:
                                primary ? FontWeight.w600 : FontWeight.normal,
                            color: ink)),
                  ),
              ]),
            ),
          ),
        )),
      ),
    );
  }
}

/// CanvasSegmented is a choice of two to four short options, all in view and
/// the chosen one lit, on a line of its own with an optional caption.
class CanvasSegmented<T> extends StatelessWidget {
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// keyOf names each option, for the tests.
  final String Function(T)? keyOf;

  /// iconOf draws an option as an icon, its words its tooltip.
  final IconData Function(T)? iconOf;

  const CanvasSegmented(
      {required this.options,
      required this.value,
      required this.onChanged,
      this.label = "",
      this.keyOf,
      this.iconOf,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var accent = theme.colors.primary;
    // Dense: one box, its choices side by side with a line between, the
    // chosen one lit by a plain fill.
    var dense = card && CanvasDense.on(context);
    if (dense) {
      var bar = Container(
        height: cardHeightIn(context),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(color: theme.colors.outlineVariant),
        ),
        child: Row(children: [
          for (var (i, (option, words)) in options.indexed) ...[
            if (i > 0) Container(width: 1, color: theme.colors.outlineVariant),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: keyOf == null ? null : ValueKey(keyOf!(option)),
                  onTap: () => onChanged(option),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    // Lighter than the rest, in either theme.
                    color: option == value
                        ? theme.colors.onSurface.withValues(alpha: 0.12)
                        : null,
                    child: iconOf != null
                        ? CanvasTip(
                            message: words,
                            child: Icon(iconOf!(option),
                                size: 16,
                                color: option == value
                                    ? theme.colors.onSurface
                                    : theme.colors.onSurfaceVariant))
                        : Text(words,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: option == value
                                    ? theme.colors.onSurface
                                    : theme.colors.onSurfaceVariant)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
      return SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(right: cardGapIn(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label.isNotEmpty)
                SizedBox(
                  height: cardLabelHeightIn(context),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          color: theme.colors.onSurfaceVariant)),
                ),
              if (label.isNotEmpty) SizedBox(height: cardLabelGapIn(context)),
              bar,
            ],
          ),
        ),
      );
    }
    var bar = Container(
      height: card ? cardHeightIn(context) + 4 : controlHeight + 2,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(card ? 10 : 5),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Row(children: [
        for (var (option, words) in options)
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: keyOf == null ? null : ValueKey(keyOf!(option)),
                borderRadius: BorderRadius.circular(card ? 8 : 4),
                onTap: () => onChanged(option),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(card ? 8 : 4),
                    color:
                        option == value ? accent.withValues(alpha: 0.16) : null,
                    border: option == value ? Border.all(color: accent) : null,
                  ),
                  child: iconOf != null
                      ? CanvasTip(
                          message: words,
                          child: Icon(iconOf!(option),
                              size: 16, color: theme.colors.onSurface))
                      : Text(words,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: card ? 12 : 11,
                              fontWeight: option == value
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: theme.colors.onSurface)),
                ),
              ),
            ),
          ),
      ]),
    );
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(right: card ? 10 : canvasControlGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                    bottom: card ? cardLabelGapIn(context) : controlLabelGap),
                child: Text(label,
                    style: TextStyle(
                        fontSize: card ? 11.5 : 9,
                        color: theme.colors.onSurfaceVariant)),
              ),
            bar,
          ],
        ),
      ),
    );
  }
}

/// CanvasChip is a named thing on a line, with a cross to take it off: the
/// shapes a document is laid out for, read at a glance as a row.
class CanvasChip extends StatelessWidget {
  final String label;

  /// here marks the one being looked at.
  final bool here;

  /// onRemove is null for a chip that cannot be taken off.
  final VoidCallback? onRemove;

  const CanvasChip(
      {required this.label, this.here = false, this.onRemove, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 4, bottom: 2),
      padding: const EdgeInsets.only(left: 8, right: 2, top: 3, bottom: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: here ? theme.colors.secondaryContainer : null,
        border: Border.all(
            color: here ? theme.colors.primary : theme.colors.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Shortened rather than overrunning a narrow card.
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ),
        if (onRemove case var remove?)
          CanvasTip(
            message: "Stop laying out for $label",
            child: Material(
              // Its own Material: see CanvasControlGroup.
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: remove,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close,
                      size: 12, color: theme.colors.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 6),
      ]),
    );
  }
}

/// CanvasToggle is a switch with a label, for the many booleans.
class CanvasToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CanvasToggle(
      {required this.label,
      required this.value,
      required this.onChanged,
      super.key});

  /// _row is the switch in a card: the words, and a switch at the far end
  /// of a line of its own.
  Widget _row(BuildContext context, ThemeNotifier theme) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(!value),
              child: SizedBox(
                height: CanvasDense.on(context) ? 30 : 36,
                child: Row(children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: CanvasDense.on(context) ? 13 : 12,
                            color: theme.colors.onSurface)),
                  ),
                  _Switch(on: value, theme: theme),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return _row(context, theme);
    }
    return Padding(
      // The nudge: see CanvasIconButton.
      padding: EdgeInsets.only(right: canvasControlGap, top: nudgeIn(context)),
      child: Material(
        // Its own Material: see CanvasControlGroup.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => onChanged(!value),
          child: Container(
            height: controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: value ? theme.colors.secondaryContainer : null,
              border: Border.all(
                  color: value
                      ? theme.colors.secondaryContainer
                      : theme.colors.outlineVariant),
            ),
            // No check box: the fill says it, and the room saved lets five
            // switches fit a narrow sidebar's line. A long label (one
            // carrying a channel's name) is shortened.
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: value
                            ? theme.colors.onSecondaryContainer
                            : theme.colors.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// _Switch is a card's switch: an accent-filled track and a sliding knob.
class _Switch extends StatelessWidget {
  final bool on;
  final ThemeNotifier theme;
  const _Switch({required this.on, required this.theme});

  @override
  Widget build(BuildContext context) {
    var dense = CanvasDense.on(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: dense ? 34 : 40,
      height: dense ? 20 : 24,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: on
            ? theme.colors.primary
            : theme.colors.outlineVariant.withValues(alpha: 0.9),
      ),
      child: Container(
        width: dense ? 14 : 18,
        height: dense ? 14 : 18,
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    );
  }
}

/// CanvasSwitch is the switch a toggle row ends in, alone: for a row laid
/// out by hand (a look's, see LooksGroup).
class CanvasSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const CanvasSwitch({required this.value, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _Switch(on: value, theme: ThemeNotifier.of(context)),
          ),
        ),
      );
}

/// CanvasReadout is a caption over something the panel can only report
/// (which document a text element is reading), where a disabled field would
/// invite typing.
class CanvasReadout extends StatelessWidget {
  final String label;
  final String value;
  final double width;

  const CanvasReadout(
      {required this.label, required this.value, this.width = 168, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      SizedBox(
        width: width,
        height: heightIn(context),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.colors.onSurface),
          ),
        ),
      ),
    );
  }
}

/// CanvasIconButton is a small square action among the fields: shuffle a
/// seed, delete a keyframe, bring to front.
class CanvasIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  /// tight drops the room left above it for its neighbours' captions, as on
  /// a section's heading.
  final bool tight;

  const CanvasIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.tight = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var enabled = onPressed != null;
    return Padding(
      // The nudge (a caption and its gap) lines a control with no caption up
      // with captioned ones. On the band captions sit beside, so no nudge.
      padding: EdgeInsets.only(
          right: CanvasCards.on(context) ? 8 : canvasControlGap,
          top: tight ? 0 : nudgeIn(context)),
      child: _maybeTooltip(
        tooltip,
        Material(
          // Its own Material: see CanvasControlGroup.
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onPressed,
            child: Container(
              width: tight ? controlHeight : heightIn(context),
              height: tight ? controlHeight : heightIn(context),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(CanvasCards.on(context) ? 8 : 4),
                color: active ? theme.colors.secondaryContainer : null,
                border: Border.all(color: theme.colors.outlineVariant),
              ),
              child: Icon(
                icon,
                size: 15,
                color: !enabled
                    ? theme.colors.onSurfaceVariant.withValues(alpha: 0.35)
                    : active
                        ? theme.colors.onSecondaryContainer
                        : theme.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// _maybeTooltip is [child] with [message] as hover text, if not empty.
Widget _maybeTooltip(String message, Widget child) =>
    message.isEmpty ? child : CanvasTip(message: message, child: child);

/// CanvasKeyframeDot is the diamond beside an animatable setting: lit where
/// a keyframe sits on the current frame, pressed to add or remove one. What
/// the keyframe holds is the caller's (see valueDot in settings_shared.dart).
class CanvasKeyframeDot extends StatelessWidget {
  final bool on;

  /// enabled is false for a still document: a keyframe has nothing to
  /// interpolate towards.
  final bool enabled;

  final String tooltip;
  final VoidCallback onPressed;

  const CanvasKeyframeDot({
    required this.on,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      // The nudge: see CanvasIconButton.
      padding: EdgeInsets.only(right: canvasControlGap, top: nudgeIn(context)),
      child: CanvasTip(
        message: tooltip,
        child: Material(
          // Its own Material: see CanvasControlGroup.
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: 18,
              height: heightIn(context),
              child: Icon(
                on ? Icons.diamond : Icons.diamond_outlined,
                size: 11,
                color: !enabled
                    ? theme.colors.onSurfaceVariant.withValues(alpha: 0.25)
                    : on
                        ? theme.colors.primary
                        : theme.colors.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// CanvasGridCell is a text field with no caption, for chart and table
/// cells: a grid of CanvasTextFields would be a grid of captions.
class CanvasGridCell extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final bool multiline;
  final bool dense;
  final String hint;

  /// suggestions are names the source knows, offered while typing (see
  /// DataPreset.rowNames). They narrow what is shown and refuse nothing.
  final List<String> suggestions;

  const CanvasGridCell({
    required this.value,
    required this.onChanged,
    required this.onCommit,
    this.multiline = false,
    this.dense = false,
    this.hint = "",
    this.suggestions = const [],
    super.key,
  });

  @override
  State<CanvasGridCell> createState() => CanvasGridCellState();
}

class CanvasGridCellState extends State<CanvasGridCell> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit();
    });
  }

  @override
  void didUpdateWidget(CanvasGridCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Not while typed in: rewriting the text under the cursor eats a
    // keystroke and moves the caret to the end.
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return _field(context);
    var theme = ThemeNotifier.of(context);
    // RawAutocomplete, so the cell keeps its own controller and focus node,
    // which stop it rewriting itself under the cursor and commit on blur.
    return RawAutocomplete<String>(
      textEditingController: _text,
      focusNode: _focus,
      optionsBuilder: (value) {
        var typed = value.text.trim().toLowerCase();
        if (typed.isEmpty) return const Iterable<String>.empty();
        // What is being typed, wherever it appears in the name: "cash" finds
        // Bitcoin Cash. An exact match offers nothing.
        var found = [
          for (var name in widget.suggestions)
            if (name.toLowerCase().contains(typed)) name,
        ];
        if (found.length == 1 && found.first.toLowerCase() == typed) {
          return const Iterable<String>.empty();
        }
        return found.take(8);
      },
      onSelected: (name) {
        widget.onChanged(name);
        widget.onCommit();
      },
      fieldViewBuilder: (context, controller, focus, submit) => _field(context),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          color: theme.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180, maxWidth: 220),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (var name in options)
                  InkWell(
                    onTap: () => select(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(name,
                          style: TextStyle(
                              fontSize: 11, color: theme.colors.onSurface)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        expands: widget.multiline,
        maxLines: widget.multiline ? null : 1,
        minLines: null,
        style: TextStyle(fontSize: widget.dense ? 11 : 12),
        // Centred on one line, top on several: a single top-aligned line
        // sits high beside the dropdown in a series row.
        textAlignVertical:
            widget.multiline ? TextAlignVertical.top : TextAlignVertical.center,
        decoration: canvasFieldDecoration(
            hint: widget.hint, fontSize: widget.dense ? 11 : 12),
        onChanged: widget.onChanged,
      );
}
