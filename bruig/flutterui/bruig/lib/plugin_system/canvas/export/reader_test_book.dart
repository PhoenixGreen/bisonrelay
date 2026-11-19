import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart'
    show epubMime;

// reader_test_book.dart is a one-page EPUB that finds out what a reading app
// lets a book do, and says so on the page: whether its scripts run, whether
// it keeps what a book stores, moves what CSS animates, plays a sound, hears
// a MIDI keyboard or the microphone, and whether it is Bison Relay's own
// reader. Opened in Apple Books, the Kobo apps, Google Play Books, Thorium
// and ours, it settles what the stores' own pages leave open (see the ebook
// platforms report, 2026-11-18). A page that shows only "Scripts: not
// running" is the answer for a reader that runs none.

/// readerTestBookName is the file the test book is saved as.
const readerTestBookName = "Reader test.epub";

/// readerTestBook is the test book's bytes.
Uint8List readerTestBook({DateTime? made}) {
  var when =
      (made ?? DateTime.now()).toUtc().toIso8601String().split(".").first;
  var archive = Archive();
  void add(String path, List<int> bytes, {bool stored = false}) {
    var f = ArchiveFile(path, bytes.length, bytes);
    if (stored) f.compression = CompressionType.none;
    archive.addFile(f);
  }

  // The mimetype first and uncompressed: a reader looks for it there.
  add("mimetype", ascii.encode(epubMime), stored: true);
  add("META-INF/container.xml", utf8.encode(_container));
  add("META-INF/com.apple.ibooks.display-options.xml",
      utf8.encode(_appleOptions));
  add("OEBPS/content.opf", utf8.encode(_opf(when)));
  add("OEBPS/nav.xhtml", utf8.encode(_nav));
  add("OEBPS/test.xhtml", utf8.encode(_page));
  add("OEBPS/test.css", utf8.encode(_css));
  add("OEBPS/test.js", utf8.encode(_script));
  add("OEBPS/tone.wav", _tone(), stored: true);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// _tone is half a second of A above middle C, as a WAV: a sound file any
/// reader's audio element can play, made here with nothing to install.
List<int> _tone() {
  const rate = 22050, seconds = 0.5;
  var samples = (rate * seconds).round();
  var data = ByteData(44 + samples * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, "RIFF");
  data.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, "WAVE");
  text(12, "fmt ");
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, "data");
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    // Faded in and out, so it does not click.
    var edge = math.min(1.0, math.min(i, samples - i) / (rate * 0.02));
    var v = math.sin(2 * math.pi * 440 * i / rate) * 0.4 * edge;
    data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

const _container = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

const _appleOptions = '''<?xml version="1.0" encoding="UTF-8"?>
<display_options>
  <platform name="*">
    <option name="fixed-layout">true</option>
    <option name="open-to-spread">false</option>
    <option name="interactive">true</option>
  </platform>
</display_options>
''';

String _opf(String when) => '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid"
    prefix="rendition: http://www.idpf.org/vocab/rendition/#">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:6a1f3c2e-9b7d-4e1a-8c35-b15e0f2d7a91</dc:identifier>
    <dc:title>Reader test</dc:title>
    <dc:creator>Bison Relay Canvas</dc:creator>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">${when}Z</meta>
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:spread">none</meta>
    <meta property="rendition:orientation">auto</meta>
    <meta name="fixed-layout" content="true"/>
    <meta name="original-resolution" content="1240x1754"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="page" href="test.xhtml" media-type="application/xhtml+xml" properties="scripted"/>
    <item id="css" href="test.css" media-type="text/css"/>
    <item id="script" href="test.js" media-type="application/javascript"/>
    <item id="tone" href="tone.wav" media-type="audio/wav"/>
  </manifest>
  <spine>
    <itemref idref="page"/>
  </spine>
</package>
''';

const _nav = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Contents</title></head>
  <body>
    <nav epub:type="toc" id="toc"><ol><li><a href="test.xhtml">Reader test</a></li></ol></nav>
  </body>
</html>
''';

/// _rows are the checks, in the order shown: id, what, and what the page
/// says before its script has run.
const _rows = [
  ("js", "Scripts", "Not running"),
  ("store", "Remembers things", "Not tested"),
  ("anim", "CSS animation", "Not tested"),
  ("wa", "Web Audio sound", "Tap Sound"),
  ("audio", "Audio file", "Tap Sound"),
  ("midi", "MIDI keyboard", "Tap MIDI"),
  ("mic", "Microphone", "Tap Microphone"),
  ("bridge", "Bison Relay reader", "Not tested"),
];

