import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter/services.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';

import 'shell_tokens.dart';

class GiftRedeemBubble extends StatelessWidget {
  const GiftRedeemBubble({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onClose,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final VoidCallback onClose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: const ValueKey<String>('gift_bubble_panel'),
            width: 280,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF219050A), Color(0xFA0A0005)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66000000)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.9),
                  offset: const Offset(0, 12),
                  blurRadius: 28,
                ),
                BoxShadow(color: const Color(0x22E11D48), blurRadius: 14),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.04),
                  offset: const Offset(0, 1),
                  blurRadius: 1,
                  inset: true,
                ),
              ],
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(height: 1, color: const Color(0xFFE11D48)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Text(
                            '🔐',
                            style: TextStyle(
                              fontSize: 16,
                              color: shellAccentPinkDeep,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '请输入兑换码',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: shellTextPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '请输入或粘贴 16 位兑换码',
                        style: TextStyle(color: shellTextHint, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: shellPanelDark,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.9),
                              offset: const Offset(0, 2),
                              blurRadius: 10,
                              inset: true,
                            ),
                          ],
                        ),
                        child: TextField(
                          key: const ValueKey<String>('gift_redeem_input'),
                          controller: controller,
                          focusNode: focusNode,
                          inputFormatters: const [_RedeemCodeFormatter()],
                          maxLength: 19,
                          buildCounter:
                              (
                                BuildContext context, {
                                required int currentLength,
                                required bool isFocused,
                                required int? maxLength,
                              }) => null,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: shellAccentPinkDeep,
                            fontSize: 15,
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'XXXX-XXXX-XXXX-XXXX',
                            hintStyle: TextStyle(
                              color: shellTextPlaceholder,
                              fontSize: 13,
                              letterSpacing: 0,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText!,
                          key: const ValueKey<String>('gift_redeem_error'),
                          style: const TextStyle(
                            color: shellAccentPink,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _GiftSubmitButton(onTap: onSubmit),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: GestureDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Text(
                        '×',
                        key: ValueKey<String>('gift_bubble_close'),
                        style: TextStyle(
                          color: shellTextMuted,
                          fontSize: 18,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 28,
            bottom: -6,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: shellPanelRedDark,
                  border: Border(
                    right: BorderSide(color: const Color(0x66E11D48)),
                    bottom: BorderSide(color: const Color(0x66E11D48)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      offset: const Offset(2, 2),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftSubmitButton extends StatefulWidget {
  const _GiftSubmitButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GiftSubmitButton> createState() => _GiftSubmitButtonState();
}

class _GiftSubmitButtonState extends State<_GiftSubmitButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
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
          child: Transform.translate(
            offset: Offset(0, _isPressed ? 2 : 0),
            child: Container(
              key: const ValueKey<String>('gift_redeem_submit'),
              height: 36,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _isHovered
                      ? const [Color(0x4DE11D48), Color(0xE60F0F12)]
                      : const [Color(0x33E11D48), Color(0xCC0F0F12)],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black.withValues(alpha: 0.9)),
                boxShadow: [
                  if (_isPressed)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.9),
                      offset: const Offset(0, 2),
                      blurRadius: 5,
                      inset: true,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      offset: const Offset(0, 4),
                      blurRadius: 8,
                    ),
                  if (_isHovered)
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.2),
                      blurRadius: 15,
                    ),
                ],
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 1,
                      color: _isHovered
                          ? const Color(0xFFF43F5E)
                          : const Color(0x99E11D48),
                    ),
                  ),
                  const Center(
                    child: Text(
                      '立即兑换',
                      style: TextStyle(
                        color: shellAccentPinkDeep,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RedeemCodeFormatter extends TextInputFormatter {
  const _RedeemCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String raw = newValue.text
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < raw.length && index < 16; index += 1) {
      if (index > 0 && index % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(raw[index]);
    }
    final String formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
