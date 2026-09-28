import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/stock_import.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// stock_panel.dart is the Stock section of the Assets sidebar: search Pixabay,
// the Noun Project, Freesound and Jamendo, look and listen, and use what fits.
//
// Nothing connects until somebody searches. Opening the sidebar, choosing a
// library or changing a filter before the first search makes no request --
// the sidebar is somewhere people pass through, and a design tool that
// phoned four companies every time it was opened would be telling them when
// its owner was at work. After a search, changing a filter searches again,
// because that is what the change was for.
//
// A result is a preview until it is used: clicked (onto the middle of the
// canvas), dragged (to where it is let go, or onto a channel), or added with
// its + (into the library only). Then it is fetched, stored, and credited --
// see stock_import.dart.

const _sourceKey = "canvasStock.source";
const _filtersKey = "canvasStock.filters";

/// _previewMaxBytes bounds a preview. Jamendo's is the whole track as a
/// stream, a few megabytes; anything far past that is not a preview.
const _previewMaxBytes = 48 * 1024 * 1024;

class StockPanel extends StatefulWidget {
  final CanvasController controller;
  const StockPanel({required this.controller, super.key});

  @override
  State<StockPanel> createState() => _StockPanelState();
}

class _StockPanelState extends State<StockPanel> {
  StockSource _source = StockSource.pixabayPictures;
  final Map<StockSource, Map<String, String>> _filters = {};
  final TextEditingController _search = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _secret = TextEditingController();

  bool? _proxied;
  bool? _hasKey;
  bool _editingKey = false;

  /// _query is the last search made, or null before the first -- which is
  /// what decides whether changing a filter searches again.
  StockQuery? _query;
  StockPage? _last;
  List<StockItem> _items = const [];
  bool _loading = false;
  String? _problem;

  /// _busy is the results being fetched right now, by key.
  final Set<String> _busy = {};