final String _page = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <title>Reader test</title>
    <meta name="viewport" content="width=1240, height=1754"/>
    <link rel="stylesheet" type="text/css" href="test.css"/>
  </head>
  <body>
    <h1>Reader test</h1>
    <p class="lead">What this reading app lets a book do. Tap each button; a
    green answer works, a red one does not.</p>
    <div class="spin" id="spin"></div>
    <table>
${[
  for (var (id, what, before) in _rows)
    '      <tr class="r" id="$id"><th>$what</th><td class="v">$before</td></tr>'
].join("\n")}
    </table>
    <div class="meter"><div id="level"></div></div>
    <div class="buttons">
      <button type="button" id="bSound">Sound</button>
      <button type="button" id="bMidi">MIDI</button>
      <button type="button" id="bMic">Microphone</button>
    </div>
    <audio id="tone" src="tone.wav" preload="auto"></audio>
    <p class="ua" id="ua">Reading app: unknown (scripts are not running)</p>
    <script src="test.js"></script>
  </body>
</html>
''';

const _css = '''
html, body { margin: 0; padding: 0; }
body { width: 1240px; height: 1754px; background: #10141f; color: #e8ecf5;
  font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
  box-sizing: border-box; padding: 110px 120px; position: relative; }
h1 { font-size: 88px; margin: 0 0 24px 0; }
.lead { font-size: 34px; line-height: 1.35; color: #a9b3c9; margin: 0 0 50px 0;
  max-width: 820px; }
.spin { position: absolute; right: 130px; top: 120px; width: 120px;
  height: 120px; border-radius: 22px; background: #3d7eff;
  animation: turn 2s linear infinite; }
