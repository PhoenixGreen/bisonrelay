import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:bruig/components/epub_reader/epub_book.dart';
import 'package:bruig/components/epub_reader/reader_inputs.dart';
import 'package:bruig/components/epub_reader/reader_shell.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

// epub_reader_view.dart is Bison Relay's own EPUB reader, as Files shows a
// book: its pages in a web view (reader_shell.dart), two side by side where
// the book is made of spreads and the view is wide enough, turned with the
// buttons, the arrow keys or a swipe, and the contents a click away. A
// book's own scripts, sound and animation run as they would in Apple Books.
// Ken, 2026-11-19: "build something like Thorium" so his interactive books
// can be read in full in Bison Relay.

/// bookFolder is where the book at [filePath] is unpacked: one folder per
/// file and version of it, so an edited book is unpacked afresh.
Future<String> bookFolder(String filePath) async {
  var file = File(filePath);
  var stat = await file.stat();
  var key = sha256
      .convert(utf8.encode("${file.absolute.path}|${stat.size}|"
          "${stat.modified.millisecondsSinceEpoch}"))
      .toString()
      .substring(0, 24);
  return path.join(Directory.systemTemp.path, "bruig-books", key);
}

/// openBook unpacks (or finds unpacked) the book at [filePath] and writes
/// the reader's shell beside its pages.
Future<EpubBook> openBook(String filePath) async {
  var folder = await bookFolder(filePath);
  EpubBook book;
  if (await File(path.join(folder, "META-INF", "container.xml")).exists()) {
    book = await readEpubFolder(folder);
  } else {
    book = await unpackEpub(await File(filePath).readAsBytes(), folder);
  }
  await File(path.join(folder, readerShellName)).writeAsString(readerShell);
  return book;
}

class EpubReaderView extends StatefulWidget {
  final String filePath;

  /// initialPage is the page it opens on; [onPage] hears each page turned
  /// to, so the place can be kept.
  final int initialPage;
  final ValueChanged<int>? onPage;

  /// inputs is the MIDI keyboard a book may ask to hear; null for none.
  final ReaderInputs? inputs;

  const EpubReaderView(
      {required this.filePath,
      this.initialPage = 0,
      this.onPage,
      this.inputs,
      super.key});

  @override
  State<EpubReaderView> createState() => EpubReaderViewState();
}

class EpubReaderViewState extends State<EpubReaderView> {
  EpubBook? _book;
  String? _error;
  InAppWebViewController? _web;
  bool _shellReady = false;

  /// _page is the first page shown: where the reader is.
  late int _page = widget.initialPage;

  /// _wide is whether the view is wide enough for spreads, as last laid out.
  bool _wide = false;

  EpubBook? get book => _book;
  int get page => _page;

  /// _stopKeys stops the keyboard a book asked for; null while not heard.
  VoidCallback? _stopKeys;

  /// _microphone is what the person said when a book asked to listen:
  /// asked once a book, as Apple Books asks once an app.
  bool? _microphone;

  @override
  void dispose() {
    _stopKeys?.call();
    super.dispose();
  }

