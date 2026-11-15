import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// code_element.dart is a Code panel on a canvas (Ken, 2026-11-15: "a
// text/coding panel on the canvas ... split screen and a file area to show
// how the code works together"): a little project of files, shown as an
// editor would show it -- a window bar, the files down the side, and one to
// three panes, each with its own tabs -- for teaching how code is written
// and how files use each other.
//
// It can type itself in (CodeTyping) and light lines with a note beside
// them (CodeStep), both on the scene's clock, so a lesson plays the same in
// the app and in an export. A Run panel (code_run_element.dart) runs it.
//
// Everything here is plain data; when what is shown at a moment is worked
// out in code_timing.dart, and drawn in render/code_painter.dart.

/// CodeLanguage is what a file is written in, by its name's ending.
enum CodeLanguage {
  html("HTML", "xml", "  "),
  css("CSS", "css", "  "),
  js("JS", "javascript", "  "),
  python("Python", "python", "    "),
  go("Go", "go", "\t"),
  dart("Dart", "dart", "  "),
  text("Text", "", "  ");

  final String label;

  /// grammar is its highlighting grammar's name (see code_highlight.dart);
  /// empty for none.
  final String grammar;

  /// indent is what Tab puts in.
  final String indent;
  const CodeLanguage(this.label, this.grammar, this.indent);

  static CodeLanguage of(String name) {
    var dot = name.lastIndexOf(".");
    var ext = dot < 0 ? "" : name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      "html" || "htm" => html,
      "css" => css,
      "js" || "mjs" => js,
      "py" => python,
      "go" => go,
      "dart" => dart,
      _ => text,
    };
  }
}

/// CodeKind is what a project is (Ken, 2026-11-15: "the user can choose the
/// code type in the Settings panel"): what it starts with, and what runs it.
enum CodeKind {
  web("Web page", CodeLayout.oneOverTwo, ["index.html", "style.css", "app.js"]),
  python("Python", CodeLayout.one, ["main.py"]),
  go("Go", CodeLayout.one, ["main.go"]),
  dart("Dart", CodeLayout.one, ["main.dart"]),
  flutter("Flutter app", CodeLayout.one, ["main.dart"]);

  final String label;

  /// layout and files are what an empty project of it starts with: one
  /// pane for each file, as far as the layout has panes.
  final CodeLayout layout;
  final List<String> files;
  const CodeKind(this.label, this.layout, this.files);

  /// of is what [files] look like they are, for a project saved before it
  /// had a kind of its own.
  static CodeKind of(List<CodeFile> files) {
    bool has(CodeLanguage l) => files.any((f) => f.language == l);
    if (has(CodeLanguage.html)) return web;
    if (has(CodeLanguage.python)) return python;
    if (has(CodeLanguage.go)) return go;
    if (files.any((f) =>
        f.language == CodeLanguage.dart &&
        f.text.contains("package:flutter/"))) {
      return flutter;
    }
    if (has(CodeLanguage.dart)) return dart;
    return web;
  }
}

/// CodeLayout is how the panes sit: the five the prototype offered.
enum CodeLayout {
  one("One pane", 1),
  twoSide("Two side by side", 2),
  twoStacked("Two stacked", 2),
  threeSide("Three side by side", 3),
  oneOverTwo("One over two", 3);

  final String label;
  final int panes;
  const CodeLayout(this.label, this.panes);

  /// evenColumns and evenRows are its panes' sizes when nobody has dragged
  /// the lines between them: the columns across (of the bottom row, for one
  /// over two), and the rows down.
  List<double> get evenColumns => switch (this) {
        twoSide || oneOverTwo => const [1, 1],
        threeSide => const [1, 1, 1],
        _ => const [1],
      };
  List<double> get evenRows => switch (this) {
        twoStacked || oneOverTwo => const [1, 1],
        _ => const [1],
      };
}

/// CodeTheme is the panel's colours: a dark editor's, a light one's, and a
/// blackboard's for a classroom.
enum CodeTheme {
  night("Night"),
  day("Day"),
  chalk("Chalkboard");

