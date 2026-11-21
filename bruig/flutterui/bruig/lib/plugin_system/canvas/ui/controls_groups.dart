part of 'controls.dart';

// What controls are gathered in: the control group and card, the More group
// with its renamable caption, rules between groups, the expander and the
// sections it remembers open, and the folding group. Part of controls.dart.

/// CanvasControlGroup is a labelled cluster of controls with a rule after
/// it, so a panel of many controls does not read as one mass.
class CanvasControlGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  /// hideCaption drops the group's own name where something above already
  /// says it (the panel's header naming the element).
  final bool hideCaption;

  /// captionGap is the room under the caption: more for a sentence, or it
  /// runs into the first control's caption.
  final double captionGap;

  /// rule is the line under the group, dropped where the next group is a
  /// continuation rather than a new subject.
  final bool rule;

  /// onRename makes the caption renamable by double-clicking it, as files,
  /// scenes and layers are; null for captions that are headings.
  final ValueChanged<String>? onRename;

  /// below goes under the group's controls and above its rule: the settings
  /// a button in the group has opened (see CanvasMoreGroup).
  final Widget? below;

  /// folded says whether this group is shut; null for groups always open.
  /// Shut, only the caption stays, pressed to reopen it. CanvasFoldingGroup
  /// remembers the answer.
  final bool? folded;

  /// onFold is the press on the caption, required wherever [folded] is set.
  final VoidCallback? onFold;

  const CanvasControlGroup({
    required this.label,
    required this.children,
    this.hideCaption = false,
    this.captionGap = canvasCaptionGap,
    this.rule = true,
    this.below,
    this.onRename,
    this.folded,
    this.onFold,
    this.help,
    super.key,
  });

  /// help is what the group is for, behind the "?" beside its name in a
  /// card. The hints among its children join it there.
  final String? help;

  /// _card is the group as a card in a section.
  Widget _card(BuildContext context, ThemeNotifier theme) {
    var hints = [
      for (var c in children)
        if (c is CanvasHint) c.message
    ];
    var rest = [
      for (var c in children)
        if (c is! CanvasHint) c
    ];
    var about =
        [if (help != null && help!.isNotEmpty) help!, ...hints].join("\n\n");
    var shut = folded == true;
    var dense = CanvasDense.on(context);
    var title = dense
        ? TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: theme.colors.onSurfaceVariant)
        : TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: theme.colors.onSurface);
    Widget name = onRename != null
        ? _RenamableCaption(label: label, style: title, onRename: onRename!)
        : Text(dense ? label.toUpperCase() : label, style: title);
    if (folded != null) {
      name = InkWell(
        onTap: onFold,
        borderRadius: BorderRadius.circular(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(shut ? Icons.chevron_right : Icons.expand_more,
              size: 16, color: theme.colors.onSurfaceVariant),
          const SizedBox(width: 2),
          name,
        ]),
      );
    }
    // Named in a card where there is a "?" to ask about it, but never with
    // the section's own name. In a dense panel a hidden name stays hidden.
    var named = label.isNotEmpty &&
        (!hideCaption || (about.isNotEmpty && !dense)) &&
        label != CanvasCards.titleOf(context);
    // Unnamed in a dense panel, its "?" ends its controls instead of taking
    // a heading line.
    var inline = dense && !named && about.isNotEmpty;
    return canvasCard(context,
        title: named ? name : null,
        help: inline ? "" : about,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!shut)
              CanvasWrap(runSpacing: cardGapIn(context), children: [
                ...rest,
                if (inline) CanvasHint(about, round: true),
              ]),
            if (below != null && !shut) below!,
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return _card(context, theme);
    }
    var style = TextStyle(
      fontSize: 9,
      letterSpacing: 0.7,
      fontWeight: FontWeight.w600,
      color: theme.colors.onSurfaceVariant.withValues(alpha: 0.7),
    );
    Widget caption = Text(label.toUpperCase(), style: style);
    if (onRename != null) {
      caption =
          _RenamableCaption(label: label, style: style, onRename: onRename!);
    }
    // A chevron before the words; the whole caption is the target.
    if (folded != null) {
      caption = Material(
        // Its own Material, so the highlight stays with the control inside a
        // scrolling list rather than on whatever Material is above it. (The
        // same holds wherever this file says "Its own Material".)
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onFold,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(1, 2, 4, 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(folded! ? Icons.chevron_right : Icons.expand_more,
                  size: 13, color: style.color),
              const SizedBox(width: 2),
              caption,
            ]),
          ),
        ),
      );
    }
    var shut = folded == true;

    // Every "?" in the group goes together on its heading row, on the right.
    var about = [
      if (help != null && help!.isNotEmpty) help!,
      for (var c in children)
        if (c is CanvasHint) c.message,
    ].join("\n\n");
    var controls = [
      for (var c in children)
        if (c is! CanvasHint) c
    ];
    var hint = about.isEmpty ? null : CanvasHint(about);

    // Along the band the groups sit side by side, so what separates them is
    // room to the right and a line between them, not a rule underneath.
    if (CanvasControlScope.isInline(context)) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hideCaption || hint != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 5, left: 1),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!hideCaption) caption,
                        if (hint != null) hint,
                      ])),
                // Spaced as well as run-spaced, so groups do not touch.
                // Centred: a switch, a captioned box and a readout differ
                // in height on a one-line strip.
                if (!shut)
                  Wrap(
                    spacing: 4,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: controls,
                  ),
                if (below != null && !shut) below!,
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Container(
                  width: 1,
                  height: bandGroupHeight,
                  color: theme.colors.outlineVariant.withValues(alpha: 0.45)),
            ),
          ],
        ),
      );
    }

    return Padding(
      // Every group leaves the same gap under it, and a rule sits in the
      // middle of a doubled one, so the line belongs to neither group.
      padding: const EdgeInsets.only(bottom: canvasGroupGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hideCaption || hint != null)
            Padding(
                padding: EdgeInsets.only(bottom: captionGap, left: 1),
                child: Row(children: [
                  Expanded(
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: hideCaption ? const SizedBox.shrink() : caption),
                  ),
                  if (hint != null) hint,
                ])),
          // No spacing: each control carries its own right-hand padding.
          if (!shut) CanvasWrap(runSpacing: canvasRowGap, children: controls),
          if (below != null && !shut) below!,
          if (rule) const CanvasGroupRule(),
        ],
      ),
    );
  }
}

