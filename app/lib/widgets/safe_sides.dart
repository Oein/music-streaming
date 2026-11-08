import 'package:flutter/material.dart';

// Safe-area policy for the whole app
// ----------------------------------
// Rotating a phone to landscape moves the notch / Dynamic Island / camera
// cutout (and the rounded display corners) to the left or right edge. Anything
// laid out against those edges must stay clear of them.
//
// - Top / bottom: handled by Scaffold chrome. AppBar pads the status bar,
//   NavigationBar / MiniPlayer pad the home indicator or gesture bar, and
//   Scaffold strips the bottom inset from its body when a bottom bar exists.
// - Left / right: AppBar, NavigationBar and NavigationRail (wrapped) already
//   pad themselves, but Scaffold bodies do NOT. Wrap every body's content in
//   [SafeSides] so lists, grids and tiles stay out of the cutout while the
//   Scaffold background still paints edge to edge.
// - Full-bleed screens (Now Playing) paint their background under the cutout
//   and position overlays with [MediaQuery.paddingOf] offsets instead — never
//   with bare `left:` / `right:` constants.

/// Pads [child] clear of the left/right system insets (landscape notch,
/// cutout, rounded corners). Top and bottom are left to the Scaffold chrome.
class SafeSides extends StatelessWidget {
  final Widget child;
  const SafeSides({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      SafeArea(top: false, bottom: false, child: child);
}
