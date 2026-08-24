import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

final sectionStartRegexp = RegExp(r'--section id=([\w]+) --');
final sectionEndRegexp = RegExp(r'--/section--');

/// includeRegexp matches a reference to a shared fragment of a site --
/// --include[navigation]-- and the like. Must match the Go side's, in
/// client/resources/pages.go.
///
/// Deliberately not Go's {{...}}, which a store's templates already use.
/// Those are expanded before anything is sent; these are the opposite --
/// they survive being sent and are filled in here, out of fragments this
/// client has already been given, so a navigation bar shared by twenty
/// pages crosses the wire once instead of twenty times.
final includeRegexp = RegExp(r'--include\[([\w-]{1,64})\]--');

/// maxPartialsPerPage is how many fragments one page may pull in.
///
/// Kept in step with resources.MaxPartialsPerPage, which is what the serving
/// side applies. Only the preview reads this now, and its files are on this
/// machine -- but a preview that showed more than a reader will ever see
/// would be a preview of a different page.
const int maxPartialsPerPage = 32;

/// partialNames returns the fragments a page refers to, without repeats and
/// no more than [maxPartialsPerPage] of them.
List<String> partialNames(String page) {
  var seen = <String>{};
  for (var m in includeRegexp.allMatches(page)) {
    seen.add(m.group(1)!);
    if (seen.length >= maxPartialsPerPage) break;
  }
  return seen.toList();
}

/// partialPath is where a fragment lives, as a request path.
List<String> partialPath(String name) => ["fragments", "$name.md"];

/// maxPartialDepth is how far a fragment may reach through others.
///
/// A header holding a navigation bar is two. Much beyond that and the page
/// being read is assembled from more pieces than anybody is keeping track
/// of, and each level costs another pass over the text.
const int maxPartialDepth = 8;

/// expandPartials fills in --include[name]-- from what is held, including
/// fragments that refer to other fragments.
///
/// Only the Writing preview needs this now. A page fetched from a site
/// arrives with its fragments already in it -- see resources.PagesResource --
/// but a page being written is a document on this machine with the markers
/// still in it, and a preview showing those as themselves would be showing
/// something no reader will ever see.
///
/// [active] is what is being expanded right now, which is what stops a cycle:
/// a header including itself, or two fragments including each other, would
/// otherwise never finish. A marker that would loop is left as written --
/// visible, which is what tells the writer they have made one.
String expandPartials(String text, Map<String, String> partials,
    {Set<String>? active, int depth = 0}) {
  if (depth >= maxPartialDepth) return text;
  active ??= <String>{};

  return text.splitMapJoin(
    includeRegexp,
    onMatch: (m) {
      var name = m.group(1)!;
      if (active!.contains(name)) return m[0]!;
      var body = partials[name];
      // Not arrived yet, or not there at all. Shown as nothing rather than
      // as the raw marker, which reads as something the writer typed wrong.
      if (body == null) return "";
      active.add(name);
      var out =
          expandPartials(body, partials, active: active, depth: depth + 1);
      active.remove(name);
      return out;
    },
    onNonMatch: (t) => t,
  );
}

/// decodePage reads a reply's bytes as text.
///
/// Lenient on purpose. A page is markdown and should decode cleanly, but a
/// reply is whatever the other end sent -- and something that is not text at
/// all used to take the whole viewer down with a FormatException rather than
/// showing a page that looks wrong. Losing a character beats losing the
/// screen, and the malformed run is visible.
String decodePage(Uint8List? data) =>
    data == null ? "" : utf8.decode(data, allowMalformed: true);

// pageFetchTimeout is how long a page request waits before the session
// reports that nothing came back.
//
// A request is delivered through the send queue, so it stays queued until the
// other side is reachable and there is no failure to observe. Without a
// deadline here, a request to someone who is offline -- or who simply runs a
// version that drops requests it cannot serve -- leaves the page view saying
// "Loading page..." for as long as it is open.
//
// Expiring the wait does not cancel the request: a reply arriving afterwards
// still lands, and replaces the message.
const pageFetchTimeout = Duration(seconds: 45);

