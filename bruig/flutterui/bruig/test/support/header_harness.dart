import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

// header_harness.dart is what the three header test files share: a page to
// draw a banner on, and a way to parse one block without the rest of
// markdown getting involved.

Widget drawHost(Widget child, {double width = 900}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

/// parseBlock runs one block syntax over some markdown and hands back the
/// element it made, without the document's other syntaxes joining in.
md.Element parseBlock(String src, md.BlockSyntax syntax) {
  var doc = md.Document(blockSyntaxes: [syntax]);
  var nodes = doc.parseLines(src.trim().split("\n"));
  return (nodes.first as md.Element).children!.first as md.Element;
}
