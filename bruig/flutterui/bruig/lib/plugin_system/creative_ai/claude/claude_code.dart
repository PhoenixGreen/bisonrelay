import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

// claude_code.dart runs Claude Code, the program, on the user's own Claude
// account: how Creative AI uses Claude on a Pro or Max plan, with no API key
// and nothing billed per word.
//
// Bison Relay never signs in to Claude itself. It runs the copy of Claude
// Code already on this computer (installed on its own, or inside the VS Code
// extension), which is signed in to the user's account by Claude Code's own
// login. Anthropic's terms allow that; a third-party app offering its own
// claude.ai login does not (see the Agent SDK documentation).
//
// Two things keep a request on the plan rather than on an API bill:
//   - ANTHROPIC_API_KEY and ANTHROPIC_AUTH_TOKEN are taken out of the
//     program's environment. With one set, Claude Code uses it and the
//     request is billed to that API account.
//   - --bare is never passed: it reads no OAuth login at all.
//
// It is run in a folder of its own, empty, so no CLAUDE.md or project
// settings from wherever Bison Relay was started reach the request.

/// ClaudeAnswer is a one-off request's reply.
class ClaudeAnswer {
  final String text;
  final String? error;
  const ClaudeAnswer(this.text, {this.error});
  bool get ok => error == null;
}

/// ClaudeEvent is one thing that happened during a run, in the order it did.
sealed class ClaudeEvent {
  const ClaudeEvent();
}

/// ClaudeStarted carries the conversation's id, to carry on from later.
class ClaudeStarted extends ClaudeEvent {
  final String sessionId;
  final String model;
  const ClaudeStarted(this.sessionId, this.model);
}

/// ClaudeSaid is text from Claude, to show as it arrives.
class ClaudeSaid extends ClaudeEvent {
  final String text;
  const ClaudeSaid(this.text);
}

/// ClaudeUsedTool is a tool Claude called, with what it sent.
class ClaudeUsedTool extends ClaudeEvent {
  final String name;
  final Map<String, dynamic> input;
  const ClaudeUsedTool(this.name, this.input);
}

/// ClaudeFinished is the end: the final answer, or what went wrong.
class ClaudeFinished extends ClaudeEvent {
  final String result;
  final String? error;
  final String? sessionId;
  final Duration took;
  const ClaudeFinished(this.result,
      {this.error, this.sessionId, this.took = Duration.zero});
  bool get ok => error == null;
}

/// ClaudeRun is a run under way: its events, and a way to stop it.
class ClaudeRun {
  final Stream<ClaudeEvent> events;
  final void Function() cancel;
  const ClaudeRun(this.events, this.cancel);
}

class ClaudeCode {
  ClaudeCode._();

  static final String _home =
      Platform.environment["HOME"] ?? Platform.environment["USERPROFILE"] ?? "";

  static String get _exeName => Platform.isWindows ? "claude.exe" : "claude";

