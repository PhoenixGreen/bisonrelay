import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:petitparser/petitparser.dart';

// sheet_formula.dart is the Data element's spreadsheet formulas: a cell typed
// "=SUM(B2:B9)" shows what it works out to. A formula is parsed into FNodes
// and worked out by SheetCalc (data_sheet.dart) to a double, String, bool,
// SheetError or null (blank). Spreadsheet rules: blanks are 0 in sums and ""
// in text, SUM passes over text in a range, an error in a sum is the sum's.
// Dates are day numbers from 30 December 1899.

/// SheetError is an error a formula works out to, written as spreadsheets
/// do: #DIV/0!, #VALUE!, #REF!, #NAME?, #N/A, #NUM!.
class SheetError {
  final String code;
  const SheetError(this.code);

  static const div0 = SheetError("#DIV/0!");
  static const value = SheetError("#VALUE!");
  static const ref = SheetError("#REF!");
  static const name = SheetError("#NAME?");
  static const na = SheetError("#N/A");
  static const num = SheetError("#NUM!");
  static const cycle = SheetError("#CYCLE!");
  static const syntax = SheetError("#ERR!");

  static const all = [div0, value, ref, name, na, num, cycle, syntax];

  @override
  bool operator ==(Object other) => other is SheetError && other.code == code;
  @override
  int get hashCode => code.hashCode;
  @override
  String toString() => code;
}

class _Thrown implements Exception {
  final SheetError error;
  const _Thrown(this.error);
}

Never _fail(SheetError e) => throw _Thrown(e);

// ---------- The tree ----------

sealed class FNode {
  const FNode();
}

class FValue extends FNode {
  final Object? value;
  const FValue(this.value);
}

class FRef extends FNode {
  final int r, c;
  const FRef(this.r, this.c);
}

class FRange extends FNode {
  final int r0, c0, r1, c1;
  const FRange(this.r0, this.c0, this.r1, this.c1);
}

class FCall extends FNode {
  final String name;
  final List<FNode> args;
  const FCall(this.name, this.args);
}

class FUnary extends FNode {
  final String op;
  final FNode x;
  const FUnary(this.op, this.x);
}

class FBinary extends FNode {
  final String op;
  final FNode a, b;
  const FBinary(this.op, this.a, this.b);
}

// ---------- Parsing ----------

(int, int)? _a1(String s) => cellAt(s.toUpperCase());

Parser<FNode> _build() {
  var expr = undefined<FNode>();
  Parser<String> sym(String s) => string(s).trim();

  var number = (digit().plus() &
              (char('.') & digit().plus()).optional() &
              (anyOf('eE') & anyOf('+-').optional() & digit().plus())
                  .optional() |
          char('.') & digit().plus())
      .flatten()
      .trim()
      .map<FNode>((s) => FValue(double.parse(s)));
  var text = (char('"') &
          (string('""').map((_) => '"') | pattern('^"')).star() &
          char('"'))
      .map<FNode>((v) => FValue((v[1] as List).join()))
      .trim();
  var cell = (char(r'$').optional() &
          letter().plus() &
          char(r'$').optional() &
          digit().plus())
      .flatten();
  var range = (cell & char(':') & cell).map<FNode>((v) {
    var a = _a1(v[0] as String), b = _a1(v[2] as String);
    if (a == null || b == null) return const FValue(SheetError.ref);
    return FRange(math.min(a.$1, b.$1), math.min(a.$2, b.$2),
        math.max(a.$1, b.$1), math.max(a.$2, b.$2));
  }).trim();
  var ref = cell.map<FNode>((s) {
    var at = _a1(s);
    return at == null ? const FValue(SheetError.ref) : FRef(at.$1, at.$2);
  }).trim();
  var args = (expr &
          ((char(',') | char(';')).trim() & expr).map((v) => v[1]).star())
      .map<List<FNode>>((v) => [v[0] as FNode, ...(v[1] as List).cast<FNode>()])
      .optional()
      .map((v) => v ?? const <FNode>[]);
  var call = ((letter() & (word() | char('.')).star()).flatten().trim() &
          char('(').trim() &
          args &
          char(')').trim())
      .map<FNode>(
          (v) => FCall((v[0] as String).toUpperCase(), v[2] as List<FNode>));
  var boolean =
      (string('TRUE', ignoreCase: true) | string('FALSE', ignoreCase: true))
          .flatten()
          .trim()
          .map<FNode>((s) => FValue(s.toUpperCase() == "TRUE"));
  var error = (char('#') & (word() | anyOf('/!?')).plus())
      .flatten()
      .trim()
      .map<FNode>((s) => FValue(SheetError.all.firstWhere(
          (e) => e.code == s.toUpperCase(),
          orElse: () => SheetError.syntax)));

  var builder = ExpressionBuilder<FNode>();
  builder.primitive(
      [call, range, ref, number, text, boolean, error].toChoiceParser());
  builder.group().wrapper(char('(').trim(), char(')').trim(), (l, v, r) => v);
  builder.group()
    ..prefix(char('-').trim(), (op, x) => FUnary('-', x))
    ..prefix(char('+').trim(), (op, x) => x);
  builder.group().postfix(char('%').trim(), (x, op) => FUnary('%', x));
  builder.group().left(char('^').trim(), (a, op, b) => FBinary('^', a, b));
  builder.group()
    ..left(char('*').trim(), (a, op, b) => FBinary('*', a, b))
    ..left(char('/').trim(), (a, op, b) => FBinary('/', a, b));
  builder.group()
    ..left(char('+').trim(), (a, op, b) => FBinary('+', a, b))
    ..left(char('-').trim(), (a, op, b) => FBinary('-', a, b));
  builder.group().left(char('&').trim(), (a, op, b) => FBinary('&', a, b));
  builder.group().left(
      (sym('<=') | sym('>=') | sym('<>') | sym('=') | sym('<') | sym('>'))
          .cast<String>(),
      (a, op, b) => FBinary(op, a, b));
  expr.set(builder.build());
  return expr.end();
}

