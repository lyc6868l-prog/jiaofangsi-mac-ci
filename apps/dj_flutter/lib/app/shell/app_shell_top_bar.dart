import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:window_manager/window_manager.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';

import '../layout/app_layout_contract.dart';
import '../update/app_update_service.dart';
import 'shell_tokens.dart';

const double windowControlButtonSize = 28;
const double windowControlGap = 8;
const double windowControlsHorizontalPadding = 10;
const double userCenterPanelRightOffset =
    2 +
    windowControlsHorizontalPadding +
    (windowControlButtonSize * 3) +
    (windowControlGap * 3);

class AppShellTopBar extends StatelessWidget {
  const AppShellTopBar({
    super.key,
    required this.isUserCenterActive,
    required this.showUserCenterTrigger,
    required this.userCenterAvatarType,
    required this.onUserCenterEnter,
    required this.onUserCenterExit,
    required this.onUserCenterTap,
    this.updateService,
  });

  final bool isUserCenterActive;
  final bool showUserCenterTrigger;
  final String? userCenterAvatarType;
  final VoidCallback onUserCenterEnter;
  final VoidCallback onUserCenterExit;
  final VoidCallback onUserCenterTap;
  final AppUpdateService? updateService;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppLayoutContract.topBarHeight,
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TopLeftBrandImage(),
                  if (updateService != null) ...[
                    const SizedBox(width: 8),
                    _UpdateButton(updateService: updateService!),
                  ],
                ],
              ),
            ),
          ),
          const Expanded(
            child: Align(
              alignment: Alignment.center,
              child: _CenterBrandImage(),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: _WindowControls(
                  isUserCenterActive: isUserCenterActive,
                  showUserCenterTrigger: showUserCenterTrigger,
                  userCenterAvatarType: userCenterAvatarType,
                  onUserCenterEnter: onUserCenterEnter,
                  onUserCenterExit: onUserCenterExit,
                  onUserCenterTap: onUserCenterTap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCenterTrigger extends StatefulWidget {
  const _UserCenterTrigger({
    required this.isActive,
    required this.avatarType,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
  });

  final bool isActive;
  final String? avatarType;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  @override
  State<_UserCenterTrigger> createState() => _UserCenterTriggerState();
}

class _UserCenterTriggerState extends State<_UserCenterTrigger> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = switch (widget.avatarType) {
      'female' => shellAccentPink,
      _ => shellAccentBlue,
    };
    final bool isHighlighted = widget.isActive || _isHovered;
    final Color topLineColor = _isHovered
        ? accentColor.withValues(alpha: _isPressed ? 0.2 : 0.6)
        : Colors.white.withValues(alpha: 0.1);
    final List<BoxShadow> boxShadow = _isPressed
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              offset: const Offset(0, 2),
              blurRadius: 5,
              inset: true,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.8 : 0.5),
              blurRadius: _isHovered ? 8 : 4,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              offset: const Offset(0, 1),
              blurRadius: 0,
              inset: true,
            ),
            if (_isHovered)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.34),
                blurRadius: 15,
              ),
          ];
    final Gradient background = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _isHovered
          ? [
              shellWindowFillTop.withValues(alpha: 0.8),
              shellWindowFillBottom.withValues(alpha: 0.9),
            ]
          : [
              shellWindowFillMid.withValues(alpha: 0.6),
              shellWindowFillBase.withValues(alpha: 0.8),
            ],
    );

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onEnter();
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
          _isPressed = false;
        });
        widget.onExit();
      },
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
            label: '打开用户中心',
            child: Transform.translate(
              offset: Offset(0, _isPressed ? 2 : 0),
              child: AnimatedContainer(
                key: const ValueKey<String>('user_center_trigger'),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: windowControlButtonSize,
                height: windowControlButtonSize,
                decoration: BoxDecoration(
                  gradient: background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.8),
                  ),
                  boxShadow: boxShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(height: 1, color: topLineColor),
                      ),
                      Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CustomPaint(
                            painter: _VipCrownPainter(
                              active: isHighlighted,
                              color: accentColor,
                            ),
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

class _TopLeftBrandImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 164,
        height: 40,
        child: Image.asset(
          'assets/brand/djbjgj.png',
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _CenterBrandImage extends StatelessWidget {
  const _CenterBrandImage();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      height: 40,
      child: Image.asset(
        'assets/brand/denlulogo.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _VipCrownPainter extends CustomPainter {
  const _VipCrownPainter({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: active ? 0.55 : 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    final Path crown = Path()
      ..moveTo(size.width * 0.2, size.height * 0.78)
      ..lineTo(size.width * 0.1, size.height * 0.22)
      ..lineTo(size.width * 0.37, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.16)
      ..lineTo(size.width * 0.63, size.height * 0.5)
      ..lineTo(size.width * 0.9, size.height * 0.22)
      ..lineTo(size.width * 0.8, size.height * 0.78)
      ..close();
    final RRect base = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.8,
        size.width * 0.64,
        size.height * 0.12,
      ),
      const Radius.circular(2),
    );

    canvas.drawPath(crown, glowPaint);
    canvas.drawRRect(base, glowPaint);
    canvas.drawPath(crown, paint);
    canvas.drawRRect(base, paint);
  }

  @override
  bool shouldRepaint(covariant _VipCrownPainter oldDelegate) {
    return oldDelegate.active != active || oldDelegate.color != color;
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls({
    required this.isUserCenterActive,
    required this.showUserCenterTrigger,
    required this.userCenterAvatarType,
    required this.onUserCenterEnter,
    required this.onUserCenterExit,
    required this.onUserCenterTap,
  });

  final bool isUserCenterActive;
  final bool showUserCenterTrigger;
  final String? userCenterAvatarType;
  final VoidCallback onUserCenterEnter;
  final VoidCallback onUserCenterExit;
  final VoidCallback onUserCenterTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            offset: const Offset(0, 2),
            blurRadius: 10,
            inset: true,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: windowControlsHorizontalPadding,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showUserCenterTrigger) ...[
              _UserCenterTrigger(
                isActive: isUserCenterActive,
                avatarType: userCenterAvatarType,
                onEnter: onUserCenterEnter,
                onExit: onUserCenterExit,
                onTap: onUserCenterTap,
              ),
              const SizedBox(width: windowControlGap),
            ],
            const _WindowControlButton(type: _WindowControlType.minimize),
            const SizedBox(width: windowControlGap),
            const _WindowControlButton(type: _WindowControlType.maximize),
            const SizedBox(width: windowControlGap),
            const _WindowControlButton(type: _WindowControlType.close),
          ],
        ),
      ),
    );
  }
}

