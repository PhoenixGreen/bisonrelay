import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_sheet_find.dart is the Data Studio's way through many sheets, too
// many for one strip of tabs: a list dropping down from "Sheets", searched
// as typed, each sheet with what shows it and where; and the order the
// tabs take, this page's sheets first.

/// SheetUse is what shows a sheet: tables and charts, and their scenes.
typedef SheetUse = ({int views, List<int> scenes});

/// sheetUses is each of [doc]'s sheets' use, by id.
Map<String, SheetUse> sheetUses(CanvasDocument doc) {
  var views = <String, int>{};
  var scenes = <String, Set<int>>{};
  for (var (i, scene) in doc.allScenes.indexed) {
    var elements = i == doc.at ? doc.elements : scene.elements;
    for (var e in elements) {
      var id = linkOf(e)?.sheet;
      if (id == null) continue;
      views[id] = (views[id] ?? 0) + 1;
      (scenes[id] ??= {}).add(i + 1);
    }
  }
  return {
    for (var s in doc.sheets)
      s.id: (
        views: views[s.id] ?? 0,
        scenes: (scenes[s.id] ?? const <int>{}).toList()..sort()
      ),
  };
}

/// sheetsInOrder is [doc]'s sheets as tabbed, this page's first, and how
/// many are this page's.
(List<DataSheet>, int) sheetsInOrder(CanvasDocument doc) {
  var here = {
    for (var e in doc.elements)
      if (linkOf(e)?.sheet case var id?) id
  };
  var mine = [
    for (var s in doc.sheets)
      if (here.contains(s.id)) s
  ];
  return (
    [
      ...mine,
      for (var s in doc.sheets)
        if (!here.contains(s.id)) s
    ],
    mine.length
  );
}

/// usesSay is a sheet's use in a few words.
String usesSay(SheetUse u) {
  if (u.views == 0) return "Nothing shows it";
  var where = u.scenes.length == 1
      ? "scene ${u.scenes.single}"
      : u.scenes.length <= 3
          ? "scenes ${u.scenes.join(", ")}"
          : "${u.scenes.length} scenes";
  return "${u.views} table${u.views == 1 ? "" : "s"} or chart"
      "${u.views == 1 ? "" : "s"} · $where";
}

/// SheetFinder is "Sheets": a list of the canvas's sheets that drops down,
/// searched as typed; picking one opens it.
class SheetFinder extends StatefulWidget {
  final CanvasDocument document;
  final String current;
  final ValueChanged<String> onOpen;
  const SheetFinder(
      {required this.document,
      required this.current,
      required this.onOpen,
      super.key});

  @override
  State<SheetFinder> createState() => _SheetFinderState();
}

class _SheetFinderState extends State<SheetFinder> {
  final _menu = MenuController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var doc = widget.document;
    var uses = sheetUses(doc);
    var (ordered, here) = sheetsInOrder(doc);
    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh)),
      onOpen: () => _search.clear(),
      menuChildren: [
        StatefulBuilder(builder: (context, setMenu) {
          var q = _search.text.trim().toLowerCase();
          // This page's first; the rest by their folders, those in none first;
          // a search matches a name or a folder.
          var rest = ordered.skip(here).toList()
            ..sort((a, b) => a.folder.compareTo(b.folder));
          var listed = [...ordered.take(here), ...rest];
          var shown = [
            for (var (i, s) in listed.indexed)
              if (q.isEmpty ||
                  s.name.toLowerCase().contains(q) ||
                  s.folder.toLowerCase().contains(q))
                (i, s)
          ];
          return SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: TextField(
                  key: const ValueKey("dataStudioFindSheet"),
                  controller: _search,
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: colors.onSurface),
                  decoration: InputDecoration(
                      isDense: true,
                      hintText: "Find a sheet",
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide.none)),
                  onChanged: (_) => setMenu(() {}),
                  onSubmitted: (_) {
                    if (shown.isNotEmpty) _open(shown.first.$2.id);
                  },
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var (k, (i, s)) in shown.indexed) ...[
                            if (q.isEmpty && i == here && here > 0)
                              Divider(height: 8, color: colors.outlineVariant),
                            // A folder's name over its sheets.
                            if (i >= here &&
                                s.folder.isNotEmpty &&
                                (k == 0 ||
                                    shown[k - 1].$1 < here ||
                                    shown[k - 1].$2.folder != s.folder))
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 8, 12, 2),
                                child: Row(children: [
                                  Icon(Icons.folder_outlined,
                                      size: 14, color: colors.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(s.folder.toUpperCase(),
                                      key: ValueKey(
                                          "dataStudioFolder-${s.folder}"),
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          letterSpacing: 0.8,
                                          fontWeight: FontWeight.w700,
                                          color: colors.onSurfaceVariant)),
                                ]),
                              ),
                            InkWell(
                              key: ValueKey("dataStudioFound-${s.id}"),
                              onTap: () => _open(s.id),
                              child: Container(
                                color: s.id == widget.current
                                    ? colors.primary.withValues(alpha: 0.12)
                                    : null,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: colors.onSurface)),
                                      Text(
                                          "${usesSay(uses[s.id]!)}"
                                          "${s.made != null ? " · made from another" : ""}",
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: colors.onSurfaceVariant)),
                                    ]),
                              ),
                            ),
                          ],
                          if (shown.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text("No sheet is called that.",
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.onSurfaceVariant)),
                            ),
                        ])),
              ),
            ]),
          );
        }),
      ],
      builder: (context, menu, _) => InkWell(
        key: const ValueKey("dataStudioSheets"),
        borderRadius: BorderRadius.circular(6),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.view_list_outlined, size: 16, color: colors.onSurface),
            const SizedBox(width: 6),
            Text("Sheets · ${doc.sheets.length}",
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
            Icon(Icons.arrow_drop_down, size: 18, color: colors.onSurface),
          ]),
        ),
      ),
    );
  }

  void _open(String id) {
    _menu.close();
    widget.onOpen(id);
  }
}
