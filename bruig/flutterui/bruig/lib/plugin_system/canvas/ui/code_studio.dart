import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/code_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// code_studio.dart is the Code Studio (Ken, 2026-11-15: "a studio option
// similar to the Sheet music element, where users can build and test their
// code snippets in a full screen studio"): a Code panel's project given the
// whole page, as the Score Studio gives a score. Its files down the left,
// its own panes and tabs in the middle -- tabs dragged between them, the
// lines between them dragged -- and on the right what it makes: the page or
// the Flutter app itself, live, over what it prints.
//
// Every change is the Code panel's, made through the controller, so the
// canvas shows it at once and a session of typing is one step to undo. A
// run is its Run panel's, kept there, where it has one.

class CodeStudio extends StatefulWidget {
  final CanvasController controller;
  final String codeId;
  final VoidCallback onDone;
  const CodeStudio(
      {required this.controller,
      required this.codeId,
      required this.onDone,
      super.key});

  @override
  State<CodeStudio> createState() => _CodeStudioState();
}

class _CodeStudioState extends State<CodeStudio> {
  CanvasController get c => widget.controller;
  CodeElement? get code {
    var e = c.document.elementById(widget.codeId);
    return e is CodeElement ? e : null;
  }

  /// _size is the code's size here, in pixels: the studio's own, not the
  /// panel's on the page.
  double _size = 15;
  int _pane = 0;

  /// _begun is whether the typing since the last tab or file change has
  /// begun a change to undo.
  bool _begun = false;

  /// _runs counts the runs, so the live preview starts again with each.
  int _runs = 0;
  bool _running = false;

  /// _logs is a run's output where there is no Run panel to keep it;
  /// _live what the live preview has printed since.
  List<CodeLog> _logs = const [];
  final List<CodeLog> _live = [];
  Widget? _app;
  String? _appError;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    _endTyping();
    c.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _endTyping() {
    if (_begun) {
      _begun = false;
      c.endInteraction();
    }
  }

  void _typed(CodeElement e, String file, String text) {
    if (!_begun) {
      _begun = true;
      c.beginInteraction();
    }
    var now = code;
    if (now != null) {
      c.replaceElement(now.withFileText(file, text), transient: true);
    }
  }

  void _show(CodeElement e, int pane, String file) {
    _endTyping();
    setState(() => _pane = pane);
    c.showCodeTab(e, pane, file);
  }

  CodeRunElement _runOf(CodeElement e) =>
      c.codeRunFor(e) ?? CodeRunElement(const ElementBase(id: ""), code: e.id);

