import 'dart:math';

import 'package:bruig/config.dart';
import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/claude/claude_code.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/creative_ai/session/ai_chat.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';
import 'package:bruig/plugin_system/creative_ai/session/writing_suggestions.dart';
import 'package:bruig/plugin_system/creative_ai/tools/canvas_ai_tools.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:bruig/plugin_system/creative_ai/tools/image_ai_tools.dart';
import 'package:bruig/plugin_system/creative_ai/tools/library_ai_tools.dart';
import 'package:bruig/plugin_system/creative_ai/tools/style_ai_tools.dart';
import 'package:bruig/plugin_system/creative_ai/tools/writing_ai_tools.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/foundation.dart';

// creative_ai_model.dart is Creative AI while the app runs: the MCP server
// and its tokens, the Claude Code program it runs, what Claude has done, and
// the one copy of the canvas from before Claude started on it.
//
// It reaches the canvas and the Writing page through functions rather than
// holding them, because both are made lazily by the app (a Canvas editing
// session is only built once someone opens Canvas or Claude asks for it).

/// AiActivity is every tool call made, newest last, from any app.
class AiActivity extends ChangeNotifier {
  static const int _max = 300;
  final List<McpCall> calls = [];

  void add(McpCall call) {
    calls.add(call);
    if (calls.length > _max) calls.removeAt(0);
    notifyListeners();
  }

  void clear() {
    calls.clear();
    notifyListeners();
  }
}

class CreativeAi extends ChangeNotifier {
  final CreativeAiPreferences prefs;
  final CanvasController Function() canvas;
  final CanvasPreferences Function() canvasPrefs;
  final ComposerSidebarController Function() composer;
  final PostLibraryModel Function() library;

  final AiActivity activity = AiActivity();
  late final WritingSuggestions suggestions = WritingSuggestions(this);
  late final AiChat canvasChat = AiChat(this, AiArea.canvas);
  late final AiChat writingChat = AiChat(this, AiArea.writing);
  late final StyleLibrary styles = StyleLibrary(stylesRoot);
  late final McpServer server;
  late final List<McpTool> tools = [
    ...canvasAiTools(this),
    ...libraryAiTools(this),
    ...imageAiTools(this),
    ...styleAiTools(this),
    ...writingAiTools(this),
  ];

  /// serve is whether the server listens while Creative AI is on; and
  /// locateClaude finds Claude Code. Both stand-ins for widget tests, which
  /// cannot wait on real sockets or programs.
  final bool serve;
  final Future<String?> Function(String chosen) locateClaude;

  /// stylesRoot is the folder style profiles are kept under (a test's own).
  final Future<String> Function() stylesRoot;

  CreativeAi({
    required this.prefs,
    required this.canvas,
    required this.canvasPrefs,
    required this.composer,
    required this.library,
    this.serve = true,
    this.locateClaude = ClaudeCode.locate,
    this.stylesRoot = CanvasScripting.presetsDir,
  }) {
    server = McpServer(
      tools: () => tools,
      instructions: () =>
          serverInstructions(canvas: canvasOn, writing: writingOn),
      callerFor: _callerFor,
      onCall: activity.add,
    );
    prefs.addListener(_sync);
    _sync();
  }

  /// canvasOn and writingOn are whether Claude may work there now: Creative
  /// AI's switch for it, and for Canvas, Canvas itself being on.
  bool get canvasOn => prefs.canvasOn && canvasPrefs().enabled;
  bool get writingOn => prefs.writingOn;

  CanvasScripting get scripting => CanvasScripting(canvas());

  // ------------------------------------------------------------------------
  // The server
  // ------------------------------------------------------------------------

  String? _serverError;

  /// serverError is why the server is not listening, while it should be.
  String? get serverError => _serverError;

  bool _syncing = false;

  /// _again is a change of the switches made while a sync was under way: it
  /// is synced again once that one is done, so no change is lost.
  bool _again = false;