class PagesSession extends ChangeNotifier {
  final int id;
  PagesSession(this.id);

  // History is the pages this session has visited, and where in them the
  // reader is. Entries hold the fetched page itself, so stepping back is
  // immediate and costs nothing -- a request is a message each way, and
  // re-fetching a page the session already has would be paying twice to see
  // what is already in hand.
  final List<FetchedResource> _history = [];
  int _cursor = -1;

  // What the outstanding request is for. Held so the viewer can say where it
  // is going before anything has come back -- on a first fetch there is no
  // page yet, so this is the only record of who is being asked.
  String _pendingUid = "";
  List<String> _pendingPath = const [];
  String get pendingUid => _pendingUid;
  List<String> get pendingPath => _pendingPath;

  void setPending(String uid, List<String> path) {
    _pendingUid = uid;
    _pendingPath = path;
  }

  List<FetchedResource> get history => List.unmodifiable(_history);
  int get historyCursor => _cursor;

  bool get canGoBack => _cursor > 0;
  bool get canGoForward => _cursor >= 0 && _cursor < _history.length - 1;

  FetchedResource? _current;
  FetchedResource? get currentPage => _current;

  /// Setting currentPage is a navigation: it truncates anything ahead in the
  /// history and appends. Use [replaceCurrentPage] to update the page in
  /// place instead.
  set currentPage(FetchedResource? v) {
    _current = v;
    if (v != null) {
      // The same page arriving again is the same page, not a second visit
      // to it. Appending it left Back moving from a page to itself, which
      // looks exactly like Back not working -- one press did nothing you
      // could see and the next did the move. A page can arrive twice
      // running for several reasons: reloading it, previewing it again, or
      // a reply for one of its sections landing when the page itself is no
      // longer held.
      if (_cursor >= 0 && _cursor < _history.length && _sameVisit(v)) {
        _history[_cursor] = v;
        _finishLoad();
        return;
      }
      if (_cursor < _history.length - 1) {
        _history.removeRange(_cursor + 1, _history.length);
      }
      _history.add(v);
      _cursor = _history.length - 1;
    }
    _finishLoad();
  }

  /// _sameVisit is whether [v] is the page already being shown.
  ///
  /// Who is serving it and what was asked for, which is all a request is
  /// when it carries no data. One that carries data is a form being
  /// submitted, and two submissions of the same form are two different
  /// things happening however alike they look -- the same reasoning as
  /// findInHistory, and it has to be the same or the two disagree about
  /// what counts as the same page.
  bool _sameVisit(FetchedResource v) {
    var at = _history[_cursor];
    if (at.request.data != null || v.request.data != null) return false;
    return at.uid == v.uid &&
        at.request.path.join("/") == v.request.path.join("/");
  }

  /// replaceCurrentPage swaps the page being shown without touching history.
  /// It is how a page whose async sections have filled in is redrawn.
  void replaceCurrentPage(FetchedResource v) {
    _current = v;
    if (_cursor >= 0 && _cursor < _history.length) {
      _history[_cursor] = v;
    }
    _finishLoad();
  }

  /// redraw tells the viewer to rebuild without changing what is shown --
  /// a fragment arriving fills part of the page already on screen.
  void redraw() => notifyListeners();

  void _finishLoad() {
    _loading = false;
    _timedOut = false;
    _timeout?.cancel();
    _timeout = null;
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    _cursor--;
    _current = _history[_cursor];
    _finishLoad();
  }

  /// findInHistory returns where a page already sits in this session's
  /// history, or null.
  ///
  /// Keyed on who is serving it and what was asked for, which is all a
  /// request is when it carries no data. A request that carries data is a
  /// form being submitted and is never a match: two submissions of the same
  /// form are two different things happening, however alike they look.
  int? findInHistory(String uid, List<String> path) {
    var wanted = path.join("/");
    for (var i = _history.length - 1; i >= 0; i--) {
      var fr = _history[i];
      if (fr.uid == uid && fr.request.path.join("/") == wanted) return i;
    }
    return null;
  }