enum _WindowControlType { minimize, maximize, close }

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({required this.type});

  final _WindowControlType type;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  Future<void> _handleTap() async {
    if (widget.type == _WindowControlType.minimize) {
      await windowManager.minimize();
      return;
    }

    if (widget.type == _WindowControlType.maximize) {
      final bool isFullScreen = await windowManager.isFullScreen();
      if (isFullScreen) {
        await windowManager.setFullScreen(false);
      } else {
        await windowManager.setFullScreen(true);
      }
      return;
    }

    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final Color accentColor = switch (widget.type) {
      _WindowControlType.minimize => shellAccentGreen,
      _WindowControlType.maximize => shellAccentAmber,
      _WindowControlType.close => shellAccentPinkDeep,
    };
    final Color glyphColor = _isHovered ? accentColor : shellTextMuted;
    final Color topLineColor = _isHovered
        ? accentColor.withValues(alpha: _isPressed ? 0.2 : 0.6)
        : Colors.white.withValues(alpha: 0.1);
    final List<BoxShadow> boxShadow = _isPressed
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              offset: const Offset(0, 2),
              blurRadius: 5,
              inset: true,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.8 : 0.5),
              blurRadius: _isHovered ? 8 : 4,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              offset: const Offset(0, 1),
              blurRadius: 0,
              inset: true,
            ),
            if (_isHovered)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.34),
                blurRadius: 15,
              ),
          ];
    final Gradient background = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _isHovered
          ? [
              shellWindowFillTop.withValues(alpha: 0.8),
              shellWindowFillBottom.withValues(alpha: 0.9),
            ]
          : [
              shellWindowFillMid.withValues(alpha: 0.6),
              shellWindowFillBase.withValues(alpha: 0.8),
            ],
    );

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
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: _semanticLabel,
            child: Transform.translate(
              offset: Offset(0, _isPressed ? 2 : 0),
              child: AnimatedContainer(
                key: ValueKey<String>(
                  'shell_window_control_${widget.type.name}',
                ),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.8),
                  ),
                  boxShadow: boxShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(height: 1, color: topLineColor),
                      ),
                      Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: _WindowControlGlyph(
                            type: widget.type,
                            color: glyphColor,
                            glow: _isHovered,
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

  String get _semanticLabel => switch (widget.type) {
    _WindowControlType.minimize => '最小化窗口',
    _WindowControlType.maximize => '切换全屏',
    _WindowControlType.close => '关闭窗口',
  };
}

class _WindowControlGlyph extends StatelessWidget {
  const _WindowControlGlyph({
    required this.type,
    required this.color,
    required this.glow,
  });