  final String label;
  const CodeTheme(this.label);
}

/// codeFileColours are the colours files are given in turn: each file's tab,
/// its square in the file list, and its name underlined where other files
/// use it.
const codeFileColours = [
  Color(0xFFE8835A),
  Color(0xFF5B9BFF),
  Color(0xFFF2C14E),
  Color(0xFF2ED6A1),
  Color(0xFFC792EA),
  Color(0xFFE36F8E),
];

/// CodeFile is one file of the project. [id] is how tabs, highlight steps
/// and a Run panel name it, so a file can be renamed without losing them.
class CodeFile {
  final String id;
  final String name;
  final String text;
  final Color colour;
  const CodeFile(
      {required this.id,
      required this.name,
      this.text = "",
      this.colour = const Color(0xFF5B9BFF)});

  CodeLanguage get language => CodeLanguage.of(name);

  CodeFile copyWith({String? name, String? text, Color? colour}) => CodeFile(
      id: id,
      name: name ?? this.name,
      text: text ?? this.text,
      colour: colour ?? this.colour);

  Map<String, dynamic> toJson() =>
      {"id": id, "name": name, "text": text, "colour": colorToJson(colour)};

  static CodeFile? fromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    var id = jsonString(j["id"], "");
    if (id.isEmpty) return null;
    return CodeFile(
        id: id,
        name: jsonString(j["name"], "file.txt"),
        text: jsonString(j["text"], ""),
        colour: colorFromJson(j["colour"], codeFileColours.first));
  }
}

/// CodePane is one pane: the files open in it as tabs, in order, and the
/// one it shows when nothing playing says otherwise.
class CodePane {
  final List<String> tabs;
  final String active;
  const CodePane({this.tabs = const [], this.active = ""});

  /// shows is the tab it shows by itself: its own pick, or its first.
  String? get shows => tabs.contains(active)
      ? active
      : tabs.isEmpty
          ? null
          : tabs.first;

  CodePane copyWith({List<String>? tabs, String? active}) =>
      CodePane(tabs: tabs ?? this.tabs, active: active ?? this.active);

  Map<String, dynamic> toJson() => {"tabs": tabs, "active": active};

  static CodePane fromJson(dynamic j) => j is Map<String, dynamic>
      ? CodePane(tabs: [
          for (var t in (j["tabs"] is List ? j["tabs"] as List : const []))
            if (t is String) t
        ], active: jsonString(j["active"], ""))
      : const CodePane();
}

/// CodeTyping is how the code types itself in: [speed] letters a second
/// from [start] seconds into the scene, a [pause] at each line's end, the
/// panes one after another or all at once ([together]), each pane's tabs in
/// order. Indents type quickly, as an editor fills them.
class CodeTyping {
  final bool on;
  final double speed;
  final double pause;
  final double start;
  final bool together;
  final bool caret;
  const CodeTyping(
      {this.on = true,
      this.speed = 30,
      this.pause = 0.08,
      this.start = 0.5,
      this.together = false,
      this.caret = true});

  CodeTyping copyWith(
          {bool? on,
          double? speed,
          double? pause,
          double? start,
          bool? together,
          bool? caret}) =>
      CodeTyping(
          on: on ?? this.on,
          speed: (speed ?? this.speed).clamp(2.0, 400.0),
          pause: (pause ?? this.pause).clamp(0.0, 3.0),
          start: math.max(0.0, start ?? this.start),
          together: together ?? this.together,
          caret: caret ?? this.caret);

  Map<String, dynamic> toJson() => {
        "on": on,
        "speed": speed,
        "pause": pause,
        "start": start,
        "together": together,
        "caret": caret,
      };

  static CodeTyping fromJson(dynamic j) => j is Map<String, dynamic>
      ? const CodeTyping().copyWith(
          on: jsonBool(j["on"], true),
          speed: jsonDouble(j["speed"], 30),
          pause: jsonDouble(j["pause"], 0.08),
          start: jsonDouble(j["start"], 0.5),
          together: jsonBool(j["together"], false),
          caret: jsonBool(j["caret"], true))
      : const CodeTyping(on: false);
}