final Parser<FNode> _parser = _build();
final Map<String, FNode?> _parsed = {};

/// parseFormula is the tree of [src] (without its "="), or null where it does
/// not parse. Cached: the same few formulas are worked out at every change.
FNode? parseFormula(String src) {
  // A formula longer than any sheet's (deeply nested brackets) is refused
  // before the parser recurses through it.
  if (src.length > maxFormulaLength) return null;
  if (_parsed.length > 4000) _parsed.clear();
  return _parsed.putIfAbsent(src, () {
    try {
      var r = _parser.parse(src);
      return r is Success<FNode> ? r.value : null;
    } catch (_) {
      return null;
    }
  });
}

/// maxFormulaLength is the longest formula worked out, as spreadsheets have.
const maxFormulaLength = 8192;

/// maxRangeCells is the most cells one range in a formula reads.
const maxRangeCells = 1000000;

// ---------- Working out ----------

/// FormulaCells is what a formula reads: each cell's value.
typedef FormulaCells = Object? Function(int r, int c);

/// evaluateFormula works [node] out against [cell], an error where it fails.
Object? evaluateFormula(FNode node, FormulaCells cell) {
  try {
    var v = _Eval(cell).eval(node);
    if (v is _Grid) return v.cells.isEmpty ? null : v.cells.first;
    return v;
  } on _Thrown catch (t) {
    return t.error;
  } catch (_) {
    // Anything else (a number too big to round, a date past the calendar, a
    // stack too deep) is the formula's error, not the sheet's or canvas's.
    return SheetError.num;
  }
}

class _Grid {
  final int rows, cols;
  final List<Object?> cells;
  const _Grid(this.rows, this.cols, this.cells);
  Object? at(int r, int c) => cells[r * cols + c];
}

/// serialOf is [d]'s spreadsheet day number.
double serialOf(DateTime d) => DateTime.utc(d.year, d.month, d.day)
    .difference(DateTime.utc(1899, 12, 30))
    .inDays
    .toDouble();

DateTime dateOf(double serial) =>
    DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));

class _Eval {
  final FormulaCells cell;
  _Eval(this.cell);

  Object? eval(FNode n) => switch (n) {
        FValue(:var value) => value is SheetError ? _fail(value) : value,
        FRef(:var r, :var c) => _cellValue(r, c),
        FRange(:var r0, :var c0, :var r1, :var c1)
            when (r1 - r0 + 1) * (c1 - c0 + 1) > maxRangeCells =>
          _fail(SheetError.ref),
        FRange(:var r0, :var c0, :var r1, :var c1) =>
          _Grid(r1 - r0 + 1, c1 - c0 + 1, [
            for (var r = r0; r <= r1; r++)
              for (var c = c0; c <= c1; c++) cell(r, c)
          ]),
        FUnary(op: '-', :var x) => -_num(eval(x)),
        FUnary(op: '%', :var x) => _num(eval(x)) / 100,
        FUnary() => _fail(SheetError.syntax),
        FBinary(:var op, :var a, :var b) => _binary(op, eval(a), eval(b)),
        FCall(:var name, :var args) => _call(name, args),
      };

