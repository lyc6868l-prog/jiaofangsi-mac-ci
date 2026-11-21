import 'package:flutter/material.dart';

class TaskFileOutcomeTile extends StatelessWidget {
  const TaskFileOutcomeTile({
    super.key,
    required this.title,
    required this.pathLabel,
    required this.pathText,
    required this.trailing,
    this.leading,
    this.secondaryText,
    this.secondaryTextColor = const Color(0xFF10B981),
    this.errorText,
    this.errorTextColor = const Color(0xFFE11D48),
    this.titleStyle,
    this.pathStyle,
    this.contentGap = 14,
    this.trailingGap = 12,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.decoration,
    this.trailingAfter,
  });

  final Widget? leading;
  final String title;
  final String? secondaryText;
  final Color secondaryTextColor;
  final String pathLabel;
  final String pathText;
  final String? errorText;
  final Color errorTextColor;
  final Widget trailing;
  final Widget? trailingAfter;
  final TextStyle? titleStyle;
  final TextStyle? pathStyle;
  final double contentGap;
  final double trailingGap;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration:
          decoration ??
          BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: <Color>[
                Colors.white.withValues(alpha: 0.03),
                Colors.white.withValues(alpha: 0.015),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            SizedBox(width: contentGap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      titleStyle ??
                      theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFD1D5DB),
                      ),
                ),
                if (secondaryText != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    secondaryText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '$pathLabel$pathText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      pathStyle ??
                      theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontFamily: 'monospace',
                      ),
                ),
                if (errorText != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    errorText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: errorTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: trailingGap),
          trailing,
          if (trailingAfter != null) ...<Widget>[
            const SizedBox(width: 10),
            trailingAfter!,
          ],
        ],
      ),
    );
  }
}
