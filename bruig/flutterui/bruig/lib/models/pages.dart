import 'dart:async';

import 'package:bruig/config.dart';
import 'package:bruig/components/pages_bar.dart';
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

/// PageDraft is a page being written.
///
/// Held on PagesModel rather than in the editor, because the Pages screen is
/// rebuilt from scratch by its route on every navigation to it -- so a draft
/// kept in the editor's State was thrown away by stepping over to Chat, with
/// no warning and nothing to undo it with. Same reasoning as
/// SettingsNavModel and ManageContentNavModel next door, with more at stake:
/// those lose a scroll position, this loses writing.
@immutable
class PageDraft {
  /// editing is the page being changed, or "" for one being written.
  final String editing;
  final String name;
  final String body;

  /// loaded is whether the body has been read off disk yet. A draft that has
  /// not been read must not be saved over the file it came from, and must
  /// not be filled in a second time on the way back.
  final bool loaded;

  const PageDraft({
    required this.editing,
    this.name = "",
    this.body = "",
    this.loaded = false,
  });

  bool get isNew => editing.isEmpty;

  PageDraft copyWith({String? name, String? body, bool? loaded}) => PageDraft(
        editing: editing,
        name: name ?? this.name,
        body: body ?? this.body,
        loaded: loaded ?? this.loaded,
      );
}

/// ProductDraft is a product being written. See [PageDraft] for why it is
/// out here; the fields are strings because that is what is in the boxes,
/// and a half-typed price is not a number yet.
@immutable
class ProductDraft {
  /// original is the product being changed, or an empty one for a new
  /// product -- kept so saving can carry over anything not on the form.
  final ManagedProduct original;
  final String title;
  final String sku;
  final String description;
  final String price;
  final String tags;
  final String sendFilename;
  final bool shipping;
  final bool disabled;

  const ProductDraft({
    required this.original,
    this.title = "",
    this.sku = "",
    this.description = "",
    this.price = "",
    this.tags = "",
    this.sendFilename = "",
    this.shipping = false,
    this.disabled = false,
  });

  factory ProductDraft.of(ManagedProduct p) => ProductDraft(
        original: p,
        title: p.title,
        sku: p.sku,
        description: p.description,
        price: p.price == 0 ? "" : p.price.toString(),
        tags: p.tags.join(", "),
        sendFilename: p.sendFilename,
        shipping: p.shipping,
        disabled: p.disabled,
      );

  bool get isNew => original.sku.isEmpty;