  Object? _cellValue(int r, int c) {
    var v = cell(r, c);
    if (v is SheetError) _fail(v);
    return v;
  }

  Object? _scalar(Object? v) {
    if (v is _Grid) {
      if (v.cells.length == 1) return _scalar(v.cells.first);
      _fail(SheetError.value);
    }
    if (v is SheetError) _fail(v);
    return v;
  }

  double _num(Object? v) {
    v = _scalar(v);
    return switch (v) {
      null => 0,
      double d => d,
      int i => i.toDouble(),
      bool b => b ? 1 : 0,
      String s => _numberIn(s) ?? _fail(SheetError.value),
      _ => _fail(SheetError.value),
    };
  }

  String _text(Object? v) {
    v = _scalar(v);
    return switch (v) {
      null => "",
      bool b => b ? "TRUE" : "FALSE",
      double d => generalNumber(d),
      _ => "$v",
    };
  }

  bool _bool(Object? v) {
    v = _scalar(v);
    return switch (v) {
      null => false,
      bool b => b,
      double d => d != 0,
      String s when s.toUpperCase() == "TRUE" => true,
      String s when s.toUpperCase() == "FALSE" => false,
      _ => _fail(SheetError.value),
    };
  }

  Object? _binary(String op, Object? a, Object? b) {
    switch (op) {
      case '+':
        return _num(a) + _num(b);
      case '-':
        return _num(a) - _num(b);
      case '*':
        return _num(a) * _num(b);
      case '/':
        var d = _num(b);
        if (d == 0) _fail(SheetError.div0);
        return _num(a) / d;
      case '^':
        var r = math.pow(_num(a), _num(b)).toDouble();
        if (r.isNaN || r.isInfinite) _fail(SheetError.num);
        return r;
      case '&':
        return _text(a) + _text(b);
    }
    return _compare(op, _scalar(a), _scalar(b));
  }

  bool _compare(String op, Object? a, Object? b) {
    var d = compareValues(a, b);
    return switch (op) {
      '=' => d == 0,
      '<>' => d != 0,
      '<' => d < 0,
      '>' => d > 0,
      '<=' => d <= 0,
      '>=' => d >= 0,
      _ => _fail(SheetError.syntax),
    };
  }

  /// _numbers is every number [args] give, ranges spread out; a range's
  /// text, TRUE/FALSE and blanks are passed over (SUM, AVERAGE).
  List<double> _numbers(List<FNode> args) {
    var out = <double>[];
    for (var a in args) {
      var v = eval(a);
      if (v is _Grid) {
        for (var x in v.cells) {
          if (x is SheetError) _fail(x);
          if (x is double) out.add(x);
        }
      } else {
        out.add(_num(v));
      }
    }
    return out;
  }

  List<Object?> _all(List<FNode> args) => [
        for (var a in args)
          ...switch (eval(a)) {
            _Grid g => g.cells,
            var v => [v],
          }
      ];

  _Grid _grid(FNode n) => switch (eval(n)) {
        _Grid g => g,
        var v => _Grid(1, 1, [v]),
      };

  void _arity(List<FNode> a, int min, [int? max]) {
    if (a.length < min || a.length > (max ?? min)) _fail(SheetError.value);
  }

