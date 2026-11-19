import 'dart:convert';
import 'dart:ui' show Color, Rect;

import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';

// epub_tasks.dart is a play task card working in an interactive EPUB: the
// card as drawn on the page, with a layer over it that ticks each step as
// it is done. It listens to whatever the reader can give it -- Bison
// Relay's own keyboard (window.bisonReader.midi), the reader's Web MIDI,
// or the microphone for single notes -- and where it can hear nothing, the
// student ticks each step. It never says it listens where it cannot: Apple
// refuses a book that promises what it does not do. Ken, 2026-11-19, step 7
// of the ebook plan.

/// EpubTask is one card on a page: its box in the page picture's pixels,
/// and what its script needs, as JSON.
class EpubTask {
  final String id;
  final Rect box;
  final String json;
  const EpubTask(this.id, this.box, this.json);
}

String _hex(Color c) =>
    "#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0")}";

List<double> _rect(Rect r, double s) => [
      double.parse((r.left * s).toStringAsFixed(2)),
      double.parse((r.top * s).toStringAsFixed(2)),
      double.parse((r.width * s).toStringAsFixed(2)),
      double.parse((r.height * s).toStringAsFixed(2)),
    ];

/// epubTaskOf is card [e] as the page carries it, [pixels] page-picture
/// pixels to a design unit; null for a turned card, which is left as drawn.
EpubTask? epubTaskOf(PlayTaskElement e, double pixels) {
  if (e.rotation != 0 || e.checks.isEmpty || !e.visible) return null;
  var plain = playTaskLayout(e, e.width);
  var again = playTaskLayout(e, e.width, again: true);
  var done = playTaskLayout(e, e.width, again: true, banner: true);
  var spec = {
    "id": e.id,
    "accent": _hex(e.accent),
    "passed": e.passed,
    "size": e.spec.fontSize * pixels,
    "checks": [
      for (var (i, c) in e.checks.indexed)
        {
          // "along" is the music played along with: ticked by the student
          // in a book, which has no sheet to score it on.
          "kind": c.kind == PlayCheckKind.along ? "self" : c.kind.name,
          "steps": [
            for (var s in c.keys) [...s]..sort()
          ],
          "count": c.count,
          "row": _rect(plain.rows[i], pixels),
          "mark": _rect(plain.marks[i], pixels),
        }
    ],
    "again": again.again == null ? null : _rect(again.again!, pixels),
    "banner": done.banner == null ? null : _rect(done.banner!, pixels),
  };
  var box = Rect.fromLTWH(
      e.x * pixels, e.y * pixels, e.width * pixels, e.height * pixels);
  return EpubTask(e.id, box, jsonEncode(spec));
}

/// epubTaskTag is [t]'s layer, placed over its card.
String epubTaskTag(EpubTask t, String Function(String) attr) {
  String px(double v) => "${v.toStringAsFixed(2)}px";
  return '<div class="task" data-task="${attr(t.json)}" style="'
      'left:${px(t.box.left)};top:${px(t.box.top)};'
      'width:${px(t.box.width)};height:${px(t.box.height)}"></div>';
}

/// epubTaskCss is how a card's layer looks.
const epubTaskCss = '''
      .task { position: absolute; pointer-events: none; }
      .task .tick, .task .row, .task .pills, .task .banner {
        position: absolute; box-sizing: border-box; }
      .task .pills { display: flex; gap: 0.4em; pointer-events: none; }
      .task .tick { border-radius: 50%; display: none; }
      .task .tick.on { display: block; }
      .task .tick svg { width: 100%; height: 100%; display: block; }
      .task .row { pointer-events: auto; background: transparent; border: 0;
        margin: 0; padding: 0; cursor: pointer;
        -webkit-tap-highlight-color: transparent; display: none; }
      .task .row.ticks { display: block; }
      .task .listen, .task .again { pointer-events: auto; border: 0;
        cursor: pointer; font-size: inherit;
        font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
        font-weight: 700; color: #ffffff; border-radius: 999px;
        padding: 0 0.9em; white-space: nowrap;
        -webkit-tap-highlight-color: transparent; }
      .task .listen .dot { display: inline-block; width: 0.55em;
        height: 0.55em; border-radius: 50%; margin-right: 0.45em;
        animation: bisonTaskPulse 1.2s ease-in-out infinite; }
      @keyframes bisonTaskPulse { 50% { opacity: 0.25; } }
      .task .banner { display: none; font-weight: 700; color: #1e9e6a;
        font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
        border-left: 0.22em solid #1e9e6a; padding-left: 0.68em; }
      .task.all .banner { display: block; }
''';