  /// jumpTo moves the reader to a page the session already holds.
  void jumpTo(int index) {
    if (index < 0 || index >= _history.length) return;
    _cursor = index;
    _current = _history[index];
    _finishLoad();
  }

  void goForward() {
    if (!canGoForward) return;
    _cursor++;
    _current = _history[_cursor];
    _finishLoad();
  }

  bool _loading = false;
  bool get loading => _loading;

  Timer? _timeout;

  bool _timedOut = false;

  /// timedOut is true when a request has been outstanding for longer than
  /// [pageFetchTimeout] with no reply.
  bool get timedOut => _timedOut;

  void _setLoading(bool v) {
    _loading = v;
    _timedOut = false;
    _timeout?.cancel();
    _timeout = v
        ? Timer(pageFetchTimeout, () {
            if (!_loading) return;
            _loading = false;
            _timedOut = true;
            notifyListeners();
          })
        : null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  String pageData() {
    var data = decodePage(currentPage?.response.data);

    // Remove --section-- strings (these are handled internally, not at the
    // markdown rendering level.
    data = data.replaceAll(sectionStartRegexp, "");
    data = data.replaceAll(sectionEndRegexp, "");
    data += "\n";

    return data;
  }

  void replaceAsyncTargetWithLoading(String asyncTargetID) {
    if (currentPage?.response.data == null) {
      return;
    }

    var data = decodePage(currentPage!.response.data);
    try {
      var reStartPattern = r'--section id=' + asyncTargetID + r' --\n';
      var reStart = RegExp(reStartPattern);
      var startPos = reStart.firstMatch(data);
      if (startPos == null) {
        // Did not find the target location.
        return;
      }

      var endPos = sectionEndRegexp.firstMatch(data.substring(startPos.end));
      if (endPos == null) {
        // Unterminated section.
        return;
      }

      var endPosStart =
          endPos.start + startPos.end; // Convert to absolute index

      // Create the new buffer, replacing the contents inside the section with
      // the new data.
      data =
          "${data.substring(0, startPos.end)}(⏳ Loading response)\n${data.substring(endPosStart)}";
    } catch (exception) {
      // Ignore any errors when trying to replace this target.
      debugPrint(
          "Unable to set target $asyncTargetID in page as loading: $exception");
    }

    var utfData = utf8.encode(data);
    replaceCurrentPage(currentPage!
        .copyWith(response: currentPage!.response.copyWith(data: utfData)));
  }

  void replaceAsyncTargets(List<FetchedResource> history) {
    if (currentPage?.response.data == null) {
      return;
    }

    var data = decodePage(currentPage!.response.data);
    for (var fr in history) {
      try {
        if (fr.response.data == null) {
          continue;
        }

        var reStartPattern = r'--section id=' + fr.asyncTargetID + r' --\n';
        var reStart = RegExp(reStartPattern);
        var startPos = reStart.firstMatch(data);
        if (startPos == null) {
          // Did not find the target location.
          continue;
        }

        var endPos = sectionEndRegexp.firstMatch(data.substring(startPos.end));
        if (endPos == null) {
          // Unterminated section.
          continue;
        }

        var endPosStart =
            endPos.start + startPos.end; // Convert to absolute index

        // Create the new buffer, replacing the contents inside the section with
        // the new data.
        data = data.substring(0, startPos.end) +
            decodePage(fr.response.data) +
            data.substring(endPosStart);
      } catch (exception) {
        // Ignore any errors when trying to replace this target.
        debugPrint(
            "Unable to replace target ${fr.asyncTargetID} in page: $exception");
      }
    }

    var utfData = utf8.encode(data);
    replaceCurrentPage(currentPage!
        .copyWith(response: currentPage!.response.copyWith(data: utfData)));
  }
}

/// _assetTarget marks a reply as a picture a page shows rather than a page.
const String _assetTarget = "asset:";

/// maxAssetsPerSite is how many pictures are kept for one site.
///
/// Pictures are the largest thing a site sends, so this is a memory bound
/// rather than a message one -- what is held has already been paid for. A
/// site with more pictures than this in one session refetches the oldest,
/// which costs a message and is better than holding everything for ever.
const int maxAssetsPerSite = 48;

class ResourcesModel extends ChangeNotifier {
  /// [runStream] is false in tests, which have no golib to listen to.
  /// Everything else about the model works without it -- the stream only
  /// feeds replies in.
  ResourcesModel({bool runStream = true}) {
    if (runStream) _handleFetchedResources();
  }