  Object? _call(String name, List<FNode> a) {
    switch (name) {
      // Sums and counts.
      case "SUM":
        return _numbers(a).fold<double>(0.0, (s, v) => s + v);
      case "PRODUCT":
        return _numbers(a).fold<double>(1.0, (s, v) => s * v);
      case "AVERAGE":
        var n = _numbers(a);
        if (n.isEmpty) _fail(SheetError.div0);
        return n.fold<double>(0.0, (s, v) => s + v) / n.length;
      case "MIN":
        var n = _numbers(a);
        return n.isEmpty ? 0.0 : n.reduce(math.min);
      case "MAX":
        var n = _numbers(a);
        return n.isEmpty ? 0.0 : n.reduce(math.max);
      case "MEDIAN":
        var n = _numbers(a)..sort();
        if (n.isEmpty) _fail(SheetError.num);
        var m = n.length ~/ 2;
        return n.length.isOdd ? n[m] : (n[m - 1] + n[m]) / 2;
      case "COUNT":
        return _all(a).whereType<double>().length.toDouble();
      case "COUNTA":
        return _all(a).where((v) => v != null && v != "").length.toDouble();
      case "COUNTBLANK":
        return _all(a).where((v) => v == null || v == "").length.toDouble();
      case "COUNTIF":
        _arity(a, 2);
        var crit = _criterion(eval(a[1]));
        return _grid(a[0]).cells.where(crit).length.toDouble();
      case "SUMIF" || "AVERAGEIF":
        _arity(a, 2, 3);
        var where = _grid(a[0]);
        var crit = _criterion(eval(a[1]));
        var take = a.length == 3 ? _grid(a[2]) : where;
        var n = <double>[];
        for (var i = 0; i < where.cells.length && i < take.cells.length; i++) {
          if (crit(where.cells[i]) && take.cells[i] is double) {
            n.add(take.cells[i] as double);
          }
        }
        if (name == "SUMIF") return n.fold<double>(0.0, (s, v) => s + v);
        if (n.isEmpty) _fail(SheetError.div0);
        return n.fold<double>(0.0, (s, v) => s + v) / n.length;
      case "SUMIFS" || "COUNTIFS" || "AVERAGEIFS":
        var sums = name != "COUNTIFS";
        var take = sums ? _grid(a[0]) : null;
        var pairs = sums ? a.sublist(1) : a;
        if (pairs.isEmpty || pairs.length.isOdd) _fail(SheetError.value);
        var tests = [
          for (var i = 0; i < pairs.length; i += 2)
            (_grid(pairs[i]), _criterion(eval(pairs[i + 1]))),
        ];
        var size = take?.cells.length ?? tests.first.$1.cells.length;
        var n = <double>[];
        var count = 0;
        for (var i = 0; i < size; i++) {
          if (!tests
              .every((t) => i < t.$1.cells.length && t.$2(t.$1.cells[i]))) {
            continue;
          }
          count++;
          if (take != null && take.cells[i] is double) {
            n.add(take.cells[i] as double);
          }
        }
        if (name == "COUNTIFS") return count.toDouble();
        if (name == "SUMIFS") return n.fold<double>(0.0, (s, v) => s + v);
        if (n.isEmpty) _fail(SheetError.div0);
        return n.fold<double>(0.0, (s, v) => s + v) / n.length;

      // Logic.
      case "IF":
        _arity(a, 1, 3);
        return _bool(eval(a[0]))
            ? (a.length > 1 ? _scalar(eval(a[1])) : true)
            : (a.length > 2 ? _scalar(eval(a[2])) : false);
      case "IFS":
        if (a.isEmpty || a.length.isOdd) _fail(SheetError.value);
        for (var i = 0; i < a.length; i += 2) {
          if (_bool(eval(a[i]))) return _scalar(eval(a[i + 1]));
        }
        _fail(SheetError.na);
      case "IFERROR":
        _arity(a, 2);
        try {
          return _scalar(eval(a[0]));
        } on _Thrown {
          return _scalar(eval(a[1]));
        }
      case "IFNA":
        _arity(a, 2);
        try {
          return _scalar(eval(a[0]));
        } on _Thrown catch (t) {
          if (t.error != SheetError.na) rethrow;
          return _scalar(eval(a[1]));
        }
      case "AND":
        return _all(a).where((v) => v != null && v is! String).every(_bool);
      case "OR":
        return _all(a).where((v) => v != null && v is! String).any(_bool);
      case "NOT":
        _arity(a, 1);
        return !_bool(eval(a[0]));
      case "TRUE":
        return true;
      case "FALSE":
        return false;
      case "ISBLANK":
        _arity(a, 1);
        return _cellOrValue(a[0]) == null;
      case "ISNUMBER":
        _arity(a, 1);
        return _cellOrValue(a[0]) is double;
      case "ISTEXT":
        _arity(a, 1);
        return _cellOrValue(a[0]) is String;
      case "ISERROR":
        _arity(a, 1);
        try {
          _scalar(eval(a[0]));
          return false;
        } on _Thrown {
          return true;
        }

      // Arithmetic.
      case "ROUND" || "ROUNDUP" || "ROUNDDOWN":
        _arity(a, 1, 2);
        var x = _num(eval(a[0]));
        var d = a.length > 1 ? _num(eval(a[1])).truncate() : 0;
        return roundTo(x, d,
            how: name == "ROUND" ? 0 : (name == "ROUNDUP" ? 1 : -1));
      case "INT":
        _arity(a, 1);
        return _num(eval(a[0])).floorToDouble();
      case "ABS":
        _arity(a, 1);
        return _num(eval(a[0])).abs();
      case "SQRT":
        _arity(a, 1);
        var x = _num(eval(a[0]));
        if (x < 0) _fail(SheetError.num);
        return math.sqrt(x);
      case "POWER":
        _arity(a, 2);
        return _binary('^', eval(a[0]), eval(a[1]));
      case "MOD":
        _arity(a, 2);
        var x = _num(eval(a[0])), y = _num(eval(a[1]));
        if (y == 0) _fail(SheetError.div0);
        return x - y * (x / y).floorToDouble();
      case "PI":
        return math.pi;

      // Looking things up.
      case "VLOOKUP":
        _arity(a, 3, 4);
        var key = _scalar(eval(a[0]));
        var t = _grid(a[1]);
        var col = _num(eval(a[2])).truncate();
        if (col < 1 || col > t.cols) _fail(SheetError.ref);
        var approx = a.length < 4 || _bool(eval(a[3]));
        var row = approx
            ? _approxRow([for (var r = 0; r < t.rows; r++) t.at(r, 0)], key)
            : _exactRow([for (var r = 0; r < t.rows; r++) t.at(r, 0)], key);
        if (row < 0) _fail(SheetError.na);
        return _scalar(t.at(row, col - 1));
      case "XLOOKUP":
        _arity(a, 3, 4);
        var key = _scalar(eval(a[0]));
        var keys = _grid(a[1]).cells, back = _grid(a[2]).cells;
        var i = _exactRow(keys, key);
        if (i < 0 || i >= back.length) {
          if (a.length == 4) return _scalar(eval(a[3]));
          _fail(SheetError.na);
        }
        return _scalar(back[i]);
      case "MATCH":
        _arity(a, 2, 3);
        var key = _scalar(eval(a[0]));
        var list = _grid(a[1]).cells;
        var type = a.length > 2 ? _num(eval(a[2])).truncate() : 1;
        var i = type == 0 ? _exactRow(list, key) : _approxRow(list, key);
        if (i < 0) _fail(SheetError.na);
        return (i + 1).toDouble();
      case "INDEX":
        _arity(a, 2, 3);
        var t = _grid(a[0]);
        var r = _num(eval(a[1])).truncate();
        var c = a.length > 2 ? _num(eval(a[2])).truncate() : 1;
        if (t.rows == 1 && a.length == 2) (r, c) = (1, r);
        if (r < 1 || r > t.rows || c < 1 || c > t.cols) _fail(SheetError.ref);
        return _scalar(t.at(r - 1, c - 1));
      case "RANK":
        _arity(a, 2, 3);
        var x = _num(eval(a[0]));
        var list = _grid(a[1]).cells.whereType<double>().toList();
        var up = a.length > 2 && _num(eval(a[2])) != 0;
        if (!list.contains(x)) _fail(SheetError.na);
        return (list.where((v) => up ? v < x : v > x).length + 1).toDouble();
      case "PERCENTILE":
        _arity(a, 2);
        var list = _grid(a[0]).cells.whereType<double>().toList()..sort();
        var k = _num(eval(a[1]));
        if (list.isEmpty || k < 0 || k > 1) _fail(SheetError.num);
        var at = k * (list.length - 1);
        var lo = at.floor(), hi = at.ceil();
        return list[lo] + (list[hi] - list[lo]) * (at - lo);

      // Words.
      case "CONCAT" || "CONCATENATE":
        return [for (var v in _all(a)) _text(v)].join();
      case "TEXT":
        _arity(a, 2);
        return textFormat(_scalar(eval(a[0])), _text(eval(a[1])));
      case "LEFT" || "RIGHT":
        _arity(a, 1, 2);
        var s = _text(eval(a[0]));
        var n = a.length > 1 ? _num(eval(a[1])).truncate() : 1;
        if (n < 0) _fail(SheetError.value);
        n = math.min(n, s.length);
        return name == "LEFT" ? s.substring(0, n) : s.substring(s.length - n);
      case "MID":
        _arity(a, 3);
        var s = _text(eval(a[0]));
        var from = _num(eval(a[1])).truncate(), n = _num(eval(a[2])).truncate();
        if (from < 1 || n < 0) _fail(SheetError.value);
        if (from > s.length) return "";
        return s.substring(from - 1, math.min(s.length, from - 1 + n));
      case "LEN":
        _arity(a, 1);
        return _text(eval(a[0])).length.toDouble();
      case "UPPER":
        _arity(a, 1);
        return _text(eval(a[0])).toUpperCase();
      case "LOWER":
        _arity(a, 1);
        return _text(eval(a[0])).toLowerCase();
      case "TRIM":
        _arity(a, 1);
        return _text(eval(a[0])).trim().replaceAll(RegExp(r" +"), " ");
      case "VALUE":
        _arity(a, 1);
        return _num(eval(a[0]));

      // Dates, as day numbers.
      case "TODAY":
        return serialOf(DateTime.now());
      case "DATE":
        _arity(a, 3);
        return serialOf(DateTime.utc(_num(eval(a[0])).truncate(),
            _num(eval(a[1])).truncate(), _num(eval(a[2])).truncate()));
      case "YEAR" || "MONTH" || "DAY":
        _arity(a, 1);
        var d = dateOf(_num(eval(a[0])));
        return (name == "YEAR" ? d.year : (name == "MONTH" ? d.month : d.day))
            .toDouble();
      case "EOMONTH":
        _arity(a, 2);
        var d = dateOf(_num(eval(a[0])));
        var m = _num(eval(a[1])).truncate();
        return serialOf(DateTime.utc(d.year, d.month + m + 1, 0));
    }
    _fail(SheetError.name);
  }

