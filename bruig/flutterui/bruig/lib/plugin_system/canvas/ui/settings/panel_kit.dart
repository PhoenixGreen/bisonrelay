import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// panel_kit.dart is the parts of the sectioned settings panel: a section that
// folds, the search and fold-all bar over a run of them, a row of picture
// tiles, and the stepper -- a number with an arrow either side.
//
// Built for the picture's panel first and meant for every element's after it,
// so nothing here knows what a picture is. See image_settings.dart for the
// first panel built from them, and settings/README.md for the rows inside a
// section, which are the same groups as ever.

/// stepperHeight is a stepper's box. Taller than the other controls' because
/// the arrows are pressed rather than aimed at.
const double stepperHeight = 30;

/// CanvasStepper is a number with an arrow either side of it.
///
/// The arrows nudge it a [step] at a time, and repeat while held. The number
/// itself is dragged sideways to run it up and down -- from the first pixel,
/// since nothing else in the box wants a drag -- and double-clicked to type
/// one. Changed from [defaultValue], its caption turns the accent colour and
/// gains a ↺ that puts it back.
class CanvasStepper extends StatefulWidget implements CanvasGrowable {
  @override
  double get least => width;

  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;

  /// step is how far an arrow moves it. Null is its last digit.
  final double? step;

  /// dragStep is how far one pixel of a drag moves it. Null is its last
  /// digit, or a fifth of [step] where that is coarser -- a step of five
  /// percent dragged at one percent a pixel is about right; at a tenth it is
  /// five hundred pixels from one end to the other.
  final double? dragStep;

  final String suffix;

  /// defaultValue is what it starts at, for the ↺. Null where it has no one
  /// value it starts at -- a position.
  final double? defaultValue;

  final double width;

  @override
  final bool grow;

  final ValueChanged<double> onChanged;
  final VoidCallback? onCommit;

  const CanvasStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = -100000,
    this.max = 100000,
    this.decimals = 0,
    this.step,
    this.dragStep,
    this.suffix = "",
    this.defaultValue,
    this.width = 104,
    this.grow = true,
    this.onCommit,
    super.key,
  });

  /// changed is whether it is away from [defaultValue].
  bool get changed {
    var d = defaultValue;
    if (d == null) return false;
    return (value - d).abs() > math.pow(10, -decimals) / 2;
  }

  @override
  State<CanvasStepper> createState() => _CanvasStepperState();
}

class _CanvasStepperState extends State<CanvasStepper> {
  bool _editing = false;
  late final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  double _from = 0;
  double _startX = 0;
  bool _down = false;
  bool _dragging = false;

  Timer? _repeat;
  bool _held = false;

  /// _running is the value while an arrow is held, counted here rather than
  /// read back off the widget: the repeats can come faster than the panel
  /// rebuilds, and each one read from a value that had not caught up.
  double _running = 0;

  double get _digit => math.pow(10, -widget.decimals).toDouble();
  double get _step => widget.step ?? _digit;
  double get _dragStep =>
      widget.dragStep ?? math.max(_digit, (widget.step ?? 0) / 5);

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  double _clamp(double v) => v.clamp(widget.min, widget.max).toDouble();

