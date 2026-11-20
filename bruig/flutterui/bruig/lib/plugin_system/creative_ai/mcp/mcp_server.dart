import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// mcp_server.dart is a Model Context Protocol server over HTTP, on this
// computer only: how Claude Code (in a terminal, in VS Code, or run by
// Creative AI itself) is given Bison Relay's tools.
//
// It speaks the "Streamable HTTP" transport in its simplest form: each
// JSON-RPC message is POSTed to /mcp and answered in the response body as
// JSON. There is no stream from the server (a GET is refused), because
// nothing here needs to speak first: the assistant asks, a tool answers.
//
// Three guards, since anything on the computer can reach a local port:
//   - it listens on 127.0.0.1 alone, never on the network;
//   - every request must carry a token (Authorization: Bearer ...), the
//     standing one given to another app or a one-off made for a single run;
//   - a request from a web page (an Origin header that is not this
//     computer) is refused, so a site cannot drive it from a browser.

/// mcpProtocolVersions are the protocol versions understood, newest first.
const mcpProtocolVersions = [
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
];

/// McpCaller is who made a request: which app, by the token it sent.
class McpCaller {
  /// source is said in the activity list ("Claude Code", "Canvas sidebar").
  final String source;
  const McpCaller(this.source);
}

/// McpResult is what a tool gives back: text and pictures, and whether it
/// failed (a failure is still an answer, worded for the assistant to act
/// on).
class McpResult {
  final List<Map<String, Object?>> content;
  final bool isError;

  /// summary is the line the activity list shows for it.
  final String summary;

  const McpResult(this.content, {this.isError = false, this.summary = ""});

  factory McpResult.text(String text, {String summary = ""}) =>
      McpResult([_text(text)], summary: summary);

  factory McpResult.json(Object? value, {String summary = ""}) =>
      McpResult([_text(const JsonEncoder.withIndent(" ").convert(value))],
          summary: summary);

  factory McpResult.error(String message) =>
      McpResult([_text(message)], isError: true, summary: message);

  /// images is pictures, each a PNG, with a line of [text] before them.
  factory McpResult.images(List<Uint8List> pngs,
          {String text = "", String summary = ""}) =>
      McpResult([
        if (text.isNotEmpty) _text(text),
        for (var png in pngs)
          {
            "type": "image",
            "data": base64Encode(png),
            "mimeType": "image/png",
          }
      ], summary: summary);

  static Map<String, Object?> _text(String text) =>
      {"type": "text", "text": text};

  Map<String, Object?> toJson() =>
      {"content": content, if (isError) "isError": true};
}

/// McpTool is one tool: its name, what it is for, the arguments it takes
/// (a JSON Schema), and what it does.
class McpTool {
  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;

  /// area groups tools for the activity list and the switches: "canvas",
  /// "writing".
  final String area;

  /// available is whether it is offered now (its area switched on).
  final bool Function() available;

  final Future<McpResult> Function(Map<String, dynamic> args, McpCaller caller)
      run;

  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.area,
    required this.available,
    required this.run,
  });

  Map<String, Object?> toJson() => {
        "name": name,
        "title": title,
        "description": description,
        "inputSchema": inputSchema,
      };
}

/// McpCall is one tool call made, for the activity list.
class McpCall {
  final DateTime at;
  final McpCaller caller;
  final McpTool tool;
  final Map<String, dynamic> args;
  final McpResult result;
  const McpCall(this.at, this.caller, this.tool, this.args, this.result);
}

class McpServer {
  /// tools are every tool there is; each says whether it is offered now.
  final List<McpTool> Function() tools;

  /// instructions is said to the assistant as it connects.
  final String Function() instructions;

  /// callerFor is who [token] belongs to, or null for nobody.
  final McpCaller? Function(String token) callerFor;

  /// onCall hears of each tool call made, as it finishes.
  final void Function(McpCall call)? onCall;

  McpServer({
    required this.tools,
    required this.instructions,
    required this.callerFor,
    this.onCall,
  });

  HttpServer? _http;

  /// port is where it is listening, or null while it is not.
  int? get port => _http?.port;
  bool get running => _http != null;

  /// start listens on [port], or the next free one of the nine after it.
  /// Returns the port taken.
  Future<int> start(int port) async {
    if (_http case var http?) return http.port;
    SocketException? last;
    for (var p = port; p < port + 10 && p <= 65535; p++) {
      try {
        var http = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        _http = http;
        http.listen(_serve, onError: (Object e) {
          debugPrint("Creative AI server: $e");
        });
        return p;
      } on SocketException catch (e) {
        last = e;
      }
    }
    throw last ?? SocketException("No free port from $port");
  }

  Future<void> stop() async {
    var http = _http;
    _http = null;
    await http?.close(force: true);
  }

