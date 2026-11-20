import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/engine/word_diff.dart';
import 'package:bruig/plugin_system/creative_ai/session/writing_suggestions.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';
import 'package:bruig/plugin_system/creative_ai/ui/chat_view.dart';
import 'package:bruig/plugin_system/creative_ai/ui/styles_panel.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_ai_panel.dart is Creative AI's panel on the Writing page: quick
// rewrites of the selection, the changes Claude has offered (each shown as
// what it takes out and puts in, to accept or reject), and a conversation
// for anything larger.

/// writingAiPanelId is the panel's id in the Writing sidebar.
const String writingAiPanelId = "creativeAi";

class WritingAiPanel extends StatelessWidget {
  final ComposerSidebarController composer;
  const WritingAiPanel({required this.composer, super.key});

  static const examples = [
    "Write an introduction for this post",
    "Tighten the whole post without changing its meaning",
    "Suggest three titles",
    "Check the post for anything unclear or repeated",
  ];

  @override
  Widget build(BuildContext context) {
    var ai = context.watch<CreativeAi>();
    return ListenableBuilder(
        // The Suggestions heading counts what is waiting.
        listenable: Listenable.merge([ai.suggestions, ai.library(), ai.styles]),
        builder: (context, _) => _stack(ai));
  }

  Widget _stack(CreativeAi ai) {
    if (composer.editor == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text("Open a document to work on it with Claude."),
      );
    }
    return PanelStack(
      key: const ValueKey("creativeAiWritingStack"),
      storageKey: "creativeAiWriting",
      panels: [
        StackPanel(
          id: "edits",
          label: "Quick edits",
          icon: Icons.auto_fix_high_outlined,
          hint: "Select some text (or put the cursor in a paragraph) and "
              "choose what to do with it. The result waits in Suggestions "
              "to be accepted or rejected.",
          body: _QuickEdits(ai: ai),
        ),
        StackPanel(
          id: "suggestions",
          label: "Suggestions",
          icon: Icons.rule_outlined,
          trailing: ai.suggestions.items.isEmpty
              ? null
              : "${ai.suggestions.items.length}",
          hint: "Changes Claude has offered to this document: words taken "
              "out are struck through, words put in are marked.",
          body: _Suggestions(ai: ai),
        ),
        StackPanel(
          id: "chat",
          label: "Ask Claude",
          icon: Icons.auto_awesome_outlined,
          hint: "For larger work on the whole document. Its changes wait in "
              "Suggestions to be accepted.",
          body: AiChatView(
            key: const ValueKey("creativeAiWritingChat"),
            ai: ai,
            chat: ai.writingChat,
            examples: examples,
            context: () =>
                _context(composer) + styleContext(ai, StyleKind.writing),
            header: StyleInUseChip(ai: ai, kind: StyleKind.writing),
            hint: "Ask Claude about this document…",
          ),
        ),
        StackPanel(
          id: "styles",
          label: "Styles",
          icon: Icons.style_outlined,
          startsOpen: false,
          trailing: ai.styles.of(StyleKind.writing).isEmpty
              ? null
              : "${ai.styles.of(StyleKind.writing).length}",
          hint: "Voices kept from documents, to write in: the one in use "
              "steers quick edits and the conversation.",
          body: StylesPanel(ai: ai, kind: StyleKind.writing),
        ),
        StackPanel(
          id: "activity",
          label: "What Claude did",
          icon: Icons.history,
          startsOpen: false,
          body: AiActivityList(ai: ai, area: "writing"),
        ),
      ],
    );
  }

  static String _context(ComposerSidebarController composer) {
    var editor = composer.editor;
    if (editor == null) return "";
    var sel = editor.selection;
    if (!sel.isValid || sel.isCollapsed) {
      return "[Nothing is selected; the cursor is at offset "
          "${sel.isValid ? sel.baseOffset : editor.text.length}.]";
    }
    var text = sel.textInside(editor.text);
    var shown = text.length > 2000 ? "${text.substring(0, 2000)}…" : text;
    return "[The person has selected offsets ${sel.start}..${sel.end}:\n"
        "$shown]";
  }
}

class _QuickEdits extends StatefulWidget {
  final CreativeAi ai;
  const _QuickEdits({required this.ai});

  @override
  State<_QuickEdits> createState() => _QuickEditsState();
}

class _QuickEditsState extends State<_QuickEdits> {
  final _own = TextEditingController();