  /// _snap rounds to the field's digits, so arrows from 0.1 land on 0.3 and
  /// not on 0.30000000000000004.
  double _snap(double v) =>
      double.parse(_clamp(v).toStringAsFixed(widget.decimals));

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finishTyping(keep: true);
    });
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTyping() {
    _text.text = _format(widget.value);
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _finishTyping({required bool keep}) {
    if (!_editing) return;
    if (keep) {
      var parsed = double.tryParse(_text.text.trim());
      if (parsed != null) {
        widget.onChanged(_snap(parsed));
        widget.onCommit?.call();
      }
    }
    setState(() => _editing = false);
  }

  void _nudge(int by) {
    _running = _snap(_running + by * _step);
    widget.onChanged(_running);
  }

  void _press(int by) {
    _held = true;
    _running = widget.value;
    _nudge(by);
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 380), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 60), (_) {
        if (mounted && _held) _nudge(by);
      });
    });
  }

  void _release() {
    _repeat?.cancel();
    _repeat = null;
    if (!_held) return;
    _held = false;
    widget.onCommit?.call();
  }

  Widget _arrow(ThemeNotifier theme, IconData icon, int by, String key) {
    var can = by < 0 ? widget.value > widget.min : widget.value < widget.max;
    return Semantics(
      button: true,
      label: "${by < 0 ? "Less" : "More"} ${widget.label}",
      child: GestureDetector(
        key: widget.key is ValueKey<String>
            ? ValueKey("${(widget.key as ValueKey<String>).value}-$key")
            : null,
        behavior: HitTestBehavior.opaque,
        onTapDown: can ? (_) => _press(by) : null,
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        child: MouseRegion(
          cursor: can ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: SizedBox(
            width: 22,
            child: Icon(icon,
                size: 16,
                color: theme.colors.onSurfaceVariant
                    .withValues(alpha: can ? 0.9 : 0.3)),
          ),
        ),
      ),
    );
  }

  Widget _number(ThemeNotifier theme, bool changed) {
    if (_editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _finishTyping(keep: false),
        },
        child: TextField(
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"^-?[0-9]*\.?[0-9]*")),
          ],
          decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero),
          onSubmitted: (_) => _finishTyping(keep: true),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _from = widget.value;
          _startX = event.position.dx;
          _down = true;
          _dragging = false;
        },
        onPointerMove: (event) {
          if (!_down) return;
          var travelled = event.position.dx - _startX;
          // A few pixels of give, so the two presses of a double-click do
          // not nudge the number on their way.
          if (!_dragging && travelled.abs() < 3) return;
          _dragging = true;
          var fine = HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0;
          widget.onChanged(_snap(_from + travelled * _dragStep * fine));
        },
        onPointerUp: (_) {
          _down = false;
          if (_dragging) widget.onCommit?.call();
          _dragging = false;
        },
        onPointerCancel: (_) {
          _down = false;
          _dragging = false;
        },
        child: GestureDetector(
          key: widget.key is ValueKey<String>
              ? ValueKey("${(widget.key as ValueKey<String>).value}-number")
              : null,
          onDoubleTap: _startTyping,
          child: Center(
            child: Text(
              "${_format(widget.value)}${widget.suffix}",
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var changed = widget.changed;
    var accent = theme.colors.primary;
    var caption = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 9.5,
                height: 1.1,
                fontWeight: changed ? FontWeight.w600 : FontWeight.normal,
                color: changed ? accent : theme.colors.onSurfaceVariant)),
      ),
      if (changed)
        Semantics(
          button: true,
          label: "Reset ${widget.label}",
          child: GestureDetector(
            key: widget.key is ValueKey<String>
                ? ValueKey("${(widget.key as ValueKey<String>).value}-reset")
                : null,
            onTap: () {
              widget.onChanged(widget.defaultValue!);
              widget.onCommit?.call();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.restart_alt, size: 11, color: accent),
              ),
            ),
          ),
        ),
    ]);
    var box = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
            color: changed
                ? accent.withValues(alpha: 0.55)
                : theme.colors.outlineVariant),
      ),
      // Stretched, so each arrow is pressed over the box's whole height,
      // not just over its icon.
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _arrow(theme, Icons.chevron_left, -1, "less"),
        Container(width: 1, color: theme.colors.outlineVariant),
        Expanded(child: _number(theme, changed)),
        Container(width: 1, color: theme.colors.outlineVariant),
        _arrow(theme, Icons.chevron_right, 1, "more"),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(right: canvasCaptionedGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Caption and box together are as tall as any other captioned
          // control, so a stepper stands level with the buttons and fields
          // beside it: the box's extra height comes out of the gap.
          SizedBox(height: controlLabelHeight, child: caption),
          SizedBox(
              height: math.max(0.0,
                  controlWithLabelHeight - controlLabelHeight - stepperHeight)),
          canvasSized(context,
              min: CanvasControlScope.widthFor(context, widget.width),
              height: stepperHeight,
              grow: widget.grow,
              child: box),
        ],
      ),
    );
  }
}

/// CanvasTile is one choice in a row of [CanvasTiles]: a picture of what it
/// does and the word for it.
class CanvasTile<T> {
  final T value;
  final String label;

  /// preview draws what choosing it does. Null shows [icon] instead.
  final WidgetBuilder? preview;
  final IconData? icon;

  const CanvasTile(this.value, this.label, {this.preview, this.icon});
}

