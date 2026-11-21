import 'package:flutter/material.dart';

class TaskItemStatusBadge extends StatelessWidget {
  const TaskItemStatusBadge({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.fontSize = 11,
    this.fontWeight = FontWeight.w700,
    this.letterSpacing = 1,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}