  Object? _cellOrValue(FNode n) {
    var v = n is FRef ? cell(n.r, n.c) : _scalar(eval(n));
    return v;
  }

  int _exactRow(List<Object?> keys, Object? key) {
    for (var (i, k) in keys.indexed) {
      if (k is! SheetError && compareValues(k, key) == 0) return i;
    }
    return -1;
  }

  /// _approxRow is the last of sorted [keys] no larger than [key].
  int _approxRow(List<Object?> keys, Object? key) {
    var at = -1;
    for (var (i, k) in keys.indexed) {
      if (k == null || k is SheetError) continue;
      if (compareValues(k, key) <= 0) {
        at = i;
      } else {
        break;
      }
    }
    return at;
  }

  /// _criterion is a COUNTIF criterion; see criterionMatches.
  bool Function(Object?) _criterion(Object? spec) {
    spec = _scalar(spec);
    if (spec is! String) return (v) => compareValues(v, spec) == 0 && v != null;
    var m = RegExp(r"^(<=|>=|<>|=|<|>)?(.*)$").firstMatch(spec)!;
    var op = m.group(1) ?? "=";
    var raw = m.group(2)!;
    Object? want = _numberIn(raw) ?? raw;
    if (want is String && op == "=" || op == "<>") {
      if (want is String && (want.contains("*") || want.contains("?"))) {
        var re = RegExp(
            "^${RegExp.escape(want).replaceAll(r"\*", ".*").replaceAll(r"\?", ".")}\$",
            caseSensitive: false);
        return op == "="
            ? (v) => re.hasMatch(_text(v))
            : (v) => !re.hasMatch(_text(v));
      }
    }
    return (v) {
      if (want is double && v is! double) return op == "<>";
      if (want is String && raw.isEmpty) {
        return op == "=" ? (v == null || v == "") : !(v == null || v == "");
      }
      var d = compareValues(v, want);
      return switch (op) {
        "=" => d == 0,
        "<>" => d != 0,
        "<" => d < 0,
        ">" => d > 0,
        "<=" => d <= 0,
        _ => d >= 0,
      };
    };
  }
}

