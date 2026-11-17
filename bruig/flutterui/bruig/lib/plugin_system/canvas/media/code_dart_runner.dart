import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_eval/flutter_eval.dart';

// code_dart_runner.dart runs Dart in the app with dart_eval, an interpreter
// written in Dart: nothing to install. A program runs in an isolate of its
// own, what it prints caught, and is stopped if it runs too long. A Flutter
// app is compiled with flutter_eval and its widget built and drawn off the
// screen for a picture -- the real widgets, so the picture is the app.

/// _package is the package a project's files are compiled as.
const _package = "lesson";

Map<String, String> _dartFiles(CodeElement code) => {
      for (var f in code.files)
        if (f.language == CodeLanguage.dart) f.name: f.text,
    };

/// runDart runs [entry]'s main, the project's other Dart files beside it,
/// for at most [limit].
Future<List<CodeLog>> runDart(CodeElement code, CodeFile entry,
    {Duration limit = const Duration(seconds: 20),
    void Function(CodeLog)? onLog}) async {
  var logs = <CodeLog>[];
  void log(CodeLog l) {
    logs.add(l);
    onLog?.call(l);
  }

  var port = ReceivePort();
  var done = Completer<void>();
  port.listen((m) {
    // Its exit (null) says done too, whether or not it said so first.
    if (m == null) {
      if (!done.isCompleted) done.complete();
      return;
    }
    if (m is List && m.length == 2) {
      var (kind, text) = (m[0] as String, m[1] as String);
      if (kind == "done") {
        if (!done.isCompleted) done.complete();
        return;
      }
      log(CodeLog(text,
          kind: kind == "error" ? CodeLogKind.error : CodeLogKind.log));
    }
  });
  var isolate = await Isolate.spawn(
      _dartMain, (port.sendPort, _dartFiles(code), entry.name),
      errorsAreFatal: true, onExit: port.sendPort);
  // The isolate shares the app's memory: a program that doubles a string
  // for ever could take all of it before the time ran out, and the app with
  // it. Watched, it is stopped once it has taken [memoryLimit] more
  // (security review, 2026-11-17).
  var before = ProcessInfo.currentRss;
  var watch = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (done.isCompleted || ProcessInfo.currentRss - before < dartMemoryLimit) {
      return;
    }
    isolate.kill(priority: Isolate.immediate);
    log(const CodeLog("Stopped: it was taking too much memory.",
        kind: CodeLogKind.error));
    done.complete();
  });
  await done.future.timeout(limit, onTimeout: () {
    isolate.kill(priority: Isolate.immediate);
    log(CodeLog("Stopped after ${limit.inSeconds} seconds.",
        kind: CodeLogKind.error));
  });
  watch.cancel();
  port.close();
  return logs;
}

void _dartMain((SendPort, Map<String, String>, String) a) {
  var (out, files, entry) = a;
  void send(String kind, String text) => out.send([kind, text]);
  runZonedGuarded(() async {
    try {
      var program = Compiler().compile({_package: files});
      var runtime = Runtime.ofProgram(program);
      var r = runtime.executeLib("package:$_package/$entry", "main");
      if (r is Future) await r;
    } catch (e) {
      send("error", _plain(e));
    }
    send("done", "");
  }, (e, _) {
    send("error", _plain(e));
    send("done", "");
  }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
    send("log", line);
  }));
}

/// _plain is an error as a learner should read it: without the
/// interpreter's own frames.
String _plain(Object e) {
  var s = e.toString();
  var cut = s.indexOf("\nRUNTIME STATE");
  if (cut > 0) s = s.substring(0, cut);
  return s.replaceFirst(RegExp(r"^(CompileError|Exception): "), "").trim();
}

/// dartMemoryLimit is the most memory a Dart program may take on top of
/// the app's before it is stopped.
const dartMemoryLimit = 1024 * 1024 * 1024;

/// _previewName is the function added to a Flutter app's main file that
/// gives back the widget its main runs.
const _previewName = r"$$previewApp";

