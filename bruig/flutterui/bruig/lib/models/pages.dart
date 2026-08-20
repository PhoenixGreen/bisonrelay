import 'dart:async';

import 'package:bruig/config.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/storage_manager.dart';
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

  /// Nothing came back before the deadline, and nothing since suggests they
  /// were there to answer. The request stays queued for whenever they
  /// reconnect.
  noAnswer,

  /// Nothing came back, but they have been heard from since the request went
  /// out -- so they were reachable and did not answer. Evidence of no site,
  /// not proof: clients before the not-hosting reply existed simply drop a
  /// request they cannot serve.
  silent,
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
      case SiteStatus.silent:
        return "Probably no site";
    }
  }

  /// visitable is whether opening this contact's site is worth offering.
  /// Everything but a definite "serves nothing" is, because an unanswered
  /// request may still be delivered -- including [silent], which is evidence
  /// rather than an answer.
  bool get visitable => this != SiteStatus.notHosting;

  /// rechecking is whether offering to ask again makes sense.
  bool get rechecking =>
      this == SiteStatus.unknown ||
      this == SiteStatus.noAnswer ||
      this == SiteStatus.silent ||
      this == SiteStatus.failed;
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

/// PagesSort is how the Visit list is ordered.
enum PagesSort {
  /// Contacts who answered with a site first, then whoever was heard from
  /// most recently. The default: the list exists to be revisited, and the
  /// sites known to work are what it is being opened for.
  sitesFirst,

  /// Plain alphabetical, for finding a particular person.
  name,
}

/// siteRank orders statuses by how much of a site is known to be there.
///
/// Deliberately not the enum's declaration order: what matters here is how
/// good a bet opening it is, so an inference of no site sorts below a wait
/// that has told us nothing either way, and only their own answer that they
/// serve nothing sorts last.
int siteRank(SiteStatus s) {
  switch (s) {
    case SiteStatus.hosting:
      return 0;
    case SiteStatus.noIndex:
      return 1;
    case SiteStatus.checking:
      return 2;
    case SiteStatus.unknown:
      return 3;
    case SiteStatus.noAnswer:
      return 4;
    case SiteStatus.failed:
      return 5;
    case SiteStatus.silent:
      return 6;
    case SiteStatus.notHosting:
      return 7;
  }
}