/// criterionMatches is whether [value] meets [criterion] as COUNTIF reads
/// one: ">5", "<>0", "=Arsenal", "Ars*", or a value to equal.
bool criterionMatches(Object? value, String criterion) {
  try {
    return _Eval((_, __) => null)._criterion(criterion)(value);
  } on _Thrown {
    return false;
  }
}

/// _numberIn reads text a person typed as a number: "1,240", "+3", "4.5".
double? _numberIn(String s) {
  var t = s.trim().replaceAll(",", "");
  if (t.startsWith("+")) t = t.substring(1);
  return t.isEmpty ? null : double.tryParse(t);
}

/// compareValues orders two values as a spreadsheet does: numbers, then text
/// (case-blind), then TRUE/FALSE; a blank as 0 or "".
int compareValues(Object? a, Object? b) {
  int rank(Object? v) =>
      v is double ? 0 : (v is String ? 1 : (v is bool ? 2 : 0));
  a ??= b is String ? "" : 0.0;
  b ??= a is String ? "" : 0.0;
  var ra = rank(a), rb = rank(b);
  if (ra != rb) return ra.compareTo(rb);
  return switch (a) {
    double x => x.compareTo(b as double),
    String x => x.toLowerCase().compareTo((b as String).toLowerCase()),
    bool x => (x ? 1 : 0).compareTo((b as bool) ? 1 : 0),
    _ => 0,
  };
}

