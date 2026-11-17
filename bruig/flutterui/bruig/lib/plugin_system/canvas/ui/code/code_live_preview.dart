import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/media/code_run_host.dart';
import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// code_live_preview.dart is a Run panel's preview opened to be used: the
// page live in a browser over the panel, or a Flutter app's own widgets,
// what it prints added to the output. Shut by a press elsewhere, it leaves
// a picture of itself as it was in place of the run's.

class CodeLivePreview extends StatefulWidget {
  final CodeRunner runner;
  final CodeElement code;
  final CodeFile entry;

  /// rect is the preview on the stage, in the stage's pixels.
  final Rect rect;

  /// appSize is the size a Flutter app is laid out at before it is fitted to
  /// [rect]: the Run panel's, as the run's picture was, not the stage's
  /// pixels, which change with the zoom.
  final Size appSize;
  final void Function(CodeLog) onLog;

  /// onSnap is given, while it is open, the way to take its picture.
  final void Function(Future<List<int>?> Function()? snap) onSnap;

  const CodeLivePreview({
    required this.runner,
    required this.code,
    required this.entry,
    required this.rect,
    required this.appSize,
    required this.onLog,
    required this.onSnap,
    super.key,
  });

  @override
  State<CodeLivePreview> createState() => _CodeLivePreviewState();
}

class _CodeLivePreviewState extends State<CodeLivePreview> {
  InAppWebViewController? _web;
  final GlobalKey _app = GlobalKey();
  Widget? _built;
  String? _error;

  /// _touched is whether it has been pressed: shut untouched, it is as its
  /// run left it, and no new picture is kept (no change to undo).
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.runner == CodeRunner.flutter) {
      var b = buildFlutterApp(widget.code, widget.entry);
      _built = b.widget;
      _error = b.error;
      if (_error != null) {
        widget.onLog(CodeLog(_error!, kind: CodeLogKind.error));
      }
    }
    widget.onSnap(_snap);
  }

  @override
  void dispose() {
    widget.onSnap(null);
    super.dispose();
  }

  Future<List<int>?> _snap() async {
    if (!_touched) return null;
    if (_web case var web?) {
      return web.takeScreenshot(
          screenshotConfiguration:
              ScreenshotConfiguration(compressFormat: CompressFormat.PNG));
    }
    var boundary =
        _app.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    var image = await boundary.toImage(pixelRatio: 2);
    var data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (widget.runner == CodeRunner.web &&
        InAppWebViewPlatform.instance == null) {
      // No browser here (a test, or a system without one): said, not an
      // error.
      body = const ColoredBox(
          color: Color(0xFF15191E),
          child: Center(
              child: Text("The page can't be shown live here.",
                  style: TextStyle(color: Color(0xFF8A93A0)))));
    } else if (widget.runner == CodeRunner.web) {
      body = InAppWebView(
        initialData: InAppWebViewInitialData(
            data: sealed(webPage(widget.code, widget.entry)),
            mimeType: "text/html",
            encoding: "utf-8"),
        initialSettings: sealedSettings(),
        shouldOverrideUrlLoading: (c, action) => stayOnPage(action),
        onWebViewCreated: (c) {
          _web = c;
          c.addJavaScriptHandler(
              handlerName: "codeConsole",
              callback: (args) {
                var kind = args.isNotEmpty ? "${args[0]}" : "log";
                widget.onLog(CodeLog(args.length > 1 ? "${args[1]}" : "",
                    kind: switch (kind) {
                      "error" => CodeLogKind.error,
                      "warn" => CodeLogKind.warn,
                      _ => CodeLogKind.log,
                    }));
                return null;
              });
        },
      );
    } else if (_built != null) {
      // Laid out as the run's picture was, and fitted to the preview.
      var w = widget.appSize.width, h = widget.appSize.height;
      body = FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: w,
          height: h,
          child: RepaintBoundary(
            key: _app,
            child: MediaQuery(
              // Not the app's text size: the run's picture is drawn
              // without it.
              data: MediaQuery.of(context)
                  .copyWith(size: Size(w, h), textScaler: TextScaler.noScaling),
              child: ownNavigator(_built!),
            ),
          ),
        ),
      );
    } else {
      body = ColoredBox(
          color: const Color(0xFF15191E),
          child: Center(
              child: Text(_error ?? "",
                  style: const TextStyle(color: Color(0xFFFF8A8A)))));
    }
    return Positioned.fromRect(
      rect: widget.rect,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2ED6A1), width: 2)),
        child: Listener(
            onPointerDown: (_) => _touched = true,
            child: ClipRect(child: body)),
      ),
    );
  }
}

/// ownNavigator gives a lesson's app a navigator of its own. Built inside
/// the app's tree, Navigator.of would otherwise find the app's, and a page
/// pushed there would cover the whole app and outlive the preview.
Widget ownNavigator(Widget app) => HeroControllerScope.none(
      child: Navigator(
        onGenerateInitialRoutes: (_, __) => [
          PageRouteBuilder<void>(
              pageBuilder: (_, __, ___) => app,
              transitionDuration: Duration.zero),
        ],
      ),
    );
