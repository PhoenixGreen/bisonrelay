import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// creative_ai_settings.dart is Creative AI's section of Settings > Plugins:
// whether it is on and where it works, which Claude models it asks for, the
// Claude Code it runs, and how other apps connect to it.

class CreativeAiSettingsSection extends StatefulWidget {
  const CreativeAiSettingsSection({super.key});

  @override
  State<CreativeAiSettingsSection> createState() =>
      _CreativeAiSettingsSectionState();
}

class _CreativeAiSettingsSectionState extends State<CreativeAiSettingsSection> {
  String? _connectResult;
  bool _connecting = false;
  bool _proxied = false;
  bool _showToken = false;
  late final TextEditingController _path;

  @override
  void initState() {
    super.initState();
    var ai = context.read<CreativeAi>();
    _path = TextEditingController(text: ai.prefs.claudePath);
    if (ai.prefs.enabled && !ai.looked) ai.findClaude();
    ai.proxied().then((p) {
      if (mounted) setState(() => _proxied = p);
    });
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _connect(CreativeAi ai) async {
    setState(() {
      _connecting = true;
      _connectResult = null;
    });
    var problem = await ai.connectClaudeCode();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connectResult = problem == null
          ? "Connected. Claude Code (in a terminal or in VS Code) now has "
              "Bison Relay's tools: start a new Claude Code conversation and "
              "ask it to work on your canvas or document."
          : "Could not connect: $problem";
    });
  }

  @override
  Widget build(BuildContext context) {
    var ai = context.watch<CreativeAi>();
    var prefs = ai.prefs;
    var colors = ThemeNotifier.of(context).colors;
    Widget help(String text) => Padding(
          padding: const EdgeInsets.only(right: 60, bottom: 8),
          child: Txt.S(text, color: TextColor.onSurfaceVariant),
        );
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged,
            {Key? key}) =>
        Row(children: [
          Expanded(child: Txt.M(label)),
          Switch(key: key, value: value, onChanged: onChanged),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      toggle("Creative AI", prefs.enabled, (v) {
        prefs.enabled = v;
        if (v && !ai.looked) ai.findClaude();
      }, key: const ValueKey("creativeAiEnabled")),
      help("Lets Claude work on your canvases and documents, inline with "
          "Bison Relay's own tools: a Creative AI sidebar on the Canvas page, "
          "a panel and right-click edits on the Writing page. It runs Claude "
          "Code on this computer, signed in to your own Claude plan: no API "
          "key, nothing billed per request."),
      if (prefs.enabled) ...[
        help("What you ask, and the canvas or document it works on, is sent "
            "to Anthropic by Claude Code under your Claude account, only when "
            "you ask. Claude cannot publish or send anything: that stays "
            "with you."),
        if (_proxied)
          Container(
            margin: const EdgeInsets.only(right: 60, bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(6)),
            child: Text(
                "This app is set to use a proxy (Settings > Network). Claude "
                "Code makes its own connection to Anthropic and does not go "
                "through it: Anthropic will see this computer's address.",
                style:
                    TextStyle(fontSize: 12.5, color: colors.onErrorContainer)),
          ),
        const SizedBox(height: 4),
        const Txt.M("Works in"),
        toggle("Canvas", prefs.canvas, (v) => prefs.canvas = v,
            key: const ValueKey("creativeAiCanvas")),
        toggle("Writing", prefs.writing, (v) => prefs.writing = v,
            key: const ValueKey("creativeAiWriting")),
        toggle("Put Claude's changes straight into documents", prefs.applyEdits,
            (v) => prefs.applyEdits = v,
            key: const ValueKey("creativeAiApplyEdits")),
        help("Off, each change Claude makes to a document waits in the "
            "Creative AI panel to be accepted or rejected."),
        const SizedBox(height: 8),
        const Txt.M("Models"),
        _modelRow(
            "Sidebar requests", prefs.chatModel, (m) => prefs.chatModel = m),
        _modelRow("Quick edits", prefs.editModel, (m) => prefs.editModel = m),
        help("Opus writes best and is the most careful; Sonnet is quicker; "
            "Haiku is quickest. All are on your plan, and Opus uses its "
            "limits fastest."),
        const SizedBox(height: 8),
        const Txt.M("Claude Code"),
        const SizedBox(height: 4),
        _claudeStatus(ai, colors),
        Padding(
          padding: const EdgeInsets.only(right: 60, top: 6, bottom: 4),
          child: TextField(
            key: const ValueKey("creativeAiClaudePath"),
            controller: _path,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              labelText: "Program (leave empty to find it)",
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              prefs.claudePath = v;
              ai.findClaude();
            },
          ),
        ),
        Row(children: [
          TextButton.icon(
            key: const ValueKey("creativeAiFind"),
            onPressed: () {
              prefs.claudePath = _path.text;
              ai.findClaude();
            },
            icon: const Icon(Icons.search, size: 16),
            label: const Text("Find again"),
          ),
        ]),
        const SizedBox(height: 8),
        const Txt.M("Other apps"),
        help("Claude Code in a terminal or in VS Code can use the same tools. "
            "Connect adds Bison Relay to Claude Code for every folder; it "
            "only works while Bison Relay is open with Creative AI on."),
        _serverStatus(ai, colors),
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilledButton.tonal(
            key: const ValueKey("creativeAiConnect"),
            onPressed:
                _connecting || !ai.server.running ? null : () => _connect(ai),
            child: Text(_connecting ? "Connecting…" : "Connect Claude Code"),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ai.connectCommand));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                  content: Text("Copied. Run it in a terminal to connect.")));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text("Copy the command"),
          ),
          TextButton(
            onPressed: () => setState(() => _showToken = !_showToken),
            child: Text(_showToken ? "Hide the token" : "Show the token"),
          ),
          TextButton(
            key: const ValueKey("creativeAiNewToken"),
            onPressed: prefs.newToken,
            child: const Text("New token"),
          ),
        ]),
        if (_showToken)
          Padding(
            padding: const EdgeInsets.only(right: 60, top: 4),
            child: SelectableText(ai.connectCommand,
                style: const TextStyle(fontSize: 12, fontFamily: "monospace")),
          ),
        if (_connectResult case var r?)
          Padding(
            padding: const EdgeInsets.only(right: 60, top: 6),
            child: Txt.S(r, color: TextColor.onSurfaceVariant),
          ),
        help("A new token cuts off every app given the old one; connect "
            "again afterwards."),
      ],
      const Divider(),
    ]);
  }

  Widget _modelRow(
          String label, ClaudeModel value, ValueChanged<ClaudeModel> set) =>
      Row(children: [
        Expanded(child: Txt.S(label)),
        DropdownButton<ClaudeModel>(
          value: value,
          isDense: true,
          items: [
            for (var m in ClaudeModel.values)
              DropdownMenuItem(value: m, child: Text(m.label)),
          ],
          onChanged: (m) {
            if (m != null) set(m);
          },
        ),
        const SizedBox(width: 60),
      ]);

  Widget _claudeStatus(CreativeAi ai, ColorScheme colors) {
    String text;
    Color colour;
    if (!ai.looked) {
      text = "Looking for Claude Code…";
      colour = colors.onSurfaceVariant;
    } else if (ai.exe == null) {
      text = CreativeAi.claudeMissing;
      colour = colors.error;
    } else {
      var inEditor = ai.exe!.contains("${Platform.pathSeparator}extensions"
          "${Platform.pathSeparator}");
      text = "Using ${ai.version ?? "Claude Code"} at ${ai.exe}. It must be "
          "signed in to your Claude account: run it once in a terminal and "
          "use /login if it is not."
          "${inEditor ? " This copy lives inside an editor's Claude Code "
              "extension: the editor need not be open, only installed. To do "
              "without the editor, install Claude Code on its own (it is "
              "found first, and shares the same sign-in)." : ""}";
      colour = colors.onSurfaceVariant;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 60),
      child: Text(text, style: TextStyle(fontSize: 12.5, color: colour)),
    );
  }

  Widget _serverStatus(CreativeAi ai, ColorScheme colors) {
    var running = ai.server.running;
    return Padding(
      padding: const EdgeInsets.only(right: 60, bottom: 6),
      child: Row(children: [
        Icon(running ? Icons.circle : Icons.circle_outlined,
            size: 10, color: running ? colors.primary : colors.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
              running
                  ? "Listening at ${ai.url} (this computer only)."
                  : ai.serverError ?? "Starting…",
              style: TextStyle(
                  fontSize: 12.5,
                  color: running ? colors.onSurfaceVariant : colors.error)),
        ),
      ]),
    );
  }
}
