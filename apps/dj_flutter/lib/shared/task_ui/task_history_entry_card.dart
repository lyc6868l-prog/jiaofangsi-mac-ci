import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'task_item_status_badge.dart';

class TaskHistoryEntryCard extends StatelessWidget {
  const TaskHistoryEntryCard({
    super.key,
    required this.title,
    required this.summaryText,
    required this.metaText,
    required this.accentColor,
    required this.pulseValue,
    required this.badgeLabel,
    required this.onTap,
    required this.onClear,
    this.clearKey,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  final String title;
  final String summaryText;
  final String metaText;
  final Color accentColor;
  final double pulseValue;
  final String badgeLabel;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final Key? clearKey;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double pulse =
        0.55 + ((math.sin(pulseValue * math.pi * 2) + 1) * 0.5 * 0.45);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: <Color>[
              accentColor.withValues(alpha: 0.14 + pulse * 0.08),
              accentColor.withValues(alpha: 0.06 + pulse * 0.04),
            ],
          ),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.55 + pulse * 0.2),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accentColor.withValues(alpha: 0.1 + pulse * 0.12),
              blurRadius: 14 + pulse * 8,
              offset: Offset.zero,
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.18 + pulse * 0.16),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '⏺',
                  style: TextStyle(
                    color: accentColor.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summaryText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: accentColor.withValues(alpha: 0.95),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD1D5DB),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                TaskItemStatusBadge(
                  label: badgeLabel,
                  foreground: accentColor,
                  background: accentColor.withValues(alpha: 0.14),
                  border: accentColor.withValues(alpha: 0.42),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  key: clearKey,
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    '清除记录',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
