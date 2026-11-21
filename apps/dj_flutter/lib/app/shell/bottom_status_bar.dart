import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';

import '../app_runtime_config.dart';
import '../layout/app_layout_contract.dart';
import 'shell_tokens.dart';

const double giftActionButtonSize = 28;

class BottomStatusBar extends StatelessWidget {
  const BottomStatusBar({
    super.key,
    required this.onGiftTap,
    required this.hasUnreadGiftSignal,
    required this.ledState,
  });

  final VoidCallback onGiftTap;
  final bool hasUnreadGiftSignal;
  final AppShellLedState ledState;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppLayoutContract.bottomStatusBarHeight,
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: _StatusLedGroup(state: ledState),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _BottomRightUtilityArea(
                onGiftTap: onGiftTap,
                hasUnreadGiftSignal: hasUnreadGiftSignal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum AppShellLedState { init, running, complete, warning, aborted, error }

class _StatusLedGroup extends StatelessWidget {
  const _StatusLedGroup({required this.state});

  final AppShellLedState state;

  @override
  Widget build(BuildContext context) {
    final List<_LedDotVisual> visuals = switch (state) {
      AppShellLedState.init => const [
        _LedDotVisual.off(),
        _LedDotVisual.silver(),
        _LedDotVisual.silver(bright: true),
      ],
      AppShellLedState.running => const [
        _LedDotVisual.off(),
        _LedDotVisual.cyan(bright: true),
        _LedDotVisual.off(),
      ],
      AppShellLedState.complete => const [
        _LedDotVisual.green(),
        _LedDotVisual.green(bright: true),
        _LedDotVisual.green(),
      ],
      AppShellLedState.warning => const [
        _LedDotVisual.green(),
        _LedDotVisual.green(),
        _LedDotVisual.amber(bright: true),
      ],
      AppShellLedState.aborted => const [
        _LedDotVisual.ember(),
        _LedDotVisual.ember(bright: true),
        _LedDotVisual.ember(),
      ],
      AppShellLedState.error => const [
        _LedDotVisual.red(),
        _LedDotVisual.red(bright: true),
        _LedDotVisual.red(),
      ],
    };

    return Container(
      key: const ValueKey<String>('bottom_led_group'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 1),
            offset: const Offset(0, 2),
            blurRadius: 8,
            inset: true,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < visuals.length; index++) ...[
            _StatusLedDot(
              key: ValueKey<String>('bottom_led_dot_$index'),
              visual: visuals[index],
            ),
            if (index < visuals.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _StatusLedDot extends StatelessWidget {
  const _StatusLedDot({super.key, required this.visual});

  final _LedDotVisual visual;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: visual.background,
        boxShadow: [
          BoxShadow(color: visual.glowColor, blurRadius: visual.glowBlur),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.1),
            offset: const Offset(0, -1),
            blurRadius: 3,
            inset: true,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 1),
            offset: const Offset(0, 2),
            blurRadius: 5,
            inset: true,
          ),
          BoxShadow(color: Colors.black.withValues(alpha: 1), blurRadius: 1),
        ],
      ),
      child: Align(
        alignment: const Alignment(-0.2, -0.25),
        child: Container(
          width: 4,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: visual.highlightAlpha),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedDotVisual {
  const _LedDotVisual({
    required this.background,
    required this.glowColor,
    required this.glowBlur,
    required this.highlightAlpha,
  });

  const _LedDotVisual.off()
    : background = shellLedOff,
      glowColor = shellLedOffGlow,
      glowBlur = 0,
      highlightAlpha = 0.18;

  const _LedDotVisual.silver({bool bright = false})
    : background = bright ? shellTextSecondary : shellTextSilver,
      glowColor = bright ? const Color(0x809CA3AF) : const Color(0x409CA3AF),
      glowBlur = bright ? 10 : 6,
      highlightAlpha = bright ? 0.6 : 0.4;

  const _LedDotVisual.cyan({bool bright = false})
    : background = bright ? shellAccentBlue : shellAccentBlueCyanDeep,
      glowColor = bright ? const Color(0xA00284C7) : const Color(0x660284C7),
      glowBlur = bright ? 15 : 8,
      highlightAlpha = bright ? 0.72 : 0.45;

  const _LedDotVisual.green({bool bright = false})
    : background = bright ? shellAccentGreen : shellAccentGreenDeep,
      glowColor = bright ? const Color(0xAA10B981) : const Color(0x66047857),
      glowBlur = bright ? 18 : 8,
      highlightAlpha = bright ? 0.68 : 0.42;

  const _LedDotVisual.amber({bool bright = false})
    : background = bright ? shellAccentAmber : shellAccentAmberDeep,
      glowColor = bright ? const Color(0x99D97706) : const Color(0x55D97706),
      glowBlur = bright ? 12 : 7,
      highlightAlpha = bright ? 0.62 : 0.4;

  const _LedDotVisual.ember({bool bright = false})
    : background = bright ? shellAccentEmber : shellAccentEmberDeep,
      glowColor = bright ? const Color(0x809A3412) : const Color(0x40451A03),
      glowBlur = bright ? 8 : 4,
      highlightAlpha = bright ? 0.35 : 0.18;

  const _LedDotVisual.red({bool bright = false})
    : background = bright ? shellAccentRed : shellAccentDangerDeep,
      glowColor = bright ? const Color(0xAADC2626) : const Color(0x66DC2626),
      glowBlur = bright ? 20 : 10,
      highlightAlpha = bright ? 0.78 : 0.48;

  final Color background;
  final Color glowColor;
  final double glowBlur;
  final double highlightAlpha;
}

class _BottomRightUtilityArea extends StatelessWidget {
  const _BottomRightUtilityArea({
    required this.onGiftTap,
    required this.hasUnreadGiftSignal,
  });

  final VoidCallback onGiftTap;
  final bool hasUnreadGiftSignal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _GiftActionButton(highlighted: hasUnreadGiftSignal, onTap: onGiftTap),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(
            appVersionLabel,
            key: const ValueKey<String>('bottom_version_label'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: shellTextMuted,
              fontFamily: 'monospace',
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _GiftActionButton extends StatefulWidget {
  const _GiftActionButton({required this.highlighted, required this.onTap});

  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_GiftActionButton> createState() => _GiftActionButtonState();
}

class _GiftActionButtonState extends State<_GiftActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double hoverLift = _isPressed ? 1 : 0;
    final double glowBlur = widget.highlighted ? 8 : (_isHovered ? 6 : 0);
    final Color glowColor = widget.highlighted
        ? const Color(0x80E11D48)
        : const Color(0x66F43F5E);
    final Color topLineColor = widget.highlighted
        ? shellAccentPink
        : (_isHovered ? shellAccentPink : const Color(0x80E11D48));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: '福利兑换',
            child: Transform.translate(
              offset: Offset(0, hoverLift),
              child: Container(
                key: const ValueKey<String>('gift_widget_button'),
                width: giftActionButtonSize,
                height: giftActionButtonSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      shellWindowFillMid.withValues(alpha: 0.9),
                      shellWindowFillBase.withValues(alpha: 0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.9),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      offset: const Offset(0, 1),
                      blurRadius: 3,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      offset: const Offset(0, 1),
                      blurRadius: 1,
                      inset: true,
                    ),
                    if (widget.highlighted || _isHovered)
                      BoxShadow(color: glowColor, blurRadius: glowBlur),
                    if (_isPressed)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        offset: const Offset(0, 1),
                        blurRadius: 3,
                        inset: true,
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(height: 1, color: topLineColor),
                      ),
                      Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CustomPaint(
                            painter: _GiftBoxIconPainter(
                              color: _isHovered
                                  ? shellAccentPink
                                  : shellAccentPinkDeep,
                              glow: widget.highlighted || _isHovered,
                            ),
                          ),
                        ),
                      ),
                      if (widget.highlighted)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: shellAccentPinkDeep,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: shellPanelBlack,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: shellAccentPinkDeep.withValues(
                                    alpha: 0.8,
                                  ),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GiftBoxIconPainter extends CustomPainter {
  const _GiftBoxIconPainter({required this.color, required this.glow});

  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Rect lidRect = Rect.fromLTWH(
      size.width * 0.125,
      size.height * 0.25,
      size.width * 0.75,
      size.height * 0.125,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lidRect, const Radius.circular(2)),
      strokePaint,
    );

    final Path body = Path()
      ..moveTo(size.width * 0.15625, size.height * 0.375)
      ..lineTo(size.width * 0.15625, size.height * 0.8125)
      ..quadraticBezierTo(
        size.width * 0.15625,
        size.height * 0.90625,
        size.width * 0.25,
        size.height * 0.90625,
      )
      ..lineTo(size.width * 0.75, size.height * 0.90625)
      ..quadraticBezierTo(
        size.width * 0.84375,
        size.height * 0.90625,
        size.width * 0.84375,
        size.height * 0.8125,
      )
      ..lineTo(size.width * 0.84375, size.height * 0.375);
    canvas.drawPath(body, strokePaint);

    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.25),
      Offset(size.width * 0.5, size.height * 0.90625),
      strokePaint,
    );

    final Path leftBow = Path()
      ..moveTo(size.width * 0.5, size.height * 0.25)
      ..lineTo(size.width * 0.34375, size.height * 0.25)
      ..quadraticBezierTo(
        size.width * 0.1875,
        size.height * 0.25,
        size.width * 0.1875,
        size.height * 0.09375,
      )
      ..quadraticBezierTo(size.width * 0.1875, 0, size.width * 0.3125, 0)
      ..quadraticBezierTo(
        size.width * 0.46875,
        0,
        size.width * 0.5,
        size.height * 0.25,
      );
    canvas.drawPath(leftBow, strokePaint);

    final Path rightBow = Path()
      ..moveTo(size.width * 0.5, size.height * 0.25)
      ..lineTo(size.width * 0.65625, size.height * 0.25)
      ..quadraticBezierTo(
        size.width * 0.8125,
        size.height * 0.25,
        size.width * 0.8125,
        size.height * 0.09375,
      )
      ..quadraticBezierTo(size.width * 0.8125, 0, size.width * 0.6875, 0)
      ..quadraticBezierTo(
        size.width * 0.53125,
        0,
        size.width * 0.5,
        size.height * 0.25,
      );
    canvas.drawPath(rightBow, strokePaint);

    if (glow) {
      final Paint highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.28)
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawRRect(
        RRect.fromRectAndRadius(lidRect, const Radius.circular(2)),
        highlightPaint,
      );
      canvas.drawPath(body, highlightPaint);
      canvas.drawLine(
        Offset(size.width * 0.5, size.height * 0.25),
        Offset(size.width * 0.5, size.height * 0.90625),
        highlightPaint,
      );
      canvas.drawPath(leftBow, highlightPaint);
      canvas.drawPath(rightBow, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GiftBoxIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.glow != glow;
  }
}