/// canvasCard is a card in a section: a [title] with a "?" holding [help]
/// beside it (either may be missing) over [body], on a ground of its own, so
/// a section reads as a stack of cards each saying what it is.
Widget canvasCard(BuildContext context,
    {Widget? title, String help = "", required Widget body}) {
  var theme = ThemeNotifier.of(context);
  var heading = title != null || help.isNotEmpty;
  // In a dense panel, a group is its name in small capitals over its
  // controls, with no ground of its own.
  if (CanvasDense.on(context)) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: title ?? const SizedBox.shrink()),
                if (help.isNotEmpty) CanvasHint(help),
              ]),
            ),
          body,
        ],
      ),
    );
  }
  // A card inside a card -- a group in a folding part of a section -- is
  // a block with its name over it, not a ground on a ground.
  if (context.dependOnInheritedWidgetOfExactType<_InCard>() != null) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 10),
              child: Row(children: [
                Expanded(child: title ?? const SizedBox.shrink()),
                if (help.isNotEmpty) CanvasHint(help, round: true),
              ]),
            ),
          body,
        ],
      ),
    );
  }
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.45),
      border:
          Border.all(color: theme.colors.outlineVariant.withValues(alpha: 0.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (heading)
          Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 12),
            child: Row(children: [
              Expanded(child: title ?? const SizedBox.shrink()),
              if (help.isNotEmpty) CanvasHint(help, round: true),
            ]),
          ),
        _InCard(child: body),
      ],
    ),
  );
}

