import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// addressBookBarItems returns the Address Book submenu's tabs, for use with
// SecondarySideMenuLayout (see containers.dart). Each item switches the
// content pane in place, matching how other submenus (Settings, LN
// Management, Feed) behave -- these used to push separate full-screen
// routes with their own page-transition animation and login-screen
// theming (via StartupScreen), which is why the 4 embedded screens below
// take an `embedded: true` flag to skip that chrome.
List<ListTile> addressBookBarItems(
    Function(int) tabChange, int selectedIndex, bool isOnline) {
  return [
    ListTile(
        selected: selectedIndex == 0,
        title: const Txt.S("New Message"),
        onTap: () => tabChange(0)),
    ListTile(
        selected: selectedIndex == 1,
        title: const Txt.S("New Group Chat"),
        onTap: () => tabChange(1)),
    ListTile(
        selected: selectedIndex == 2,
        enabled: isOnline,
        title: const Txt.S("Generate Invite"),
        onTap: () => tabChange(2)),
    ListTile(
        selected: selectedIndex == 3,
        title: const Txt.S("Received Message Time"),
        onTap: () => tabChange(3)),
    ListTile(
        selected: selectedIndex == 4,
        enabled: isOnline,
        title: const Txt.S("Fetch or Accept Invite"),
        onTap: () => tabChange(4)),
    ListTile(
        selected: selectedIndex == 5,
        title: const Txt.S("Show GC Invitations"),
        trailing: Consumer<GCInviteCountModel>(
            builder: (context, gcInviteCount, child) => gcInviteCount.value == 0
                ? const SizedBox.shrink()
                : CircleAvatar(
                    radius: 10,
                    child: Txt.S(gcInviteCount.value > 9
                        ? "9+"
                        : gcInviteCount.value.toString()))),
        onTap: () => tabChange(5)),
  ];
}