  late final _Previewer _previewer =
      _Previewer(widget.controller.audio.engine, () {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _previewer.dispose();
    _search.dispose();
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    var proxied = await networkIsProxied();
    var source =
        StockSource.fromName(await StorageManager.readString(_sourceKey));
    try {
      var saved = jsonDecode(await StorageManager.readString(_filtersKey));
      if (saved is Map) {
        for (var e in saved.entries) {
          if (e.value is! Map) continue;
          _filters[StockSource.fromName(e.key as String?)] = {
            for (var f in (e.value as Map).entries) "${f.key}": "${f.value}",
          };
        }
      }
    } catch (_) {
      // Nothing saved yet, or something unreadable: the defaults.
    }
    var hasKey = await StockKeys.has(source);
    if (!mounted) return;
    setState(() {
      _proxied = proxied;
      _source = source;
      _hasKey = hasKey;
    });
  }

  void _saveFilters() => StorageManager.saveString(
      _filtersKey,
      jsonEncode({
        for (var e in _filters.entries) e.key.name: e.value,
      }));

  Future<void> _choose(StockSource source) async {
    if (source == _source) return;
    _previewer.stop();
    StorageManager.saveString(_sourceKey, source.name);
    var hasKey = await StockKeys.has(source);
    if (!mounted) return;
    setState(() {
      _source = source;
      _hasKey = hasKey;
      _editingKey = false;
      _items = const [];
      _last = null;
      _problem = null;
    });
    if (_query != null && hasKey) _run();
  }

  void _setFilter(String id, String value) {
    setState(() => (_filters[_source] ??= {})[id] = value);
    _saveFilters();
    if (_query != null && _hasKey == true) _run();
  }

  Future<void> _saveKey() async {
    var key = _key.text.trim();
    var secret = _secret.text.trim();
    if (key.isEmpty || (_source.needsSecret && secret.isEmpty)) return;
    await StockKeys.save(_source, key, secret);
    _key.clear();
    _secret.clear();
    if (!mounted) return;
    setState(() {
      _hasKey = true;
      _editingKey = false;
    });
  }

  Future<void> _forgetKey() async {
    await StockKeys.forget(_source);
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _editingKey = false;
      _items = const [];
      _last = null;
    });
  }

  /// _run searches afresh; [more] fetches the next page of the last search
  /// instead.
  Future<void> _run({bool more = false}) async {
    var prefs = context.read<CanvasPreferences>();
    var last = _last;
    var q = more && _query != null && last != null
        ? _query!.next(last)
        : StockQuery(_source,
            text: _search.text, filters: {...?_filters[_source]});
    if (!more) _previewer.stop();
    setState(() {
      _query = q;
      _loading = true;
      _problem = null;
      if (!more) _items = const [];
    });
    var page = await StockClient.instance.search(q,
        allowFetching: prefs.allowFetching, proxied: _proxied ?? true);
    if (!mounted || _query != q) return;
    setState(() {
      _loading = false;
      _last = page;
      if (page.worked) {
        _items = [..._items, ...page.items];
        if (_items.isEmpty) _problem = "Nothing found.";
      } else {
        _problem = page.problem;
      }
    });
  }

  Future<LibraryAsset?> _fetch(StockItem item) async {
    if (_busy.contains(item.key)) return null;
    setState(() => _busy.add(item.key));
    try {
      return await fetchStockItem(context, widget.controller, item);
    } finally {
      if (mounted) setState(() => _busy.remove(item.key));
    }
  }

  Future<void> _use(StockItem item) async {
    var asset = await _fetch(item);
    if (asset == null) return;
    var c = widget.controller;
    c.addElement(elementForAsset(asset, c.document));
  }

  Future<void> _add(StockItem item) async {
    var snacks = SnackBarModel.of(context);
    var asset = await _fetch(item);
    if (asset != null) snacks.success("${asset.name} is in the library.");
  }

  Future<void> _listen(StockItem item) async {
    var prefs = context.read<CanvasPreferences>();
    var ok = await _previewer.toggle(item,
        allowFetching: prefs.allowFetching, proxied: _proxied ?? true);
    if (!ok && mounted) {
      SnackBarModel.of(context)
          .error("The preview of ${item.title} could not be played.");
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var prefs = context.watch<CanvasPreferences>();
    var muted = TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant);

    Widget note(String text, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text, style: muted),
        );

    if (_proxied == null) return const SizedBox.shrink();

    // The two gates, before anything else is drawn: a search box that could
    // only ever answer "no" is worse than saying so.
    if (!prefs.allowFetching) {
      return ListView(padding: const EdgeInsets.all(8), children: [
        note(
            key: const ValueKey("stockOff"),
            "Searching Pixabay, the Noun Project, Freesound and Jamendo "
            "connects to them directly -- not through the proxy in Settings "
            "> Network -- so they see your connection. Nothing is sent until "
            "you search, and nothing is downloaded until you use a result. "
            "Each needs a free key of your own."),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey("stockAllowFetching"),
            onPressed: () => prefs.allowFetching = true,
            child: const Text("Allow fetching"),
          ),
        ),
        note("The same switch is in Settings > Plugins > Canvas, as \"Let a "
            "canvas fetch data\"."),
      ]);
    }
    if (_proxied == true) {
      return ListView(padding: const EdgeInsets.all(8), children: [
        note(
            key: const ValueKey("stockProxied"),
            StockClient.refusal(allowFetching: true, proxied: true)!),
      ]);
    }

    var filters = filtersFor(_source);
    var chosen = _filters[_source] ?? const {};
    var visual = _source.kind != AssetKind.audio;

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      children: [
        CanvasWrap(children: [
          CanvasDropdown<StockSource>(
            key: const ValueKey("stockSource"),
            label: "Library",
            value: _source,
            width: 200,
            options: [for (var s in StockSource.values) (s, s.label)],
            onChanged: _choose,
          ),
        ]),
        if (_hasKey == false || _editingKey)
          ..._keyForm(theme, muted)
        else if (_hasKey == true) ...[
          Row(children: [
            Expanded(
                child: Text("Using your ${_source.from} key.", style: muted)),
            TextButton(
              key: const ValueKey("stockChangeKey"),
              onPressed: () => setState(() => _editingKey = true),
              child: const Text("Change"),
            ),
            TextButton(
              key: const ValueKey("stockForgetKey"),
              onPressed: _forgetKey,
              child: const Text("Forget"),
            ),
          ]),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey("stockSearch"),
                controller: _search,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: "Search ${_source.label}",
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                onSubmitted: (_) => _run(),
              ),
            ),
            CanvasIconButton(
              key: const ValueKey("stockGo"),
              icon: Icons.arrow_forward,
              tooltip: "Search",
              tight: true,
              onPressed: _loading ? null : () => _run(),
            ),
          ]),
          const SizedBox(height: 6),
          CanvasWrap(children: [
            for (var f in filters)
              CanvasDropdown<String>(
                key: ValueKey("stockFilter-${f.id}"),
                label: f.label,
                value: f.options.any((o) => o.$1 == chosen[f.id])
                    ? chosen[f.id]!
                    : f.options.first.$1,
                width: 110,
                options: f.options,
                onChanged: (v) => _setFilter(f.id, v),
              ),
          ]),
          note(_source.terms),
          if (_problem != null)
            note(key: const ValueKey("stockProblem"), _problem!),
          if (visual)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var item in _items) _draggable(item, _tile(item, theme)),
            ])
          else
            for (var item in _items) _draggable(item, _row(item, theme)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_last?.more == true)
            Center(
              child: TextButton(
                key: const ValueKey("stockMore"),
                onPressed: () => _run(more: true),
                child: const Text("More"),
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> _keyForm(ThemeNotifier theme, TextStyle muted) => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SelectableText(
            "${_source.from} needs a key of your own, free from "
            "${_source.keyPage}${_source.needsSecret ? " (a key and a secret)" : ""}. "
            "It is kept on this computer, never in a canvas.",
            style: muted,
          ),
        ),
        TextField(
          key: const ValueKey("stockKey"),
          controller: _key,
          obscureText: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true, hintText: "Key"),
          onSubmitted: (_) => _saveKey(),
        ),
        if (_source.needsSecret)
          TextField(
            key: const ValueKey("stockSecret"),
            controller: _secret,
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration:
                const InputDecoration(isDense: true, hintText: "Secret"),
            onSubmitted: (_) => _saveKey(),
          ),
        Row(children: [
          TextButton(
            key: const ValueKey("stockSaveKey"),
            onPressed: _saveKey,
            child: const Text("Save key"),
          ),
          if (_editingKey)
            TextButton(
              onPressed: () => setState(() => _editingKey = false),
              child: const Text("Cancel"),
            ),
        ]),
      ];

  Widget _draggable(StockItem item, Widget body) => Draggable<PendingAsset>(
        key: ValueKey("stock-${item.key}"),
        data: PendingAsset(
            kind: item.kind, name: item.title, fetch: () => _fetch(item)),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.8,
            child: SizedBox(
                width: 96,
                height: 72,
                child: _Thumb(item: item, width: 96, height: 72)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _use(item),
          child: body,
        ),
      );

  Widget _tile(StockItem item, ThemeNotifier theme) => _Hover(
        builder: (over) => SizedBox(
          width: 96,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              _Thumb(item: item, width: 96, height: 72),
              if (item.length > 0)
                Positioned(
                    left: 4, bottom: 4, child: _Badge(_duration(item.length))),
              if (over || _busy.contains(item.key))
                Positioned(right: 2, top: 2, child: _addButton(item, theme)),
            ]),
            const SizedBox(height: 2),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.colors.onSurface)),
            if (item.author.isNotEmpty)
              Text(item.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, color: theme.colors.onSurfaceVariant)),
          ]),
        ),
      );

  Widget _row(StockItem item, ThemeNotifier theme) {
    var playing = _previewer.playing == item.key;
    var fetching = _previewer.loading == item.key;
    return _Hover(
      builder: (over) => SizedBox(
        height: 40,
        child: Row(children: [
          SizedBox(
            width: 32,
            child: fetching
                ? const Center(
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : InkResponse(
                    key: ValueKey("stockPlay-${item.key}"),
                    radius: 16,
                    onTap: () => _listen(item),
                    child: Icon(playing ? Icons.stop_circle : Icons.play_circle,
                        size: 22, color: theme.colors.primary),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: theme.colors.onSurface)),
                  Text(
                      [item.author, item.license]
                          .where((s) => s.isNotEmpty)
                          .join(" · "),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: theme.colors.onSurfaceVariant)),
                ]),
          ),
          if (item.length > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(_duration(item.length),
                  style: TextStyle(
                      fontSize: 11, color: theme.colors.onSurfaceVariant)),
            ),
          SizedBox(
            width: 28,
            child: over || _busy.contains(item.key)
                ? _addButton(item, theme)
                : null,
          ),
        ]),
      ),
    );
  }

  Widget _addButton(StockItem item, ThemeNotifier theme) {
    var busy = _busy.contains(item.key);
    return InkResponse(
      key: ValueKey("stockAdd-${item.key}"),
      onTap: busy ? null : () => _add(item),
      radius: 14,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.colors.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.add, size: 14, color: theme.colors.onSurface),
      ),
    );
  }
}

