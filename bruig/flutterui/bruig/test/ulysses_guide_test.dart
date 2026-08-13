import 'dart:convert';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter_test/flutter_test.dart';

// ulysses_guide_test.dart pins the shipped "Ulysses" style guide to the one
// it was authored as in the editor.
//
// It was hand-transcribed from an exported guide into a Dart literal, which
// is a long list of numbers and colours and exactly the sort of thing a
// typo hides in. This compares the shipped guide against the exported JSON
// field by field, through the guide's own toJson, so a slipped digit fails
// here rather than looking subtly wrong in a post.
const _authored = r'''
{"id":"ulysses","name":"Ulysses","body":{"lineHeight":1.6},"headings":[{"scale":1.9,"bold":true,"lineHeight":1.25},{"scale":1.5,"bold":true,"lineHeight":1.3},{"scale":1.25,"bold":true,"lineHeight":1.35},{"scale":1.1,"bold":true},{"bold":true},{"ink":"muted","bold":true}],"link":{"ink":{"color":"#ffc08a5b","slot":25},"underline":false},"strong":{"bold":true,"italic":false},"emphasis":{"italic":true},"quote":{"ink":"muted","italic":true},"code":{"font":"mono"},"listBullet":{},"tableHead":{"scale":1.1,"bold":true,"italic":false},"tableBody":{},"blockGap":16.0,"listItemGap":4.0,"listIndent":24.0,"quoteBarInk":{"color":"#ffc08a5b","slot":25},"quoteBarWidth":5.0,"quotePadding":20.0,"codePadding":16.0,"codeLineNumbers":true,"codeHighlight":true,"ruleInk":{"color":"#ff3f3f3f","slot":18},"ruleThickness":1.0,"tableBorderInk":{"color":"#ff4a4a4a","slot":8},"tableBorderWidth":1.0,"tableHeadBackground":{"color":"#ff1e1e1e","slot":0},"tableCellPadding":8.0,"tableFit":"equal","bodyAlign":"inherit","image":{"widthPercent":100.0,"cornerRadius":8.0,"borderWidth":0.0,"borderInk":"outline","align":"left","gap":10.0},"columns":{"gap":30.0,"stackBelow":220.0,"marginSides":[0.0,5.0,0.0,5.0],"borderInk":"outline","dividerWidth":1.0,"dividerInk":{"color":"#ff3f3f3f","slot":18}},"cards":{"gap":16.0,"padding":16.0,"background":{"color":"#ff1e1e1e","slot":0},"borderWidth":1.0,"borderInk":{"color":"#ff8c8c94","slot":13},"radius":12.0,"iconSize":52.0,"iconInk":{"color":"#ffc08a5b","slot":25},"iconBackground":{"color":"#ff3f3f3f","slot":18},"title":{"scale":1.5,"bold":true},"text":{"ink":"muted"},"button":"outlined"}}
''';

void main() {
  var shipped = builtInGuideFor("ulysses");

  test("Ulysses ships as a built-in guide", () {
    expect(shipped, isNotNull);
    expect(shipped!.builtIn, isTrue);
    expect(shipped.name, "Ulysses");
  });

  test("it matches the guide it was authored as", () {
    var want = jsonDecode(_authored) as Map<String, Object?>;
    var got = shipped!.toJson();
    // Compared through fromJson on both sides, so the two are normalised the
    // same way and only real differences show.
    var wantAgain = MarkdownStyleGuide.fromJson(want).toJson();
    for (var key in wantAgain.keys) {
      expect(jsonEncode(got[key]), jsonEncode(wantAgain[key]),
          reason: "\"$key\" differs from the authored guide");
    }
  });

  test("the settings it exists to carry are on", () {
    expect(shipped!.codeLineNumbers, isTrue);
    expect(shipped.codeHighlight, isTrue);
    expect(shipped.codePadding, 16);
    expect(shipped.cards.button, ButtonRole.outlined);
  });
}
