import 'package:flutter/material.dart';

/// One configurable row in a [ReusableActionMenu].
class ActionMenuItem {
  const ActionMenuItem({
    required this.label,
    required this.onTap,
    this.leading,
    this.trailing,
    this.color,
    this.textStyle,
    this.height = 58,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.dividerAfter = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final Color? color;
  final TextStyle? textStyle;
  final double height;
  final EdgeInsetsGeometry padding;
  final bool dividerAfter;
  final bool enabled;
}

/// A reusable boxed action menu for popup and bottom-sheet actions.
///
/// Each item can use any widget as [ActionMenuItem.leading], including a
/// normal Flutter [Icon], `HugeIcon`, SVG, or a custom widget.
class ReusableActionMenu extends StatelessWidget {
  const ReusableActionMenu({
    super.key,
    required this.items,
    this.header,
    this.footer,
    this.width,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.backgroundColor = const Color(0xFF161616),
    this.borderColor = const Color(0xFF2A2A2A),
    this.borderWidth = 1,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.elevation = 0,
    this.dividerColor = const Color(0xFF2A2A2A),
    this.dividerThickness = 1,
    this.dividerIndent = 18,
    this.dividerEndIndent = 18,
    this.itemColor = const Color(0xFFF4F4F5),
    this.disabledItemColor = const Color(0xFFA1A1AA),
    this.itemTextStyle,
  });

  final List<ActionMenuItem> items;
  final Widget? header;
  final Widget? footer;
  final double? width;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final BorderRadiusGeometry borderRadius;
  final double elevation;
  final Color dividerColor;
  final double dividerThickness;
  final double dividerIndent;
  final double dividerEndIndent;
  final Color itemColor;
  final Color disabledItemColor;
  final TextStyle? itemTextStyle;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (header != null) children.add(header!);
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      children.add(_buildItem(item));
      if (item.dividerAfter && index < items.length - 1) {
        children.add(
          Divider(
            height: dividerThickness,
            thickness: dividerThickness,
            indent: dividerIndent,
            endIndent: dividerEndIndent,
            color: dividerColor,
          ),
        );
      }
    }
    if (footer != null) children.add(footer!);

    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor, width: borderWidth),
        borderRadius: borderRadius,
        boxShadow: elevation == 0
            ? null
            : [BoxShadow(blurRadius: elevation, color: Colors.black54)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildItem(ActionMenuItem item) {
    final enabled = item.enabled && item.onTap != null;
    final color = enabled ? (item.color ?? itemColor) : disabledItemColor;
    final style =
        (item.textStyle ?? itemTextStyle)?.copyWith(color: color) ??
        TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w500);

    return InkWell(
      onTap: enabled ? item.onTap : null,
      child: SizedBox(
        height: item.height,
        child: Padding(
          padding: item.padding,
          child: Row(
            children: [
              if (item.leading != null) item.leading!,
              if (item.leading != null) const SizedBox(width: 16),
              Expanded(child: Text(item.label, style: style)),
              if (item.trailing != null) item.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