/// _InCard marks what is inside a card, so a card in it draws as a block.
class _InCard extends InheritedWidget {
  const _InCard({required super.child});

  @override
  bool updateShouldNotify(_InCard old) => false;
}

/// canvasCardTitle is a card's name, as text.
Widget canvasCardTitle(BuildContext context, String text) => Text(text,
    style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: ThemeNotifier.of(context).colors.onSurface));

/// CanvasMoreGroup is a group of settings with the rest behind a button at
/// the end of its first line: what changes often is in view, what is set
/// once is one press away. The open state is remembered under [remember]
/// for the run, so a panel rebuilt on every change does not shut it.
class CanvasMoreGroup extends StatefulWidget {
  final String label;
  final bool hideCaption;

  /// rule is the line under the group; see CanvasControlGroup.rule.
  final bool rule;

  /// remember names where the open state is kept; null keeps it only while
  /// the widget is in the tree.
  final String? remember;

  /// row is always shown and more is what the button reveals. The button
  /// ends the row, so [row] should leave space for it.
  final List<Widget> row;
  final List<Widget> more;

  /// tooltip says what is behind the button.
  final String tooltip;

  /// onRename: see CanvasControlGroup.onRename.
  final ValueChanged<String>? onRename;

  const CanvasMoreGroup({
    required this.label,
    required this.row,
    required this.more,
    this.tooltip = "More settings",
    this.hideCaption = false,
    this.rule = true,
    this.remember,
    this.onRename,
    super.key,
  });

  @override
  State<CanvasMoreGroup> createState() => _CanvasMoreGroupState();
}

class _CanvasMoreGroupState extends State<CanvasMoreGroup> {
  static final Map<String, bool> _remembered = {};

  late bool _open = _remembered[widget.remember] ?? false;

  void _toggle() {
    setState(() => _open = !_open);
    var key = widget.remember;
    if (key != null) _remembered[key] = _open;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // In a card, everything at once: the section it is in already folds.
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return CanvasControlGroup(
        label: widget.label,
        hideCaption: widget.hideCaption,
        rule: widget.rule,
        onRename: widget.onRename,
        children: [
          ...widget.row,
          if (widget.more.isNotEmpty) const CanvasLineBreak(),
          ...widget.more,
        ],
      );
    }
    return CanvasControlGroup(
      label: widget.label,
      hideCaption: widget.hideCaption,
      rule: widget.rule,
      onRename: widget.onRename,
      // What the button opened, on a tinted ground that shows where it
      // starts and stops. It is laid out apart, so opening it cannot narrow
      // the button's own row.
      below: !_open
          ? null
          : Padding(
              key: const ValueKey("more-ground"),
              padding: const EdgeInsets.only(top: canvasRowGap),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(canvasMoreInset,
                    canvasMoreInset, canvasMoreInset - 3, canvasMoreInset),
                decoration: BoxDecoration(
                  // A boxed section's ground, a little stronger.
                  color: theme.colors.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: Border.all(
                      color:
                          theme.colors.outlineVariant.withValues(alpha: 0.55)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child:
                    CanvasWrap(runSpacing: canvasRowGap, children: widget.more),
              ),
            ),
      children: [
        ...widget.row,
        if (widget.more.isNotEmpty)
          CanvasIconButton(
            key: ValueKey("more-${widget.remember ?? widget.label}"),
            icon: _open ? Icons.expand_less : Icons.tune,
            tooltip: _open ? "Hide these settings" : widget.tooltip,
            active: _open,
            onPressed: _toggle,
          ),
      ],
    );
  }
}

/// _RenamableCaption is a group's caption renamed by double-clicking, never
/// a single click, since these captions sit above controls people aim at.
class _RenamableCaption extends StatefulWidget {
  final String label;
  final TextStyle style;
  final ValueChanged<String> onRename;

