import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

// epub_check.dart checks an EPUB before it goes to a store. Apple refuses a
// book that fails EPUBCheck, the W3C's own checker; it is run where it is
// installed (Homebrew's `epubcheck`, which brings the Java it needs), found
// as ffmpeg is. Beside it, a check of our own that needs nothing installed:
// the mistakes in a book's structure EPUBCheck finds first. Ken, 2026-11-19,
// step 5 of the ebook plan.

/// epubcheckHelp is what to tell somebody without EPUBCheck.
const epubcheckHelp =
    "Apple checks every book with EPUBCheck. Install it to check yours "
    "first: \"brew install epubcheck\" on a Mac, then restart.";

const List<String> _candidates = [
  "/opt/homebrew/bin/epubcheck",
  "/usr/local/bin/epubcheck",
  "/usr/bin/epubcheck",
];

String? _found;
bool _looked = false;

/// epubcheckPath is where EPUBCheck is, or null; looked for once.
Future<String?> epubcheckPath() async {
  if (_looked) return _found;
  _looked = true;
  if (Platform.isAndroid || Platform.isIOS) return null;
  try {
    var which = await Process.run(
        Platform.isWindows ? "where" : "which", ["epubcheck"]);
    if (which.exitCode == 0) {
      var first = "${which.stdout}".trim().split("\n").first.trim();
      if (first.isNotEmpty && await File(first).exists()) {
        return _found = first;
      }
    }
  } catch (_) {
    // No `which`: the list below.
  }
  for (var c in _candidates) {
    if (await File(c).exists()) return _found = c;
  }
  return null;
}

/// useEpubcheckForTest fixes epubcheckPath's answer; forgetEpubcheckForTest
/// puts it back.
@visibleForTesting
void useEpubcheckForTest(String? found) {
  _looked = true;
  _found = found;
}

@visibleForTesting
void forgetEpubcheckForTest() {
  _looked = false;
  _found = null;
}

/// EpubCheckReport is what a check found: [errors] would stop a store,
/// [warnings] would not. [byEpubcheck] says EPUBCheck itself ran.
class EpubCheckReport {
  final List<String> errors, warnings;
  final bool byEpubcheck;
  const EpubCheckReport(
      {this.errors = const [],
      this.warnings = const [],
      this.byEpubcheck = false});

  bool get passed => errors.isEmpty;
}

/// checkEpub checks [bytes]: our own structural check always, and EPUBCheck
/// where it is installed (its findings then stand for both).
Future<EpubCheckReport> checkEpub(Uint8List bytes) async {
  var own = selfCheckEpub(bytes);
  var tool = await epubcheckPath();
  if (tool == null) return EpubCheckReport(errors: own);
  var w3c = await _runEpubcheck(tool, bytes);
  if (w3c == null) return EpubCheckReport(errors: own);
  return EpubCheckReport(
      errors: [...own, ...w3c.errors],
      warnings: w3c.warnings,
      byEpubcheck: true);
}

/// _runEpubcheck runs EPUBCheck on [bytes] and reads its JSON report; null
/// where it could not be run.
Future<EpubCheckReport?> _runEpubcheck(String tool, Uint8List bytes) async {
  var work = await Directory.systemTemp.createTemp("bruig-epubcheck");
  try {
    var book = path.join(work.path, "book.epub");
    var report = path.join(work.path, "report.json");
    await File(book).writeAsBytes(bytes);
    await Process.run(tool, [book, "--json", report]);
    var file = File(report);
    if (!await file.exists()) return null;
    return parseEpubcheckJson(await file.readAsString());
  } catch (exception) {
    debugPrint("Unable to run EPUBCheck: $exception");
    return null;
  } finally {
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  }
}

/// parseEpubcheckJson reads EPUBCheck's --json report: each message with
/// where it is, fatal and error ones as errors.
EpubCheckReport? parseEpubcheckJson(String json) {
  Object? data;
  try {
    data = jsonDecode(json);
  } catch (_) {
    return null;
  }
  if (data is! Map) return null;
  var errors = <String>[], warnings = <String>[];
  var messages = data["messages"];
  if (messages is List) {
    for (var m in messages) {
      if (m is! Map) continue;
      var severity = "${m["severity"]}".toUpperCase();
      var where = "";
      if (m["locations"] case List locations when locations.isNotEmpty) {
        var at = locations.first;
        if (at is Map && at["path"] != null) {
          where = " (${at["path"]}"
              "${at["line"] is int && at["line"] > 0 ? ", line ${at["line"]}" : ""})";
        }
      }
      var line = "${m["ID"] ?? ""}: ${m["message"] ?? ""}$where".trim();
      if (severity == "FATAL" || severity == "ERROR") {
        errors.add(line);
      } else if (severity == "WARNING") {
        warnings.add(line);
      }
    }
  }
  return EpubCheckReport(errors: errors, warnings: warnings, byEpubcheck: true);
}

