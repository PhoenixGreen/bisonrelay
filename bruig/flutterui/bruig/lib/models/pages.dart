import 'dart:async';

import 'package:bruig/config.dart';
import 'package:bruig/models/resources.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

/// SiteStatus is what is known about whether a contact serves pages.
///
/// Bison Relay has no presence: there is no way to ask whether someone is
/// online, and adding one would leak exactly the metadata the protocol is
/// built to avoid. So every value here is the record of an answer that did or
/// did not arrive, never a claim about the other side's state right now.
enum SiteStatus {
  /// Never asked.
  unknown,

  /// Asked, still waiting.
  checking,

  /// Answered with a page.
  hosting,

  /// Answered, but has nothing at the front page. They host something --
  /// a store's paths, or pages under other names.
  noIndex,

  /// Answered that they serve nothing at all.
  notHosting,

  /// Answered with some other status.
  failed,

  /// Nothing came back before the deadline. Says nothing about whether they
  /// host a site: the request is still queued for whenever they reconnect.
  noAnswer,
}

extension SiteStatusLabel on SiteStatus {
  String get label {
    switch (this) {
      case SiteStatus.unknown:
        return "Not checked";
      case SiteStatus.checking:
        return "Checking…";
      case SiteStatus.hosting:
        return "Has a site";
      case SiteStatus.noIndex:
        return "No front page";
      case SiteStatus.notHosting:
        return "No site";
      case SiteStatus.failed:
        return "Error";
      case SiteStatus.noAnswer:
        return "No answer yet";
    }
  }

  /// visitable is whether opening this contact's site is worth offering.
  /// Everything but a definite "serves nothing" is, because an unanswered
  /// request may still be delivered.
  bool get visitable => this != SiteStatus.notHosting;
}

/// SiteInfo is what is known about one contact's site.
@immutable
class SiteInfo {
  final SiteStatus status;

  /// checkedAt is when the answer recorded here arrived, or when the check
  /// that is still outstanding was sent.
  final DateTime? checkedAt;

  /// lastSeen is the last time anything at all was decrypted from this
  /// contact -- the closest thing to liveness that exists here. It comes from
  /// the ratchet, not from any page request, so it is meaningful even for a
  /// contact whose site has never been checked.
  final DateTime? lastSeen;

  const SiteInfo({
    this.status = SiteStatus.unknown,
    this.checkedAt,
    this.lastSeen,
  });

  SiteInfo copyWith({
    SiteStatus? status,
    DateTime? checkedAt,
    DateTime? lastSeen,
  }) =>
      SiteInfo(
        status: status ?? this.status,
        checkedAt: checkedAt ?? this.checkedAt,
        lastSeen: lastSeen ?? this.lastSeen,
      );
}

/// siteStatusForReply maps a reply's status code onto what it tells the
/// visitor. Split out from the model so it can be tested without a client.
SiteStatus siteStatusForReply(int status) {
  switch (status) {
    case 200:
      return SiteStatus.hosting;
    case 404:
      return SiteStatus.noIndex;
    case 501:
      return SiteStatus.notHosting;
    default:
      return SiteStatus.failed;
  }
}

/// PagesModel holds the Pages section's own state: which tab is open, what
/// this client hosts, and what is known about other people's sites.
///
/// Out here rather than in the screen for the same reason
/// [ManageContentNavModel] is: every screen is rebuilt from scratch by its
/// route, so anything kept in State is lost by stepping over to Chat and
/// back -- and a site check that has to be redone on every visit is a
/// message paid for twice.
class PagesModel extends ChangeNotifier {
  final ResourcesModel resources;

  PagesModel(this.resources) {
    resources.addFetchListener(_onFetched);
  }

  @override
  void dispose() {
    resources.removeFetchListener(_onFetched);
    for (var t in _timeouts.values) {
      t.cancel();
    }
    super.dispose();
  }

  // ---- navigation ----

  int _tab = 0;
  int get tab => _tab;
  set tab(int v) {
    if (_tab == v) return;
    _tab = v;
    notifyListeners();
  }

  // ---- what other people host ----

  final Map<String, SiteInfo> _sites = {};
  final Map<String, Timer> _timeouts = {};

  SiteInfo siteInfo(String uid) => _sites[uid] ?? const SiteInfo();

  void _setSite(String uid, SiteInfo info) {
    _sites[uid] = info;
    notifyListeners();
  }

  /// lastSeen reads the ratchet's last-decrypt time for a contact and
  /// remembers it. Failure is silent and leaves the field null: a contact
  /// whose ratchet cannot be read simply has no last-seen to show.
  Future<void> refreshLastSeen(String uid) async {
    try {
      var info = await Golib.userRatchetInfo(uid);
      var t = info.lastDecTime;
      if (t.millisecondsSinceEpoch == 0) return;
      _setSite(uid, siteInfo(uid).copyWith(lastSeen: t));
    } catch (_) {
      // No ratchet info for this contact; nothing to show.
    }
  }