/// CanvasTiles is a choice made by looking rather than by reading: a grid of
/// small pictures, each named under it.
///
/// Pointed at, a tile is tried on the canvas through [onPreview] -- null when
/// the pointer leaves -- as a dropdown's options are; see CanvasDropdown. With
/// [multiple], each tile is switched on and off by itself and wears a tick.
class CanvasTiles<T> extends StatelessWidget {
  final String? label;
  final List<CanvasTile<T>> tiles;
  final bool Function(T) selected;
  final ValueChanged<T> onPick;
  final ValueChanged<T?>? onPreview;
  final int columns;
  final bool multiple;

  /// keyOf names each tile, for the tests.
  final String Function(T)? keyOf;

  /// previewHeight is how tall the picture on each tile is.
  final double previewHeight;

  const CanvasTiles({
    required this.tiles,
    required this.selected,
    required this.onPick,
    this.label,
    this.onPreview,
    this.columns = 3,
    this.multiple = false,
    this.keyOf,
    this.previewHeight = 38,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    const gap = 6.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: canvasRowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: controlLabelGap + 1),
              child: Text(label!,
                  style: TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      color: theme.colors.onSurfaceVariant)),
            ),
          LayoutBuilder(builder: (context, box) {
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = (width - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var t in tiles)
                  SizedBox(
                      width: math.max(40, each),
                      child: _tile(context, theme, t)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ThemeNotifier theme, CanvasTile<T> t) {
    var on = selected(t.value);
    var accent = theme.colors.primary;
    return MouseRegion(
      onEnter:
          onPreview == null || multiple ? null : (_) => onPreview!(t.value),
      onExit: onPreview == null || multiple ? null : (_) => onPreview!(null),
      child: Semantics(
        button: true,
        selected: on,
        label: t.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: keyOf == null ? null : ValueKey(keyOf!(t.value)),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              onPreview?.call(null);
              onPick(t.value);
            },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: on ? accent.withValues(alpha: 0.14) : null,
                border: Border.all(
                    color: on ? accent : theme.colors.outlineVariant,
                    width: on ? 1.5 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(children: [
                  Container(
                    height: previewHeight,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: theme.colors.surfaceContainerHighest,
                    ),
                    alignment: Alignment.center,
                    child: t.preview != null
                        ? SizedBox.expand(child: t.preview!(context))
                        : Icon(t.icon ?? Icons.circle_outlined,
                            size: 20,
                            color: on ? accent : theme.colors.onSurfaceVariant),
                  ),
                  if (multiple && on)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                        child: Icon(Icons.check,
                            size: 10, color: theme.colors.onPrimary),
                      ),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                        color: theme.colors.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// CanvasSectionsController is what a run of sections shares: the words
/// typed into the search over them, and a fold-all.
class CanvasSectionsController extends ChangeNotifier {
  String _query = "";
  String get query => _query;
  set query(String v) {
    if (v == _query) return;
    _query = v;
    notifyListeners();
  }

  /// fold is the last fold-all: every section to [foldOpen], counted by
  /// [folds] so a section can tell a new one from one it has seen.
  int folds = 0;
  bool foldOpen = false;
  void foldAll(bool open) {
    foldOpen = open;
    folds++;
    notifyListeners();
  }

  /// opened is every section's open state as it reports it, for the fold-all
  /// button's icon.
  final Map<String, bool> opened = {};
  bool get anyOpen => opened.values.any((o) => o);

  void _report(String key, bool open) {
    if (opened[key] == open) return;
    opened[key] = open;
    // After the frame: a section reports while it builds.
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  void _forget(String key) => opened.remove(key);
}

class _SectionsScope extends InheritedNotifier<CanvasSectionsController> {
  const _SectionsScope({required super.notifier, required super.child});

  static CanvasSectionsController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SectionsScope>()?.notifier;
}

/// CanvasSections is a run of [CanvasSection]s with a search box and a
/// fold-all button over them.
class CanvasSections extends StatefulWidget {
  final List<Widget> children;

  /// what names the settings for the search box's hint -- "a picture layer".
  final String what;

  const CanvasSections({required this.children, this.what = "", super.key});

  @override
  State<CanvasSections> createState() => _CanvasSectionsState();
}

/// _sectionQueries keeps the search across the panel being rebuilt -- which
/// it is on every edit -- for this run of the app.
final Map<String, String> _sectionQueries = {};

class _CanvasSectionsState extends State<CanvasSections> {
  late final CanvasSectionsController _sections = CanvasSectionsController()
    ..query = _sectionQueries[_memoryKey] ?? "";
  late final TextEditingController _search =
      TextEditingController(text: _sections.query);

  String get _memoryKey => widget.key is ValueKey<String>
      ? (widget.key as ValueKey<String>).value
      : "sections";

  @override
  void dispose() {
    _sections.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _SectionsScope(
      notifier: _sections,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    key: const ValueKey("settingsSearch"),
                    controller: _search,
                    style: const TextStyle(fontSize: 12),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "Find a setting",
                      hintStyle: TextStyle(
                          fontSize: 12,
                          color: theme.colors.onSurfaceVariant
                              .withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.search,
                          size: 16, color: theme.colors.onSurfaceVariant),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 30, minHeight: 28),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : InkWell(
                              key: const ValueKey("settingsSearchClear"),
                              onTap: () {
                                _search.clear();
                                _sectionQueries[_memoryKey] = "";
                                _sections.query = "";
                                setState(() {});
                              },
                              child: Icon(Icons.close,
                                  size: 14,
                                  color: theme.colors.onSurfaceVariant),
                            ),
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: theme.colors.outlineVariant)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: theme.colors.outlineVariant)),
                    ),
                    onChanged: (v) {
                      _sectionQueries[_memoryKey] = v;
                      _sections.query = v;
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ListenableBuilder(
                listenable: _sections,
                builder: (context, _) {
                  var open = _sections.anyOpen;
                  return CanvasIconButton(
                    key: const ValueKey("settingsFoldAll"),
                    tight: true,
                    icon: open ? Icons.unfold_less : Icons.unfold_more,
                    tooltip: open ? "Fold every section" : "Open every section",
                    onPressed: () => _sections.foldAll(!open),
                  );
                },
              ),
            ]),
          ),
          ...widget.children,
          ListenableBuilder(
            listenable: _sections,
            builder: (context, _) {
              var q = _sections.query.trim();
              var any = widget.children
                  .whereType<CanvasSection>()
                  .any((section) => section.matches(q));
              if (q.isEmpty || any) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "No setting called “$q” on ${widget.what.isEmpty ? "this" : widget.what}.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, color: theme.colors.onSurfaceVariant),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// CanvasSection is one subject of an element's settings -- where it is, its
/// mask, its colour -- as a card that folds.
///
/// Shut, it is its icon, its name and a line saying how it is set now, so
/// the panel reads as a summary of the element before anything is opened.
/// [changes] puts a dot on it, and once open a reset beside the chevron, for
/// a section moved away from how it starts.
class CanvasSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String summary;

  /// scope is a tag beside the title for a section that is not about what
  /// the rest are -- "Whole image" on a picture's frame, under a layer's
  /// settings.
  final String? scope;

  final int changes;
  final VoidCallback? onReset;

  /// keywords are the words the search finds this section by, besides its
  /// title: the names of the settings in it.
  final List<String> keywords;

  /// remember names where its open state is kept, as CanvasExpander's.
  final String remember;
  final bool initiallyOpen;

  /// forceOpen opens it, whenever it turns true: a tool in hand opens the
  /// section it belongs to, picked from the keyboard or not.
  final bool forceOpen;
  final List<Widget> children;

  const CanvasSection({
    required this.icon,
    required this.title,
    required this.remember,
    required this.children,
    this.summary = "",
    this.scope,
    this.changes = 0,
    this.onReset,
    this.keywords = const [],
    this.initiallyOpen = false,
    this.forceOpen = false,
    super.key,
  });

  /// matches is whether the search [query] finds this section.
  bool matches(String query) {
    var q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [title, ...keywords].any((w) => w.toLowerCase().contains(q));
  }

  @override
  State<CanvasSection> createState() => _CanvasSectionState();
}

class _CanvasSectionState extends State<CanvasSection> {
  late bool _open = rememberedSection(widget.remember) ?? widget.initiallyOpen;
  int _folds = 0;
  CanvasSectionsController? _sections;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen) {
      _open = true;
    } else if (rememberedSection(widget.remember) == null) {
      restoreSection(widget.remember, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  @override
  void didUpdateWidget(CanvasSection old) {
    super.didUpdateWidget(old);
    if (widget.forceOpen && !old.forceOpen && !_open) {
      _open = true;
      keepSection(widget.remember, true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var sections = _SectionsScope.of(context);
    if (sections != _sections) {
      _sections = sections;
      _folds = sections?.folds ?? 0;
    }
    if (sections != null && sections.folds != _folds) {
      _folds = sections.folds;
      _open = sections.foldOpen;
      keepSection(widget.remember, _open);
    }
  }

  @override
  void dispose() {
    _sections?._forget(widget.remember);
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    keepSection(widget.remember, _open);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var sections = _SectionsScope.of(context);
    var query = sections?.query ?? "";
    var searching = query.trim().isNotEmpty;
    if (searching && !widget.matches(query)) return const SizedBox.shrink();
    var open = searching || _open;
    sections?._report(widget.remember, open);

    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    var changed = widget.changes > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: open
            ? theme.colors.surfaceContainerHighest.withValues(alpha: 0.35)
            : null,
        border: Border.all(
            color: open
                ? theme.colors.outline.withValues(alpha: 0.5)
                : theme.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey("section-${widget.remember}"),
                  borderRadius: BorderRadius.circular(10),
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
                    child: Row(children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: open
                              ? accent.withValues(alpha: 0.16)
                              : theme.colors.surfaceContainerHighest,
                        ),
                        child: Icon(widget.icon,
                            size: 16, color: open ? accent : muted),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colors.onSurface)),
                              ),
                              if (widget.scope != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: theme.colors.outlineVariant),
                                  ),
                                  child: Text(widget.scope!,
                                      style:
                                          TextStyle(fontSize: 9, color: muted)),
                                ),
                              ],
                            ]),
                            if (widget.summary.isNotEmpty)
                              Text(widget.summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(fontSize: 10.5, color: muted)),
                          ],
                        ),
                      ),
                      if (changed)
                        Container(
                          key: ValueKey("sectionChanged-${widget.remember}"),
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                        ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 120),
                        child:
                            Icon(Icons.chevron_right, size: 18, color: muted),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            // Outside the heading's ink, so pressing it does not also fold
            // the section.
            if (open && changed && widget.onReset != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CanvasIconButton(
                  key: ValueKey("sectionReset-${widget.remember}"),
                  tight: true,
                  icon: Icons.restart_alt,
                  tooltip: "Reset ${widget.title}",
                  onPressed: widget.onReset,
                ),
              ),
          ]),
          if (open)
            Padding(
              key: ValueKey("sectionBody-${widget.remember}"),
              padding: const EdgeInsets.fromLTRB(10, 2, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

/// CanvasToolTiles is a section's tools, as tiles with their names under
/// them, and -- on a line of their own below -- the settings of the one in
/// hand. Pressing the tool in hand puts it down again.
class CanvasToolTiles<T> extends StatelessWidget {
  final List<(T, IconData, String)> tools;
  final T? active;
  final ValueChanged<T?> onPick;
  final String Function(T) keyOf;
  final String Function(T) tooltipOf;

  /// settings are the active tool's, under the tiles.
  final List<Widget> settings;

  const CanvasToolTiles({
    required this.tools,
    required this.active,
    required this.onPick,
    required this.keyOf,
    required this.tooltipOf,
    this.settings = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: canvasGroupGap / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(builder: (context, box) {
            const gap = 5.0;
            var n = tools.length;
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = math.max(40.0, (width - gap * (n - 1)) / n);
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (var (tool, icon, short) in tools)
                SizedBox(
                  width: each,
                  child: Tooltip(
                    message: tooltipOf(tool),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: ValueKey(keyOf(tool)),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onPick(tool == active ? null : tool),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: tool == active
                                ? accent.withValues(alpha: 0.16)
                                : null,
                            border: Border.all(
                                color: tool == active
                                    ? accent
                                    : theme.colors.outlineVariant,
                                width: tool == active ? 1.5 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon,
                                  size: 18,
                                  color: tool == active
                                      ? accent
                                      : theme.colors.onSurfaceVariant),
                              const SizedBox(height: 3),
                              Text(short,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      color: theme.colors.onSurface)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
          if (active == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text("Pick a tool to work on the canvas.",
                  style: TextStyle(
                      fontSize: 10.5, color: theme.colors.onSurfaceVariant)),
            )
          else if (settings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CanvasWrap(children: settings),
            ),
        ],
      ),
    );
  }
}