  final Map<int, PagesSession> _sessions = {};
  PagesSession session(int id) {
    if (!_sessions.containsKey(id)) {
      var sess = PagesSession(id);
      _sessions[id] = sess;
      notifyListeners();
    }
    return _sessions[id]!;
  }

  List<PagesSession> get sessions => _sessions.values.toList(growable: false);

  /// closeSession forgets an open page.
  ///
  /// The session's history goes with it: keeping it would mean a closed page
  /// still holding every page it visited, and "close" would not mean what it
  /// says. The pages themselves are still in the client's own store, so
  /// nothing is lost that a fresh request would not find again.
  void closeSession(int id) {
    var order = _sessions.keys.toList();
    var at = order.indexOf(id);
    if (at < 0) return;

    var sess = _sessions.remove(id)!;
    if (identical(_mostRecent, sess)) {
      // Move to the neighbour on the right, or on the left when the one
      // closed was the last. Removing at [at] shifts the right-hand
      // neighbour down into that index, so it is the same subscript both
      // times; clamping is what turns it into the left-hand one at the end.
      var left = _sessions.values.toList();
      _mostRecent = left.isEmpty ? null : left[at.clamp(0, left.length - 1)];
    }
    sess.dispose();
    notifyListeners();
  }

  PagesSession? _mostRecent;
  PagesSession? get mostRecent => _mostRecent;
  set mostRecent(PagesSession? v) {
    if (_mostRecent != v) {
      _mostRecent = v;
      notifyListeners();
    }
  }

  /// fetchPage asks for a page, or shows one the session already has.
  ///
  /// A page already in this session's history is shown from it rather than
  /// asked for again. A request is a message each way, so following a link
  /// back to somewhere already visited would be paying a second time for
  /// what is already in hand -- and it is the same page the Back button
  /// would have shown, reached a different way.
  ///
  /// [reload] is how to insist on asking anyway, which is what the browser's
  /// reload button does. There is no way to tell whether a page has changed
  /// since it was fetched: the protocol carries no validator, so the choice
  /// is between showing what we have and paying to find out.
  Future<PagesSession> fetchPage(String uid, List<String> path, int sessionID,
      int parentPage, dynamic data, String asyncTargetID,
      {bool reload = false}) async {
    // Only a plain request for a page. Submitting a form, or filling in a
    // section of one, is an exchange rather than a fetch.
    if (!reload && data == null && asyncTargetID == "" && sessionID != 0) {
      var sess = _sessions[sessionID];
      var at = sess?.findInHistory(uid, path);
      if (sess != null && at != null) {
        sess.jumpTo(at);
        return sess;
      }
    }

    sessionID = await Golib.fetchResource(
        uid, path, null, sessionID, parentPage, data, asyncTargetID);

    var sess = session(sessionID);
    if (asyncTargetID == "") {
      sess.setPending(uid, path);
      sess._setLoading(true);
    } else {
      sess.replaceAsyncTargetWithLoading(asyncTargetID);
    }
    return sess;
  }

  // _assets are the pictures held for each site, by path.
  //
  // A picture is a file of its own and is asked for on its own, so a banner
  // behind every page of a site is fetched once and shown on all of them.
  // Never sent with the page that shows it: the page arrives and draws while
  // its pictures are still on their way.
  final Map<String, Map<String, Uint8List>> _assets = {};

