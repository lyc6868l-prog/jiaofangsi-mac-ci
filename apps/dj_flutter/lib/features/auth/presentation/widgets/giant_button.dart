import 'package:flutter/material.dart';

enum GiantButtonStyle { primary, guest }

class GiantButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final GiantButtonStyle style;
  final bool isLoading;
  final bool isDisabled;

  const GiantButton({
    super.key,
    required this.text,
    this.onPressed,
    this.style = GiantButtonStyle.primary,
    this.isLoading = false,
    this.isDisabled = false,
  });

  @override
  State<GiantButton> createState() => _GiantButtonState();
}

class _GiantButtonState extends State<GiantButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool effectiveDisabled =
        widget.isDisabled || widget.isLoading || widget.onPressed == null;
    final bool isPrimary = widget.style == GiantButtonStyle.primary;

    BoxDecoration decoration;
    TextStyle textStyle;
    double translateY = 0;

    if (effectiveDisabled) {
      decoration = BoxDecoration(
        color: const Color(0xFF374151),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      );
      textStyle = const TextStyle(
        color: Color(0xFF9CA3AF),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        letterSpacing: 8,
      );
    } else if (isPrimary) {
      double shadowBlur = 15;
      double shadowAlpha = 0.3;
      double offsetY = 4;

      if (_isHovered) {
        shadowBlur = 20;
        shadowAlpha = 0.5;
      }
      if (_isPressed) {
        shadowBlur = 8;
        shadowAlpha = 0.4;
        offsetY = 2;
        translateY = 2;
      }

      decoration = BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFFBE123C), Color(0xFFE11D48), Color(0xFFBE123C)],
          stops: [0, 0.5, 1],
        ),
        border: Border.all(color: const Color(0xFFF43F5E)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE11D48).withValues(alpha: shadowAlpha),
            blurRadius: shadowBlur,
            offset: Offset(0, offsetY),
          ),
        ],
      );
      textStyle = const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        letterSpacing: 8,
      );
    } else {
      double bgAlpha = _isHovered ? 0.1 : 0.05;
      double borderAlpha = _isHovered ? 1.0 : 0.4;

      decoration = BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: borderAlpha),
        ),
        boxShadow: _isHovered
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  blurRadius: 15,
                ),
              ]
            : null,
      );
      textStyle = const TextStyle(
        color: Color(0xFF10B981),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: effectiveDisabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: effectiveDisabled
            ? null
            : (_) => setState(() => _isPressed = true),
        onTapUp: effectiveDisabled
            ? null
            : (_) => setState(() => _isPressed = false),
        onTapCancel: effectiveDisabled
            ? null
            : () => setState(() => _isPressed = false),
        onTap: effectiveDisabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: Matrix4.translationValues(0, translateY, 0),
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: decoration,
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(isPrimary ? 8 : 0, 0),
              child: Text(
                widget.text,
                style: textStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