/// CodeStep lights lines [from] to [to] of [file] from [at] seconds for
/// [length], with [note] beside them; the pane holding the file shows it
/// while it is lit.
class CodeStep {
  final double at;
  final double length;
  final String file;
  final int from;
  final int to;
  final String note;
  const CodeStep(
      {required this.at,
      this.length = 3,
      required this.file,
      this.from = 1,
      this.to = 1,
      this.note = ""});

  bool litAt(double t) => t >= at && t < at + length;

  CodeStep copyWith(
      {double? at,
      double? length,
      String? file,
      int? from,
      int? to,
      String? note}) {
    var f = math.max(1, from ?? this.from);
    var l = math.max(1, to ?? this.to);
    // From never after To: whichever was just set wins.
    if (l < f) {
      if (from != null) {
        l = f;
      } else {
        f = l;
      }
    }
    return CodeStep(
        at: math.max(0.0, at ?? this.at),
        length: (length ?? this.length).clamp(0.2, 600.0),
        file: file ?? this.file,
        from: f,
        to: l,
        note: note ?? this.note);
  }

  Map<String, dynamic> toJson() => {
        "at": at,
        "length": length,
        "file": file,
        "from": from,
        "to": to,
        if (note.isNotEmpty) "note": note,
      };

  static CodeStep? fromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    return CodeStep(at: 0, file: jsonString(j["file"], "")).copyWith(
        at: jsonDouble(j["at"], 0),
        length: jsonDouble(j["length"], 3),
        from: jsonInt(j["from"], 1),
        to: jsonInt(j["to"], 1),
        note: jsonString(j["note"], ""));
  }
}

/// CodeElement is the element itself.
class CodeElement extends CanvasElement {
  /// title is the project's name, on the window bar.
  final String title;

  /// project is what the project is: see CodeKind.
  final CodeKind project;
  final List<CodeFile> files;
  final CodeLayout layout;
  final List<CodePane> panes;

  /// columns and rows are the panes' sizes as shares (see
  /// CodeLayout.evenColumns): changed by dragging the lines between them.
  final List<double> columns;
  final List<double> rows;
  final CodeTheme theme;

  /// fontSize is the code's size on the page; the window's own parts (its
  /// bar, tabs, file list) are sized from it.
  final double fontSize;
  final bool showFiles;

  /// links underlines, in its colour, another file's name where the code
  /// uses it ("style.css", "app.js", an import).
  final bool links;
  final bool lineNumbers;
  final bool windowBar;

  /// playbar puts play controls in its window bar: back to the start, play
  /// and pause, and where its lesson has got to (Ken, 2026-11-15).
  final bool playbar;
  final CodeTyping typing;
  final List<CodeStep> steps;

  /// dim darkens the other lines of a pane while lines are lit in it.
  final bool dim;

  /// start is its code as it began -- kept the first time it is typed into
  /// on the canvas or in the Code Studio (typedInto) -- for Reset to go
  /// back to (Ken: "if the student makes a mistake editing the code it
  /// can go back to the initial version"); null until then.
  final List<CodeFile>? start;

  const CodeElement(
    super.base, {
    this.title = "project",
    this.project = CodeKind.web,
    this.files = const [],
    this.layout = CodeLayout.one,
    this.panes = const [],
    this.columns = const [1],
    this.rows = const [1],
    this.theme = CodeTheme.night,
    this.fontSize = 16,
    this.showFiles = true,
    this.links = true,
    this.lineNumbers = true,
    this.windowBar = true,
    this.playbar = true,
    this.typing = const CodeTyping(on: false),
    this.steps = const [],
    this.dim = true,
    this.start,
  });

  @override
  ElementKind get kind => ElementKind.code;