  Future<void> _sync() async {
    if (!serve) {
      notifyListeners();
      return;
    }
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      if (!prefs.enabled) {
        if (server.running) await server.stop();
        canvasChat.stop();
        writingChat.stop();
        _serverError = null;
      } else if (!server.running) {
        try {
          await server.start(prefs.port);
          _serverError = null;
        } catch (e) {
          _serverError = "Could not listen on port ${prefs.port}: $e";
        }
      } else if (server.port != null &&
          (server.port! < prefs.port || server.port! >= prefs.port + 10)) {
        // The port setting moved: listen there instead.
        await server.stop();
        try {
          await server.start(prefs.port);
          _serverError = null;
        } catch (e) {
          _serverError = "Could not listen on port ${prefs.port}: $e";
        }
      }
    } finally {
      _syncing = false;
    }
    notifyListeners();
    if (_again) {
      _again = false;
      await _sync();
    }
  }

  /// url is where the server is reached.
  String get url => "http://127.0.0.1:${server.port ?? prefs.port}/mcp";

  final Map<String, McpCaller> _runTokens = {};

  McpCaller? _callerFor(String token) {
    if (token.isEmpty) return null;
    if (token == prefs.token) return const McpCaller("Claude Code");
    return _runTokens[token];
  }

  /// openRunToken is a token for one run from a sidebar, named [source] in
  /// the activity list; [closeRunToken] ends it.
  String openRunToken(String source) {
    var r = Random.secure();
    var token = [for (var i = 0; i < 24; i++) r.nextInt(256)]
        .map((b) => b.toRadixString(16).padLeft(2, "0"))
        .join();
    _runTokens[token] = McpCaller(source);
    return token;
  }

  void closeRunToken(String token) => _runTokens.remove(token);

  /// mcpServers is the --mcp-config entry that reaches this server with
  /// [token].
  Map<String, Object?> mcpServers(String token) => {
        "bisonrelay": {
          "type": "http",
          "url": url,
          "headers": {"Authorization": "Bearer $token"},
        }
      };

  /// connectCommand is what to type to add the server to Claude Code by
  /// hand.
  String get connectCommand => "claude mcp add --scope user --transport http "
      "bisonrelay $url --header \"Authorization: Bearer ${prefs.token}\"";

  // ------------------------------------------------------------------------
  // Claude Code
  // ------------------------------------------------------------------------

  String? _exe;
  String? _version;
  bool _looked = false;

  /// exe and version are the Claude Code found, once [findClaude] has run.
  String? get exe => _exe;
  String? get version => _version;
  bool get looked => _looked;

  /// findClaude looks for Claude Code again (after an install, or a path
  /// typed in settings).
  Future<String?> findClaude() async {
    _exe = await locateClaude(prefs.claudePath);
    _version = _exe == null ? null : await ClaudeCode.version(_exe!);
    if (_version == null) _exe = null;
    _looked = true;
    notifyListeners();
    return _exe;
  }

  /// claude is the program to run, looked for the first time it is needed.
  Future<String?> claude() async => _exe ?? await findClaude();

  /// connectClaudeCode adds this server to Claude Code for every folder,
  /// the VS Code extension included. Returns what went wrong, or null.
  Future<String?> connectClaudeCode() async {
    var exe = await claude();
    if (exe == null) return claudeMissing;
    if (!server.running) return "Creative AI is not listening: $_serverError";
    return ClaudeCode.connect(
        exe: exe, name: "bisonrelay", url: url, token: prefs.token);
  }

  static const String claudeMissing =
      "Claude Code was not found on this computer. Install it from "
      "claude.com/code (or the Claude Code extension for VS Code) and sign "
      "in to your Claude account, then press Find again in Settings > "
      "Plugins > Creative AI.";

  /// proxied is whether the app is set to go through a proxy (often Tor):
  /// Claude Code connects to Anthropic directly, not through it.
  Future<bool> proxied() async {
    try {
      var config = await loadConfig(mainConfigFilename);
      return config.proxyaddr.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------------
  // The canvas from before Claude started
  // ------------------------------------------------------------------------

  CanvasDocument? _checkpoint;
  String? _checkpointFile;
  DateTime? _checkpointAt;

  /// hasCheckpoint is whether Claude has changed the open canvas since it
  /// was last kept, so [undoCanvas] can put it back.
  bool get hasCheckpoint {
    if (_checkpoint == null) return false;
    if (_checkpointFile != _canvasFile()) {
      _checkpoint = null;
      return false;
    }
    return true;
  }

  DateTime? get checkpointAt => _checkpointAt;

  String _canvasFile() {
    var c = canvas();
    return "${c.folder ?? ""}/${c.name ?? ""}";
  }

  /// beforeCanvasChange keeps the canvas as it is, unless a copy from
  /// before this run of changes is already kept.
  void beforeCanvasChange() {
    if (hasCheckpoint) return;
    _checkpoint = scripting.snapshot();
    _checkpointFile = _canvasFile();
    _checkpointAt = DateTime.now();
    notifyListeners();
  }

  /// undoCanvas puts the canvas back as it was before Claude started on it,
  /// as one step (itself undoable).
  void undoCanvas() {
    if (!hasCheckpoint) return;
    scripting.restore(_checkpoint!);
    keepCanvas();
  }

  /// keepCanvas accepts what Claude did; the next change starts afresh.
  void keepCanvas() {
    _checkpoint = null;
    _checkpointFile = null;
    _checkpointAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    prefs.removeListener(_sync);
    server.stop();
    canvasChat.dispose();
    writingChat.dispose();
    suggestions.dispose();
    styles.dispose();
    activity.dispose();
    super.dispose();
  }
}