  /// _keys hands the keyboard to the page that asked for it.
  Future<void> _keys() async {
    if (_stopKeys != null) return;
    var inputs = widget.inputs;
    var stop = await inputs?.listenToKeys((key) {
      _web?.evaluateJavascript(source: keyScript(key));
    });
    if (!mounted) {
      stop?.call();
      return;
    }
    _stopKeys = stop;
    if (stop == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text("This book listens to a MIDI keyboard, and none is "
              "plugged in.")));
    }
  }

  /// _askMicrophone asks the person whether the book may listen.
  Future<PermissionResponse> _askMicrophone(PermissionRequest request) async {
    var wanted = request.resources;
    var hears = wanted.contains(PermissionResourceType.MICROPHONE);
    var other = wanted.any((r) => r != PermissionResourceType.MICROPHONE);
    if (!hears || other) {
      // A camera, the screen, the place it is read: never.
      return PermissionResponse(
          resources: wanted, action: PermissionResponseAction.DENY);
    }
    var yes = _microphone ??= await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Let this book listen?"),
            content: Text("\"${_book?.title ?? "This book"}\" wants to hear "
                "you through the microphone, to check what you play or "
                "sing. It is heard only while the book is open."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Don't allow")),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Allow")),
            ],
          ),
        ) ??
        false;
    return PermissionResponse(
        resources: wanted,
        action: yes
            ? PermissionResponseAction.GRANT
            : PermissionResponseAction.DENY);
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      setState(() {
        _book = null;
        _error = null;
        _shellReady = false;
        _page = widget.initialPage;
      });
      _open();
    }
  }

  Future<void> _open() async {
    try {
      var book = await openBook(widget.filePath);
      if (!mounted) return;
      setState(() {
        _book = book;
        _page = _page.clamp(0, book.pages.length - 1);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is EpubError ? e.message : "$e");
    }
  }

  /// spreads is whether pages are shown two at a time now.
  bool get spreads {
    var b = _book;
    if (b == null || !b.fixed || b.spread == EpubSpread.none) return false;
    return b.spread == EpubSpread.both || _wide;
  }

  /// _units are what one turn moves by: spreads, or single pages.
  List<(int?, int?)> get _units => spreads
      ? _book!.spreads
      : [for (var i = 0; i < _book!.pages.length; i++) (i, null)];

  int get _unit {
    var units = _units;
    var i = units.indexWhere((u) => u.$1 == _page || u.$2 == _page);
    return i < 0 ? 0 : i;
  }

  /// panel is the panel being read in Panel View, (page, index in its
  /// page's panels), or null for whole pages. Entered with a double tap on
  /// a panel, as Kindle's is; left with another, or Escape.
  (int, int)? get panel => _panel;
  (int, int)? _panel;

  /// _panels is every panel in the book, page by page, in reading order.
  List<(int, int)> get _panels => [
        for (var (i, p) in _book!.pages.indexed)
          for (var j = 0; j < p.panels.length; j++) (i, j)
      ];

  /// _sideOf is which frame of the shell page [page] is in now, or null
  /// where it is not shown.
  String? _sideOf(int page) {
    var u = _units[_unit];
    if (!spreads) return u.$1 == page ? "single" : null;
    if (u.$1 == page) return "left";
    if (u.$2 == page) return "right";
    return null;
  }

  /// readPanel zooms to panel [at], turning to its page first if it is not
  /// shown.
  Future<void> readPanel((int, int) at) async {
    var (page, i) = at;
    var b = _book;
    if (b == null || i >= b.pages[page].panels.length) return;
    if (_sideOf(page) == null) {
      setState(() => _page = page);
      widget.onPage?.call(page);
      await _show();
    }
    setState(() => _panel = at);
    await _zoom();
  }

  Future<void> _zoom() async {
    var at = _panel, web = _web;
    if (at == null || web == null || !_shellReady) return;
    var side = _sideOf(at.$1);
    if (side == null) return;
    var p = _book!.pages[at.$1].panels[at.$2];
    await web.evaluateJavascript(
        source: "reader.zoom(${jsonEncode({
          "side": side,
          "x": p.x,
          "y": p.y,
          "w": p.width,
          "h": p.height
        })});");
  }

  /// readPanels starts Panel View at the first panel on show.
  void readPanels() {
    var u = _units[_unit];
    for (var page in [u.$1, u.$2]) {
      if (page != null && _book!.pages[page].panels.isNotEmpty) {
        readPanel((page, 0));
        return;
      }
    }
  }

  /// leavePanels shows whole pages again.
  void leavePanels() {
    if (_panel == null) return;
    setState(() => _panel = null);
    _web?.evaluateJavascript(source: "reader.unzoom();");
  }

  /// doubleTap is a double tap at ([x], [y]) on the page in frame [side]:
  /// into the panel there, or out of Panel View.
  void doubleTap(String side, double x, double y) {
    if (_panel != null) {
      leavePanels();
      return;
    }
    var u = _units[_unit];
    var page = side == "right" ? u.$2 : u.$1;
    if (page == null) return;
    var panels = _book!.pages[page].panels;
    var i = panels.indexWhere((p) =>
        x >= p.x && x <= p.x + p.width && y >= p.y && y <= p.y + p.height);
    if (i >= 0) readPanel((page, i));
  }

  /// turn goes [by] spreads or pages on; in Panel View, [by] panels, onto
  /// the next page's panels when one page's run out, and back to whole
  /// pages where the next page has none.
  void turn(int by) {
    if (_panel case var at?) {
      var all = _panels;
      var i = all.indexOf(at) + by;
      if (i >= 0 && i < all.length && (all[i].$1 - at.$1).abs() <= 1) {
        readPanel(all[i]);
        return;
      }
      leavePanels();
    }
    var units = _units;
    if (units.isEmpty) return;
    var to = (_unit + by).clamp(0, units.length - 1);
    var u = units[to];
    var first = u.$1 ?? u.$2 ?? 0;
    if (first == _page) return;
    setState(() => _page = first);
    widget.onPage?.call(first);
    _show();
  }

  /// goTo opens the page [href] is on.
  void goTo(String href) {
    var i = _book?.pageOf(href) ?? -1;
    if (i < 0) return;
    setState(() => _page = i);
    widget.onPage?.call(i);
    _show();
  }

  Future<void> _show() async {
    var b = _book, web = _web;
    if (b == null || web == null || !_shellReady) return;
    var u = _units[_unit];
    ShellPage? of(int? i) => i == null ? null : ShellPage.of(b.pages[i]);
    await web.evaluateJavascript(
        source: showScript(of(u.$1), of(u.$2), spread: spreads));
    // A panel still on show (the view turned on its side) is zoomed again.
    if (_panel case var at? when _sideOf(at.$1) == null) {
      setState(() => _panel = null);
    }
    await _zoom();
  }

  /// heard is a message from the shell: ready, a key, a swipe, a double
  /// tap, or a page asking for the keyboard.
  @visibleForTesting
  void heard(List<dynamic> args) {
    if (args.isEmpty || args.first is! Map) return;
    var m = args.first as Map;
    switch (m["type"]) {
      case "ready":
        _shellReady = true;
        _show();
      case "key":
        switch (m["key"]) {
          case "ArrowRight" || "ArrowDown" || "PageDown" || " ":
            turn(1);
          case "ArrowLeft" || "ArrowUp" || "PageUp":
            turn(-1);
          case "Escape":
            leavePanels();
        }
      case "swipe":
        turn(m["dir"] == "next" ? 1 : -1);
      case "midi":
        _keys();
      case "double":
        doubleTap("${m["side"]}", (m["x"] as num? ?? 0).toDouble(),
            (m["y"] as num? ?? 0).toDouble());
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight ||
            LogicalKeyboardKey.arrowDown ||
            LogicalKeyboardKey.pageDown ||
            LogicalKeyboardKey.space:
        turn(1);
      case LogicalKeyboardKey.arrowLeft ||
            LogicalKeyboardKey.arrowUp ||
            LogicalKeyboardKey.pageUp:
        turn(-1);
      case LogicalKeyboardKey.escape when _panel != null:
        leavePanels();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// _stay keeps the view inside the book: a link out goes to the browser.
  Future<NavigationActionPolicy> _stay(NavigationAction action) async {
    var url = action.request.url;
    if (url == null) return NavigationActionPolicy.CANCEL;
    if (url.scheme == "file") {
      var p = path.normalize(url.toFilePath());
      var folder = _book?.folder;
      return folder != null && (p == folder || path.isWithin(folder, p))
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    }
    if (url.scheme == "about" || url.scheme == "data") {
      return NavigationActionPolicy.ALLOW;
    }
    if ((url.scheme == "https" || url.scheme == "http") &&
        action.isForMainFrame != false) {
      launchUrl(url, mode: LaunchMode.externalApplication);
    }
    return NavigationActionPolicy.CANCEL;
  }

  String _where() {
    var b = _book;
    if (b == null) return "";
    if (_panel case (var page, var i)) {
      return "Panel ${i + 1} of ${b.pages[page].panels.length} · "
          "page ${page + 1}";
    }
    var u = _units[_unit];
    var first = (u.$1 ?? u.$2 ?? 0) + 1, last = (u.$2 ?? u.$1 ?? 0) + 1;
    var n = b.pages.length;
    return first == last ? "Page $first of $n" : "Pages $first–$last of $n";
  }

  @override
  Widget build(BuildContext context) {
    if (_error case var e?) return Center(child: Text(e));
    var b = _book;
    if (b == null) return const Center(child: CircularProgressIndicator());
    var theme = Theme.of(context);
    Widget view;
    if (InAppWebViewPlatform.instance == null) {
      // No web view here (a test, or Linux): said, not an error.
      view = Center(
          key: const ValueKey("epubNoView"),
          child: Text("Books can't be shown on this system yet.",
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)));
    } else {
      view = InAppWebView(
        key: const ValueKey("epubView"),
        initialUrlRequest: URLRequest(
            url: WebUri.uri(Uri.file(path.join(b.folder, readerShellName)))),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          allowingReadAccessTo: WebUri.uri(Uri.directory(b.folder)),
          transparentBackground: true,
          // A book's sound and video play in the page, not full screen.
          allowsInlineMediaPlayback: true,
          supportZoom: false,
          disableContextMenu: true,
          isInspectable: false,
        ),
        // Bison Relay's own bridge in every page, before its scripts.
        initialUserScripts: UnmodifiableListView([
          UserScript(
              source: readerBridge,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false),
        ]),
        onPermissionRequest: (_, request) => _askMicrophone(request),
        shouldOverrideUrlLoading: (_, action) => _stay(action),
        onWebViewCreated: (c) {
          _web = c;
          c.addJavaScriptHandler(
              handlerName: "reader",
              callback: (args) {
                heard(args);
                return null;
              });
        },
      );
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Column(children: [
        _bar(context, b),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            // Turned on its side, a book of spreads shows two pages: the
            // bar and the pages are both redrawn for it, after this frame.
            var wide = box.maxWidth > box.maxHeight * 1.1;
            if (wide != _wide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || wide == _wide) return;
                setState(() => _wide = wide);
                _show();
              });
            }
            return view;
          }),
        ),
      ]),
    );
  }

  Widget _bar(BuildContext context, EpubBook b) {
    var theme = Theme.of(context);
    var units = _units;
    var at = _unit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text(
              [b.title, if (b.authors.isNotEmpty) b.authors.join(", ")]
                  .where((s) => s.isNotEmpty)
                  .join(" · "),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (b.contents.isNotEmpty)
          PopupMenuButton<String>(
            key: const ValueKey("epubContents"),
            tooltip: "Contents",
            icon: const Icon(Icons.toc),
            onSelected: goTo,
            itemBuilder: (_) => [
              for (var c in b.contents)
                PopupMenuItem(
                  value: c.href,
                  child: Padding(
                    padding: EdgeInsets.only(left: 14.0 * c.depth),
                    child: Text(c.title.isEmpty ? c.href : c.title),
                  ),
                ),
            ],
          ),
        if (b.hasPanels)
          IconButton(
            key: const ValueKey("epubPanels"),
            icon: Icon(_panel == null
                ? Icons.auto_stories_outlined
                : Icons.auto_stories),
            tooltip: _panel == null
                ? "Panel View: one panel at a time (or double-tap a panel)"
                : "Whole pages (Escape)",
            isSelected: _panel != null,
            onPressed: _panel == null ? readPanels : leavePanels,
          ),
        IconButton(
          key: const ValueKey("epubBack"),
          icon: const Icon(Icons.chevron_left),
          tooltip: "Back",
          onPressed: at > 0 || _panel != null ? () => turn(-1) : null,
        ),
        Text(_where(),
            key: const ValueKey("epubWhere"),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        IconButton(
          key: const ValueKey("epubForward"),
          icon: const Icon(Icons.chevron_right),
          tooltip: "Forward",
          onPressed:
              at < units.length - 1 || _panel != null ? () => turn(1) : null,
        ),
      ]),
    );
  }
}