/// _Hover is whether the pointer is over [builder]'s widget -- no Tooltip,
/// which crashes inside a Draggable's row as its overlay is torn down.
class _Hover extends StatefulWidget {
  final Widget Function(bool over) builder;
  const _Hover({required this.builder});

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _over = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: widget.builder(_over),
      );
}

/// _Thumb is a result's picture, from the library's own server: shown, not
/// kept. A sound with nothing to show is its note.
class _Thumb extends StatelessWidget {
  final StockItem item;
  final double width;
  final double height;
  const _Thumb({required this.item, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    Widget blank() => Icon(
        item.kind == AssetKind.audio
            ? Icons.music_note_outlined
            : Icons.image_outlined,
        size: height * 0.4,
        color: theme.colors.onSurfaceVariant);
    var url = item.thumb;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        color: theme.colors.surfaceContainerHighest,
        child: url.isEmpty
            ? blank()
            : url.toLowerCase().endsWith(".svg")
                ? SvgPicture.network(url,
                    fit: BoxFit.contain, placeholderBuilder: (_) => blank())
                : Image(
                    image: StockClient.instance.thumbnail(url),
                    // Icons are drawings on nothing, and would be cropped.
                    fit: item.source == StockSource.nounProject
                        ? BoxFit.contain
                        : BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => blank(),
                  ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xAA000000),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 10, color: Color(0xFFFFFFFF))),
      );
}

