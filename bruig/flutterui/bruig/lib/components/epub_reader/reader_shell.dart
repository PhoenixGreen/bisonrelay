import 'dart:convert';

import 'package:bruig/components/epub_reader/epub_book.dart';

// reader_shell.dart is the page Bison Relay's reader shows a book through:
// one web view holding one or two frames, each a page of the book, scaled
// to fit and set side by side as a spread. Written into the book's own
// folder so its pages are the same origin as it, and driven from Dart
// (epub_reader_view.dart) by calling `reader.show(...)`. Taps, swipes and
// keys inside a page come back through the "reader" handler.
//
// Kept to one HTML string so it can be opened in a browser as it is, which
// is how it is checked without the app (see the tests).

/// readerShellName is the shell's file, in the book's folder.
const readerShellName = "__bisonreader__.html";

/// ShellPage is one page as the shell is told it: its file from the shell,
/// and a fixed page's own size.
class ShellPage {
  final String href;
  final int width, height;
  final bool fixed;
  const ShellPage(this.href,
      {this.width = 0, this.height = 0, this.fixed = false});

  factory ShellPage.of(EpubPage p) =>
      ShellPage(p.href, width: p.width, height: p.height, fixed: p.fixed);

  Map<String, dynamic> toJson() =>
      {"href": href, "w": width, "h": height, "fixed": fixed};
}

/// showScript is the call that shows [left] and [right] as a spread, or
/// [left] alone; either may be null for an empty side.
String showScript(ShellPage? left, ShellPage? right, {bool spread = false}) =>
    "reader.show(${jsonEncode({
          "left": left?.toJson(),
          "right": right?.toJson(),
          "spread": spread,
        })});";

/// readerBridge is added to every page of the book before its own scripts
/// run: `window.bisonReader`, Bison Relay's own, through which a book asks
/// for the reader's MIDI keyboard (reader_inputs.dart). In the shell itself
/// it does nothing.
const readerBridge = r'''
(function () {
  if (window.parent === window) return;
  try {
    var host = window.parent.reader;
    if (!host || !host._ask) return;
    window.bisonReader = {
      version: 'Bison Relay reader 1',
      // onKey(key, velocity): a key pressed, or let go at velocity 0.
      midi: function (onKey) { return host._ask('midi', onKey); }
    };
  } catch (e) { }
})();
''';

/// keyScript hands key [key], pressed at [velocity] (0, let go), to the
/// pages that asked for the keyboard.
String keyScript(int key, int velocity) => "reader._key($key,$velocity);";

