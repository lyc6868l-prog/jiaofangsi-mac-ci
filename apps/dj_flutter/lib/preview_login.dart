// 仅用于 UI 鐐览，不接正式业务
// 此文件不接 AuthController，不接 Python runtime
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'features/auth/presentation/widgets/login_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(480, 680),
    minimumSize: Size(480, 680),
    maximumSize: Size(480, 680),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
  });

  runApp(const LoginPreviewApp());
}

class LoginPreviewApp extends StatelessWidget {
  const LoginPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '教坊司 - 登录预览',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF030303),
        body: Stack(
          children: [
            const LoginCard(),
            Positioned(
              top: 16,
              right: 18,
              child: Row(
                children: [
                  _WindowBtn(type: _WindowBtnType.min),
                  const SizedBox(width: 12),
                  _WindowBtn(type: _WindowBtnType.close),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _WindowBtnType { min, close }

class _WindowBtn extends StatefulWidget {
  final _WindowBtnType type;

  const _WindowBtn({required this.type});

  @override
  State<_WindowBtn> createState() => _WindowBtnState();
}

class _WindowBtnState extends State<_WindowBtn> {
  bool _isHovered = false;

  Future<void> _handlePress() async {
    if (widget.type == _WindowBtnType.min) {
      await windowManager.minimize();
      return;
    }
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final bool isClose = widget.type == _WindowBtnType.close;
    final Color baseColor = const Color(0xFF4B5563);
    final Color activeColor = isClose ? const Color(0xFFF43F5E) : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handlePress,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: isClose
                ? [
                    _line(45, _isHovered ? activeColor : baseColor),
                    _line(-45, _isHovered ? activeColor : baseColor),
                  ]
                : [
                    Container(
                      width: 12,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _isHovered ? activeColor : baseColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: _isHovered
                            ? [
                                BoxShadow(
                                  color: activeColor.withValues(alpha: 0.8),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _line(double angle, Color color) {
    return Transform.rotate(
      angle: angle * 0.0174533,
      child: Container(
        width: 14,
        height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: _isHovered
              ? [BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: 10)]
              : null,
        ),
      ),
    );
  }
}