  /// assetFor is the picture held at [path] for [uid], or null if it has not
  /// arrived. Asking for one that is missing starts fetching it.
  Uint8List? assetFor(String uid, String path, {PagesSession? session}) {
    var held = _assets[uid];
    var got = held?[path];
    if (got != null) return got.isEmpty ? null : got;
    if (held != null && held.containsKey(path)) {
      // Asked for already, still on its way.
      return null;
    }
    _requestAsset(uid, path, session);
    return null;
  }

  void _requestAsset(String uid, String path, PagesSession? session) {
    var held = _assets[uid] ??= {};
    if (held.length >= maxAssetsPerSite) {
      // Oldest first, which for a map is insertion order.
      held.remove(held.keys.first);
    }
    // Marked as asked before the reply arrives, so a page drawn twice while
    // it is in flight does not ask twice.
    held[path] = Uint8List(0);

    var segments = path.split("/").where((p) => p.isNotEmpty).toList();
    Golib.fetchResource(uid, segments, null, session?.id ?? 0,
            session?.currentPage?.pageID ?? 0, null, "$_assetTarget$path")
        .catchError((exception) {
      debugPrint("Unable to fetch picture $path: $exception");
      return 0;
    });
  }

  /// forgetSite drops what is held for one site.
  ///
  /// Called when this client publishes: fragments are kept for the whole run
  /// -- the part of a site least likely to change -- which is right for
  /// somebody else's site and wrong for your own the moment you edit it. A
  /// header rewritten and republished went on showing the old one until the
  /// app was restarted.
  void forgetSite(String uid) {
    _assets.remove(uid);
    notifyListeners();
  }

  // _fetchListeners are told about every reply that arrives, whichever
  // session it belongs to. PagesModel uses this to learn what a contact
  // answered without having to own the fetch itself.
  final List<void Function(FetchedResource)> _fetchListeners = [];

  void addFetchListener(void Function(FetchedResource) f) =>
      _fetchListeners.add(f);
  void removeFetchListener(void Function(FetchedResource) f) =>
      _fetchListeners.remove(f);

  void _handleFetchedResources() async {
    var stream = Golib.fetchedResources();
    await for (var fr in stream) {
      // A picture, not a page: kept for the site it came from and drawn
      // wherever it is shown, without disturbing the history.
      if (fr.asyncTargetID.startsWith(_assetTarget)) {
        var path = fr.asyncTargetID.substring(_assetTarget.length);
        if (fr.response.status == 200 && fr.response.data != null) {
          (_assets[fr.uid] ??= {})[path] = fr.response.data!;
        } else {
          // Said out loud, because the alternative is a picture that is
          // simply not there. The path stays marked as asked -- retrying on
          // every rebuild would be a request per frame -- so without this
          // line a picture that did not arrive leaves nothing at all to go
          // on: no error, no retry, and a page that looks like the markup
          // was wrong.
          debugPrint("Picture $path from ${fr.uid} came back "
              "${fr.response.status}; it will not be asked for again until "
              "this site is opened afresh");
        }
        // Notified either way: a picture that is not there should stop
        // whatever is waiting for it from waiting.
        notifyListeners();
        continue;
      }

      for (var l in List.of(_fetchListeners)) {
        l(fr);
      }

      var sess = session(fr.sessionID);

      if (fr.asyncTargetID != "") {
        List<FetchedResource> targets;
        if (sess.currentPage == null) {
          // Received async response without having full page, load page and
          // prior history.
          try {
            var history = await Golib.loadFetchedResource(
                fr.uid, fr.sessionID, fr.pageID);
            sess.currentPage = history[0];
            targets = history.sublist(1);
          } catch (exception) {
            debugPrint("Exception handling fetched resource: $exception");
            continue;
          }
        } else {
          targets = [fr];
        }

        // Replace the async target contents.
        sess.replaceAsyncTargets(targets);
      } else {
        // Full page reload.
        sess.currentPage = fr;
      }
    }
  }
}
