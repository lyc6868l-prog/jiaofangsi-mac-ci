import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';

class TacticalInput extends StatefulWidget {
  final String label;
  final String placeholder;
  final bool isPassword;
  final TextEditingController? controller;
  final Widget? suffixIcon;
  final VoidCallback? onSuffixPressed;

  const TacticalInput({
    super.key,
    required this.label,
    required this.placeholder,
    this.isPassword = false,
    this.controller,
    this.suffixIcon,
    this.onSuffixPressed,
  });

  @override
  State<TacticalInput> createState() => _TacticalInputState();
}

class _TacticalInputState extends State<TacticalInput> {
  bool _obscureText = true;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSuffix = widget.isPassword || widget.suffixIcon != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isFocused = hasFocus;
            });
          },
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF020202),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused
                    ? const Color(0xFFE11D48).withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.9),
                  offset: const Offset(0, 2),
                  blurRadius: 10,
                  inset: true,
                ),
                if (_isFocused)
                  BoxShadow(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: hasSuffix ? 40 : 16,
                    ),
                    child: TextField(
                      controller: widget.controller,
                      obscureText: _obscureText,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      enableSuggestions: false,
                      autocorrect: false,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 14,
                        height: 1.0,
                        letterSpacing: 1,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.placeholder,
                        hintStyle: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 14,
                          height: 1.0,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        isDense: true,
                        isCollapsed: false,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasSuffix)
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 24,
                      child: _InputIconButton(
                        onPressed: widget.isPassword
                            ? () => setState(() => _obscureText = !_obscureText)
                            : widget.onSuffixPressed,
                        child: widget.isPassword
                            ? Text(
                                _obscureText ? '👁️' : '🙈',
                                style: const TextStyle(fontSize: 12),
                              )
                            : widget.suffixIcon!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InputIconButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const _InputIconButton({required this.child, this.onPressed});

  @override
  State<_InputIconButton> createState() => _InputIconButtonState();
}

class _InputIconButtonState extends State<_InputIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color color = _isHovered
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF6B7280);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IconTheme(
            data: IconThemeData(color: color, size: 14),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: color, fontSize: 14),
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
