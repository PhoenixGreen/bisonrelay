import 'package:bruig/plugin_system/creative_ai/claude/claude_code.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:flutter/foundation.dart';

// ai_chat.dart is a sidebar's conversation with Claude: what the person
// asked, what Claude said and which tools it used, one run at a time.
//
// Each request runs Claude Code once, given this app's MCP server and a token
// for that run alone. The conversation carries on (Claude Code's --resume)
// until the person starts a new one, so "now make it bigger" means what was
// just made.

/// AiArea is where a sidebar is.
enum AiArea {
  canvas("Canvas sidebar"),
  writing("Writing sidebar");

  final String source;
  const AiArea(this.source);
}

enum ChatRole { you, claude, tool, error }

class ChatEntry {
  final ChatRole role;
  final String text;
  const ChatEntry(this.role, this.text);
}

/// toolLabel is a tool's name as the person reads it: "canvas_add_element"
/// from Claude Code's "mcp__bisonrelay__canvas_add_element".
String toolLabel(String name) {
  var short = name.startsWith("mcp__") ? name.split("__").last : name;
  return short.replaceAll("_", " ");
}

class AiChat extends ChangeNotifier {
  final CreativeAi ai;
  final AiArea area;
  AiChat(this.ai, this.area);

  final List<ChatEntry> entries = [];
  String? _session;
  ClaudeRun? _run;
  bool _disposed = false;

  bool get running => _run != null;

  /// hasConversation is whether the next request carries on from the last.
  bool get hasConversation => _session != null;

  void _add(ChatEntry e) {
    entries.add(e);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// send asks Claude [prompt], with [context] (what is selected, say) put
  /// before it for Claude but not shown.
  Future<void> send(String prompt, {String context = ""}) async {
    prompt = prompt.trim();
    if (prompt.isEmpty || running) return;
    _add(ChatEntry(ChatRole.you, prompt));
    var exe = await ai.claude();
    if (exe == null) {
      _add(const ChatEntry(ChatRole.error, CreativeAi.claudeMissing));
      return;
    }
    if (!ai.server.running) {
      _add(ChatEntry(ChatRole.error,
          "Creative AI's server is not running: ${ai.serverError ?? "it is starting"}."));
      return;
    }
    var token = ai.openRunToken(area.source);
    var run = ClaudeCode.run(
      exe: exe,
      prompt: context.isEmpty ? prompt : "$context\n\n$prompt",
      system: sidebarSystemPrompt(area.name,
          canvas: ai.canvasOn, writing: ai.writingOn),
      model: ai.prefs.chatModel.alias,
      mcpServers: ai.mcpServers(token),
      resume: _session,
    );
    _run = run;
    _notify();
    var said = false;
    try {
      await for (var e in run.events) {
        switch (e) {
          case ClaudeStarted():
            _session = e.sessionId;
          case ClaudeSaid():
            said = true;
            _add(ChatEntry(ChatRole.claude, e.text.trim()));
          case ClaudeUsedTool():
            _add(ChatEntry(ChatRole.tool, toolLabel(e.name)));
          case ClaudeFinished():
            if (e.sessionId != null) _session = e.sessionId;
            if (!e.ok) {
              _add(ChatEntry(ChatRole.error, e.error!));
            } else if (!said && e.result.trim().isNotEmpty) {
              _add(ChatEntry(ChatRole.claude, e.result.trim()));
            }
        }
      }
    } finally {
      _run = null;
      ai.closeRunToken(token);
      _notify();
    }
  }

  /// stop ends the run under way; what it changed stays (and can be undone).
  void stop() => _run?.cancel();

  /// newConversation forgets this one: the next request starts afresh.
  void newConversation() {
    stop();
    entries.clear();
    _session = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
