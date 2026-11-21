import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

typedef TaskImportEmptyBuilder =
    Widget Function(BuildContext context, bool isDragging);

typedef TaskImportContentBuilder = Widget Function(BuildContext context);

class TaskImportListShell extends StatelessWidget {
  const TaskImportListShell({
    super.key,
    required this.hasItems,
    required this.isDragging,
    required this.onDropDone,
    required this.emptyBuilder,
    required this.contentBuilder,
    this.onDragStateChanged,
    this.onEmptyTap,
    this.header,
    this.isInteractionLocked = false,
    this.disabledOpacity = 1.0,
    this.highlightWhenHasItems = true,
    this.backgroundColor = const Color(0xFF020202),
    this.idleBorderColorWhenEmpty = const Color(0x0DFFFFFF),
    this.idleBorderColorWhenFilled = const Color(0x05FFFFFF),
    this.dragActiveBorderColor = const Color(0xCCE11D48),
    this.idleShadowColor = const Color(0xF2000000),
    this.dragShadowColor = const Color(0x33E11D48),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.inkBorderRadius,
    this.emptyBorderWidth = 2,
    this.filledBorderWidth = 1,
    this.animationDuration = const Duration(milliseconds: 180),
  });

  final bool hasItems;
  final bool isDragging;
  final bool isInteractionLocked;
  final double disabledOpacity;
  final bool highlightWhenHasItems;
  final Future<void> Function(List<XFile> files) onDropDone;
  final ValueChanged<bool>? onDragStateChanged;
  final VoidCallback? onEmptyTap;
  final Widget? header;
  final TaskImportEmptyBuilder emptyBuilder;
  final TaskImportContentBuilder contentBuilder;
  final Color backgroundColor;
  final Color idleBorderColorWhenEmpty;
  final Color idleBorderColorWhenFilled;
  final Color dragActiveBorderColor;
  final Color idleShadowColor;
  final Color dragShadowColor;
  final BorderRadiusGeometry borderRadius;
  final BorderRadius? inkBorderRadius;
  final double emptyBorderWidth;
  final double filledBorderWidth;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final bool showDragHighlight =
        isDragging && (!hasItems || highlightWhenHasItems);
    final Widget panelChild = AnimatedContainer(
      duration: animationDuration,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: showDragHighlight
              ? dragActiveBorderColor
              : (hasItems
                    ? idleBorderColorWhenFilled
                    : idleBorderColorWhenEmpty),
          width: hasItems ? filledBorderWidth : emptyBorderWidth,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: idleShadowColor,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          if (showDragHighlight)
            BoxShadow(
              color: dragShadowColor,
              blurRadius: 24,
              offset: Offset.zero,
            ),
        ],
      ),
      child: hasItems
          ? Column(
              children: <Widget>[
                header ?? const SizedBox.shrink(),
                Expanded(child: contentBuilder(context)),
              ],
            )
          : InkWell(
              borderRadius: inkBorderRadius,
              onTap: onEmptyTap,
              child: Center(child: emptyBuilder(context, isDragging)),
            ),
    );

    final Widget dropTarget = DropTarget(
      onDragEntered: (_) => onDragStateChanged?.call(true),
      onDragExited: (_) => onDragStateChanged?.call(false),
      onDragDone: (DropDoneDetails details) async {
        onDragStateChanged?.call(false);
        await onDropDone(details.files);
      },
      child: panelChild,
    );

    final Widget maybeLocked = isInteractionLocked
        ? IgnorePointer(ignoring: true, child: dropTarget)
        : dropTarget;

    if (disabledOpacity >= 1) {
      return maybeLocked;
    }

    return Opacity(opacity: disabledOpacity, child: maybeLocked);
  }
}