const readerShell = r'''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Reader</title>
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%;
    overflow: hidden; background: #1b1e24; }
  #stage { position: absolute; left: 0; top: 0; right: 0; bottom: 0; }
  .leaf { position: absolute; border: 0; background: #ffffff;
    transform-origin: 0 0; box-shadow: 0 2px 14px rgba(0,0,0,0.45); }
  .flow { position: absolute; border: 0; background: #ffffff; }
  #spine { position: absolute; width: 2px; background: rgba(0,0,0,0.25);
    pointer-events: none; display: none; }
  /* Panel View: the pages zoomed on one panel, the rest dimmed. */
  #world { position: absolute; left: 0; top: 0; width: 100%; height: 100%;
    transform-origin: 0 0; transition: transform 0.35s ease-in-out; }
  .dim { position: absolute; background: #000000; opacity: 0;
    pointer-events: none; transition: opacity 0.35s ease-in-out; }
  .zoomed .dim { opacity: 0.66; }
</style>
</head>
<body>
<div id="stage"><div id="world"><div id="spine"></div></div>
<div class="dim" id="dimT"></div><div class="dim" id="dimB"></div>
<div class="dim" id="dimL"></div><div class="dim" id="dimR"></div></div>
<script>
(function () {
  var stage = document.getElementById('stage');
  var world = document.getElementById('world');
  var spine = document.getElementById('spine');
  var shown = null;
  var frames = [];
  var bySide = {};
  var zoom = null;
  // What the shown pages asked to hear, cleared when they go.
  var asked = { midi: [] };

  function tell(message) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('reader', message);
      }
    } catch (e) { }
  }

  // Keys and swipes inside a page come back here, as the page has the
  // focus and the app would not otherwise see them.
  function listen(frame, side) {
    var doc;
    try { doc = frame.contentDocument; } catch (e) { return; }
    if (!doc) return;
    doc.addEventListener('keydown', function (e) {
      tell({ type: 'key', key: e.key });
    });
    var x0 = null, y0 = null, t0 = 0;
    doc.addEventListener('touchstart', function (e) {
      if (e.touches.length !== 1) { x0 = null; return; }
      x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; t0 = Date.now();
    }, { passive: true });
    function double(cx, cy) {
      var w = doc.documentElement.clientWidth || 1;
      var h = doc.documentElement.clientHeight || 1;
      tell({ type: 'double', side: side, x: cx / w, y: cy / h });
    }
    // A double tap is two quick taps in one place: found here, as a
    // touch screen does not always say so.
    var lastTap = 0, lastX = 0, lastY = 0;
    doc.addEventListener('touchend', function (e) {
      if (x0 === null) return;
      var t = e.changedTouches[0];
      var dx = t.clientX - x0, dy = t.clientY - y0, now = Date.now();
      if (now - t0 < 600 && Math.abs(dx) > 60 && Math.abs(dx) > 2 * Math.abs(dy)) {
        tell({ type: 'swipe', dir: dx < 0 ? 'next' : 'back' });
        lastTap = 0;
      } else if (Math.abs(dx) < 12 && Math.abs(dy) < 12 && now - t0 < 300) {
        if (now - lastTap < 320 && Math.abs(t.clientX - lastX) < 30 &&
            Math.abs(t.clientY - lastY) < 30) {
          double(t.clientX, t.clientY);
          lastTap = 0;
        } else {
          lastTap = now; lastX = t.clientX; lastY = t.clientY;
        }
      }
      x0 = null;
    }, { passive: true });
    doc.addEventListener('dblclick', function (e) { double(e.clientX, e.clientY); });
  }

  function frameFor(page, side) {
    var f = document.createElement('iframe');
    f.className = page.fixed ? 'leaf' : 'flow';
    f.setAttribute('scrolling', page.fixed ? 'no' : 'yes');
    f.src = page.href;
    f.addEventListener('load', function () { listen(f, side); });
    world.appendChild(f);
    bySide[side] = { frame: f, page: page };
    return f;
  }

  function layout() {
    if (!shown) return;
    var W = window.innerWidth, H = window.innerHeight, pad = 12;
    var pages = [];
    if (shown.left) pages.push(shown.left);
    if (shown.right) pages.push(shown.right);
    if (!pages.length) return;
    if (!pages[0].fixed) {
      // A flowing page fills the view, like a screen of text.
      var f = frames[0];
      f.style.left = '0px'; f.style.top = '0px';
      f.style.width = W + 'px'; f.style.height = H + 'px';
      spine.style.display = 'none';
      return;
    }
    // A spread is two pages wide whether or not both sides are filled, so
    // a lone left or right page sits on its own side.
    var pw = 0, ph = 0, i;
    for (i = 0; i < pages.length; i++) {
      pw = Math.max(pw, pages[i].w || 1000);
      ph = Math.max(ph, pages[i].h || 1400);
    }
    var across = shown.spread ? 2 : 1;
    var s = Math.min((W - 2 * pad) / (pw * across), (H - 2 * pad) / ph);
    var left0 = (W - pw * across * s) / 2, top0 = (H - ph * s) / 2;
    var slots = shown.spread ? [shown.left, shown.right] : [pages[0]];
    var k = 0;
    for (i = 0; i < slots.length; i++) {
      var p = slots[i];
      if (!p) continue;
      var fr = frames[k++];
      var w = p.w || pw, h = p.h || ph;
      fr.style.width = w + 'px'; fr.style.height = h + 'px';
      fr.style.transform = 'scale(' + s + ')';
      fr.style.left = (left0 + i * pw * s + (pw - w) * s / 2) + 'px';
      fr.style.top = (top0 + (ph - h) * s / 2) + 'px';
    }
    if (shown.spread && shown.left && shown.right) {
      spine.style.display = 'block';
      spine.style.left = (left0 + pw * s - 1) + 'px';
      spine.style.top = top0 + 'px';
      spine.style.height = (ph * s) + 'px';
    } else spine.style.display = 'none';
    place();
  }

  function rectOf(id, x, y, w, h) {
    var d = document.getElementById(id);
    d.style.left = x + 'px'; d.style.top = y + 'px';
    d.style.width = Math.max(0, w) + 'px'; d.style.height = Math.max(0, h) + 'px';
  }

  // place sets the world zoomed on the panel asked for, or not at all, and
  // the dimming round where that panel ends up.
  function place() {
    var W = window.innerWidth, H = window.innerHeight;
    var on = zoom && bySide[zoom.side];
    if (!on) {
      world.style.transform = 'none';
      stage.className = '';
      return;
    }
    var f = on.frame, p = on.page;
    var s = parseFloat((f.style.transform.match(/scale\(([^)]+)\)/) || [0, 1])[1]);
    var fw = (p.w || 1000) * s, fh = (p.h || 1400) * s;
    var fx = parseFloat(f.style.left), fy = parseFloat(f.style.top);
    var px = fx + zoom.x * fw, py = fy + zoom.y * fh;
    var pw = zoom.w * fw, ph = zoom.h * fh;
    var z = Math.min(W * 0.94 / Math.max(1, pw), H * 0.94 / Math.max(1, ph));
    var tx = W / 2 - (px + pw / 2) * z, ty = H / 2 - (py + ph / 2) * z;
    world.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + z + ')';
    var L = W / 2 - pw * z / 2, T = H / 2 - ph * z / 2, R = L + pw * z, B = T + ph * z;
    rectOf('dimT', 0, 0, W, T);
    rectOf('dimB', 0, B, W, H - B);
    rectOf('dimL', 0, T, L, B - T);
    rectOf('dimR', R, T, W - R, B - T);
    stage.className = 'zoomed';
  }

  window.reader = {
    show: function (spec) {
      for (var i = 0; i < frames.length; i++) world.removeChild(frames[i]);
      frames = [];
      bySide = {};
      zoom = null;
      asked = { midi: [] };
      world.style.transition = 'none';
      shown = spec;
      if (spec.left) frames.push(frameFor(spec.left, spec.spread ? 'left' : 'single'));
      if (spec.right) frames.push(frameFor(spec.right, 'right'));
      layout();
      // Shown at once; zooming after it glides.
      setTimeout(function () { world.style.transition = ''; }, 30);
      return true;
    },
    // zoom shows the panel {side, x, y, w, h} (shares of its page) filling
    // the view, the rest dimmed; unzoom, the pages whole again.
    zoom: function (spec) { zoom = spec; place(); return true; },
    unzoom: function () { zoom = null; place(); return true; },
    // A page asks for the keyboard (see readerBridge); its keys come back.
    _ask: function (kind, then) {
      if (!asked[kind] || typeof then !== 'function') return false;
      asked[kind].push(then);
      tell({ type: kind });
      return true;
    },
    _key: function (key, velocity) {
      var to = asked.midi.slice();
      for (var i = 0; i < to.length; i++) { try { to[i](key, velocity); } catch (e) { } }
      return true;
    },
    // The page frames, for what is laid over them later (panels).
    frames: function () { return frames; }
  };
  window.addEventListener('resize', layout);
  document.addEventListener('keydown', function (e) { tell({ type: 'key', key: e.key }); });
  // Opened in a browser to check it: the spread to show rides the address.
  if (location.hash.length > 1) {
    try {
      var spec = JSON.parse(decodeURIComponent(location.hash.slice(1)));
      window.reader.show(spec);
      if (spec.zoom) { world.style.transition = 'none'; window.reader.zoom(spec.zoom); }
    } catch (e) { }
  }
  tell({ type: 'ready' });
})();
</script>
</body>
</html>
''';
