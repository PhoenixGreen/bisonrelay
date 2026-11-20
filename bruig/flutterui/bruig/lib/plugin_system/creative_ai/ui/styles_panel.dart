import 'dart:io';

import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:bruig/plugin_system/creative_ai/tools/style_ai_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// styles_panel.dart is the Styles panel of Creative AI's Canvas sidebar: keep
// the open canvas's style as a profile, and use one -- in the conversation,
// to restyle the canvas, or in Claude Code anywhere as a skill.

class StylesPanel extends StatefulWidget {
  final CreativeAi ai;
  const StylesPanel({required this.ai, super.key});

  @override
  State<StylesPanel> createState() => _StylesPanelState();
}

class _StylesPanelState extends State<StylesPanel> {
  StyleLibrary get styles => widget.ai.styles;

  @override
  void initState() {
    super.initState();
    if (!styles.loaded) styles.refresh();
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    var answer = await showDialog<(String, String, bool)>(
      context: context,
      builder: (context) =>
          _SaveStyleDialog(name: widget.ai.canvas().document.title),
    );
    if (answer == null) return;
    var (named, desc, withClaude) = answer;
    if (withClaude) {
      widget.ai.canvasChat.send(saveStylePrompt(named, desc));
      _say("Claude is studying the canvas: the style appears here when it "
          "is saved.");
      return;
    }
    try {
      await saveCanvasStyle(widget.ai, name: named, description: desc);
      _say("Saved the style $named.");
    } catch (e) {
      _say("Could not save the style: $e");
    }
  }

  Future<void> _editGuide(StyleProfile style) async {
    var answer = await showDialog<(String, String)>(
        context: context, builder: (context) => _GuideDialog(style: style));
    if (answer == null) return;
    await styles.updateGuide(style, guide: answer.$1, description: answer.$2);
  }

  Future<void> _delete(StyleProfile style) async {
    var go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete ${style.name}?"),
        content: const Text("Its guide and facts go. Canvases made in it "
            "stay as they are, and a copy added to Claude Code's skills "
            "stays there."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
              key: const ValueKey("styleDeleteConfirm"),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (go == true) await styles.delete(style);
  }

  Future<void> _toSkills(StyleProfile style) async {
    try {
      var into = await styles.copyToSkills(style);
      _say("Added to Claude Code's skills ($into). Claude Code uses it when "
          "a request mentions the style.");
    } catch (e) {
      _say("Could not add it: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return ListenableBuilder(
      listenable: Listenable.merge([styles, widget.ai.canvasChat]),
      builder: (context, _) {
        var list = styles.styles;
        var busy = widget.ai.canvasChat.running;
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey("stylesSave"),
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text("Save this canvas as a style"),
              ),
            ),
            const SizedBox(height: 8),
            // Words rather than a spinner: nothing here animates forever.
            if (!styles.loaded)
              Text("Reading the styles…",
                  style:
                      TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant))
            else if (styles.error case var error?)
              Text("The styles could not be read: $error",
                  style: TextStyle(fontSize: 12.5, color: colors.error))
            else if (list.isEmpty)
              Text(
                "No styles yet. Save a canvas whose look you like, then make "
                "new work in it: ask in the conversation with the style in "
                "use, or restyle another canvas with it.",
                style:
                    TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
              ),
            for (var s in list)
              _StyleCard(
                key: ValueKey("style-${s.slug}"),
                style: s,
                active: styles.active?.slug == s.slug,
                busy: busy,
                onUse: () =>
                    styles.active = styles.active?.slug == s.slug ? null : s,
                onRestyle: () =>
                    widget.ai.canvasChat.send(restylePrompt(s.name)),
                onEdit: () => _editGuide(s),
                onSkills: () => _toSkills(s),
                onDelete: () => _delete(s),
              ),
          ],
        );
      },
    );
  }
}

class _StyleCard extends StatelessWidget {
  final StyleProfile style;
  final bool active;
  final bool busy;
  final VoidCallback onUse;
  final VoidCallback onRestyle;
  final VoidCallback onEdit;
  final VoidCallback onSkills;
  final VoidCallback onDelete;

