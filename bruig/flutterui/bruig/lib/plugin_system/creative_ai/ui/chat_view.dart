import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/session/ai_chat.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// chat_view.dart is a conversation with Claude in a sidebar: what was said,
// the tools it used as it worked, and the box to ask in. Shared by the
// Canvas and Writing sidebars.

class AiChatView extends StatefulWidget {
  final CreativeAi ai;
  final AiChat chat;

  /// examples are offered while the conversation is empty, to show what
  /// can be asked.
  final List<String> examples;

  /// context is put before each request for Claude (what is selected, say).
  final String Function()? context;

  final String hint;

  const AiChatView({
    required this.ai,
    required this.chat,
    this.examples = const [],
    this.context,
    this.hint = "Ask Claude…",
    super.key,
  });

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _seen = 0;

  AiChat get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    chat.addListener(_changed);
  }

  @override
  void didUpdateWidget(AiChatView old) {
    super.didUpdateWidget(old);
    if (old.chat != chat) {
      old.chat.removeListener(_changed);
      chat.addListener(_changed);
    }
  }

  @override
  void dispose() {
    chat.removeListener(_changed);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// _changed follows the conversation to its end as it grows.
  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (chat.entries.length != _seen) {
      _seen = chat.entries.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
    }
  }

  void _send([String? text]) {
    var prompt = (text ?? _input.text).trim();
    if (prompt.isEmpty || chat.running) return;
    _input.clear();
    chat.send(prompt, context: widget.context?.call() ?? "");
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bar(colors),
      Expanded(
        child: chat.entries.isEmpty
            ? _empty(colors)
            : ListView.builder(
                key: const ValueKey("aiChatList"),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                itemCount: chat.entries.length,
                itemBuilder: (context, i) => _entry(colors, chat.entries[i]),
              ),
      ),
      if (chat.running)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 4, 4),
          child: Row(children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Expanded(
              child: Text("Claude is working…",
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            ),
            TextButton.icon(
              key: const ValueKey("aiChatStop"),
              onPressed: chat.stop,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text("Stop"),
            ),
          ]),
        ),
      _box(colors),
    ]);
  }

  /// _bar is the model the sidebar asks, and a fresh conversation.
  Widget _bar(ColorScheme colors) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
        child: Row(children: [
          Text("Model",
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          const SizedBox(width: 6),
          ListenableBuilder(
            listenable: widget.ai.prefs,
            builder: (context, _) => DropdownButton<ClaudeModel>(
              key: const ValueKey("aiChatModel"),
              value: widget.ai.prefs.chatModel,
              isDense: true,
              underline: const SizedBox(),
              style: TextStyle(fontSize: 12.5, color: colors.onSurface),
              items: [
                for (var m in ClaudeModel.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (m) {
                if (m != null) widget.ai.prefs.chatModel = m;
              },
            ),
          ),
          const Spacer(),
          IconButton(
            key: const ValueKey("aiChatNew"),
            tooltip: "Start a new conversation",
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: chat.entries.isEmpty && !chat.hasConversation
                ? null
                : chat.newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ]),
      );

  Widget _empty(ColorScheme colors) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            "Ask Claude to work on what is open. It changes it with Bison "
            "Relay's own tools, and every change can be undone.",
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (var e in widget.examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  _input.text = e;
                  _focus.requestFocus();
                },
              ),
            ),
        ],
      );

  Widget _entry(ColorScheme colors, ChatEntry e) => switch (e.role) {
        ChatRole.you => Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4, left: 24),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(e.text,
                  style: TextStyle(
                      fontSize: 13, color: colors.onSecondaryContainer)),
            ),
          ),
        ChatRole.claude => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(e.text,
                style: TextStyle(fontSize: 13, color: colors.onSurface)),
          ),
        ChatRole.tool => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(children: [
              Icon(Icons.build_outlined,
                  size: 12, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(e.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: colors.onSurfaceVariant)),
              ),
            ]),
          ),
        ChatRole.error => Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(e.text,
                style:
                    TextStyle(fontSize: 12.5, color: colors.onErrorContainer)),
          ),
      };

  /// _box is where a request is typed: Enter sends, Shift+Enter starts a
  /// new line.
  Widget _box(ColorScheme colors) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _send();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const ValueKey("aiChatInput"),
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey("aiChatSend"),
            tooltip: "Send",
            onPressed: chat.running ? null : _send,
            icon: const Icon(Icons.send_rounded),
          ),
        ]),
      );
}

/// AiActivityList is every tool call made, newest first, by whichever app.
class AiActivityList extends StatelessWidget {
  final CreativeAi ai;

  /// area shows only one area's calls when given.
  final String? area;
  const AiActivityList({required this.ai, this.area, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return ListenableBuilder(
      listenable: ai.activity,
      builder: (context, _) {
        var calls = [
          for (var c in ai.activity.calls.reversed)
            if (area == null || c.tool.area == area) c
        ];
        if (calls.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              "Nothing yet. Every tool Claude uses here is listed, whether "
              "it was asked from this sidebar or from Claude Code elsewhere.",
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          itemCount: calls.length,
          itemBuilder: (context, i) {
            var c = calls[i];
            var t = c.at;
            var time = "${t.hour.toString().padLeft(2, "0")}:"
                "${t.minute.toString().padLeft(2, "0")}";
            var line =
                c.result.summary.isNotEmpty ? c.result.summary : c.tool.title;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 38,
                  child: Text(time,
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceVariant)),
                ),
                Icon(
                    c.result.isError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    size: 13,
                    color: c.result.isError ? colors.error : colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text("$line  ·  ${c.caller.source}",
                      style: TextStyle(
                          fontSize: 12,
                          color: c.result.isError
                              ? colors.error
                              : colors.onSurface)),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}
