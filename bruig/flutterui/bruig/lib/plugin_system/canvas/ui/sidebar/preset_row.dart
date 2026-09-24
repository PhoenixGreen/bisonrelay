import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// preset_row.dart is one saved thing in the Presets sidebar.
//
// The same row whichever list it is in -- an element, a scene, a whole canvas
// -- because the things you do to one are the same three: use it, rename it,
// throw it away. A second row shape per list would be three places to keep a
// rename working.

/// askForPresetName asks what to call one, with [initial] filled in.
///
/// Shared by everything that saves a preset -- an element's settings, a
/// scene's menu, a canvas in the Files list -- so that all three ask the same
/// question in the same words.
Future<String?> askForPresetName(BuildContext context, String title,
    {String initial = ""}) {
  var text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: "Name"),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel")),
        TextButton(
            onPressed: () => Navigator.of(context).pop(text.text),
            child: const Text("OK")),
      ],
    ),
  );
}

/// PresetRow is a preset's name, what it is, and its own menu.
class PresetRow extends StatefulWidget {
  final String name;

  /// says is the line under the name: what kind of element it makes, how
  /// many scenes it holds. Left out where there is nothing to say.
  final String? says;

  final IconData icon;

  /// onUse is the tap: add it, or start from it.
  final VoidCallback onUse;

  /// onRename is null for a preset that is not the reader's to rename --
  /// the ones that ship with the app.
  final ValueChanged<String>? onRename;

  /// onDelete is null for the same ones.
  final VoidCallback? onDelete;

  /// extra are more entries for the row's menu, by label.
  final Map<String, VoidCallback> extra;

  /// leading is drawn in place of the icon where there is a picture of the
  /// preset to show instead.
  final Widget? leading;

  const PresetRow({
    required this.name,
    required this.icon,
    required this.onUse,
    this.says,
    this.onRename,
    this.onDelete,
    this.extra = const {},
    this.leading,
    super.key,
  });

  @override
  State<PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<PresetRow> {
  /// _renaming is whether the name has been opened for typing.
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();

  /// _clicks counts the second click of a pair on the name.
  ///
  /// Counted by hand rather than through a double-tap recognizer: one sits in
  /// the gesture arena and holds back the press that uses the preset and the
  /// one that opens its menu. See DoubleClick.
  final DoubleClick _clicks = DoubleClick();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _clicked() {
    if (!_clicks.isSecond(this) || widget.onRename == null) return;
    // After the frame: this replaces the very widget the pointer is inside.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _renaming = true;
        _name.text = widget.name;
      });
    });
  }

  void _commit() {
    if (!_renaming) return;
    var typed = _name.text.trim();
    setState(() => _renaming = false);
    if (typed.isEmpty || typed == widget.name) return;
    widget.onRename?.call(typed);
  }

  Future<void> _menu(BuildContext context) async {
    var box = context.findRenderObject() as RenderBox?;
    var overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    var where = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    var chose = await showMenu<String>(
      context: context,
      position: where,
      items: [
        for (var label in widget.extra.keys)
          PopupMenuItem(value: label, child: Text(label)),
        if (widget.onRename != null)
          const PopupMenuItem(value: "rename", child: Text("Rename…")),
        if (widget.onDelete != null)
          const PopupMenuItem(value: "delete", child: Text("Delete")),
      ],
    );
    if (!mounted || chose == null) return;
    switch (chose) {
      case "rename":
        setState(() {
          _renaming = true;
          _name.text = widget.name;
        });
      case "delete":
        widget.onDelete?.call();
      default:
        widget.extra[chose]?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var hasMenu = widget.onDelete != null ||
        widget.onRename != null ||
        widget.extra.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        // Its own Material, so the row's ink lands in front of whatever the
        // sidebar is painted with rather than behind it.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _renaming ? null : widget.onUse,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child: Row(children: [
              widget.leading ??
                  Icon(widget.icon,
                      size: 16, color: theme.colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _renaming
                        ? TextField(
                            key: const ValueKey("presetRename"),
                            controller: _name,
                            autofocus: true,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                                isDense: true, border: InputBorder.none),
                            onSubmitted: (_) => _commit(),
                            onTapOutside: (_) => _commit(),
                          )
                        : Listener(
                            // Double-clicked to rename, counted by hand. See
                            // _clicked.
                            onPointerDown: (_) => _clicked(),
                            child: Text(widget.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                    if (widget.says case var says?)
                      Text(says,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: theme.colors.onSurfaceVariant)),
                  ],
                ),
              ),
              if (hasMenu)
                Builder(
                  // The button's own context, so the menu opens under the
                  // button rather than beside the panel.
                  builder: (context) => Tooltip(
                    message: "More",
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _menu(context),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.more_horiz,
                            size: 15, color: theme.colors.onSurfaceVariant),
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