  /// locate is the Claude Code program to run: [chosen] if it is one, or
  /// else the first found of: on the login shell's PATH, the usual install
  /// places, and inside an editor's Claude Code extension (newest first).
  static Future<String?> locate(String chosen) async {
    if (chosen.isNotEmpty) {
      return await File(chosen).exists() ? chosen : null;
    }
    for (var p in await candidates()) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  /// candidates are the places looked in, in order.
  static Future<List<String>> candidates() async {
    var out = <String>[];
    if (!Platform.isWindows) {
      try {
        var shell = Platform.environment["SHELL"] ?? "/bin/zsh";
        var r = await Process.run(shell, ["-lc", "command -v claude"])
            .timeout(const Duration(seconds: 5));
        var found = "${r.stdout}".trim().split("\n").first.trim();
        if (r.exitCode == 0 && found.startsWith("/")) out.add(found);
      } catch (_) {}
    }
    out.addAll([
      path.join(_home, ".claude", "local", _exeName),
      path.join(_home, ".local", "bin", _exeName),
      if (!Platform.isWindows) ...[
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        path.join(_home, ".npm-global", "bin", "claude"),
      ],
    ]);
    out.addAll(await _inExtensions());
    return out;
  }

  /// _inExtensions are the copies inside VS Code (and its kin)'s Claude Code
  /// extension, newest version first.
  static Future<List<String>> _inExtensions() async {
    var found = <(List<int>, String)>[];
    for (var editor in [
      ".vscode",
      ".vscode-insiders",
      ".cursor",
      ".windsurf"
    ]) {
      var dir = Directory(path.join(_home, editor, "extensions"));
      if (!await dir.exists()) continue;
      try {
        await for (var e in dir.list()) {
          var name = path.basename(e.path);
          if (!name.startsWith("anthropic.claude-code-")) continue;
          var exe = path.join(e.path, "resources", "native-binary", _exeName);
          var version = RegExp(r"(\d+)\.(\d+)\.(\d+)").firstMatch(name);
          found.add((
            [for (var i = 1; i <= 3; i++) int.parse(version?.group(i) ?? "0")],
            exe
          ));
        }
      } catch (_) {}
    }
    found.sort((a, b) {
      for (var i = 0; i < 3; i++) {
        var c = b.$1[i].compareTo(a.$1[i]);
        if (c != 0) return c;
      }
      return 0;
    });
    return [for (var f in found) f.$2];
  }

  /// environment is this app's, less what would bill an API account or make
  /// Claude Code think it is running inside itself.
  static Map<String, String> environment() => {
        for (var e in Platform.environment.entries)
          if (!const {
            "ANTHROPIC_API_KEY",
            "ANTHROPIC_AUTH_TOKEN",
            "CLAUDECODE",
            "CLAUDE_CODE_ENTRYPOINT",
            "CLAUDE_CODE_SSE_PORT",
          }.contains(e.key))
            e.key: e.value,
      };

  /// workDir is the empty folder runs happen in. The same one each time, so
  /// a conversation can be carried on (Claude Code files them by folder).
  static Future<String> workDir() async {
    var dir =
        Directory(path.join(Directory.systemTemp.path, "bruig-creative-ai"));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// version is what [exe] says it is, or null if it will not run.
  static Future<String?> version(String exe) async {
    try {
      var r = await Process.run(exe, ["--version"],
              environment: environment(), includeParentEnvironment: false)
          .timeout(const Duration(seconds: 15));
      return r.exitCode == 0 ? "${r.stdout}".trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// ask sends [prompt] alone, with no tools, for a reply in words: a
  /// rewrite of some text, an answer. [system] replaces Claude Code's own
  /// instructions, which are about programming.
  static Future<ClaudeAnswer> ask({
    required String exe,
    required String prompt,
    required String system,
    required String model,
    String effort = "low",
    Duration timeout = const Duration(minutes: 3),
  }) async {
    Process process;
    try {
      process = await Process.start(
        exe,
        [
          "-p",
          "--output-format",
          "json",
          "--model",
          model,
          "--effort",
          effort,
          "--tools",
          "",
          "--strict-mcp-config",
          "--no-session-persistence",
          "--disable-slash-commands",
          "--system-prompt",
          system,
        ],
        workingDirectory: await workDir(),
        environment: environment(),
        includeParentEnvironment: false,
      );
    } catch (e) {
      return ClaudeAnswer("", error: "Claude Code would not start: $e");
    }
    process.stdin.write(prompt);
    await process.stdin.close();
    var out = process.stdout.transform(utf8.decoder).join();
    var err = process.stderr.transform(utf8.decoder).join();
    int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      return const ClaudeAnswer("", error: "Claude took too long to answer.");
    }
    var text = await out;
    var problem = (await err).trim();
    try {
      var json = jsonDecode(text.trim());
      if (json is Map) {
        var result = "${json["result"] ?? ""}";
        if (json["is_error"] == true || json["subtype"] != "success") {
          return ClaudeAnswer("",
              error: result.isNotEmpty ? result : "Claude could not answer.");
        }
        return ClaudeAnswer(result);
      }
    } catch (_) {}
    return ClaudeAnswer("",
        error: problem.isNotEmpty
            ? problem
            : "Claude Code stopped (code $code) without an answer.");
  }

  /// run gives Claude [prompt] with the MCP servers in [mcpServers] (as a
  /// --mcp-config "mcpServers" map) and no other tools, carrying on
  /// conversation [resume] if given. Every tool of those servers is
  /// allowed without asking: the person asked for the work, and each
  /// change can be undone.
  static ClaudeRun run({
    required String exe,
    required String prompt,
    required String system,
    required String model,
    required Map<String, Object?> mcpServers,
    String? resume,
    String effort = "medium",
  }) {
    var controller = StreamController<ClaudeEvent>();
    Process? process;
    var cancelled = false;
    var started = DateTime.now();

    Future<void> go() async {
      try {
        process = await Process.start(
          exe,
          [
            "-p",
            "--output-format",
            "stream-json",
            "--verbose",
            "--model",
            model,
            "--effort",
            effort,
            "--tools",
            "",
            "--mcp-config",
            jsonEncode({"mcpServers": mcpServers}),
            "--strict-mcp-config",
            "--allowedTools",
            mcpServers.keys.map((k) => "mcp__$k").join(","),
            "--disable-slash-commands",
            "--system-prompt",
            system,
            if (resume != null) ...["--resume", resume],
          ],
          workingDirectory: await workDir(),
          environment: environment(),
          includeParentEnvironment: false,
        );
      } catch (e) {
        controller
            .add(ClaudeFinished("", error: "Claude Code would not start: $e"));
        await controller.close();
        return;
      }
      var p = process!;
      if (cancelled) p.kill();
      p.stdin.write(prompt);
      await p.stdin.close();
      var err = StringBuffer();
      var errDone = p.stderr.transform(utf8.decoder).forEach(err.write);
      var finished = false;
      await for (var line
          in p.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
        for (var event in parseStreamLine(line, started)) {
          if (event is ClaudeFinished) finished = true;
          controller.add(event);
        }
      }
      var code = await p.exitCode;
      await errDone;
      if (!finished) {
        var said = err.toString().trim();
        controller.add(ClaudeFinished("",
            error: cancelled
                ? "Stopped."
                : said.isNotEmpty
                    ? said
                    : "Claude Code stopped (code $code)."));
      }
      await controller.close();
    }

    go();
    return ClaudeRun(controller.stream, () {
      cancelled = true;
      process?.kill();
    });
  }

  /// parseStreamLine reads one line of Claude Code's stream-json output.
  static List<ClaudeEvent> parseStreamLine(String line, DateTime started) {
    Object? json;
    try {
      json = jsonDecode(line);
    } catch (_) {
      return const [];
    }
    if (json is! Map) return const [];
    switch (json["type"]) {
      case "system":
        if (json["subtype"] == "init" && json["session_id"] is String) {
          return [
            ClaudeStarted(
                json["session_id"] as String, "${json["model"] ?? ""}")
          ];
        }
        return const [];
      case "assistant":
        var content = (json["message"] as Map?)?["content"];
        if (content is! List) return const [];
        return [
          for (var block in content)
            if (block is Map &&
                block["type"] == "text" &&
                "${block["text"]}".trim().isNotEmpty)
              ClaudeSaid("${block["text"]}")
            else if (block is Map && block["type"] == "tool_use")
              ClaudeUsedTool(
                  "${block["name"]}",
                  block["input"] is Map
                      ? Map<String, dynamic>.from(block["input"] as Map)
                      : const {}),
        ];
      case "result":
        var result = "${json["result"] ?? ""}";
        var failed = json["is_error"] == true || json["subtype"] != "success";
        return [
          ClaudeFinished(result,
              error: failed
                  ? (result.isNotEmpty ? result : "Claude could not finish.")
                  : null,
              sessionId: json["session_id"] as String?,
              took: DateTime.now().difference(started))
        ];
    }
    return const [];
  }

  /// connect adds Bison Relay's server to Claude Code for this user (every
  /// folder, the VS Code extension included), replacing an earlier entry.
  /// Returns what went wrong, or null.
  static Future<String?> connect(
      {required String exe,
      required String name,
      required String url,
      required String token}) async {
    try {
      await Process.run(exe, ["mcp", "remove", name, "-s", "user"],
          environment: environment(), includeParentEnvironment: false);
      var r = await Process.run(
          exe,
          [
            "mcp",
            "add",
            "--scope",
            "user",
            "--transport",
            "http",
            name,
            url,
            "--header",
            "Authorization: Bearer $token",
          ],
          environment: environment(),
          includeParentEnvironment: false);
      if (r.exitCode == 0) return null;
      var said = "${r.stderr}".trim();
      return said.isEmpty ? "${r.stdout}".trim() : said;
    } catch (e) {
      return "$e";
    }
  }
}