  @override
  CanvasElement rebase(ElementBase base) => CodeElement(base,
      title: title,
      project: project,
      files: files,
      layout: layout,
      panes: panes,
      columns: columns,
      rows: rows,
      theme: theme,
      fontSize: fontSize,
      showFiles: showFiles,
      links: links,
      lineNumbers: lineNumbers,
      windowBar: windowBar,
      playbar: playbar,
      typing: typing,
      steps: steps,
      dim: dim,
      start: start);

  CodeElement copyWith({
    String? title,
    CodeKind? project,
    List<CodeFile>? files,
    CodeLayout? layout,
    List<CodePane>? panes,
    List<double>? columns,
    List<double>? rows,
    CodeTheme? theme,
    double? fontSize,
    bool? showFiles,
    bool? links,
    bool? lineNumbers,
    bool? windowBar,
    bool? playbar,
    CodeTyping? typing,
    List<CodeStep>? steps,
    bool? dim,
    List<CodeFile>? start,
    bool clearStart = false,
  }) =>
      CodeElement(base,
          title: title ?? this.title,
          project: project ?? this.project,
          files: files ?? this.files,
          layout: layout ?? this.layout,
          panes: panes ?? this.panes,
          columns: columns ?? this.columns,
          rows: rows ?? this.rows,
          theme: theme ?? this.theme,
          fontSize: (fontSize ?? this.fontSize).clamp(4.0, 1000.0),
          showFiles: showFiles ?? this.showFiles,
          links: links ?? this.links,
          lineNumbers: lineNumbers ?? this.lineNumbers,
          windowBar: windowBar ?? this.windowBar,
          playbar: playbar ?? this.playbar,
          typing: typing ?? this.typing,
          steps: steps ?? this.steps,
          dim: dim ?? this.dim,
          start: clearStart ? null : start ?? this.start);

  /// startedAs is it begun again as an empty project of [k]: its kind's
  /// files, empty, each in a pane of its own as far as there are panes;
  /// nothing typed in or lit. Its look and box stay.
  CodeElement startedAs(CodeKind k) {
    var made = [
      for (var (i, name) in k.files.indexed)
        CodeFile(
            id: "f${i + 1}",
            name: name,
            colour: codeFileColours[i % codeFileColours.length]),
    ];
    var panes = <CodePane>[];
    for (var i = 0; i < k.layout.panes; i++) {
      var tabs = i < k.layout.panes - 1
          ? [if (i < made.length) made[i].id]
          : [for (var f in made.skip(i)) f.id];
      panes.add(CodePane(tabs: tabs, active: tabs.isEmpty ? "" : tabs.first));
    }
    return copyWith(
        project: k,
        files: made,
        layout: k.layout,
        panes: panes,
        columns: k.layout.evenColumns,
        rows: k.layout.evenRows,
        typing: typing.copyWith(on: false),
        steps: const []);
  }

  CodeFile? file(String id) {
    for (var f in files) {
      if (f.id == id) return f;
    }
    return null;
  }

