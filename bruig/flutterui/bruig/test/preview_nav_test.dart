import 'package:bruig/models/uistate.dart';
import 'package:flutter_test/flutter_test.dart';

// preview_nav_test.dart covers ManageContentNavModel -- what the Manage
// Content page remembers about where the reader was, so that stepping over to
// Chat and coming back does not close the document they were reading.
//
// The screen itself is out of reach of a unit test (it resolves a ClientModel,
// whose construction loads golib.dylib), so what is pinned here is the model
// the screen reads and writes. See header_label_test.dart for the same note.

void main() {
  test('it starts on the first tab with nothing open', () {
    var nav = ManageContentNavModel();
    expect(nav.tab, 0);
    expect(nav.path, isNull);
    expect(nav.position, 0);
    expect(nav.zoom, 1);
  });

  test('the tab is remembered, which is what makes the preview worth it', () {
    // MainMenuModel.activeRoute resets activePageTab on every navigation, so
    // without this the page always came back on Shared and a remembered
    // Downloads preview could never be shown.
    var nav = ManageContentNavModel()..tab = 2;
    expect(nav.tab, 2);
  });

  test('opening a file records it, closing clears it', () {
    var nav = ManageContentNavModel()..open('/tmp/a.pdf');
    expect(nav.path, '/tmp/a.pdf');
    nav.open(null);
    expect(nav.path, isNull);
  });

  test('the place in a document is kept while it stays open', () {
    var nav = ManageContentNavModel()..open('/tmp/a.pdf');
    nav.remember(position: 42, zoom: 0.5);
    expect(nav.position, 42);
    expect(nav.zoom, 0.5);

    // Re-opening the same file is a no-op, so coming back to the page finds
    // the document where it was rather than at the top.
    nav.open('/tmp/a.pdf');
    expect(nav.position, 42);
    expect(nav.zoom, 0.5);
  });

  test('a different document starts at its own beginning', () {
    var nav = ManageContentNavModel()..open('/tmp/a.pdf');
    nav.remember(position: 42, zoom: 0.25);

    nav.open('/tmp/b.pdf');
    // Page 42 of the last document means nothing in this one.
    expect(nav.position, 0);
    expect(nav.zoom, 1);
  });

  test('closing forgets the place, so reopening comes back cold', () {
    // Reopening from cold is what the Continue button and the sidecar beside
    // the file are for -- this model is only "the page was never closed".
    var nav = ManageContentNavModel()..open('/tmp/a.pdf');
    nav.remember(position: 42);
    nav.open(null);
    nav.open('/tmp/a.pdf');
    expect(nav.position, 0);
  });

  test('remembering a position does not rebuild the page', () {
    // It is called as the reader scrolls or plays; nothing on screen is
    // driven by it, and notifying would rebuild the viewer under them.
    var nav = ManageContentNavModel()..open('/tmp/a.pdf');
    var notified = 0;
    nav.addListener(() => notified++);

    nav.remember(position: 10);
    nav.remember(zoom: 0.5);
    expect(notified, 0);

    // Opening a different file does, since that changes what is on screen.
    nav.open('/tmp/b.pdf');
    expect(notified, 1);
  });

  test('setting the tab it is already on changes nothing', () {
    var nav = ManageContentNavModel()..tab = 2;
    var notified = 0;
    nav.addListener(() => notified++);
    nav.tab = 2;
    expect(notified, 0);
  });
}