  const _RenamableCaption(
      {required this.label, required this.style, required this.onRename});

  @override
  State<_RenamableCaption> createState() => _RenamableCaptionState();
}

class _RenamableCaptionState extends State<_RenamableCaption> {
  bool _typing = false;
  late final TextEditingController _text =
      TextEditingController(text: widget.label);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _finish();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = widget.label;
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _typing = true);
    _focus.requestFocus();
  }

  void _finish() {
    if (!_typing) return;
    setState(() => _typing = false);
    widget.onRename(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (!_typing) {
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          onDoubleTap: _start,
          child: CanvasTip(
            message: "Double-click to rename",
            waitDuration: CanvasNoHover.on(context)
                ? const Duration(days: 1)
                : const Duration(milliseconds: 700),
            child: Text(widget.label.toUpperCase(), style: widget.style),
          ),
        ),
      );
    }
    return SizedBox(
      width: 160,
      height: controlLabelHeight + 6,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        style: TextStyle(fontSize: 10, color: theme.colors.onSurface),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        ),
        onSubmitted: (_) => _finish(),
        onTapOutside: (_) => _finish(),
      ),
    );
  }
}

/// canvasMoreInset is the padding inside an opened more-settings ground.
const double canvasMoreInset = 8;

/// CanvasGroupRule is the line between one group of settings and the next,
/// midway: the gap above it matches the gap below.
class CanvasGroupRule extends StatelessWidget {
  const CanvasGroupRule({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: canvasGroupGap),
        child: Container(
            height: 1,
            color: ThemeNotifier.of(context)
                .colors
                .outlineVariant
                .withValues(alpha: 0.45)),
      );
}

/// CanvasExpander is a heading that opens to reveal a long list (a team's
/// squad, say). Not ExpansionTile, whose height, dividers and animation are
/// a Material list's.
class CanvasExpander extends StatefulWidget {
  final String label;

  /// trailing is shown beside the label (a count, usually), ellipsised
  /// rather than widening the heading.
  final String? trailing;

  /// action is a button on the right of the heading, working whether the
  /// section is open or shut (refreshing a table's data, say).
  final Widget? action;

  final List<Widget> children;

  final bool initiallyOpen;

  /// remember names where this section's open state is kept (see
  /// _rememberedSections), or null to start closed every time.
  final String? remember;

  /// flat draws only the children, always open, for a section already
  /// inside one of its own.
  final bool flat;

  const CanvasExpander({
    required this.label,
    required this.children,
    this.trailing,
    this.action,
    this.initiallyOpen = false,
    this.remember,
    this.flat = false,
    super.key,
  });

  @override
  State<CanvasExpander> createState() => _CanvasExpanderState();
}

/// _rememberedSections is every named section's open state for this run,
/// shared by [CanvasExpander] and [CanvasFoldingGroup]. In memory as well as
/// on disk, because a panel is rebuilt on every selection change and a fresh
/// State reading the disk asynchronously would show the section shut first.
final Map<String, bool> _rememberedSections = {};

/// forgetSectionsForTest lets go of everything the controls keep for a run,
/// as a new run has it: which sections and "more" groups are open, which
/// side fields are split into four, and the widths measured for dropdowns.
/// State added to this library that outlasts a widget belongs here.
@visibleForTesting
void forgetSectionsForTest() {
  _rememberedSections.clear();
  _CanvasMoreGroupState._remembered.clear();
  _unlinked.clear();
  CanvasDropdown._widths.clear();
}

/// _restoreSection loads a section's saved state and tells [then].
Future<void> _restoreSection(String key, ValueChanged<bool> then) async {
  var saved = await StorageManager.readData("canvasSection.$key");
  if (saved is! bool) return;
  _rememberedSections[key] = saved;
  then(saved);
}

void _keepSection(String? key, bool open) {
  if (key == null) return;
  _rememberedSections[key] = open;
  StorageManager.saveData("canvasSection.$key", open);
}