/// roundTo is [x] to [places] decimals: halves away from zero ([how] 0,
/// ROUND), always away (1) or toward it (-1). A hair is added first, so
/// 2.675 rounds to 2.68 as spreadsheets do, not 2.67 as binary would.
double roundTo(double x, int places, {int how = 0}) {
  var f = math.pow(10, places).toDouble();
  var y = (x.abs() * f) * (1 + 1e-13);
  var r = how == 0
      ? (y + 0.5).floorToDouble()
      : (how > 0 ? y.ceilToDouble() : y.floorToDouble());
  return (x < 0 ? -r : r) / f;
}

/// generalNumber is [v] in a spreadsheet's General format: whole numbers
/// whole, others to ten significant figures without trailing noughts.
String generalNumber(double v) {
  if (v.isNaN) return SheetError.num.code;
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsPrecision(10);
  if (s.contains("e")) {
    var parts = s.split("e");
    var m = parts[0].contains(".")
        ? parts[0].replaceAll(RegExp(r"0+$"), "").replaceAll(RegExp(r"\.$"), "")
        : parts[0];
    return "${m}E${parts[1].startsWith("-") ? "" : "+"}${parts[1]}";
  }
  if (s.contains(".")) {
    s = s.replaceAll(RegExp(r"0+$"), "").replaceAll(RegExp(r"\.$"), "");
  }
  return s;
}

const _months = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December"
];
const _days = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday"
];

/// textFormat is [v] written by a number format code (TEXT's, or a cell's):
/// "0.00", "#,##0", "0%", "$#,##0.00", "dd/mm/yyyy", "d mmm yyyy",
/// "yyyy-mm-dd", "mmmm". Text stays as it is.
String textFormat(Object? v, String code) {
  if (v is! double) {
    return v == null ? "" : (v is bool ? (v ? "TRUE" : "FALSE") : "$v");
  }
  var lower = code.toLowerCase();
  if (RegExp(r"[dy]|m{3,}").hasMatch(lower) ||
      (lower.contains("m") && RegExp(r"[dy]").hasMatch(lower))) {
    return _dateFormat(dateOf(v), code);
  }
  var percent = code.contains("%");
  var x = percent ? v * 100 : v;
  var m = RegExp(r"([^#0,.]*)([#0,]*)(?:\.(0+|#+))?(.*)")
      .firstMatch(code.replaceAll("%", ""))!;
  var before = m.group(1) ?? "", whole = m.group(2) ?? "";
  var places = (m.group(3) ?? "").length;
  var after = (m.group(4) ?? "") + (percent ? "%" : "");
  var grouped = whole.contains(",");
  var r = roundTo(x, places);
  var neg = r < 0;
  var fixed = r.abs().toStringAsFixed(places);
  var parts = fixed.split(".");
  var intPart = parts[0];
  if (grouped) intPart = _grouped(intPart);
  var out = places > 0 ? "$intPart.${parts[1]}" : intPart;
  return "${neg ? "-" : ""}$before$out$after";
}

String _grouped(String digits) {
  var b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(",");
    b.write(digits[i]);
  }
  return b.toString();
}