@keyframes turn { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
table { width: 100%; border-collapse: collapse; font-size: 36px; }
th { text-align: left; font-weight: 600; padding: 22px 20px 22px 0;
  width: 42%; vertical-align: top; }
td { padding: 22px 0; color: #a9b3c9; }
tr { border-bottom: 2px solid #232a3b; }
tr.yes td { color: #4fd08a; }
tr.no td { color: #ff6b6b; }
.meter { height: 26px; background: #232a3b; border-radius: 13px; margin: 40px 0 0 0;
  overflow: hidden; }
#level { height: 100%; width: 0; background: #4fd08a; }
.buttons { margin: 60px 0 0 0; text-align: center; }
button { font-size: 40px; padding: 28px 54px; margin: 0 16px; border-radius: 18px;
  border: 0; background: #3d7eff; color: #ffffff; }
.ua { position: absolute; left: 120px; right: 120px; bottom: 90px;
  font-size: 22px; color: #6f7a92; word-wrap: break-word; }
''';

/// _script runs the checks. Written for old readers too: no arrow
/// functions, no let, nothing a reader from years ago would refuse to run.
const _script = r'''
(function () {
  function row(id, ok, text) {
    var tr = document.getElementById(id);
    if (!tr) return;
    tr.className = 'r ' + (ok === true ? 'yes' : ok === false ? 'no' : '');
    tr.querySelector('.v').textContent = text;
  }
  function said(e) { return (e && (e.message || e.name)) || String(e); }
  function press(id, run) {
    var b = document.getElementById(id);
    if (!b) return;
    b.addEventListener('click', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      try { run(); } catch (e) { }
    });
  }

  row('js', true, 'Running');
  document.getElementById('ua').textContent = 'Reading app: ' + navigator.userAgent;

  // What a book keeps: counts up each time the book is opened.
  try {
    var n = parseInt(localStorage.getItem('readerTestOpened') || '0', 10) + 1;
    localStorage.setItem('readerTestOpened', String(n));
    row('store', true, 'Opened ' + n + (n === 1 ? ' time' : ' times') +
      ' (close and reopen: it should count up)');
  } catch (e) { row('store', false, 'Blocked: ' + said(e)); }

  // CSS animation: the blue square turns, or it does not.
  var spin = document.getElementById('spin');
  var before = getComputedStyle(spin).transform;
  setTimeout(function () {
    var moved = getComputedStyle(spin).transform !== before;
    row('anim', moved, moved ? 'Moving' : 'Not moving');
  }, 700);

  // Bison Relay's own reader hands a book its MIDI and microphone.
  var br = window.bisonReader;
  row('bridge', br ? true : null,
    br ? 'Yes' + (br.version ? ', ' + br.version : '') : 'No (another reader)');

  var Ctx = window.AudioContext || window.webkitAudioContext;
  var ctx = null;
  function audio() { if (!ctx && Ctx) ctx = new Ctx(); return ctx; }

  press('bSound', function () {
    if (!Ctx) row('wa', false, 'No Web Audio');
    else {
      try {
        var c = audio();
        if (c.resume) c.resume();
        var o = c.createOscillator(), g = c.createGain();
        g.gain.value = 0.2; o.frequency.value = 660;
        o.connect(g); g.connect(c.destination);
        o.start(); o.stop(c.currentTime + 0.4);
        row('wa', true, 'Played a high beep (did you hear it?)');
      } catch (e) { row('wa', false, 'Error: ' + said(e)); }
    }
    var a = document.getElementById('tone');
    try {
      a.currentTime = 0;
      var p = a.play();
      if (p && p.then) {
        p.then(function () { row('audio', true, 'Played a low tone (did you hear it?)'); },
          function (e) { row('audio', false, 'Refused: ' + said(e)); });
      } else row('audio', true, 'Asked to play a low tone (did you hear it?)');
    } catch (e) { row('audio', false, 'Error: ' + said(e)); }
  });

  function noteName(hz) {
    var names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    var m = Math.round(12 * Math.log(hz / 440) / Math.LN2) + 69;
    return names[(m % 12 + 12) % 12] + (Math.floor(m / 12) - 1);
  }
  function heard(note, from) {
    var names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    row('midi', true, 'Heard ' + names[note % 12] + (Math.floor(note / 12) - 1) +
      (from ? ' from ' + from : ''));
  }

  press('bMidi', function () {
    if (br && br.midi) {
      br.midi(function (note) { heard(note, 'Bison Relay'); });
      row('midi', true, 'Through Bison Relay. Play a key.');
      return;
    }
    if (!navigator.requestMIDIAccess) { row('midi', false, 'No MIDI in this reader'); return; }
    navigator.requestMIDIAccess().then(function (m) {
      var names = [];
      m.inputs.forEach(function (input) {
        names.push(input.name);
        input.onmidimessage = function (e) {
          var d = e.data;
          if ((d[0] & 0xf0) === 0x90 && d[2] > 0) heard(d[1], input.name);
        };
      });
      row('midi', true, names.length ? 'Allowed. Play a key on ' + names.join(', ')
        : 'Allowed, but no keyboard is plugged in');
    }, function (e) { row('midi', false, 'Refused: ' + said(e)); });
  });

  // Pitch by autocorrelation: enough to name one sung or played note.
  function pitch(buf, rate) {
    var size = buf.length, best = -1, bestCorr = 0, rms = 0, i, j;
    for (i = 0; i < size; i++) rms += buf[i] * buf[i];
    rms = Math.sqrt(rms / size);
    if (rms < 0.01) return -1;
    for (var lag = Math.floor(rate / 1200); lag < Math.floor(rate / 60); lag++) {
      var corr = 0;
      for (j = 0; j < size - lag; j++) corr += buf[j] * buf[j + lag];
      if (corr > bestCorr) { bestCorr = corr; best = lag; }
    }
    return best > 0 ? rate / best : -1;
  }

  press('bMic', function () {
    if (br && br.microphone) {
      br.microphone(function (hz, level) {
        document.getElementById('level').style.width = Math.min(100, level * 100) + '%';
        if (hz > 0) row('mic', true, 'Through Bison Relay: hearing ' + noteName(hz));
      });
      row('mic', true, 'Through Bison Relay. Sing or play a note.');
      return;
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      row('mic', false, 'No microphone in this reader'); return;
    }
    navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
      var c = audio();
      if (!c) { row('mic', false, 'Allowed, but no Web Audio to hear it with'); return; }
      if (c.resume) c.resume();
      var an = c.createAnalyser();
      an.fftSize = 2048;
      c.createMediaStreamSource(stream).connect(an);
      var buf = new Float32Array(an.fftSize);
      row('mic', true, 'Allowed. Sing or play a note.');
      (function tick() {
        an.getFloatTimeDomainData(buf);
        var rms = 0;
        for (var i = 0; i < buf.length; i++) rms += buf[i] * buf[i];
        rms = Math.sqrt(rms / buf.length);
        document.getElementById('level').style.width = Math.min(100, rms * 400) + '%';
        var hz = pitch(buf, c.sampleRate);
        if (hz > 0) row('mic', true, 'Hearing ' + noteName(hz) + ' (' + Math.round(hz) + ' Hz)');
        requestAnimationFrame(tick);
      })();
    }, function (e) { row('mic', false, 'Refused: ' + said(e)); });
  });
})();
''';
