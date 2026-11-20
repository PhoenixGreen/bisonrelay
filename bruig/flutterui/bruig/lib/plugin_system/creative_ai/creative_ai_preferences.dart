import 'dart:math';

import 'package:bruig/storage_manager.dart';
import 'package:flutter/foundation.dart';

// creative_ai_preferences.dart is what Creative AI remembers about the app:
// whether it is on, where it works, which Claude model it asks for and how
// other apps reach it. Nothing about one document or canvas is kept here.

/// ClaudeModel is which Claude model a request goes to, by the alias Claude
/// Code takes (it always means that family's latest).
enum ClaudeModel {
  opus(
      "opus",
      "Opus",
      "Best writing and the most careful work; uses your "
          "plan's limits fastest."),
  sonnet("sonnet", "Sonnet", "Fast and capable; a good everyday choice."),
  haiku("haiku", "Haiku", "Quickest; fine for grammar and small fixes.");

  final String alias;
  final String label;
  final String help;
  const ClaudeModel(this.alias, this.label, this.help);

  static ClaudeModel fromName(String? name, ClaudeModel fallback) =>
      values.where((m) => m.name == name).firstOrNull ?? fallback;
}

/// defaultMcpPort is where the MCP server listens unless told otherwise:
/// high, unassigned, and on this computer only.
const int defaultMcpPort = 47815;

class CreativeAiPreferences extends ChangeNotifier {
  static const _enabledKey = "creativeAiEnabled";
  static const _canvasKey = "creativeAiCanvas";
  static const _writingKey = "creativeAiWriting";
  static const _chatModelKey = "creativeAiChatModel";
  static const _editModelKey = "creativeAiEditModel";
  static const _claudePathKey = "creativeAiClaudePath";
  static const _portKey = "creativeAiPort";
  static const _tokenKey = "creativeAiToken";
  static const _applyEditsKey = "creativeAiApplyEdits";

  bool _enabled = false;
  bool _canvas = true;
  bool _writing = true;
  ClaudeModel _chatModel = ClaudeModel.opus;
  ClaudeModel _editModel = ClaudeModel.opus;
  String _claudePath = "";
  int _port = defaultMcpPort;
  String _token = "";
  bool _applyEdits = false;

  /// enabled is the whole feature. Off, it leaves nothing behind: no
  /// sidebar, no menu entry, no server listening.
  bool get enabled => _enabled;
  set enabled(bool v) => _setBool(_enabledKey, v, () => _enabled = v);

  /// canvas and writing say where it works while it is on.
  bool get canvas => _canvas;
  set canvas(bool v) => _setBool(_canvasKey, v, () => _canvas = v);
  bool get writing => _writing;
  set writing(bool v) => _setBool(_writingKey, v, () => _writing = v);

  /// canvasOn and writingOn are the questions everything else asks.
  bool get canvasOn => _enabled && _canvas;
  bool get writingOn => _enabled && _writing;

  /// chatModel answers prompts typed in a sidebar; editModel does the quick
  /// rewrites of selected text.
  ClaudeModel get chatModel => _chatModel;
  set chatModel(ClaudeModel v) {
    _chatModel = v;
    StorageManager.saveString(_chatModelKey, v.name);
    notifyListeners();
  }

  ClaudeModel get editModel => _editModel;
  set editModel(ClaudeModel v) {
    _editModel = v;
    StorageManager.saveString(_editModelKey, v.name);
    notifyListeners();
  }

  /// claudePath is the Claude Code program chosen by hand; empty looks for
  /// one (see claude_code.dart).
  String get claudePath => _claudePath;
  set claudePath(String v) {
    _claudePath = v.trim();
    StorageManager.saveString(_claudePathKey, _claudePath);
    notifyListeners();
  }

  /// port is where the MCP server listens, on 127.0.0.1 only.
  int get port => _port;
  set port(int v) {
    _port = v.clamp(1024, 65535).toInt();
    StorageManager.saveString(_portKey, "$_port");
    notifyListeners();
  }

  /// token is what another app must send to use the server: anything on
  /// this computer can reach a local port, so reaching it is not enough.
  String get token => _token;

  /// newToken makes a fresh one, cutting off every app given the old.
  void newToken() {
    _token = _makeToken();
    StorageManager.saveString(_tokenKey, _token);
    notifyListeners();
  }

  /// applyEdits puts an assistant's changes to a document straight in,
  /// rather than offering each to be accepted. Off: you see each first.
  bool get applyEdits => _applyEdits;
  set applyEdits(bool v) => _setBool(_applyEditsKey, v, () => _applyEdits = v);

  void _setBool(String key, bool v, VoidCallback set) {
    set();
    StorageManager.saveBool(key, v);
    notifyListeners();
  }

  static String _makeToken() {
    var r = Random.secure();
    return [for (var i = 0; i < 32; i++) r.nextInt(256)]
        .map((b) => b.toRadixString(16).padLeft(2, "0"))
        .join();
  }

  Future<void> load() async {
    _enabled = await StorageManager.readBool(_enabledKey, defaultVal: false);
    _canvas = await StorageManager.readBool(_canvasKey, defaultVal: true);
    _writing = await StorageManager.readBool(_writingKey, defaultVal: true);
    _chatModel = ClaudeModel.fromName(
        await StorageManager.readString(_chatModelKey), ClaudeModel.opus);
    _editModel = ClaudeModel.fromName(
        await StorageManager.readString(_editModelKey), ClaudeModel.opus);
    _claudePath = await StorageManager.readString(_claudePathKey);
    _port = int.tryParse(await StorageManager.readString(_portKey)) ??
        defaultMcpPort;
    _token = await StorageManager.readString(_tokenKey);
    if (_token.length < 32) {
      _token = _makeToken();
      await StorageManager.saveString(_tokenKey, _token);
    }
    _applyEdits =
        await StorageManager.readBool(_applyEditsKey, defaultVal: false);
    notifyListeners();
  }
}