/// rememberedSection, restoreSection and keepSection share this memory with
/// panel_kit.dart's sections.
bool? rememberedSection(String key) => _rememberedSections[key];

Future<void> restoreSection(String key, ValueChanged<bool> then) =>
    _restoreSection(key, then);

void keepSection(String? key, bool open) => _keepSection(key, open);

class _CanvasExpanderState extends State<CanvasExpander> {
  late bool _open =
      _rememberedSections[widget.remember] ?? widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    var key = widget.remember;
    if (key != null && !_rememberedSections.containsKey(key)) {
      _restoreSection(key, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    _keepSection(widget.remember, _open);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (widget.flat) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: widget.children,
      );
    }
    // In a section, a card that folds when its name is pressed.
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      var muted = theme.colors.onSurfaceVariant;
      return canvasCard(context,
          title: Row(children: [
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: widget.remember == null
                      ? null
                      : ValueKey("expander-${widget.remember}"),
                  borderRadius: BorderRadius.circular(6),
                  onTap: _toggle,
                  child: Row(children: [
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(Icons.chevron_right, size: 18, color: muted),
                    ),
                    const SizedBox(width: 4),
                    Flexible(child: canvasCardTitle(context, widget.label)),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(widget.trailing!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: muted)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            if (widget.action != null) widget.action!,
          ]),
          body: !_open
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children,
                  ),
                ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Down the sidebar the action sits at the right edge with the summary
        // taking what is left. On the band, a horizontal scroller with
        // unbounded width, an Expanded asserts, so the heading shrink-wraps.
        LayoutBuilder(builder: (context, constraints) {
          var fills = constraints.maxWidth.isFinite;
          Widget heading = Material(
            // Its own Material: see CanvasControlGroup.
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_open ? Icons.expand_more : Icons.chevron_right,
                      size: 16, color: theme.colors.onSurfaceVariant),
                  const SizedBox(width: 3),
                  // Both name and summary clip: a Text that cannot shrink
                  // overflows however flexible everything beside it is.
                  Flexible(
                    child: Text(
                      widget.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        widget.trailing!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9,
                            color: theme.colors.onSurfaceVariant
                                .withValues(alpha: 0.5)),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          );

          return Row(
            mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
            children: [
              fills ? Expanded(child: heading) : Flexible(child: heading),
              // Outside the InkWell, so pressing it does not fold the section.
              if (widget.action != null) widget.action!,
            ],
          );
        }),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// CanvasFoldingGroup is a [CanvasControlGroup] that can be shut by a
/// chevron on its caption. [remember] names where that is kept, so it lasts
/// across a rebuild and a restart (see _rememberedSections).
class CanvasFoldingGroup extends StatefulWidget {
  final String label;
  final List<Widget> children;

  final String remember;

  /// startShut is whether an untouched group starts shut.
  final bool startShut;

  final bool rule;
  final Widget? below;

  const CanvasFoldingGroup({
    required this.label,
    required this.children,
    required this.remember,
    this.startShut = false,
    this.rule = true,
    this.below,
    super.key,
  });

  @override
  State<CanvasFoldingGroup> createState() => _CanvasFoldingGroupState();
}

class _CanvasFoldingGroupState extends State<CanvasFoldingGroup> {
  late bool _shut =
      !(_rememberedSections[widget.remember] ?? !widget.startShut);

  @override
  void initState() {
    super.initState();
    if (!_rememberedSections.containsKey(widget.remember)) {
      _restoreSection(widget.remember, (open) {
        if (mounted) setState(() => _shut = !open);
      });
    }
  }

  void _toggle() {
    setState(() => _shut = !_shut);
    _keepSection(widget.remember, !_shut);
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
        label: widget.label,
        rule: widget.rule,
        below: widget.below,
        folded: _shut,
        onFold: _toggle,
        children: widget.children,
      );
}