  WritingSuggestions get s => widget.ai.suggestions;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  void _ownRewrite() {
    var ask = _own.text.trim();
    if (ask.isEmpty) return;
    s.rewrite(instruction: ask);
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return ListenableBuilder(
      listenable: Listenable.merge([s, widget.ai.prefs, widget.ai.styles]),
      builder: (context, _) {
        var busy = s.busy;
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          children: [
            // First, where a short panel cannot hide them.
            if (busy != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text("$busy…",
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant)),
                ]),
              ),
            if (s.error case var error?)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(error,
                    style: TextStyle(
                        fontSize: 12.5, color: colors.onErrorContainer)),
              ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var a in RewriteAction.values)
                // In my style only while a writing style is in use.
                if (a != RewriteAction.inStyle ||
                    widget.ai.styles.activeOf(StyleKind.writing) != null)
                  ActionChip(
                    key: ValueKey("aiRewrite-${a.name}"),
                    label: Text(a.label, style: const TextStyle(fontSize: 12)),
                    onPressed: busy != null ? null : () => s.rewrite(action: a),
                  ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey("aiRewriteOwn"),
                  controller: _own,
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _ownRewrite(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: "Or say what to do with it…",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  ),
                ),
              ),
              IconButton(
                tooltip: "Rewrite",
                onPressed: busy != null ? null : _ownRewrite,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
            Row(children: [
              Text("Model",
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              const SizedBox(width: 6),
              DropdownButton<ClaudeModel>(
                key: const ValueKey("aiEditModel"),
                value: widget.ai.prefs.editModel,
                isDense: true,
                underline: const SizedBox(),
                style: TextStyle(fontSize: 12.5, color: colors.onSurface),
                items: [
                  for (var m in ClaudeModel.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) {
                  if (m != null) widget.ai.prefs.editModel = m;
                },
              ),
            ]),
          ],
        );
      },
    );
  }
}

/// _Suggestions is what is waiting on the document, newest first.
class _Suggestions extends StatelessWidget {
  final CreativeAi ai;
  const _Suggestions({required this.ai});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var s = ai.suggestions;
    return ListenableBuilder(
      listenable: Listenable.merge([s, ai.prefs, ai.library()]),
      builder: (context, _) {
        var items = s.items;
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              ai.prefs.applyEdits
                  ? "Changes go straight into the document (Settings > "
                      "Plugins > Creative AI). Undo takes one back."
                  : "Nothing waiting. Changes Claude suggests appear here to "
                      "be accepted or rejected.",
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          children: [
            if (items.length > 1)
              // Wraps rather than overflowing a narrow sidebar or large text.
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text("${items.length} waiting",
                      style: TextStyle(
                          fontSize: 12, color: colors.onSurfaceVariant)),
                ),
                TextButton(
                  key: const ValueKey("aiAcceptAll"),
                  onPressed: () => _report(context, s.acceptAll()),
                  child: const Text("Accept all"),
                ),
                TextButton(
                  key: const ValueKey("aiRejectAll"),
                  onPressed: s.rejectAll,
                  child: const Text("Reject all"),
                ),
              ]),
            for (var item in items.reversed)
              SuggestionCard(
                  key: ValueKey("aiSuggestion-${item.id}"),
                  suggestion: item,
                  suggestions: s),
          ],
        );
      },
    );
  }

  void _report(BuildContext context, int failed) {
    if (failed == 0) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text("$failed could not be put in: the text they were for "
            "has changed.")));
  }
}

/// SuggestionCard is one waiting change: what made it, why, and the words it
/// takes out and puts in.
class SuggestionCard extends StatelessWidget {
  final WritingSuggestion suggestion;
  final WritingSuggestions suggestions;
  const SuggestionCard(
      {required this.suggestion, required this.suggestions, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var s = suggestion;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            [
              s.isInsertion ? "Add" : s.source,
              if (s.note.isNotEmpty) s.note,
            ].join(" · "),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: DiffText(before: s.original, after: s.replacement),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            key: ValueKey("aiReject-${s.id}"),
            onPressed: () => suggestions.reject(s.id),
            child: const Text("Reject"),
          ),
          FilledButton.tonal(
            key: ValueKey("aiAccept-${s.id}"),
            onPressed: () {
              var problem = suggestions.accept(s.id);
              if (problem != null) {
                ScaffoldMessenger.maybeOf(context)
                    ?.showSnackBar(SnackBar(content: Text(problem)));
              }
            },
            child: const Text("Accept"),
          ),
        ]),
      ]),
    );
  }
}

/// DiffText shows [before] becoming [after]: words taken out struck through,
/// words put in marked.
class DiffText extends StatelessWidget {
  final String before;
  final String after;
  const DiffText({required this.before, required this.after, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var base = TextStyle(fontSize: 13, height: 1.4, color: colors.onSurface);
    return SelectableText.rich(TextSpan(style: base, children: [
      for (var p in wordDiff(before, after))
        switch (p.kind) {
          DiffKind.same => TextSpan(text: p.text),
          DiffKind.removed => TextSpan(
              text: p.text,
              style: TextStyle(
                color: colors.error,
                decoration: TextDecoration.lineThrough,
                decorationColor: colors.error,
              )),
          DiffKind.added => TextSpan(
              text: p.text,
              style: TextStyle(
                color: colors.onPrimaryContainer,
                backgroundColor: colors.primaryContainer,
              )),
        },
    ]));
  }
}
