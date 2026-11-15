import 'package:bruig/plugin_system/canvas/model/sheet_formula.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_sheet_formula_test.dart is the Data element's formulas: each row
// a formula and what LibreOffice Calc works it out to, over a small sheet.
//
//   A        B    C             D
//   10       10   Arsenal       1
//   20       20   Aston Villa   2
//   x        30   Chelsea       3
//   (blank)  x

const _cells = <String, Object?>{
  "A1": 10.0, "A2": 20.0, "A3": "x", //
  "B1": 10.0, "B2": 20.0, "B3": 30.0, "B4": "x",
  "C1": "Arsenal", "C2": "Aston Villa", "C3": "Chelsea",
  "D1": 1.0, "D2": 2.0, "D3": 3.0,
};

Object? cell(int r, int c) => _cells["${String.fromCharCode(65 + c)}${r + 1}"];

Object? calc(String f) {
  var node = parseFormula(f);
  if (node == null) return SheetError.syntax;
  return evaluateFormula(node, cell);
}

String shown(Object? v) => switch (v) {
      double d => generalNumber(d),
      bool b => b ? "TRUE" : "FALSE",
      SheetError e => e.code,
      null => "",
      _ => "$v",
    };

void main() {
  test("what Calc works each formula out to", () {
    const table = <String, String>{
      // Arithmetic and its order.
      "1+2*3": "7", "(1+2)*3": "9", "-2^2": "4", "2^3^2": "64",
      "10/4": "2.5", "1/0": "#DIV/0!", "5%": "0.05", "0.1+0.2": "0.3",
      "\"a\"&\"b\"": "ab", "1&2": "12", "3>2": "TRUE", "\"a\"=\"A\"": "TRUE",
      // Blanks, text and errors in sums.
      "SUM(A1:A4)": "30", "AVERAGE(A1:A4)": "15", "COUNT(A1:A4)": "2",
      "COUNTA(A1:A4)": "3", "A3+1": "#VALUE!", "A4+1": "1",
      "MAX(A1:A4)": "20", "MIN(A1:A4)": "10", "SUM(B1:B4)": "60",
      "PRODUCT(2,3,4)": "24", "MEDIAN(10,20,30,40)": "25",
      "SUM(1/0,2)": "#DIV/0!", "COUNTBLANK(A1:A4)": "1",
      // Logic.
      "IF(A1>15,\"big\",\"small\")": "small", "IF(A2>15,\"big\")": "big",
      "IFERROR(1/0,\"none\")": "none", "AND(TRUE,1)": "TRUE",
      "OR(FALSE,0)": "FALSE", "NOT(1)": "FALSE",
      "IFS(A1>15,\"a\",A1>5,\"b\")": "b", "ISBLANK(A4)": "TRUE",
      "ISNUMBER(A1)": "TRUE", "ISTEXT(A3)": "TRUE",
      // Rounding.
      "ROUND(2.675,2)": "2.68", "ROUND(-2.5,0)": "-3",
      "ROUNDDOWN(2.79,1)": "2.7", "ROUNDUP(2.71,1)": "2.8",
      "ROUND(1234.5,-2)": "1200", "MOD(-3,2)": "1", "INT(-2.5)": "-3",
      "ABS(-4)": "4", "SQRT(16)": "4", "SQRT(-1)": "#NUM!",
      "POWER(2,10)": "1024",
      // Conditions.
      "COUNTIF(B1:B4,\">15\")": "2", "SUMIF(B1:B4,\">15\")": "50",
      "COUNTIF(C1:C3,\"Ars*\")": "1", "COUNTIF(C1:C3,\"a*\")": "2",
      "SUMIF(C1:C3,\"Chelsea\",D1:D3)": "3",
      "AVERAGEIF(B1:B4,\"<>20\")": "20",
      "COUNTIFS(B1:B3,\">5\",D1:D3,\"<3\")": "2",
      "SUMIFS(D1:D3,B1:B3,\">15\")": "5",
      // Looking up.
      "VLOOKUP(\"Chelsea\",C1:D3,2,FALSE)": "3",
      "VLOOKUP(\"Spurs\",C1:D3,2,FALSE)": "#N/A",
      "VLOOKUP(25,B1:D3,3)": "2",
      "XLOOKUP(\"Arsenal\",C1:C3,D1:D3)": "1",
      "XLOOKUP(\"Spurs\",C1:C3,D1:D3,\"-\")": "-",
      "MATCH(\"Chelsea\",C1:C3,0)": "3", "INDEX(D1:D3,2)": "2",
      "INDEX(C1:D3,3,2)": "3", "RANK(20,B1:B3)": "2",
      "RANK(20,B1:B3,1)": "2", "PERCENTILE(B1:B3,0.5)": "20",
      "PERCENTILE(B1:B3,0.25)": "15",
      // Words.
      "LEFT(\"Arsenal\",3)": "Ars", "RIGHT(\"Arsenal\",2)": "al",
      "MID(\"Arsenal\",2,3)": "rse", "LEN(C2)": "11",
      "UPPER(\"dcr\")": "DCR", "TRIM(\"  a   b \")": "a b",
      "CONCAT(\"a\",1,TRUE)": "a1TRUE",
      "TEXT(1234.5,\"#,##0.00\")": "1,234.50",
      "TEXT(0.256,\"0.0%\")": "25.6%", "TEXT(14.2,\"\$0.00\")": "\$14.20",
      "VALUE(\"1,240\")": "1240",
      // Dates as day numbers.
      "DATE(2026,11,15)": "46341",
      "TEXT(DATE(2026,11,15),\"dd/mm/yyyy\")": "15/11/2026",
      "TEXT(DATE(2026,11,15),\"d mmm yyyy\")": "15 Nov 2026",
      "YEAR(DATE(2026,11,15))": "2026", "MONTH(46341)": "11",
      "EOMONTH(DATE(2026,11,15),0)": "46356",
      "EOMONTH(DATE(2026,11,15),1)": "46387",
      // Mistakes.
      "NOSUCH(1)": "#NAME?", "1+": "#ERR!", "SUM(": "#ERR!",
    };
    for (var MapEntry(key: f, value: want) in table.entries) {
      expect(shown(calc(f)), want, reason: "=$f");
    }
  });

  test(r"references copied move; $ ones stay", () {
    expect(shiftedFormula(r"=A1+$B$2+A$3+$C4", 1, 1), r"=B2+$B$2+B$3+$C5");
    expect(shiftedFormula("=SUM(A1:A5)", 2, 0), "=SUM(A3:A7)");
    expect(shiftedFormula("=A1", -1, 0), "=#REF!");
    expect(shiftedFormula('="A1"&A1', 1, 0), '="A1"&A2',
        reason: "words in quotes are words");
  });

  test("rows put in or taken out: references follow, ranges grow and shrink",
      () {
    expect(movedFormula("=SUM(A1:A5)", 2, 1), "=SUM(A1:A6)");
    expect(movedFormula("=A3+B1", 2, 1), "=A4+B1");
    expect(movedFormula(r"=$A$3", 2, 1), r"=$A$4", reason: r"$ follows too");
    expect(movedFormula("=SUM(A1:A5)", 2, -1), "=SUM(A1:A4)");
    expect(movedFormula("=SUM(A3:A5)", 2, -1), "=SUM(A3:A4)",
        reason: "its first row taken out: it starts at the next");
    expect(movedFormula("=A3", 2, -1), "=#REF!");
    expect(movedFormula("=SUM(A3:A4)", 2, -2), "=SUM(#REF!)");
    expect(movedFormula("=B1+D1", 1, -1, columns: true), "=#REF!+C1");
    expect(movedFormula("=SUM(LOG10(A1))", 0, 1), "=SUM(LOG10(A2))",
        reason: "a function's name isn't a reference");
  });
}
