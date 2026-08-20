import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

class RequestedResource extends ChangeNotifier {
  final String uid;
  final ResourceTag tag;
  RMFetchResource? request;
  RMFetchResourceReply? reply;

  RequestedResource(this.uid, this.tag);
}

final sectionStartRegexp = RegExp(r'--section id=([\w]+) --');
final sectionEndRegexp = RegExp(r'--/section--');

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
      if (_cursor < _history.length - 1) {
        _history.removeRange(_cursor + 1, _history.length);
      }
      _history.add(v);
      _cursor = _history.length - 1;
    }
    _finishLoad();
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
    var utfData = currentPage?.response.data ?? Uint8List(0);
    var data = utf8.decode(utfData);

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

    var data = utf8.decode(currentPage!.response.data!);
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

    var data = utf8.decode(currentPage!.response.data!);
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
            utf8.decode(fr.response.data!) +
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
    var sess = _sessions.remove(id);
    if (sess == null) return;
    if (identical(_mostRecent, sess)) _mostRecent = null;
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
