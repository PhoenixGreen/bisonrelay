import 'package:bruig/models/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// product_picture_test.dart covers a product carrying a picture.
//
// A name and not a path: the product records "guitar.jpg" and the shop's
// template builds "assets/guitar.jpg" round it, so the directory is named in
// one place and a template cannot spell it differently.

void main() {
  group('a product with a picture', () {
    test('keeps it through an edit', () {
      var p = ManagedProduct.empty().copyWith(image: "guitar.jpg");
      expect(p.copyWith(title: "A guitar").image, "guitar.jpg");
    });

    test('records the name, not a path', () {
      // If a path crept in, the template would build assets/assets/x.jpg.
      var p = ManagedProduct.empty().copyWith(image: "guitar.jpg");
      expect(p.image, isNot(contains("/")));
    });

    test('has none by default', () {
      expect(ManagedProduct.empty().image, isEmpty);
    });
  });

  group('the draft the editor holds', () {
    test('starts from the product', () {
      var p = ManagedProduct.empty().copyWith(image: "guitar.jpg");
      expect(ProductDraft.of(p).image, "guitar.jpg");
    });

    test('carries a picture chosen while editing', () {
      var d = ProductDraft.of(ManagedProduct.empty());
      expect(d.copyWith(image: "drum.png").image, "drum.png");
    });

    test('can be cleared back to none', () {
      // A product that had a picture and should not any more. copyWith
      // treats null as "unchanged", so clearing has to be an empty string
      // and not a null -- easy to get wrong and silent when it is.
      var d = ProductDraft.of(
          ManagedProduct.empty().copyWith(image: "guitar.jpg"));
      expect(d.copyWith(image: "").image, isEmpty);
    });

    test('editing something else leaves the picture alone', () {
      var d = ProductDraft.of(
          ManagedProduct.empty().copyWith(image: "guitar.jpg"));
      expect(d.copyWith(title: "A guitar").image, "guitar.jpg");
    });
  });
}
