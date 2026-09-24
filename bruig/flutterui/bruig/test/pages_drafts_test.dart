import 'package:bruig/components/pages_bar.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/models/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

// pages_drafts_test.dart covers writing that has not been saved yet.
//
// The Pages screen is rebuilt from scratch by its route on every navigation
// to it, so anything the editors kept in their own State was thrown away by
// stepping over to Chat -- silently, and with nothing to undo it with. The
// drafts live on PagesModel now, which outlives the screen, and these pin
// that they are neither lost nor quietly notified away.

/// _Hosting answers the hosting question without golib, so the notification
/// this is about can be watched.
class _Hosting extends PagesModel {
  _Hosting() : super(ResourcesModel(runStream: false));

  @override
  Future<PagesHostStatus> fetchHost() async => PagesHostStatus(
      PagesHostConfig(pagesHostModePages, "", "/pages", "ln", "", 0, ""),
      true,
      "",
      "", const []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PagesModel model() => PagesModel(ResourcesModel(runStream: false));

  /// shop is the product half. A page draft and a product draft outlive the
  /// screen for the same reason, and now live on the two models that own
  /// what is being written.
  StoreModel shop() => StoreModel(model());

  group('opening on a section', () {
    test('the one the route named is taken without telling anybody', () {
      // The screen reads the route argument as it is first built, and a
      // model that told its listeners there marked widgets that had already
      // been built dirty -- "setState() called during build", twice, every
      // time Pages was opened from another screen.
      var m = model();
      var notes = 0;
      m.addListener(() => notes++);

      m.openAt(pagesTabStore);
      expect(m.tab, pagesTabStore);
      expect(m.browsing, isFalse);
      expect(m.openSections, contains(pagesTabStore),
          reason: "and it is one of the open tabs, as choosing it would be");
      expect(notes, 0, reason: "nothing has drawn the old value yet");
    });

    test('and Visit is still never a tab of its own', () {
      var m = model();
      m.openAt(pagesTabVisit);
      expect(m.tab, pagesTabVisit);
      expect(m.openSections, isEmpty);
    });

    test('everything after that notifies as usual', () {
      var m = model();
      var notes = 0;
      m.openAt(pagesTabStore);
      m.addListener(() => notes++);

      m.tab = pagesTabMySite;
      expect(notes, 1);
    });
  });

  group('loading the hosting config', () {
    testWidgets('does not tell anybody while the frame is being built',
        (tester) async {
      // It is asked for from a section's initState, which runs inside the
      // build -- so raising the loading flag there marked widgets that had
      // already been built dirty: "setState() called during build", every
      // time Pages was opened.
      var m = _Hosting();
      var notes = 0;
      m.addListener(() => notes++);

      var duringBuild = -1;
      await tester.pumpWidget(Builder(builder: (context) {
        m.loadHost();
        duringBuild = notes;
        return const SizedBox();
      }));

      expect(duringBuild, 0, reason: "nothing told mid-build");
      await tester.pumpAndSettle();
      expect(notes, greaterThan(0), reason: "and told once the frame was over");
      expect(m.loadingHost, isFalse, reason: "the load finished");
    });

    test('and tells straight away when no frame is being built', () {
      var m = _Hosting();
      var notes = 0;
      m.addListener(() => notes++);
      m.loadHost();
      expect(notes, 1, reason: "outside a frame there is nothing to wait for");
    });
  });

  group('a page draft', () {
    test('is kept as it is typed, and is there on the way back', () {
      var m = model();
      m.startPageDraft("");
      m.updatePageDraft(
          m.pageDraft!.copyWith(name: "about.md", body: "half a page"));

      // Leaving Pages destroys the screen; the model is what survives it.
      expect(m.pageDraft?.name, "about.md");
      expect(m.pageDraft?.body, "half a page");
    });

    test('a new page starts loaded, an existing one does not', () {
      // A draft that has not been read off disk must not be saved over the
      // file it came from -- and a new page has no file to read.
      var m = model();
      m.startPageDraft("");
      expect(m.pageDraft?.loaded, isTrue);
      expect(m.pageDraft?.isNew, isTrue);

      m.startPageDraft("about.md");
      expect(m.pageDraft?.loaded, isFalse);
      expect(m.pageDraft?.isNew, isFalse);
      // Seeded with the name, so the box is not empty while it loads.
      expect(m.pageDraft?.name, "about.md");
    });

    test('typing does not notify, opening and closing do', () {
      // A rebuild of the whole section on every keystroke buys nothing --
      // the editor already has what it typed. Swapping between the list and
      // the editor does have to be drawn.
      var m = model();
      var notes = 0;
      m.addListener(() => notes++);

      m.startPageDraft("");
      expect(notes, 1);

      m.updatePageDraft(m.pageDraft!.copyWith(body: "a"));
      m.updatePageDraft(m.pageDraft!.copyWith(body: "ab"));
      expect(notes, 1, reason: "typing is storage, not a redraw");

      m.endPageDraft();
      expect(notes, 2);
      expect(m.pageDraft, isNull);
    });

    test('the page being renamed is remembered apart from the new name', () {
      // Saving under a new name has to delete the old file, so which file
      // this started as cannot be read off the name box.
      var m = model();
      m.startPageDraft("old.md");
      m.updatePageDraft(m.pageDraft!.copyWith(name: "new.md"));
      expect(m.pageDraft?.editing, "old.md");
      expect(m.pageDraft?.name, "new.md");
    });
  });

  group('a product draft', () {
    ManagedProduct product() => ManagedProduct("A thing", "SKU1", "About it",
        ["tag"], 1.5, false, true, "file.zip", "products.toml");

    test('is seeded from the product and kept as it is typed', () {
      var m = shop();
      m.startProductDraft(product());
      expect(m.productDraft?.title, "A thing");
      expect(m.productDraft?.price, "1.5");
      expect(m.productDraft?.tags, "tag");
      expect(m.productDraft?.isNew, isFalse);

      m.updateProductDraft(m.productDraft!.copyWith(title: "Renamed"));
      expect(m.productDraft?.title, "Renamed");
      // The product it started from is kept, for the fields not on the form.
      expect(m.productDraft?.original.sku, "SKU1");
    });

    test('a half-typed price is still just text', () {
      // Parsing on every keystroke would eat a decimal point as it is
      // typed, so the draft holds what is in the box.
      var m = shop();
      m.startProductDraft(ManagedProduct.empty());
      m.updateProductDraft(m.productDraft!.copyWith(price: "1."));
      expect(m.productDraft?.price, "1.");
    });

    test('an empty product is a new one, and shows no zero price', () {
      var m = shop();
      m.startProductDraft(ManagedProduct.empty());
      expect(m.productDraft?.isNew, isTrue);
      expect(m.productDraft?.price, "");
    });

    test('typing does not notify, opening and closing do', () {
      var m = shop();
      var notes = 0;
      m.addListener(() => notes++);

      m.startProductDraft(product());
      expect(notes, 1);
      m.updateProductDraft(m.productDraft!.copyWith(sku: "S2"));
      expect(notes, 1);
      m.endProductDraft();
      expect(notes, 2);
      expect(m.productDraft, isNull);
    });
  });
}