/// sortSites orders a Visit list in place.
///
/// [nick] and [info] are passed in rather than the model reaching for them so
/// this can be tested without a client. Ties break on nick so the order is
/// stable between rebuilds -- two contacts with the same status and no
/// last-seen would otherwise swap places as the list redrew.
void sortSites<T>(
  List<T> items,
  PagesSort mode, {
  required String Function(T) nick,
  required SiteInfo Function(T) info,
}) {
  int byNick(T a, T b) =>
      nick(a).toLowerCase().compareTo(nick(b).toLowerCase());

  if (mode == PagesSort.name) {
    items.sort(byNick);
    return;
  }

  items.sort((a, b) {
    var ra = siteRank(info(a).status), rb = siteRank(info(b).status);
    if (ra != rb) return ra.compareTo(rb);

    // Most recently heard from first. A contact never heard from sorts
    // after every contact who has been -- an unknown last-seen is not the
    // same as a very old one, but it belongs at the same end.
    var la = info(a).lastSeen, lb = info(b).lastSeen;
    if (la != null && lb != null && la != lb) return lb.compareTo(la);
    if (la != null && lb == null) return -1;
    if (la == null && lb != null) return 1;

    return byNick(a, b);
  });
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
    _loadSort();
    _loadSidebar();
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
    // Choosing a tab is asking to look at it, so it also stops the browser
    // covering the content area -- but the page stays open, in the sidebar,
    // rather than being closed on the reader's behalf.
    if (_tab == v && !_browsing) return;
    _tab = v;
    _browsing = false;
    notifyListeners();
  }

  /// sidebarOpen is whether the Pages sidebar is showing.
  ///
  /// The reader's setting for the whole section, not a property of whatever
  /// is on screen. It used to be closed automatically whenever a page was
  /// opened, on the reasoning that a page wants the width -- but that made
  /// the toggle a suggestion rather than a switch: closing the sidebar and
  /// stepping to another page, or back to the contact list, opened it again.
  /// A control that undoes itself is worse than no control.
  ///
  /// Starts open, and stays wherever it was put, across pages and restarts.
  bool _sidebarOpen = true;
  bool get sidebarOpen => _sidebarOpen;
  set sidebarOpen(bool v) {
    if (_sidebarOpen == v) return;
    _sidebarOpen = v;
    StorageManager.saveBool(StorageManager.pagesSidebarOpenKey, v);
    notifyListeners();
  }

  Future<void> _loadSidebar() async {
    var v = await StorageManager.readBool(StorageManager.pagesSidebarOpenKey,
        defaultVal: true);
    if (v == _sidebarOpen) return;
    _sidebarOpen = v;
    notifyListeners();
  }

  /// browsing is whether the content area is showing an open page rather
  /// than the selected tab.
  ///
  /// Separate from "is a page open" because those stopped being the same
  /// thing once pages could stay open behind a tab.
  bool _browsing = false;
  bool get browsing => _browsing;
  set browsing(bool v) {
    if (_browsing == v) return;
    _browsing = v;
    notifyListeners();
  }

  // ---- how the Visit list is ordered ----

  PagesSort _sort = PagesSort.sitesFirst;
  PagesSort get sort => _sort;

  set sort(PagesSort v) {
    if (_sort == v) return;
    _sort = v;
    StorageManager.saveString(StorageManager.pagesSortKey, v.name);
    notifyListeners();
  }

  Future<void> _loadSort() async {
    var saved = await StorageManager.readString(StorageManager.pagesSortKey);
    var found = PagesSort.values.where((v) => v.name == saved);
    if (found.isEmpty) return;
    _sort = found.first;
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

  /// refreshAllLastSeen fills in last-seen for a whole contact list.
  ///
  /// Safe to call on entering the Visit tab: the ratchet is held in memory
  /// on this side, so each of these reads local state and sends nothing.
  /// That is what makes ordering by last-seen worth offering at all -- it
  /// would otherwise only be known for contacts whose site had been asked
  /// for, which is the small minority the ordering is meant to surface.
  Future<void> refreshAllLastSeen(Iterable<String> uids) async {
    await Future.wait(uids.map(refreshLastSeen));
  }

  /// open fetches a contact's front page and records what comes of it.
  ///
  /// Both checking and visiting go through here. They are the same request --
  /// a visit that is never answered is exactly as informative as a check that
  /// is never answered, and routing visits around this is what left a
  /// contact reading "Not checked" after being opened.
  ///
  /// Each call costs a message each way, so nothing calls it for the whole
  /// contact list: [SiteStatus.unknown] is an honest thing to show, and
  /// asking is the visitor's decision.
  Future<PagesSession> open(String uid, {List<String>? path}) async {
    _timeouts.remove(uid)?.cancel();
    _setSite(
        uid,
        siteInfo(uid).copyWith(
            status: SiteStatus.checking, checkedAt: DateTime.now()));

    PagesSession sess;
    try {
      sess = await resources.fetchPage(
          uid, path ?? const ["index.md"], 0, 0, null, "");
    } catch (exception) {
      _setSite(uid, siteInfo(uid).copyWith(status: SiteStatus.failed));
      rethrow;
    }

    _timeouts[uid] = Timer(pageFetchTimeout, () => _onCheckTimeout(uid));
    return sess;
  }

  /// check asks for a contact's front page purely to find out whether they
  /// have one, discarding the page itself.
  Future<void> check(String uid) async {
    if (siteInfo(uid).status == SiteStatus.checking) return;
    try {
      await open(uid);
    } catch (_) {
      // open has already recorded the failure.
    }
  }

  /// _onCheckTimeout decides what an unanswered request means.
  ///
  /// If the contact has been heard from since it went out, they were
  /// reachable and did not answer -- which is evidence they host nothing,
  /// because a client from before the not-hosting reply existed simply drops
  /// a request it cannot serve. If they have not been heard from, the honest
  /// answer is that nothing has come back yet.
  Future<void> _onCheckTimeout(String uid) async {
    _timeouts.remove(uid);
    if (siteInfo(uid).status != SiteStatus.checking) return;

    var sentAt = siteInfo(uid).checkedAt;
    await refreshLastSeen(uid);

    var info = siteInfo(uid);
    if (info.status != SiteStatus.checking) return;

    var heardSince = sentAt != null &&
        info.lastSeen != null &&
        info.lastSeen!.isAfter(sentAt);
    _setSite(
        uid,
        info.copyWith(
            status: heardSince ? SiteStatus.silent : SiteStatus.noAnswer));
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

  // ---- the store ----
  //
  // Products and orders are read on demand rather than kept in step with the
  // running store: the store reloads its catalogue from disk on every change,
  // so the files are the record and this is a view of them.

  List<ManagedProduct> _products = const [];
  List<ManagedProduct> get products => _products;

  List<ManagedOrder> _orders = const [];
  List<ManagedOrder> get orders => _orders;

  String? _storeError;
  String? get storeError => _storeError;

  bool _loadingStore = false;
  bool get loadingStore => _loadingStore;

  /// loadStore reads the catalogue and order book. A store that is not being
  /// hosted is not an error worth showing -- the UI offers to switch one on
  /// instead -- so the lists are simply left empty.
  Future<void> loadStore() async {
    if (!hostConfig.hostsStore) {
      _products = const [];
      _orders = const [];
      _storeError = null;
      notifyListeners();
      return;
    }

    _loadingStore = true;
    notifyListeners();
    try {
      _products = await Golib.listStoreProducts();
      _orders = await Golib.listStoreOrders();
      _storeError = null;
    } catch (exception) {
      _storeError = "$exception";
    } finally {
      _loadingStore = false;
      notifyListeners();
    }
  }

  Future<void> saveProduct(ManagedProduct product, String file) async {
    _products = await Golib.saveStoreProduct(product, file);
    notifyListeners();
  }

  Future<void> deleteProduct(String sku) async {
    _products = await Golib.deleteStoreProduct(sku);
    notifyListeners();
  }

  Future<void> setOrderStatus(String user, int order, String status) async {
    _orders = await Golib.setStoreOrderStatus(user, order, status);
    notifyListeners();
  }

  Future<void> addOrderComment(String user, int order, String comment) async {
    _orders = await Golib.addStoreOrderComment(user, order, comment);
    notifyListeners();
  }

  void _replacePages(List<LocalPage> pages) {
    var h = _host;
    if (h == null) return;
    _host = PagesHostStatus(
        h.config, h.editable, h.defaultPath, h.defaultStorePath, pages);
    notifyListeners();
  }
}