  CodeFile? fileNamed(String name) {
    for (var f in files) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// shownPanes is its panes as many as its layout has, any missing empty.
  List<CodePane> get shownPanes => [
        for (var i = 0; i < layout.panes; i++)
          i < panes.length ? panes[i] : const CodePane(),
      ];

  /// newFileId is an id no file of it has.
  String newFileId() {
    var n = files.length + 1;
    while (file("f$n") != null) {
      n++;
    }
    return "f$n";
  }

  /// withFile is it with [f] added, opened as a tab in pane [pane].
  CodeElement withFile(CodeFile f, {int pane = 0}) =>
      copyWith(files: [...files, f]).openTab(pane, f.id);

  /// withFileText is it with file [id]'s text [text].
  CodeElement withFileText(String id, String text) => copyWith(files: [
        for (var f in files) f.id == id ? f.copyWith(text: text) : f,
      ]);

  /// typedInto is it with file [id]'s text [text], typed by hand: its code
  /// as it was kept first, as the [start] Reset goes back to.
  CodeElement typedInto(String id, String text) =>
      (start == null ? copyWith(start: files) : this).withFileText(id, text);

  /// changedFromStart is whether its code is no longer as it began: Reset
  /// shows only then.
  bool get changedFromStart {
    var s = start;
    if (s == null) return false;
    if (s.length != files.length) return true;
    for (var i = 0; i < s.length; i++) {
      if (s[i].id != files[i].id ||
          s[i].name != files[i].name ||
          s[i].text != files[i].text) {
        return true;
      }
    }
    return false;
  }

  /// reset is it with its code as it began again; its tabs on files it
  /// no longer has closed. Its start is kept, to go back to again.
  CodeElement get reset {
    var s = start;
    if (s == null) return this;
    var ids = {for (var f in s) f.id};
    return copyWith(files: s, panes: [
      for (var p in panes)
        p.copyWith(tabs: [
          for (var t in p.tabs)
            if (ids.contains(t)) t
        ])
    ]);
  }

  /// withoutFile is it without file [id]: out of every pane, its steps
  /// gone.
  CodeElement withoutFile(String id) => copyWith(
        files: [
          for (var f in files)
            if (f.id != id) f
        ],
        panes: [
          for (var p in panes)
            p.copyWith(tabs: [
              for (var t in p.tabs)
                if (t != id) t
            ]),
        ],
        steps: [
          for (var s in steps)
            if (s.file != id) s
        ],
      );

  /// withLayout is it laid out as [next], keeping every open tab: fewer
  /// panes fold their tabs into the last one; more panes each take a file
  /// not yet open, or a spare tab from the pane with most.
  CodeElement withLayout(CodeLayout next) {
    var ps = [
      for (var p in panes) p.copyWith(tabs: [...p.tabs])
    ];
    while (ps.length > next.panes) {
      var gone = ps.removeLast();
      var last = ps.last;
      ps[ps.length - 1] = last.copyWith(tabs: [
        ...last.tabs,
        for (var t in gone.tabs)
          if (!last.tabs.contains(t)) t
      ]);
    }
    while (ps.length < next.panes) {
      var open = {for (var p in ps) ...p.tabs};
      var free = files.where((f) => !open.contains(f.id)).firstOrNull;
      if (free != null) {
        ps.add(CodePane(tabs: [free.id], active: free.id));
        continue;
      }
      var donor = -1;
      for (var (i, p) in ps.indexed) {
        if (p.tabs.length > 1 &&
            (donor < 0 || p.tabs.length > ps[donor].tabs.length)) {
          donor = i;
        }
      }
      if (donor < 0) {
        ps.add(const CodePane());
        continue;
      }
      var d = ps[donor];
      var moved = d.tabs.last;
      var rest = d.tabs.sublist(0, d.tabs.length - 1);
      ps[donor] = d.copyWith(
          tabs: rest, active: d.active == moved ? rest.last : d.active);
      ps.add(CodePane(tabs: [moved], active: moved));
    }
    return copyWith(
        layout: next,
        panes: ps,
        columns: next.evenColumns,
        rows: next.evenRows);
  }

  CodeElement _withPane(int i, CodePane p) => copyWith(panes: [
        for (var (k, q) in shownPanes.indexed) k == i ? p : q,
      ]);

  /// openTab opens file [id] in pane [pane] (after the tab it shows), and
  /// shows it.
  CodeElement openTab(int pane, String id) {
    var ps = shownPanes;
    if (pane < 0 || pane >= ps.length || file(id) == null) return this;
    var p = ps[pane];
    if (p.tabs.contains(id)) return _withPane(pane, p.copyWith(active: id));
    var at = p.shows == null ? p.tabs.length : p.tabs.indexOf(p.shows!) + 1;
    return _withPane(
        pane, CodePane(tabs: [...p.tabs]..insert(at, id), active: id));
  }

  /// closeTab closes file [id]'s tab in pane [pane]; the tab beside it is
  /// shown in its place.
  CodeElement closeTab(int pane, String id) {
    var ps = shownPanes;
    if (pane < 0 || pane >= ps.length) return this;
    var p = ps[pane];
    var at = p.tabs.indexOf(id);
    if (at < 0) return this;
    var rest = [...p.tabs]..removeAt(at);
    var active = p.active == id
        ? (rest.isEmpty ? "" : rest[math.min(at, rest.length - 1)])
        : p.active;
    return _withPane(pane, CodePane(tabs: rest, active: active));
  }

  /// moveTab moves file [id]'s tab from pane [from] to pane [to], before
  /// that pane's tab [index] (its count for the end), and shows it there.
  CodeElement moveTab(String id, int from, int to, int index) {
    var ps = [...shownPanes];
    if (from < 0 || from >= ps.length || to < 0 || to >= ps.length) {
      return this;
    }
    var old = ps[from].tabs.indexOf(id);
    if (old < 0) return this;
    if (from == to) {
      var tabs = [...ps[from].tabs]..removeAt(old);
      if (old < index) index--;
      tabs.insert(index.clamp(0, tabs.length), id);
      ps[from] = CodePane(tabs: tabs, active: id);
      return copyWith(panes: ps);
    }
    var after = closeTab(from, id);
    ps = [...after.shownPanes];
    var dst = [...ps[to].tabs];
    var dup = dst.indexOf(id);
    if (dup >= 0) {
      dst.removeAt(dup);
      if (dup < index) index--;
    }
    dst.insert(index.clamp(0, dst.length), id);
    ps[to] = CodePane(tabs: dst, active: id);
    return after.copyWith(panes: ps);
  }

  @override
  Map<String, dynamic> props() => {
        "title": title,
        "projectKind": project.name,
        "files": [for (var f in files) f.toJson()],
        "layout": layout.name,
        "panes": [for (var p in panes) p.toJson()],
        "columns": columns,
        "rows": rows,
        "theme": theme.name,
        "fontSize": fontSize,
        "showFiles": showFiles,
        "links": links,
        "lineNumbers": lineNumbers,
        "windowBar": windowBar,
        if (!playbar) "playbar": false,
        "typing": typing.toJson(),
        "steps": [for (var s in steps) s.toJson()],
        "dim": dim,
        if (start case var s?) "start": [for (var f in s) f.toJson()],
      };

  factory CodeElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    List<double> shares(dynamic v, List<double> even) {
      var out = [
        for (var x in (v is List ? v : const []))
          if (x is num && x.isFinite && x > 0) x.toDouble()
      ];
      return out.length == even.length ? out : even;
    }

    var layout =
        CodeLayout.values.asNameMap()[json["layout"]] ?? CodeLayout.one;
    var files = [
      for (var f in (json["files"] is List ? json["files"] as List : []))
        if (CodeFile.fromJson(f) case var file?) file
    ];
    return CodeElement(b,
        title: jsonString(json["title"], "project"),
        project: CodeKind.values.asNameMap()[json["projectKind"]] ??
            CodeKind.of(files),
        files: files,
        layout: layout,
        panes: [
          for (var p in (json["panes"] is List ? json["panes"] as List : []))
            CodePane.fromJson(p)
        ],
        columns: shares(json["columns"], layout.evenColumns),
        rows: shares(json["rows"], layout.evenRows),
        theme: CodeTheme.values.asNameMap()[json["theme"]] ?? CodeTheme.night,
        fontSize: jsonDouble(json["fontSize"], 16).clamp(4.0, 1000.0),
        showFiles: jsonBool(json["showFiles"], true),
        links: jsonBool(json["links"], true),
        lineNumbers: jsonBool(json["lineNumbers"], true),
        windowBar: jsonBool(json["windowBar"], true),
        playbar: jsonBool(json["playbar"], true),
        typing: CodeTyping.fromJson(json["typing"]),
        steps: [
          for (var s in (json["steps"] is List ? json["steps"] as List : []))
            if (CodeStep.fromJson(s) case var step?) step
        ],
        dim: jsonBool(json["dim"], true),
        start: json["start"] is List
            ? [
                for (var f in json["start"] as List)
                  if (CodeFile.fromJson(f) case var file?) file
              ]
            : null);
  }
}
