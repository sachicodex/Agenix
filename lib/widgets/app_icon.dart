import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

// Importing this file is all a UI file needs to use HugeIcons through AppIcon.
export 'package:hugeicons/hugeicons.dart' show HugeIcons;

/// An icon definition that can be backed by either Material or HugeIcons.
///
/// Use this in reusable widgets and design-system components so callers can
/// select an icon pack without changing the widget's public API.
class AppIconData {
  const AppIconData.material(this.materialIcon) : hugeIcon = null;

  const AppIconData.huge(this.hugeIcon) : materialIcon = null;

  final IconData? materialIcon;
  final List<List<dynamic>>? hugeIcon;
}

/// Renders an [AppIconData] from the selected icon pack.
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.icon,
    this.color,
    this.size,
    this.strokeWidth,
    this.semanticLabel,
  });

  final AppIconData icon;
  final Color? color;
  final double? size;
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final materialIcon = icon.materialIcon;
    if (materialIcon != null) {
      return Icon(
        materialIcon,
        color: color,
        size: size,
        semanticLabel: semanticLabel,
      );
    }

    final hugeIcon = icon.hugeIcon;
    assert(hugeIcon != null, 'AppIconData must contain an icon.');
    return Semantics(
      label: semanticLabel,
      child: HugeIcon(
        icon: hugeIcon!,
        color: color,
        size: size ?? 24,
        strokeWidth: strokeWidth,
      ),
    );
  }
}