/// selfCheckEpub is what is wrong with [bytes]'s structure, by our own
/// reading, as plain sentences: none for a sound book.
List<String> selfCheckEpub(List<int> bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return ["It is not a zip, so no reader can open it."];
  }
  if (archive.files.isEmpty) {
    return ["It is not a zip of a book, so no reader can open it."];
  }
  var out = <String>[];
  var files = {
    for (var f in archive.files)
      if (f.isFile) f.name: f
  };
  if (archive.files.isEmpty || archive.files.first.name != "mimetype") {
    out.add("The mimetype file is not first.");
  } else {
    var head = utf8.decode(archive.files.first.content as List<int>,
        allowMalformed: true);
    if (head != "application/epub+zip") {
      out.add("The mimetype file does not say application/epub+zip.");
    }
    // Stored, not compressed: readers find its words at a fixed place,
    // straight after its name in the zip's first header (whose method, at
    // bytes 8 and 9, is nought for stored).
    if (bytes.length < 58 ||
        bytes[8] != 0 ||
        bytes[9] != 0 ||
        String.fromCharCodes(bytes.sublist(38, 58)) != "application/epub+zip") {
      out.add("The mimetype file is compressed; it must be stored as is.");
    }
  }
  XmlDocument? parse(String name) {
    var f = files[name];
    if (f == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(f.content as List<int>));
    } catch (e) {
      out.add("$name is not well-formed XML.");
      return null;
    }
  }

  var container = parse("META-INF/container.xml");
  if (container == null) {
    if (!files.containsKey("META-INF/container.xml")) {
      out.add("There is no META-INF/container.xml.");
    }
    return out;
  }
  var opfPath = container.descendants
      .whereType<XmlElement>()
      .where((e) => e.localName == "rootfile")
      .map((e) => e.getAttribute("full-path"))
      .whereType<String>()
      .firstOrNull;
  if (opfPath == null) return [...out, "The container names no package."];
  var opf = parse(opfPath);
  if (opf == null) {
    if (!files.containsKey(opfPath)) {
      out.add("The package $opfPath is missing.");
    }
    return out;
  }
  var dir = path.posix.dirname(opfPath);
  String inBook(String href) => path.posix.normalize(dir == "."
      ? Uri.decodeComponent(href)
      : path.posix.join(dir, Uri.decodeComponent(href)));
  Iterable<XmlElement> all(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.localName == local);

  for (var need in ["identifier", "title", "language"]) {
    if (all(opf, need).every((e) => e.innerText.trim().isEmpty)) {
      out.add("The package has no $need.");
    }
  }
  var ids = <String>{};
  var hasNav = false;
  for (var item in all(opf, "item")) {
    var id = item.getAttribute("id"), href = item.getAttribute("href");
    if (id == null || href == null) {
      out.add("An item in the manifest has no id or href.");
      continue;
    }
    if (!ids.add(id)) out.add("Two items in the manifest are both \"$id\".");
    var file = inBook(href.split("#").first);
    if (!files.containsKey(file)) {
      out.add("$file is listed but not in the book.");
    }
    var props = (item.getAttribute("properties") ?? "").split(" ");
    if (props.contains("nav")) hasNav = true;
    var type = item.getAttribute("media-type") ?? "";
    if (type == "application/xhtml+xml" && files.containsKey(file)) {
      parse(file);
    }
  }
  if (!hasNav) out.add("There is no navigation document (the contents).");
  var spine = all(opf, "itemref").toList();
  if (spine.isEmpty) out.add("The reading order (spine) is empty.");
  for (var ref in spine) {
    var id = ref.getAttribute("idref");
    if (id == null || !ids.contains(id)) {
      out.add("The reading order names \"$id\", which is not in the book.");
    }
  }
  return out;
}
