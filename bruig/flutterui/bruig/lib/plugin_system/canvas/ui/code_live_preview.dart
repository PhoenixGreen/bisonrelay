import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// code_live_preview.dart is a Run panel's preview opened to be used (as the
// prototype's was): the page itself, live in a browser over the panel, or a
// Flutter app's own widgets -- its buttons pressed, what it prints added to
// the output. Shut (a press elsewhere), a picture of it as it was left is
// kept in place of the run's.

class CodeLivePreview extends StatefulWidget {
  final CodeRunner runner;
  final CodeElement code;
  final CodeFile entry;

  /// rect is the preview on the stage, in the stage's pixels.
  final Rect rect;
  final void Function(CodeLog) onLog;

  /// onSnap is given, while it is open, the way to take its picture.
  final void Function(Future<List<int>?> Function()? snap) onSnap;

  const CodeLivePreview({
    required this.runner,
    required this.code,
    required this.entry,
    required this.rect,
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
    if (widget.runner == CodeRunner.web) {
      body = InAppWebView(
        initialData: InAppWebViewInitialData(
            data: webPage(widget.code, widget.entry),
            mimeType: "text/html",
            encoding: "utf-8"),
        initialSettings:
            InAppWebViewSettings(javaScriptEnabled: true, isInspectable: false),
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
      // Laid out at least a phone's width, and fitted to the preview.
      var w = widget.rect.width < 360 ? 360.0 : widget.rect.width;
      var h = widget.rect.height * w / widget.rect.width;
      body = FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: w,
          height: h,
          child: RepaintBoundary(
            key: _app,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(w, h)),
              child: _built!,
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
        child: ClipRect(child: body),
      ),
    );
  }
}