  /// check asks a contact for their front page, purely to find out whether
  /// they have one.
  ///
  /// This costs one message each way, so it is never done for the whole
  /// contact list at once -- [SiteStatus.unknown] is an honest thing to show,
  /// and checking is the visitor's decision.
  Future<void> check(String uid) async {
    if (siteInfo(uid).status == SiteStatus.checking) return;

    _setSite(uid,
        siteInfo(uid).copyWith(status: SiteStatus.checking, checkedAt: DateTime.now()));
    unawaited(refreshLastSeen(uid));

    try {
      await resources.fetchPage(uid, ["index.md"], 0, 0, null, "");
    } catch (exception) {
      _timeouts.remove(uid)?.cancel();
      _setSite(uid, siteInfo(uid).copyWith(status: SiteStatus.failed));
      return;
    }

    _timeouts[uid]?.cancel();
    _timeouts[uid] = Timer(pageFetchTimeout, () {
      _timeouts.remove(uid);
      if (siteInfo(uid).status != SiteStatus.checking) return;
      _setSite(uid, siteInfo(uid).copyWith(status: SiteStatus.noAnswer));
    });
  }

  /// _onFetched records what came back. It listens to every reply rather than
  /// only the ones [check] asked for, so ordinary browsing keeps the Visit
  /// list current for free.
  void _onFetched(FetchedResource fr) {
    _timeouts.remove(fr.uid)?.cancel();
    _setSite(
        fr.uid,
        siteInfo(fr.uid).copyWith(
          status: siteStatusForReply(fr.response.status),
          checkedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ));
  }

  // ---- what this client hosts ----

  PagesHostStatus? _host;
  PagesHostStatus? get host => _host;

  PagesHostConfig get hostConfig => _host?.config ?? PagesHostConfig.off();
  List<LocalPage> get localPages => _host?.pages ?? const [];

  /// hostEditable is false when hosting is delegated to an http upstream or
  /// to a client over the RPC interface. The app is not the thing serving in
  /// those modes, so it does not offer to change them.
  bool get hostEditable => _host?.editable ?? true;

  String? _hostError;
  String? get hostError => _hostError;

  bool _loadingHost = false;
  bool get loadingHost => _loadingHost;

  Future<void> loadHost() async {
    _loadingHost = true;
    notifyListeners();
    try {
      _host = await Golib.getPagesHostConfig();
      _hostError = null;
    } catch (exception) {
      _hostError = "$exception";
    } finally {
      _loadingHost = false;
      notifyListeners();
    }
  }

  /// setHost applies a new hosting configuration. It throws on failure so the
  /// caller can surface it, and leaves the last good config in place.
  ///
  /// The change takes effect immediately -- the client swaps what it serves
  /// without restarting -- and is also written back to the config file, or a
  /// site switched on here would stop being served at the next start.
  Future<void> setHost(PagesHostConfig cfg) async {
    _host = await Golib.setPagesHostConfig(cfg);
    _hostError = null;
    notifyListeners();
    await _persistHost(_host!.config);
  }

  /// _persistHost mirrors the running configuration into brclient.conf.
  ///
  /// Failure here is not fatal and not thrown: hosting is already live, and
  /// losing it at the next restart is a smaller problem than refusing the
  /// change that just worked.
  Future<void> _persistHost(PagesHostConfig cfg) async {
    // The single upstream line can only name one thing, so a site with a
    // shop in it is written as a pages upstream plus a storepath -- which is
    // what parseUpstream reads back as "both".
    var upstream = "";
    var storePath = "";
    switch (cfg.mode) {
      case pagesHostModePages:
        upstream = "pages:${cfg.pagesPath}";
        break;
      case pagesHostModeBoth:
        upstream = "pages:${cfg.pagesPath}";
        storePath = cfg.storePath;
        break;
      case pagesHostModeStore:
        upstream = "simplestore:${cfg.storePath}";
        break;
    }

    try {
      await replaceConfig(
        mainConfigFilename,
        resourcesUpstream: upstream,
        simpleStorePath: storePath,
        simpleStorePayType: cfg.storePayType,
        simpleStoreAccount: cfg.storeAccount,
        simpleStoreShipCharge: cfg.storeShipCharge,
      );
    } catch (exception) {
      _hostError = "Hosting is running, but could not be saved to the "
          "config file: $exception";
      notifyListeners();
    }
  }

  Future<void> refreshLocalPages() async {
    var pages = await Golib.listLocalPages();
    var h = _host;
    if (h == null) return;
    _host = PagesHostStatus(
        h.config, h.editable, h.defaultPath, h.defaultStorePath, pages);
    notifyListeners();
  }

  Future<void> savePage(String name, String content) async {
    var pages = await Golib.writeLocalPage(name, content);
    _replacePages(pages);
  }

  Future<void> deletePage(String name) async {
    var pages = await Golib.deleteLocalPage(name);
    _replacePages(pages);
  }

  Future<String> readPage(String name) => Golib.readLocalPage(name);

  void _replacePages(List<LocalPage> pages) {
    var h = _host;
    if (h == null) return;
    _host = PagesHostStatus(
        h.config, h.editable, h.defaultPath, h.defaultStorePath, pages);
    notifyListeners();
  }
}
