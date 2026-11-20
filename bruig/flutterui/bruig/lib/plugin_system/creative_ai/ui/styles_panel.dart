import 'dart:io';

import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/session/ai_chat.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:bruig/plugin_system/creative_ai/tools/style_ai_tools.dart';
import 'package:bruig/plugin_system/creative_ai/ui/style_sharing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// styles_panel.dart is the Styles panel of Creative AI's sidebars: keep the
// open canvas's look, or the open document's voice, as a style, and use one
// -- in the conversation, to restyle what is open, or in Claude Code anywhere
// as a skill. One panel for both kinds; what differs is said by [kind].

class StylesPanel extends StatefulWidget {
  final CreativeAi ai;
  final StyleKind kind;
  const StylesPanel(
      {required this.ai, this.kind = StyleKind.canvas, super.key});

  @override
  State<StylesPanel> createState() => _StylesPanelState();
}

class _StylesPanelState extends State<StylesPanel> {
  StyleLibrary get styles => widget.ai.styles;
  bool get _canvas => widget.kind == StyleKind.canvas;
  AiChat get _chat => _canvas ? widget.ai.canvasChat : widget.ai.writingChat;

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
      builder: (context) => _SaveStyleDialog(
          name: _canvas
              ? widget.ai.canvas().document.title
              : widget.ai.library().openName ?? "",
          what: _canvas ? "canvas" : "document"),
    );
    if (answer == null) return;
    var (named, desc, withClaude) = answer;
    if (withClaude) {
      _chat.send(_canvas
          ? saveStylePrompt(named, desc)
          : saveWritingStylePrompt(named, desc));
      _say("Claude is studying the ${_canvas ? "canvas" : "document"}: the "
          "style appears here when it is saved.");
      return;
    }
    try {
      var saved = _canvas
          ? await saveCanvasStyle(widget.ai, name: named, description: desc)
          : await saveWritingStyle(widget.ai, name: named, description: desc);
      _say(
          saved == null ? "Open a document first." : "Saved the style $named.");
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
      listenable: Listenable.merge([styles, _chat]),
      builder: (context, _) {
        var list = styles.of(widget.kind);
        var busy = _chat.running;
        var active = styles.activeOf(widget.kind);
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              FilledButton.tonalIcon(
                key: const ValueKey("stylesSave"),
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(_canvas
                    ? "Save this canvas as a style"
                    : "Save this document's voice as a style"),
              ),
              TextButton.icon(
                key: const ValueKey("stylesImport"),
                onPressed: () => pickStyleFile(context, widget.ai),
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text("Import…"),
              ),
            ]),
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
                _canvas
                    ? "No styles yet. Save a canvas whose look you like, then "
                        "make new work in it: ask in the conversation with "
                        "the style in use, or restyle another canvas with it."
                    : "No writing styles yet. Save a document whose voice you "
                        "like, then write in it: quick edits and the "
                        "conversation follow the style in use, and In my "
                        "style rewrites a passage in it.",
                style:
                    TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
              ),
            for (var s in list)
              _StyleCard(
                key: ValueKey("style-${s.slug}"),
                style: s,
                active: active?.slug == s.slug,
                busy: busy,
                onUse: () =>
                    styles.use(widget.kind, active?.slug == s.slug ? null : s),
                onRestyle: () => _chat.send(_canvas
                    ? restylePrompt(s.name)
                    : rewriteInStylePrompt(s.name)),
                onEdit: () => _editGuide(s),
                onSend: () => sendStyleToChat(context, widget.ai, s),
                onSaveFile: () => saveStyleFile(context, widget.ai, s),
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
  final VoidCallback onSend;
  final VoidCallback onSaveFile;
  final VoidCallback onSkills;
  final VoidCallback onDelete;

  const _StyleCard({
    required this.style,
    required this.active,
    required this.busy,
    required this.onUse,
    required this.onRestyle,
    required this.onEdit,
    required this.onSend,
    required this.onSaveFile,
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
              if (style.receivedFrom.isNotEmpty)
                Text("From ${style.receivedFrom}",
                    style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: colors.onSurfaceVariant)),
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
              if (style.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(style.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: colors.onSurfaceVariant)),
                ),
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
                  value: "send", height: 32, child: Text("Send to a chat…")),
              PopupMenuItem(
                  value: "file", height: 32, child: Text("Save as a file…")),
              PopupMenuItem(
                  value: "skills",
                  height: 32,
                  child: Text("Add to Claude Code's skills")),
              PopupMenuItem(
                  value: "delete", height: 32, child: Text("Delete…")),
            ],
            onSelected: (v) => switch (v) {
              "edit" => onEdit(),
              "send" => onSend(),
              "file" => onSaveFile(),
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
            child: Text(style.kind == StyleKind.canvas
                ? "Restyle this canvas"
                : "Rewrite the document in it"),
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

  /// what is studied: "canvas" or "document".
  final String what;
  const _SaveStyleDialog({required this.name, required this.what});

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
              title: Text("Have Claude study the ${widget.what} and write "
                  "the guide"),
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

/// StyleInUseChip says which style a sidebar's work is done in, with a way
/// to stop.
class StyleInUseChip extends StatelessWidget {
  final CreativeAi ai;
  final StyleKind kind;
  const StyleInUseChip({required this.ai, required this.kind, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ai.styles,
        builder: (context, _) {
          var style = ai.styles.activeOf(kind);
          if (style == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                key: const ValueKey("styleInUse"),
                avatar: const Icon(Icons.style_outlined, size: 16),
                label: Text("Style: ${style.name}",
                    style: const TextStyle(fontSize: 12)),
                onDeleted: () => ai.styles.use(kind, null),
                deleteButtonTooltipMessage: "Stop using this style",
              ),
            ),
          );
        },
      );
}

/// styleContext is the line put before a request while a style is in use.
String styleContext(CreativeAi ai, StyleKind kind) {
  var style = ai.styles.activeOf(kind);
  if (style == null) return "";
  var get = kind == StyleKind.canvas ? "canvas_style_get" : "writing_style_get";
  return "\n[Work in the style \"${style.name}\" ($get \"${style.slug}\"): "
      "read it first if you have not in this conversation, and follow it.]";
}