  const _StyleCard({
    required this.style,
    required this.active,
    required this.busy,
    required this.onUse,
    required this.onRestyle,
    required this.onEdit,
    required this.onSkills,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var preview = File(style.previewPath);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
            color: active ? colors.primary : colors.outlineVariant,
            width: active ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (preview.existsSync())
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(preview,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 72)),
              ),
            ),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(style.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              if (style.description.isNotEmpty)
                Text(style.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(spacing: 3, runSpacing: 3, children: [
                for (var c in style.colours.take(8))
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                  ),
              ]),
              if (style.fonts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(style.fonts.join(", "),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: colors.onSurfaceVariant)),
                ),
            ]),
          ),
          PopupMenuButton<String>(
            key: ValueKey("styleMenu-${style.slug}"),
            tooltip: "More",
            iconSize: 18,
            padding: EdgeInsets.zero,
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: "edit", height: 32, child: Text("Edit the guide…")),
              PopupMenuItem(
                  value: "skills",
                  height: 32,
                  child: Text("Add to Claude Code's skills")),
              PopupMenuItem(
                  value: "delete", height: 32, child: Text("Delete…")),
            ],
            onSelected: (v) => switch (v) {
              "edit" => onEdit(),
              "skills" => onSkills(),
              _ => onDelete(),
            },
          ),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          active
              ? FilledButton.tonal(
                  key: ValueKey("styleUse-${style.slug}"),
                  onPressed: onUse,
                  child: const Text("In use"))
              : OutlinedButton(
                  key: ValueKey("styleUse-${style.slug}"),
                  onPressed: onUse,
                  child: const Text("Use in the conversation")),
          TextButton(
            key: ValueKey("styleRestyle-${style.slug}"),
            onPressed: busy ? null : onRestyle,
            child: const Text("Restyle this canvas"),
          ),
        ]),
      ]),
    );
  }
}

/// _SaveStyleDialog asks a new style's name, what it is for, and whether
/// Claude writes its guide. Its fields are its own, so they outlive its
/// closing.
class _SaveStyleDialog extends StatefulWidget {
  final String name;
  const _SaveStyleDialog({required this.name});

  @override
  State<_SaveStyleDialog> createState() => _SaveStyleDialogState();
}

class _SaveStyleDialogState extends State<_SaveStyleDialog> {
  late final _name = TextEditingController(text: widget.name);
  final _description = TextEditingController();
  bool _withClaude = true;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _done() {
    var name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name, _description.text.trim(), _withClaude));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text("Save as a style"),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey("styleName"),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              key: const ValueKey("styleDescription"),
              controller: _description,
              decoration:
                  const InputDecoration(labelText: "What it is for (optional)"),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey("styleWithClaude"),
              contentPadding: EdgeInsets.zero,
              value: _withClaude,
              onChanged: (v) => setState(() => _withClaude = v ?? true),
              title: const Text("Have Claude study it and write the guide"),
              subtitle: const Text("Off: the guide lists what was measured, "
                  "for you to add to."),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          FilledButton(
              key: const ValueKey("styleSaveConfirm"),
              onPressed: _done,
              child: const Text("Save")),
        ],
      );
}

/// _GuideDialog edits a style's guide and what it is for.
class _GuideDialog extends StatefulWidget {
  final StyleProfile style;
  const _GuideDialog({required this.style});

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  late final _guide = TextEditingController(text: widget.style.guide);
  late final _description =
      TextEditingController(text: widget.style.description);

  @override
  void dispose() {
    _guide.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("The ${widget.style.name} guide"),
        content: SizedBox(
          width: 560,
          height: 480,
          child: Column(children: [
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: "What it is for"),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                key: const ValueKey("styleGuideEdit"),
                controller: _guide,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "The style's rules, in Markdown"),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          FilledButton(
              key: const ValueKey("styleGuideSave"),
              onPressed: () => Navigator.pop(
                  context, (_guide.text, _description.text.trim())),
              child: const Text("Save")),
        ],
      );
}
