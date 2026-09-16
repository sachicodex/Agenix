import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable app bar with an optional bottom border.
class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  const AppBarWidget({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.backgroundColor = const Color(0xFF101010),
    this.foregroundColor,
    this.borderColor = const Color(0xFF2A2A2A),
    this.showBottomBorder = false,
    this.borderWidth = 1,
    this.elevation = 0,
    this.centerTitle,
    this.titleTextStyle,
    this.toolbarTextStyle,
    this.titleSpacing,
    this.toolbarHeight,
    this.leadingWidth,
    this.automaticallyImplyLeading = true,
    this.scrolledUnderElevation = 0,
    this.surfaceTintColor = Colors.transparent,
    this.systemOverlayStyle,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Color backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool showBottomBorder;
  final double borderWidth;
  final double elevation;
  final bool? centerTitle;
  final TextStyle? titleTextStyle;
  final TextStyle? toolbarTextStyle;
  final double? titleSpacing;
  final double? toolbarHeight;
  final double? leadingWidth;
  final bool automaticallyImplyLeading;
  final double scrolledUnderElevation;
  final Color? surfaceTintColor;
  final SystemUiOverlayStyle? systemOverlayStyle;

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: elevation,
      centerTitle: centerTitle,
      titleTextStyle: titleTextStyle,
      toolbarTextStyle: toolbarTextStyle,
      titleSpacing: titleSpacing,
      toolbarHeight: toolbarHeight,
      leadingWidth: leadingWidth,
      automaticallyImplyLeading: automaticallyImplyLeading,
      scrolledUnderElevation: scrolledUnderElevation,
      surfaceTintColor: surfaceTintColor,
      systemOverlayStyle: systemOverlayStyle,
      shape: showBottomBorder && borderColor != null
          ? Border(
              bottom: BorderSide(color: borderColor!, width: borderWidth),
            )
          : null,
    );
  }
}