  final _WindowControlType type;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final List<BoxShadow>? glowShadow = glow
        ? [BoxShadow(color: color.withValues(alpha: 0.85), blurRadius: 4)]
        : null;

    return Stack(
      alignment: Alignment.center,
      children: switch (type) {
        _WindowControlType.minimize => [
          Container(
            width: 8,
            height: 1.5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              boxShadow: glowShadow,
            ),
          ),
        ],
        _WindowControlType.maximize => [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(1.5),
              boxShadow: glowShadow,
            ),
          ),
        ],
        _WindowControlType.close => [
          _WindowControlStroke(angle: 45, color: color, shadows: glowShadow),
          _WindowControlStroke(angle: -45, color: color, shadows: glowShadow),
        ],
      },
    );
  }
}

class _WindowControlStroke extends StatelessWidget {
  const _WindowControlStroke({
    required this.angle,
    required this.color,
    required this.shadows,
  });

  final double angle;
  final Color color;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle * 0.0174533,
      child: Container(
        width: 8.5,
        height: 1.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: shadows,
        ),
      ),
    );
  }
}

class _UpdateButton extends StatefulWidget {
  const _UpdateButton({required this.updateService});

  final AppUpdateService updateService;

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    widget.updateService.addListener(_onUpdateChanged);
    widget.updateService.checkForUpdate();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    widget.updateService.removeListener(_onUpdateChanged);
    super.dispose();
  }

  void _onUpdateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleTap() async {
    final AppUpdateService svc = widget.updateService;
    switch (svc.status) {
      case AppUpdateStatus.updateAvailable:
        await svc.downloadUpdate();
        break;
      case AppUpdateStatus.downloadComplete:
        await svc.installAndRestart();
        break;
      case AppUpdateStatus.error:
        await svc.checkForUpdate();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUpdateService svc = widget.updateService;
    final bool isVisible = svc.hasUpdate;
    final bool showProgress = svc.status == AppUpdateStatus.downloading;

    if (!isVisible) {
      return const SizedBox.shrink();
    }

    final Color pulseColor = const Color(0xFFFF3B30);
    final Color glyphColor = pulseColor;
    final double pulseAlpha = 0.15 + _pulseAnimation.value * 0.25;
    final List<BoxShadow> boxShadow = _isPressed
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              offset: const Offset(0, 2),
              blurRadius: 5,
              inset: true,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.8 : 0.5),
              blurRadius: _isHovered ? 8 : 4,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              offset: const Offset(0, 1),
              blurRadius: 0,
              inset: true,
            ),
            BoxShadow(
              color: pulseColor.withValues(alpha: pulseAlpha),
              blurRadius: _isHovered ? 18 : 12,
              spreadRadius: _isHovered ? 2 : 0,
            ),
          ];
    final Gradient background = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _isHovered
          ? [
              shellWindowFillTop.withValues(alpha: 0.8),
              shellWindowFillBottom.withValues(alpha: 0.9),
            ]
          : [
              shellWindowFillMid.withValues(alpha: 0.6),
              shellWindowFillBase.withValues(alpha: 0.8),
            ],
    );

    return Tooltip(
      message: svc.status == AppUpdateStatus.downloadComplete
          ? '点击重启以更新'
          : svc.status == AppUpdateStatus.downloading
              ? '正在下载更新...'
              : '发现新版本 ${svc.updateInfo?.version ?? ""}，点击下载',
      preferBelow: false,
      child: MouseRegion(
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
            onTap: _handleTap,
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              label: _semanticLabel,
              child: Transform.translate(
                offset: Offset(0, _isPressed ? 2 : 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: windowControlButtonSize,
                  height: windowControlButtonSize,
                  decoration: BoxDecoration(
                    gradient: background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: pulseColor.withValues(alpha: 0.4 + _pulseAnimation.value * 0.3),
                    ),
                    boxShadow: boxShadow,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (showProgress)
                        SizedBox(
                          width: windowControlButtonSize,
                          height: windowControlButtonSize,
                          child: CircularProgressIndicator(
                            value: svc.downloadProgress,
                            strokeWidth: 2,
                            color: pulseColor,
                          ),
                        ),
                      if (!showProgress)
                        Icon(
                          Icons.download,
                          size: 14,
                          color: glyphColor,
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

  String get _semanticLabel {
    final AppUpdateService svc = widget.updateService;
    return switch (svc.status) {
      AppUpdateStatus.updateAvailable =>
        '发现新版本 ${svc.updateInfo?.version ?? ""}，点击下载',
      AppUpdateStatus.downloading => '正在下载更新',
      AppUpdateStatus.downloadComplete => '下载完成，点击重启以更新',
      AppUpdateStatus.error => '更新失败，点击重试',
      _ => '检查更新中',
    };
  }
}
