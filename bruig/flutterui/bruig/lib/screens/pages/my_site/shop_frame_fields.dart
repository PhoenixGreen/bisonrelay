import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/components/pages/add_picture_dialog.dart';
import 'package:bruig/screens/pages/page_editor.dart';
import 'package:bruig/screens/pages/site_rows.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:golib_plugin/definitions.dart';

// shop_frame_fields.dart is what the shop is called and what it wears.
//
// Here rather than with the shop because it is hosting: the shop wears the
// site's own fragments, and this is the screen where what this client serves
// is set.

class ShopFrameFields extends StatefulWidget {
  final PagesModel pages;
  const ShopFrameFields({super.key, required this.pages});

  @override
  State<ShopFrameFields> createState() => _ShopFrameFieldsState();
}

class _ShopFrameFieldsState extends State<ShopFrameFields> {
  late final _header =
      TextEditingController(text: widget.pages.hostConfig.storeHeader);
  late final _footer =
      TextEditingController(text: widget.pages.hostConfig.storeFooter);
  late final _name =
      TextEditingController(text: widget.pages.hostConfig.storeName);
  late final _tagline =
      TextEditingController(text: widget.pages.hostConfig.storeTagline);

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _name.dispose();
    _tagline.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var snackbar = SnackBarModel.of(context);
    try {
      await widget.pages.setHost(widget.pages.hostConfig.copyWith(
        storeHeader: _header.text.trim(),
        storeFooter: _footer.text.trim(),
        storeName: _name.text.trim(),
        storeTagline: _tagline.text.trim(),
      ));
    } catch (exception) {
      snackbar.error("Unable to save the shop's frame: $exception");
    }
  }

  Widget _field(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
          onTapOutside: (_) => _save(),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Txt.L("What the shop is called"),
          const SizedBox(height: 6),
          const Txt.S(
              "Shown at the top of the shop's front page. Leave both empty "
              "and the front page starts with your products -- which is the "
              "right answer when the site's own banner already says whose "
              "shop this is.",
              color: TextColor.onSurfaceVariant),
          const SizedBox(height: 10),
          _field("Shop name", _name),
          _field("Tagline", _tagline),
          const SizedBox(height: 20),
          const Txt.L("The shop's frame"),
          const SizedBox(height: 6),
          const Txt.S(
              "Fragments wrapped round every page of the shop -- the front, "
              "a product, the cart, the order list and the rest. Name one of "
              "your own fragments, or leave a field empty for none.",
              color: TextColor.onSurfaceVariant),
          const SizedBox(height: 10),
          _field("Header fragment", _header),
          _field("Footer fragment", _footer),
        ],
      );
}

/// ManagedElsewhere is shown when hosting is pointed at an http upstream or
/// handed to a client over the RPC interface. The app is not the thing
/// serving in those modes, so there is nothing here to change.