  Future<void> _run() async {
    var e = code;
    if (e == null || _running) return;
    _endTyping();
    var run = _runOf(e);
    var runner = runnerOf(run, e);
    var entry = entryFile(run, e);
    if (entry == null || runner == CodeRunner.none) return;
    setState(() {
      _running = true;
      _live.clear();
      _runs++;
      if (runner == CodeRunner.flutter) {
        var built = buildFlutterApp(e, entry);
        _app = built.widget;
        _appError = built.error;
      }
    });
    try {
      if (run.id.isNotEmpty) {
        // Its Run panel's run: kept there, with its picture.
        await c.runCode(run);
      } else if (CanvasController.codeRunHost case var host?) {
        var out = await host.run(
            runner, e, entry, const Size(480, 360), (l) => setState(() {}));
        _logs = out.logs;
      } else {
        _logs = const [
          CodeLog("Code can't be run here.", kind: CodeLogKind.note)
        ];
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    var keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        (keys.isMetaPressed || keys.isControlPressed)) {
      _run();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var e = code;
    if (e == null) {
      return Material(
          color: colors.surface,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("That Code panel is no longer here.",
                style: TextStyle(color: colors.onSurface)),
            const SizedBox(height: 12),
            StudioPill(
                label: "Back to the canvas",
                filled: true,
                onTap: widget.onDone),
          ])));
    }
    _pane = _pane.clamp(0, e.layout.panes - 1);
    var run = _runOf(e);
    var runner = runnerOf(run, e);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Material(
        color: colors.surface,
        child: Column(children: [
          _topBar(context, e, runner),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                  width: 210,
                  color: colors.surfaceContainerLow,
                  child: _files(context, e)),
              VerticalDivider(
                  width: 1, thickness: 1, color: colors.outlineVariant),
              Expanded(child: _panes(context, e)),
              VerticalDivider(
                  width: 1, thickness: 1, color: colors.outlineVariant),
              SizedBox(width: 420, child: _runColumn(context, e, run, runner)),
            ]),
          ),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          _status(context, e, runner),
        ]),
      ),
    );
  }

  Widget _topBar(BuildContext context, CodeElement e, CodeRunner runner) {
    final colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text("Code Studio",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.onSurface)),
        const SizedBox(width: 12),
        Expanded(
          child: Text("${e.title} · ${e.project.label}",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
        ),
        StudioPill(
            key: const ValueKey("codeStudioSmaller"),
            label: "A−",
            onTap: () => setState(() => _size = math.max(9, _size - 1))),
        const SizedBox(width: 4),
        StudioPill(
            key: const ValueKey("codeStudioBigger"),
            label: "A+",
            onTap: () => setState(() => _size = math.min(32, _size + 1))),
        const SizedBox(width: 12),
        StudioPill(
            key: const ValueKey("codeStudioRun"),
            label: _running ? "Running…" : "▶ Run  ⌘↵",
            selected: _running,
            onTap: runner == CodeRunner.none || _running ? null : _run),
        const SizedBox(width: 8),
        StudioPill(
            key: const ValueKey("codeStudioDone"),
            label: "Done",
            filled: true,
            onTap: () {
              _endTyping();
              widget.onDone();
            }),
      ]),
    );
  }

  Widget _files(BuildContext context, CodeElement e) {
    final colors = ThemeNotifier.of(context).colors;
    var open = e.shownPanes[_pane].tabs;
    return ListView(padding: const EdgeInsets.all(10), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        child: Text("FILES",
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant)),
      ),
      for (var f in e.files)
        Material(
          key: ValueKey("codeStudioFile-${f.id}"),
          color: open.contains(f.id)
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => _show(e, _pane, f.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
              child: Row(children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: f.colour,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(f.name,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 13, color: colors.onSurface))),
                Text(f.language.label,
                    style: TextStyle(
                        fontSize: 10.5, color: colors.onSurfaceVariant)),
                PopupMenuButton<String>(
                  key: ValueKey("codeStudioFileMenu-${f.id}"),
                  tooltip: "",
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert,
                      size: 16, color: colors.onSurfaceVariant),
                  onSelected: (act) => act == "rename"
                      ? _rename(context, e, f)
                      : c.replaceElement(e.withoutFile(f.id)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: "rename", child: Text("Rename")),
                    if (e.files.length > 1)
                      const PopupMenuItem(
                          value: "delete", child: Text("Delete")),
                  ],
                ),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var (ext, label) in const [
          ("html", "HTML"),
          ("css", "CSS"),
          ("js", "JS"),
          ("py", "Python"),
          ("go", "Go"),
          ("dart", "Dart"),
        ])
          StudioPill(
              key: ValueKey("codeStudioAdd-$ext"),
              label: "+ $label",
              onTap: () {
                var n = 1;
                String name() => n == 1 ? "new.$ext" : "new$n.$ext";
                while (e.fileNamed(name()) != null) {
                  n++;
                }
                c.replaceElement(e.withFile(
                    CodeFile(
                        id: e.newFileId(),
                        name: name(),
                        colour: codeFileColours[
                            e.files.length % codeFileColours.length]),
                    pane: _pane));
              }),
      ]),
    ]);
  }

  Future<void> _rename(BuildContext context, CodeElement e, CodeFile f) async {
    var text = TextEditingController(text: f.name);
    var name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Rename file"),
              content: TextField(
                  key: const ValueKey("codeStudioRenameField"),
                  controller: text,
                  autofocus: true,
                  onSubmitted: (v) => Navigator.pop(context, v)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                TextButton(
                    onPressed: () => Navigator.pop(context, text.text),
                    child: const Text("Rename")),
              ],
            ));
    text.dispose();
    var clean = name?.trim() ?? "";
    var now = code;
    if (now == null || clean.isEmpty || clean == f.name) return;
    // Each file its own name.
    if (now.fileNamed(clean) != null) return;
    c.replaceElement(now.copyWith(files: [
      for (var g in now.files) g.id == f.id ? g.copyWith(name: clean) : g
    ]));
  }

  Widget _panes(BuildContext context, CodeElement e) {
    final colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, room) {
      var area = Offset.zero & room.biggest;
      var (rects, dividers) = paneRects(e, area);
      return Stack(children: [
        for (var (i, r) in rects.indexed)
          Positioned.fromRect(
              rect: r.deflate(0.5), child: _pane1(context, e, i)),
        for (var d in dividers)
          Positioned.fromRect(
            rect: d.hit,
            child: MouseRegion(
              cursor: d.columns
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.resizeRow,
              child: GestureDetector(
                key: ValueKey(
                    "codeStudioDivider-${d.columns ? "c" : "r"}${d.index}"),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _endTyping();
                  c.beginInteraction();
                },
                onPanUpdate: (u) {
                  var box = context.findRenderObject() as RenderBox;
                  var now = code;
                  if (now == null) return;
                  c.replaceElement(
                      codeDividerDraggedIn(
                          now, d, box.globalToLocal(u.globalPosition), area),
                      transient: true);
                },
                onPanEnd: (_) => c.endInteraction(),
                child: Center(
                  child: Container(
                    width: d.columns ? 1 : double.infinity,
                    height: d.columns ? double.infinity : 1,
                    color: colors.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  Widget _pane1(BuildContext context, CodeElement e, int i) {
    final colors = ThemeNotifier.of(context).colors;
    var p = e.shownPanes[i];
    var shown = p.shows;
    var f = shown == null ? null : e.file(shown);
    var look = CodeColours.of(e.theme);
    Widget tab(CodeFile t) {
      var on = t.id == shown;
      var body = Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 2),
        decoration: BoxDecoration(
          color: on ? look.bg : look.side,
          border: Border(
              top: BorderSide(
                  color: on ? t.colour : Colors.transparent, width: 3),
              right: BorderSide(color: look.line)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!on) ...[
            Container(width: 7, height: 7, color: t.colour),
            const SizedBox(width: 7),
          ],
          Text(t.name,
              style: TextStyle(fontSize: 13, color: on ? look.fg : look.dim)),
          IconButton(
            key: ValueKey("codeStudioClose-$i-${t.id}"),
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            splashRadius: 14,
            icon: Icon(Icons.close, color: look.dim),
            onPressed: () {
              _endTyping();
              c.closeCodeTab(e, i, t.id);
            },
          ),
        ]),
      );
      return Draggable<(int, String)>(
        data: (i, t.id),
        feedback: Material(color: Colors.transparent, child: body),
        childWhenDragging: Opacity(opacity: 0.4, child: body),
        child: GestureDetector(
            key: ValueKey("codeStudioTab-$i-${t.id}"),
            onTap: () => _show(e, i, t.id),
            child: body),
      );
    }

    var tabs = [
      for (var id in p.tabs)
        if (e.file(id) case var t?) t
    ];
    return Container(
      decoration: BoxDecoration(
          border: Border.all(
              color: i == _pane
                  ? colors.primary.withValues(alpha: 0.5)
                  : look.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Its tabs: a tab dropped on one goes before it; on the rest of
        // the row, at the end.
        DragTarget<(int, String)>(
          onAcceptWithDetails: (d) => _drop(d.data, i, tabs.length),
          builder: (context, waiting, _) => Container(
            height: 34,
            color: waiting.isEmpty
                ? look.side
                : colors.primary.withValues(alpha: 0.2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var (k, t) in tabs.indexed)
                  DragTarget<(int, String)>(
                    onAcceptWithDetails: (d) => _drop(d.data, i, k),
                    builder: (context, over, _) => Container(
                      decoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(
                                  color: over.isEmpty
                                      ? Colors.transparent
                                      : colors.primary,
                                  width: 3))),
                      child: tab(t),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: f == null
              ? ColoredBox(
                  color: look.bg,
                  child: Center(
                      child: Text("Drag a tab here, or pick a file",
                          style: TextStyle(color: look.dim, fontSize: 13))))
              : Listener(
                  onPointerDown: (_) {
                    if (_pane != i) setState(() => _pane = i);
                  },
                  child: CodeEditorBody(
                    key: ValueKey("codeStudioEditor-$i-${f.id}"),
                    element: e,
                    file: f.id,
                    fontSize: _size,
                    autofocus: i == _pane,
                    onChanged: (text) => _typed(e, f.id, text),
                    onRun: _run,
                  ),
                ),
        ),
      ]),
    );
  }

  /// _drop moves tab [what] (its pane and file) to pane [pane], before its
  /// tab [at].
  void _drop((int, String) what, int pane, int at) {
    var now = code;
    if (now == null) return;
    _endTyping();
    c.moveCodeTab(now, what.$2, what.$1, pane, at);
    setState(() => _pane = pane);
  }

  Widget _runColumn(BuildContext context, CodeElement e, CodeRunElement run,
      CodeRunner runner) {
    final colors = ThemeNotifier.of(context).colors;
    var entry = entryFile(run, e);
    var logs = [
      ...(run.id.isNotEmpty
          ? (c.codeRunShowFor(run).running
              ? c.codeRunShowFor(run).logs
              : (run.result?.logs ?? const <CodeLog>[]))
          : _logs),
      ..._live,
    ];
    Widget? preview;
    if (runner.previews && _runs > 0 && entry != null) {
      if (runner == CodeRunner.web) {
        preview = InAppWebView(
          key: ValueKey("codeStudioPage-$_runs"),
          initialData: InAppWebViewInitialData(
              data: webPage(e, entry),
              mimeType: "text/html",
              encoding: "utf-8"),
          initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true, isInspectable: false),
          onWebViewCreated: (w) => w.addJavaScriptHandler(
              handlerName: "codeConsole",
              callback: (args) {
                var kind = args.isNotEmpty ? "${args[0]}" : "log";
                // The run's own output already has the page's first lines:
                // these are what the page prints as it is used.
                if (!_running) {
                  setState(() =>
                      _live.add(CodeLog(args.length > 1 ? "${args[1]}" : "",
                          kind: kind == "error"
                              ? CodeLogKind.error
                              : kind == "warn"
                                  ? CodeLogKind.warn
                                  : CodeLogKind.log)));
                }
                return null;
              }),
        );
      } else if (runner == CodeRunner.flutter && _app != null) {
        preview = LayoutBuilder(
            builder: (context, room) => FittedBox(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: math.max(360, room.maxWidth),
                    height: room.maxHeight *
                        math.max(360, room.maxWidth) /
                        math.max(1, room.maxWidth),
                    child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            size: Size(
                                math.max(360, room.maxWidth), room.maxHeight)),
                        child: _app!),
                  ),
                ));
      } else if (runner == CodeRunner.flutter && _appError != null) {
        preview = Center(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_appError!,
                    style: const TextStyle(color: Color(0xFFFF8A8A)))));
      }
    }
    var console = Container(
      color: const Color(0xFF0E1114),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(children: [
            const Text("OUTPUT",
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A93A0))),
            const Spacer(),
            Text(runner.label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A93A0))),
          ]),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey("codeStudioOutput"),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            children: [
              if (logs.isEmpty)
                Text(
                    _running
                        ? "Running…"
                        : "Press Run (⌘↵) to run ${entry?.name ?? "it"}.",
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF8A93A0))),
              for (var l in logs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: SelectableText(
                    l.text,
                    style: TextStyle(
                        fontFamily:
                            l.kind == CodeLogKind.note ? null : "RobotoMono",
                        fontSize: 13,
                        fontStyle: l.kind == CodeLogKind.note
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: switch (l.kind) {
                          CodeLogKind.error => const Color(0xFFFF8A8A),
                          CodeLogKind.warn => const Color(0xFFF2C14E),
                          CodeLogKind.note => const Color(0xFF8A93A0),
                          CodeLogKind.log => const Color(0xFFD7DEE7),
                        }),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
    if (!runner.previews) return console;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        flex: 3,
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: preview ??
              Center(
                  child: Text("Press Run (⌘↵) to see it",
                      style: TextStyle(color: colors.onSurfaceVariant))),
        ),
      ),
      Divider(height: 1, thickness: 1, color: colors.outlineVariant),
      Expanded(flex: 2, child: console),
    ]);
  }

  Widget _status(BuildContext context, CodeElement e, CodeRunner runner) {
    final colors = ThemeNotifier.of(context).colors;
    var style = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        Text("${e.project.label} · runs with ${runner.label}", style: style),
        const Spacer(),
        Text("⌘↵ runs · Tab indents · drag a tab to another pane",
            style: style),
      ]),
    );
  }
}