String _dateFormat(DateTime d, String code) {
  var out = StringBuffer();
  var i = 0;
  var lower = code.toLowerCase();
  while (i < code.length) {
    var ch = lower[i];
    var run = 1;
    while (i + run < code.length && lower[i + run] == ch) {
      run++;
    }
    switch (ch) {
      case 'y':
        out.write(run <= 2 ? "${d.year % 100}".padLeft(2, "0") : "${d.year}");
      case 'm':
        out.write(switch (run) {
          1 => "${d.month}",
          2 => "${d.month}".padLeft(2, "0"),
          3 => _months[d.month - 1].substring(0, 3),
          _ => _months[d.month - 1],
        });
      case 'd':
        out.write(switch (run) {
          1 => "${d.day}",
          2 => "${d.day}".padLeft(2, "0"),
          3 => _days[d.weekday - 1].substring(0, 3),
          _ => _days[d.weekday - 1],
        });
      default:
        out.write(code.substring(i, i + run));
    }
    i += run;
  }
  return out.toString();
}

// ---------- References moved ----------

final _refs = RegExp(
    r'("(?:[^"]|"")*")|(\$?[A-Za-z]{1,3}\$?\d+)(?::(\$?[A-Za-z]{1,3}\$?\d+))?(?![A-Za-z0-9_(])');
final _refParts = RegExp(r'^(\$?)([A-Za-z]{1,3})(\$?)(\d+)$');

/// _Ref is one reference as written: column, row, and which are $-fixed.
class _Ref {
  final bool fixC, fixR;
  final int r, c;
  const _Ref(this.fixC, this.c, this.fixR, this.r);
  static _Ref? parse(String s) {
    var m = _refParts.firstMatch(s);
    var at = m == null ? null : _a1("${m.group(2)}${m.group(4)}");
    if (m == null || at == null) return null;
    return _Ref(m.group(1)!.isNotEmpty, at.$2, m.group(3)!.isNotEmpty, at.$1);
  }

  _Ref at(int r, int c) => _Ref(fixC, c, fixR, r);
  @override
  String toString() =>
      "${fixC ? r"$" : ""}${columnName(c)}${fixR ? r"$" : ""}${r + 1}";
}

String _rewrite(String raw, String? Function(_Ref a, _Ref? b) f) =>
    raw.replaceAllMapped(_refs, (m) {
      if (m.group(1) != null) return m.group(0)!;
      var a = _Ref.parse(m.group(2)!);
      var b = m.group(3) == null ? null : _Ref.parse(m.group(3)!);
      if (a == null || (m.group(3) != null && b == null)) return m.group(0)!;
      return f(a, b) ?? m.group(0)!;
    });

/// shiftedFormula is [raw] (with its "=") copied [dr] rows down and [dc]
/// columns across: relative references move, $ ones stay, as a fill does.
String shiftedFormula(String raw, int dr, int dc) {
  if (!raw.startsWith("=") || (dr == 0 && dc == 0)) return raw;
  _Ref? move(_Ref x) {
    var r = x.fixR ? x.r : x.r + dr, c = x.fixC ? x.c : x.c + dc;
    return r < 0 || c < 0 ? null : x.at(r, c);
  }

  return _rewrite(raw, (a, b) {
    var na = move(a), nb = b == null ? null : move(b);
    if (na == null || (b != null && nb == null)) return SheetError.ref.code;
    return nb == null ? "$na" : "$na:$nb";
  });
}

/// movedFormula is [raw] after [n] rows (or [columns]) were put in before
/// [at] (n > 0) or taken out from [at] (n < 0): every reference to a moved
/// cell follows it, $ or not; a range shrinks or grows; a reference to a
/// removed cell is #REF!, as Calc does.
String movedFormula(String raw, int at, int n, {bool columns = false}) {
  if (!raw.startsWith("=") || n == 0) return raw;
  int get(_Ref x) => columns ? x.c : x.r;
  _Ref put(_Ref x, int v) => columns ? x.at(x.r, v) : x.at(v, x.c);
  var end = at - n - 1; // the last taken out, when n < 0
  return _rewrite(raw, (a, b) {
    if (n > 0) {
      int moved(int v) => v >= at ? v + n : v;
      var na = put(a, moved(get(a)));
      return b == null ? "$na" : "$na:${put(b, moved(get(b)))}";
    }
    if (b == null) {
      var v = get(a);
      if (v >= at && v <= end) return SheetError.ref.code;
      return "${put(a, v > end ? v + n : v)}";
    }
    var lo = get(a), hi = get(b);
    if (lo >= at && hi <= end) return SheetError.ref.code;
    var nlo = lo < at ? lo : (lo > end ? lo + n : at);
    var nhi = hi < at ? hi : (hi > end ? hi + n : at - 1);
    return "${put(a, nlo)}:${put(b, nhi)}";
  });
}