/// epubTaskScript runs every card on a page (see the top of this file).
/// Its judging of keys is heardBy's (play_task_element.dart), written again
/// for the page.
const epubTaskScript = r'''
(function () {
  function el(tag, cls, parent) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (parent) parent.appendChild(e);
    return e;
  }
  function place(e, r) {
    e.style.left = r[0] + 'px'; e.style.top = r[1] + 'px';
    e.style.width = r[2] + 'px'; e.style.height = r[3] + 'px';
  }
  function store(key, value) {
    try {
      if (value === undefined) return JSON.parse(localStorage.getItem(key) || 'null');
      localStorage.setItem(key, JSON.stringify(value));
    } catch (e) { }
    return null;
  }

  // What the reader lets a book hear, asked once for every card. One card
  // listens at a time (active): starting another stops it, and a card
  // stopped with none listening lets the microphone go.
  var listeners = [];
  var hearing = null, asking = null, mic = null, active = null;
  function heard(note) { for (var i = 0; i < listeners.length; i++) listeners[i](note); }
  function startHearing(then) {
    if (hearing) { then(hearing); return; }
    if (asking) { asking.push(then); return; }
    asking = [then];
    found(function (how) {
      var waiting = asking; asking = null;
      waiting.forEach(function (w) { w(how); });
    });
  }
  function stopHearing() {
    listeners = [];
    if (!mic) return;
    mic.stream.getTracks().forEach(function (t) { t.stop(); });
    if (mic.ctx.close) mic.ctx.close();
    mic = null;
    hearing = null;
  }
  function found(then) {
    var br = window.bisonReader;
    if (br && br.midi) {
      br.midi(function (n, velocity) {
        if (velocity === undefined || velocity > 0) heard(n);
      });
      hearing = 'keyboard';
      then(hearing);
      return;
    }
    if (navigator.requestMIDIAccess) {
      navigator.requestMIDIAccess().then(function (m) {
        var any = false;
        m.inputs.forEach(function (input) {
          any = true;
          input.onmidimessage = function (e) {
            var d = e.data;
            if ((d[0] & 0xf0) === 0x90 && d[2] > 0) heard(d[1]);
          };
        });
        if (any) { hearing = 'keyboard'; then(hearing); } else microphone(then);
      }, function () { microphone(then); });
      return;
    }
    microphone(then);
  }
  function microphone(then) {
    var Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      hearing = 'none'; then(hearing); return;
    }
    navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
      var c = new Ctx();
      if (c.resume) c.resume();
      var an = c.createAnalyser();
      an.fftSize = 2048;
      c.createMediaStreamSource(stream).connect(an);
      var buf = new Float32Array(an.fftSize);
      var last = -1, since = 0, sent = -1;
      var mine = mic = { stream: stream, ctx: c };
      (function tick() {
        if (mic !== mine) return;
        an.getFloatTimeDomainData(buf);
        var note = pitch(buf, c.sampleRate);
        var now = Date.now();
        if (note !== last) { last = note; since = now; }
        // A note held a moment is a note played; silence lets it be again.
        if (note < 0) sent = -1;
        else if (note !== sent && now - since > 90) { sent = note; heard(note); }
        requestAnimationFrame(tick);
      })();
      hearing = 'microphone'; then(hearing);
    }, function () { hearing = 'none'; then(hearing); });
  }
  function pitch(buf, rate) {
    var size = buf.length, rms = 0, i, j, best = -1, bestCorr = 0;
    for (i = 0; i < size; i++) rms += buf[i] * buf[i];
    if (Math.sqrt(rms / size) < 0.02) return -1;
    for (var lag = Math.floor(rate / 1100); lag < Math.floor(rate / 60); lag++) {
      var corr = 0;
      for (j = 0; j < size - lag; j++) corr += buf[j] * buf[j + lag];
      if (corr > bestCorr) { bestCorr = corr; best = lag; }
    }
    if (best <= 0) return -1;
    return Math.round(12 * Math.log(rate / best / 440) / Math.LN2) + 69;
  }

  // With its namespace: a book's page is XHTML, where what a script writes
  // is read as XML, and an svg without one is not drawn.
  var TICK = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M6.6 12.2 L10.3 15.8 L17.6 8.2" ' +
    'fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" ' +
    'stroke-linejoin="round"/></svg>';

  function setup(card) {
    var spec = JSON.parse(card.getAttribute('data-task'));
    var key = 'bisonTask:' + spec.id;
    var checks = spec.checks;
    var fresh = function () {
      return checks.map(function () { return { done: false, counts: [], at: 0 }; });
    };
    var state = store(key) || fresh();
    if (state.length !== checks.length) state = fresh();
    var recent = [];
    card.style.fontSize = spec.size + 'px';

    var ticks = [], rows = [];
    checks.forEach(function (c, i) {
      var t = el('div', 'tick', card);
      place(t, c.mark);
      t.style.background = spec.accent;
      t.innerHTML = TICK;
      ticks.push(t);
      var r = el('button', 'row' + (c.kind === 'self' ? ' ticks' : ''), card);
      r.type = 'button';
      place(r, c.row);
      r.addEventListener('click', function (ev) {
        ev.preventDefault(); ev.stopPropagation();
        if (!r.classList.contains('ticks')) return;
        state[i].done = !state[i].done;
        save();
      });
      rows.push(r);
    });
    var banner = el('div', 'banner', card);
    if (spec.banner) place(banner, spec.banner);
    banner.textContent = spec.passed;
    // Start again and Listen, side by side and ending where the drawn card
    // keeps its Start again.
    var pills = el('div', 'pills', card);
    var slot = spec.again || [card.offsetWidth - 200, 0, 200, spec.size * 1.4];
    pills.style.fontSize = (spec.size * 0.72) + 'px';
    pills.style.right = (card.offsetWidth - slot[0] - slot[2]) + 'px';
    pills.style.top = slot[1] + 'px';
    pills.style.height = Math.max(slot[3], spec.size * 1.3) + 'px';
    var again = el('button', 'again', pills);
    again.type = 'button';
    again.textContent = 'Start again';
    again.style.background = '#ffffff';
    again.style.color = spec.accent;
    again.style.boxShadow = 'inset 0 0 0 0.14em ' + spec.accent;
    var button = el('button', 'listen', pills);
    button.type = 'button';

    // idle, asking, keyboard, microphone or none (nothing can be heard,
    // so each step is tapped).
    var mode = 'idle';
    var me = { stop: stop };
    function stop() {
      mode = 'idle';
      if (active === me) { active = null; stopHearing(); }
      show();
    }
    function show() {
      var any = false, all = true;
      for (var i = 0; i < checks.length; i++) {
        ticks[i].className = 'tick' + (state[i].done ? ' on' : '');
        if (state[i].done) any = true; else all = false;
      }
      // Every step played: nothing more to listen for.
      if (all && mode !== 'idle') { stop(); return; }
      card.className = 'task' + (all ? ' all' : '');
      // A step is ticked by hand where it is the student's to tick, where
      // nothing can be heard, or where it is a chord and only a microphone
      // listens (it hears one note at a time).
      checks.forEach(function (c, i) {
        var chord = c.steps.some(function (s) { return s.length > 1; });
        var byHand = c.kind === 'self' || mode === 'none' ||
          (mode === 'microphone' && chord);
        rows[i].className = 'row' + (byHand ? ' ticks' : '');
      });
      again.style.display = any ? '' : 'none';
      button.style.display = all ? 'none' : '';
      // Listening, the pill turns white with a beating dot, and a tap on
      // it stops.
      var on = mode !== 'idle';
      button.style.background = on ? '#ffffff' : spec.accent;
      button.style.color = on ? spec.accent : '#ffffff';
      button.style.boxShadow = on ? 'inset 0 0 0 0.14em ' + spec.accent : 'none';
      button.textContent = mode === 'idle' ? 'Listen' :
        mode === 'asking' ? 'Listen' :
        mode === 'none' ? 'Tap each step' : 'Stop listening';
      button.title = mode === 'keyboard' ? 'Listening to the keyboard' :
        mode === 'microphone' ? 'Listening through the microphone' : '';
      if (mode === 'keyboard' || mode === 'microphone') {
        var dot = document.createElement('span');
        dot.className = 'dot';
        dot.style.background = spec.accent;
        button.insertBefore(dot, button.firstChild);
      }
    }
    function save() { store(key, state); show(); }

    function played(step, held) {
      for (var i = 0; i < step.length; i++) if (held.indexOf(step[i]) < 0) return false;
      return true;
    }
    // heardBy, for one key: held is what was played a moment ago with it.
    function hear(note) {
      var now = Date.now();
      recent = recent.filter(function (r) { return now - r[1] < 600; });
      recent.push([note, now]);
      var held = recent.map(function (r) { return r[0]; });
      checks.forEach(function (c, i) {
        var s = state[i];
        if (s.done || (c.kind !== 'keys' && c.kind !== 'order') || !c.steps.length) return;
        var steps = c.steps;
        if (c.kind === 'keys') {
          var counts = steps.map(function (_, k) { return s.counts[k] || 0; });
          steps.forEach(function (step, k) {
            if (step.indexOf(note) >= 0 && played(step, held)) counts[k]++;
          });
          s.counts = counts;
          s.done = counts.every(function (n) { return n >= c.count; });
          return;
        }
        var at = s.at;
        if (steps[at].indexOf(note) >= 0 && played(steps[at], held)) {
          s.at = at + 1; s.done = s.at >= steps.length; return;
        }
        if (steps[at].indexOf(note) >= 0) return;
        if (at > 0 && steps[at - 1].indexOf(note) >= 0) return;
        s.at = steps[0].indexOf(note) >= 0 && played(steps[0], held) ? 1 : 0;
        s.done = s.at >= steps.length;
      });
      save();
    }

    again.addEventListener('click', function (ev) {
      ev.preventDefault(); ev.stopPropagation();
      state = fresh(); recent = []; save();
    });
    // A second tap stops; a tap on another card's Listen stops this one.
    button.addEventListener('click', function (ev) {
      ev.preventDefault(); ev.stopPropagation();
      if (mode !== 'idle') { stop(); return; }
      if (active) active.stop();
      active = me;
      mode = 'asking';
      show();
      startHearing(function (how) {
        // Stopped while the reader was asked: let go of what it gave.
        if (active !== me) { if (!active) stopHearing(); return; }
        mode = how;
        listeners = how === 'none' ? [] : [hear];
        show();
      });
    });
    show();
    card.bisonTask = { hear: hear, state: function () { return state; } };
  }

  var cards = document.querySelectorAll('.task');
  for (var i = 0; i < cards.length; i++) setup(cards[i]);
})();
''';