String _duration(double seconds) {
  if (seconds <= 0) return "";
  var s = seconds.round();
  return "${s ~/ 60}:${(s % 60).toString().padLeft(2, "0")}";
}

/// _Previewer plays one stock sound at a time, fetched to a temporary file --
/// the player reads files -- and forgotten when the sidebar closes.
class _Previewer {
  final AudioEngine engine;
  final VoidCallback changed;
  _Previewer(this.engine, this.changed);

  /// playing and loading are the item keys being heard and being fetched.
  String? playing;
  String? loading;

  AudioTrack? _track;
  AudioVoice? _voice;
  Timer? _watch;
  Directory? _dir;

  /// toggle stops [item] if it is playing, or plays it; false when it could
  /// not be.
  Future<bool> toggle(StockItem item,
      {required bool allowFetching, required bool proxied}) async {
    if (playing == item.key) {
      stop();
      return true;
    }
    stop();
    loading = item.key;
    changed();
    try {
      _dir ??= await Directory.systemTemp.createTemp("canvas-stock-preview");
      var file = File(path.join(_dir!.path, "${fileNameFor(item.key)}.mp3"));
      if (!await file.exists()) {
        var got = await StockClient.instance.download(item.preview, file,
            maxBytes: _previewMaxBytes,
            allowFetching: allowFetching,
            proxied: proxied);
        if (!got) return false;
      }
      // Another preview asked for while this one was fetching wins.
      if (loading != item.key) return true;
      if (!await engine.start()) return false;
      var track = await engine.open(file.path);
      if (track == null) return false;
      if (loading != item.key) {
        engine.close(track);
        return true;
      }
      _track = track;
      _voice = engine.play(track, volume: 1);
      playing = item.key;
      _watch = Timer.periodic(const Duration(milliseconds: 250), (_) {
        var v = _voice;
        if (v == null || !engine.alive(v)) stop();
      });
      return true;
    } finally {
      if (loading == item.key) loading = null;
      changed();
    }
  }

  void stop() {
    _watch?.cancel();
    _watch = null;
    var voice = _voice, track = _track;
    _voice = null;
    _track = null;
    if (voice != null) engine.stop(voice);
    if (track != null) engine.close(track);
    var was = playing != null || loading != null;
    playing = null;
    loading = null;
    if (was) changed();
  }

  void dispose() {
    _watch?.cancel();
    var voice = _voice, track = _track;
    if (voice != null) engine.stop(voice);
    if (track != null) engine.close(track);
    var dir = _dir;
    if (dir != null) {
      dir.delete(recursive: true).catchError((_) => dir);
    }
  }
}