/// flutterPreviewSource is [main] with what runApp is given handed back by
/// a function of its own instead, as flutter_eval runs functions, not
/// apps: runApp(X) becomes $$previewApp, and X what it returns.
String? flutterPreviewSource(String main) {
  var at = main.indexOf(RegExp(r"\brunApp\s*\("));
  if (at < 0) return null;
  var open = main.indexOf("(", at);
  var depth = 0;
  for (var i = open; i < main.length; i++) {
    var c = main[i];
    if (c == "(") depth++;
    if (c == ")" && --depth == 0) {
      var widget = main.substring(open + 1, i).trim();
      if (widget.endsWith(",")) {
        widget = widget.substring(0, widget.length - 1);
      }
      // runApp itself is not bound, so it is one of ours that does
      // nothing (main is never run).
      var body = main.replaceRange(at, open, r"$$noRunApp");
      return "$body\n\nvoid \$\$noRunApp(Widget app) {}\n"
          "Widget $_previewName() => $widget;\n";
    }
  }
  return null;
}

/// flutterOpLimit is the most steps one call into a Flutter app may take --
/// its main, one widget's build, one button's press -- before it is
/// stopped: about a second of work, far more than any lesson's app needs.
const flutterOpLimit = 50000000;

/// FlutterBuild is a Flutter app compiled: its widget, or what stopped it.
class FlutterBuild {
  final Widget? widget;
  final String? error;
  const FlutterBuild({this.widget, this.error});
}

/// buildFlutterApp compiles [entry] (a Flutter app) and the project's other
/// Dart files, and builds the widget its main would run.
FlutterBuild buildFlutterApp(CodeElement code, CodeFile entry) {
  // A lesson's app without Flutter's "DEBUG" ribbon across its corner,
  // which a debug build of this app would otherwise put on it.
  WidgetsApp.debugAllowBannerOverride = false;
  var src = flutterPreviewSource(entry.text);
  if (src == null) {
    return const FlutterBuild(
        error: "No runApp(...) in main: nothing to show.");
  }
  try {
    var files = {..._dartFiles(code), entry.name: src};
    var compiler = Compiler()..addPlugin(flutterEvalPlugin);
    var program = compiler.compile({_package: files});
    var runtime = Runtime.ofProgram(program)
      ..addPlugin(flutterEvalPlugin)
      // Built on the app's own isolate, in its frames: a loop that never
      // ends stops here, not the app (security review, 2026-11-17).
      ..opLimit = flutterOpLimit;
    var w = runtime.executeLib("package:$_package/${entry.name}", _previewName);
    var widget = w is $Value ? w.$value : w;
    if (widget is! Widget) {
      return const FlutterBuild(error: "The app gave no widget to show.");
    }
    return FlutterBuild(widget: widget);
  } catch (e) {
    return FlutterBuild(error: _plain(e));
  }
}

/// pictureOfWidget draws [widget] off the screen at [size] (logical
/// pixels, at [ratio] to the screen's) and gives back its picture as PNG.
Future<List<int>?> pictureOfWidget(Widget widget, ui.Size size,
    {double ratio = 2}) async {
  var view = WidgetsBinding.instance.platformDispatcher.views.first;
  var boundary = RenderRepaintBoundary();
  var renderView = RenderView(
    view: view,
    child: RenderPositionedBox(child: boundary),
    configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size * ratio),
        devicePixelRatio: ratio),
  );
  var pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  // The app's own: a GlobalKey (ListTile's ink has one) is found only in
  // the BuildOwner the app builds with.
  var build = WidgetsBinding.instance.buildOwner!;
  var root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: size, devicePixelRatio: ratio),
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    ),
  ).attachToRenderTree(build);
  // Two frames: the first lays out, the second has anything that waited
  // for a frame (an app bar's title) in place.
  for (var i = 0; i < 2; i++) {
    build.buildScope(root);
    build.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
  }
  try {
    var image = await boundary.toImage(pixelRatio: ratio);
    var data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    // Taken down again, so nothing of it -- its keys, its state -- is left
    // in the app's tree.
    var gone = RenderObjectToWidgetAdapter<RenderBox>(
            container: boundary, child: const SizedBox.shrink())
        .attachToRenderTree(build, root);
    build.buildScope(gone);
    build.finalizeTree();
  }
}