  ProductDraft copyWith({
    String? title,
    String? sku,
    String? description,
    String? price,
    String? tags,
    String? sendFilename,
    bool? shipping,
    bool? disabled,
  }) =>
      ProductDraft(
        original: original,
        title: title ?? this.title,
        sku: sku ?? this.sku,
        description: description ?? this.description,
        price: price ?? this.price,
        tags: tags ?? this.tags,
        sendFilename: sendFilename ?? this.sendFilename,
        shipping: shipping ?? this.shipping,
        disabled: disabled ?? this.disabled,
      );
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
    // Choosing a section is asking to look at it, so it also stops the
    // browser covering the content area -- but the page stays open, in the
    // strip, rather than being closed on the reader's behalf.
    var opened = v != pagesTabVisit && _openSections.add(v);
    if (_tab == v && !_browsing && !opened) return;
    _tab = v;
    _browsing = false;
    notifyListeners();
  }

  /// openSections are the sections open as tabs, beside the open pages.
  ///
  /// Visit is never one. It is where a page or a section is opened from --
  /// the equivalent of a browser's new-tab page -- so a tab for it would be
  /// a tab for "no tab".
  final Set<int> _openSections = {};
  Set<int> get openSections => Set.unmodifiable(_openSections);

  /// closeSection takes a section's tab away. What was in it is not lost:
  /// a section is a view of what is on disk, not a document.
  ///
  /// Where to go next is not decided here. It used to be -- straight to
  /// Visit -- which made closing one of three open tabs leave the other two
  /// sitting there while the area jumped somewhere else entirely. Only the
  /// screen knows what else is open, because the other tabs are pages and
  /// those belong to ResourcesModel. See ViewPageScreen.closeTab.
  void closeSection(int v) {
    if (!_openSections.remove(v)) return;
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

  // ---- what is being written ----
  //
  // Opening and closing an editor notifies, because the screen swaps between
  // the list and the editor on it. Typing does not: a rebuild of the whole
  // section on every keystroke is a cost with nothing to show for it, and
  // the editor already has what it typed. The draft is storage here, read
  // back when the screen is built again.

  PageDraft? _pageDraft;
  PageDraft? get pageDraft => _pageDraft;

  void startPageDraft(String name) {
    _pageDraft = PageDraft(editing: name, name: name, loaded: name.isEmpty);
    notifyListeners();
  }

  void updatePageDraft(PageDraft draft) => _pageDraft = draft;

  void endPageDraft() {
    _pageDraft = null;
    notifyListeners();
  }

  ProductDraft? _productDraft;
  ProductDraft? get productDraft => _productDraft;

  void startProductDraft(ManagedProduct p) {
    _productDraft = ProductDraft.of(p);
    notifyListeners();
  }

  void updateProductDraft(ProductDraft draft) => _productDraft = draft;

  void endProductDraft() {
    _productDraft = null;
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

  Future<void>? _hostLoad;

  /// hostReady completes once the hosting configuration has been read.
  ///
  /// Anything that depends on what is being hosted has to wait for this. The
  /// store's catalogue is read on the Store section being built, which now
  /// happens as Pages opens rather than when the section is first looked at
  /// -- so without this it asked whether a store was being hosted before the
  /// answer had arrived, was told no, and showed an empty catalogue until
  /// something else refilled it.
  Future<void> get hostReady =>
      _host != null ? Future.value() : (_hostLoad ??= loadHost());

  Future<void> loadHost() {
    var load = _load();
    _hostLoad = load;
    return load;
  }

  /// fetchHost, fetchProducts and fetchOrders are the calls into golib,
  /// named so a test can stand in for them. PagesModel talks to golib
  /// directly and the plugin's own mock is long out of date, so without
  /// these the ordering below -- which is what this went wrong on -- cannot
  /// be tested at all.
  @visibleForTesting
  Future<PagesHostStatus> fetchHost() => Golib.getPagesHostConfig();

  @visibleForTesting
  Future<List<ManagedProduct>> fetchProducts() => Golib.listStoreProducts();

  @visibleForTesting
  Future<List<ManagedOrder>> fetchOrders() => Golib.listStoreOrders();

  Future<void> _load() async {
    _loadingHost = true;
    notifyListeners();
    try {
      _host = await fetchHost();
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

  Future<void> savePage(String name, String content) async {
    var pages = await Golib.writeLocalPage(name, content);
    _replacePages(pages);
    _ownSiteChanged();
  }

  Future<void> deletePage(String name) async {
    var pages = await Golib.deleteLocalPage(name);
    _replacePages(pages);
    _ownSiteChanged();
  }

  /// _ownSiteChanged forgets what is cached about this client's own site.
  ///
  /// Fragments are held for the whole run and pages for the session, which
  /// is right for somebody else's site -- they cost a message to fetch and
  /// rarely change. Your own costs nothing to re-read and changes every time
  /// you publish, so keeping either is only a way to be shown yesterday's
  /// page.
  void _ownSiteChanged() {
    var me = _ownUid;
    if (me != null) resources.forgetSite(me);
  }

  /// ownUid is this client's own identity, told to the model rather than
  /// looked up: PagesModel is built before there is a client to ask.
  String? _ownUid;
  set ownUid(String v) => _ownUid = v;

  Future<String> readPage(String name) => Golib.readLocalPage(name);

  // ---- the pictures a site shows ----
  //
  // Files of their own rather than written into a page. A banner behind
  // every page of a site, written into every page, is that banner sent every
  // time; asked for on its own it crosses the wire once. See
  // resources.AssetsDir.

  List<LocalAsset> _assets = const [];
  List<LocalAsset> get assets => _assets;

  Future<void> loadAssets() async {
    _assets = await Golib.listLocalAssets();
    notifyListeners();
  }

  Future<void> deleteAsset(String path) async {
    _assets = await Golib.deleteLocalAsset(path);
    forgetLocalAsset(path);
    notifyListeners();
    _ownSiteChanged();
  }

  /// addAssetBytes writes an already-encoded picture into the site.
  ///
  /// The path the page writes to show it, as [addAsset] returns.
  Future<String> addAssetBytes(String name, Uint8List data) async {
    _assets = await Golib.addLocalAssetBytes(name, data);
    // Named rather than "the last one added", because there is no such
    // thing: the list comes back sorted. An empty list means the write did
    // not happen, and saying so beats the "Bad state: No element" that
    // reaching into it produced.
    var added = _assets.where((a) => a.name == name).firstOrNull;
    if (added == null) {
      throw "the site has no picture called $name after adding it -- "
          "is the app running against an older golib?";
    }
    forgetLocalAsset(added.path);
    notifyListeners();
    _ownSiteChanged();
    return added.path;
  }

  // ---- reading this site's own pictures ----
  //
  // So a page can be seen as it is written. Shaped like the remote side on
  // purpose -- ask, get null, get told when it arrives -- because the widget
  // that draws a picture should not have to know which of the two it is
  // looking at.

  final Map<String, Uint8List> _localBytes = {};
  final Set<String> _localAsking = {};

  /// localAssetBytes returns a picture of this site's, or null while it is
  /// being read. Listeners are notified when it arrives.
  Uint8List? localAssetBytes(String path) {
    var have = _localBytes[path];
    if (have != null) return have;
    if (_localAsking.add(path)) unawaited(_readLocalAsset(path));
    return null;
  }

  /// forgetLocalAsset drops what was read for [path].
  ///
  /// Called whenever the file behind it changes. Replacing a banner and
  /// still seeing the old one is worse than seeing nothing: it reads as the
  /// add having quietly failed, and the usual response is to do it again.
  void forgetLocalAsset(String path) {
    _localBytes.remove(path);
    notifyListeners();
  }

  Future<void> _readLocalAsset(String path) async {
    try {
      var data = await readAsset(path);
      // A file that is not there reads as nothing. Kept anyway: without it
      // the next build asks again, and a page naming a picture that was
      // deleted would read the disk on every frame.
      _localBytes[path] = data;
      notifyListeners();
    } catch (exception) {
      _localBytes[path] = Uint8List(0);
    } finally {
      _localAsking.remove(path);
    }
  }

  @visibleForTesting
  Future<Uint8List> readAsset(String path) => Golib.readLocalAsset(path);

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
    await hostReady;
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
      _products = await fetchProducts();
      _orders = await fetchOrders();
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

  void _replacePages(List<LocalPage> pages) {
    var h = _host;
    if (h == null) return;
    _host = PagesHostStatus(
        h.config, h.editable, h.defaultPath, h.defaultStorePath, pages);
    notifyListeners();
  }
}