  static const int _maxBody = 8 << 20;

  Future<void> _serve(HttpRequest req) async {
    var res = req.response;
    try {
      if (req.uri.path != "/mcp") {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      var origin = req.headers.value("origin");
      if (origin != null && !_localOrigin(origin)) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      var auth = req.headers.value(HttpHeaders.authorizationHeader) ?? "";
      var caller = auth.startsWith("Bearer ")
          ? callerFor(auth.substring(7).trim())
          : null;
      if (caller == null) {
        res.statusCode = HttpStatus.unauthorized;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(_error(
            null,
            -32001,
            "Not allowed: this server needs the token from Bison Relay's "
            "Settings > Plugins > Creative AI.")));
        return;
      }
      if (req.method == "DELETE") return;
      if (req.method != "POST") {
        res.statusCode = HttpStatus.methodNotAllowed;
        res.headers.set(HttpHeaders.allowHeader, "POST, DELETE");
        return;
      }
      var bytes = BytesBuilder(copy: false);
      await for (var chunk in req) {
        bytes.add(chunk);
        if (bytes.length > _maxBody) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
      }
      Object? message;
      try {
        message = jsonDecode(utf8.decode(bytes.takeBytes()));
      } catch (_) {
        res.statusCode = HttpStatus.badRequest;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(_error(null, -32700, "Not JSON.")));
        return;
      }
      var reply = await handle(message, caller);
      if (reply == null) {
        res.statusCode = HttpStatus.accepted;
        return;
      }
      res.headers.contentType = ContentType.json;
      if (message is Map && message["method"] == "initialize") {
        res.headers.set("Mcp-Session-Id", _sessionId());
      }
      res.write(jsonEncode(reply));
    } catch (e) {
      debugPrint("Creative AI server: $e");
      try {
        res.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      await res.close().catchError((_) => res);
    }
  }

  static bool _localOrigin(String origin) {
    var host = Uri.tryParse(origin)?.host ?? "";
    return host == "127.0.0.1" || host == "localhost" || host == "::1";
  }

  static String _sessionId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// handle answers one JSON-RPC message, or a batch of them; null for a
  /// message that wants no answer (a notification).
  Future<Object?> handle(Object? message, McpCaller caller) async {
    if (message is List) {
      var out = [
        for (var m in message)
          if (await _one(m, caller) case var r?) r
      ];
      return out.isEmpty ? null : out;
    }
    return _one(message, caller);
  }

  Future<Map<String, Object?>?> _one(Object? m, McpCaller caller) async {
    if (m is! Map) return _error(null, -32600, "Not a JSON-RPC message.");
    var id = m["id"];
    var method = m["method"];
    // A response or a notification: nothing to say back.
    if (method is! String) return null;
    if (id == null) return null;
    var params = m["params"] is Map
        ? Map<String, dynamic>.from(m["params"] as Map)
        : <String, dynamic>{};
    switch (method) {
      case "initialize":
        var asked = params["protocolVersion"];
        return _ok(id, {
          "protocolVersion": mcpProtocolVersions.contains(asked)
              ? asked
              : mcpProtocolVersions[1],
          "capabilities": {
            "tools": {"listChanged": false},
          },
          "serverInfo": {
            "name": "bison-relay",
            "title": "Bison Relay Creative AI",
            "version": "1.0.0",
          },
          "instructions": instructions(),
        });
      case "ping":
        return _ok(id, {});
      case "tools/list":
        return _ok(id, {
          "tools": [
            for (var t in tools())
              if (t.available()) t.toJson()
          ]
        });
      case "tools/call":
        var name = params["name"];
        var tool = tools().where((t) => t.name == name).firstOrNull;
        if (tool == null) {
          return _error(id, -32602, "There is no tool called $name.");
        }
        var args = params["arguments"] is Map
            ? Map<String, dynamic>.from(params["arguments"] as Map)
            : <String, dynamic>{};
        McpResult result;
        if (!tool.available()) {
          result = McpResult.error(
              "${tool.title} is switched off in Bison Relay (Settings > "
              "Plugins > Creative AI).");
        } else {
          try {
            result = await tool.run(args, caller);
          } catch (e) {
            result = McpResult.error("$e");
          }
        }
        onCall?.call(McpCall(DateTime.now(), caller, tool, args, result));
        return _ok(id, result.toJson());
      default:
        return _error(id, -32601, "Unknown method $method.");
    }
  }

  static Map<String, Object?> _ok(Object? id, Object? result) =>
      {"jsonrpc": "2.0", "id": id, "result": result};

  static Map<String, Object?> _error(Object? id, int code, String message) => {
        "jsonrpc": "2.0",
        "id": id,
        "error": {"code": code, "message": message},
      };
}
