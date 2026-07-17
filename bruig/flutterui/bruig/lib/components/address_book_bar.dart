import 'package:bruig/components/containers.dart';
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
List<SidebarNavItem> addressBookBarItems(
    Function(int) tabChange, int selectedIndex, bool isOnline) {
  return [
    SidebarNavItem(
        icon: Icons.chat_bubble_outline,
        selected: selectedIndex == 0,
        label: "New Message",
        onTap: () => tabChange(0)),
    SidebarNavItem(
        icon: Icons.group_add_outlined,
        selected: selectedIndex == 1,
        label: "New Group Chat",
        onTap: () => tabChange(1)),
    SidebarNavItem(
        icon: Icons.person_add_alt_outlined,
        selected: selectedIndex == 2,
        enabled: isOnline,
        label: "Generate Invite",
        onTap: () => tabChange(2)),
    SidebarNavItem(
        icon: Icons.schedule_outlined,
        selected: selectedIndex == 3,
        label: "Received Message Time",
        onTap: () => tabChange(3)),
    SidebarNavItem(
        icon: Icons.mail_outline,
        selected: selectedIndex == 4,
        enabled: isOnline,
        label: "Fetch or Accept Invite",
        onTap: () => tabChange(4)),
    SidebarNavItem(
        icon: Icons.mark_email_unread_outlined,
        selected: selectedIndex == 5,
        label: "Show GC Invitations",
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
