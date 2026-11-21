import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart'
    as inset;
import 'package:dj_flutter/app/layout/app_layout_contract.dart';
import 'package:dj_flutter/app/router/app_router.dart';
import 'package:dj_flutter/features/auth/presentation/models/auth_session_snapshot.dart';

/// 一个高保真的旗舰级硬件按键工作台卡片，支持双层物理结构、缝隙爆光与全局微光追踪。
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
    this.globalMousePosition,
    this.statusColor,
    this.statusLabel,
  });

  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;
  final Offset? globalMousePosition;
  final Color? statusColor;
  final String? statusLabel;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  final GlobalKey _cardKey = GlobalKey();

  // 转换全局/父级坐标为当前卡片局部坐标
  Offset _getLocalMousePos() {
    if (widget.globalMousePosition == null) return Offset.zero;
    final RenderBox? renderBox =
        _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return Offset.zero;
    return renderBox.globalToLocal(widget.globalMousePosition!);
  }

  @override
  Widget build(BuildContext context) {
    final bool isRunning = widget.isActive;
    final Color statusColor =
        widget.statusColor ??
        (isRunning ? const Color(0xFF10B981) : const Color(0xFFD97706));
    final String statusLabel = widget.statusLabel ?? (isRunning ? '运行中' : '待机');

    return Listener(
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) {
        if (_isPressed) {
          setState(() => _isPressed = false);
          widget.onTap();
        }
      },
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _isPressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 50),
          curve: Curves.easeOut,
          child: Container(
            key: _cardKey,
            width: double.infinity,
            height: 125,
            decoration: inset.BoxDecoration(
              color: const Color(0xFF08080A),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                // 1. 底座核心 Inset 阴影 (制造物理挖槽深度)
                const inset.BoxShadow(
                  offset: Offset(0, 4),
                  blurRadius: 15,
                  color: Color(0xE6000000),
                  inset: true,
                ),
                const inset.BoxShadow(
                  offset: Offset(0, 0),
                  blurRadius: 8,
                  color: Color(0xCC000000),
                  inset: true,
                ),
                // 2. 按压时的缝隙爆光 (HTML: .key-slot:active::before)
                if (_isPressed) ...[
                  const inset.BoxShadow(
                    offset: Offset.zero,
                    blurRadius: 25,
                    spreadRadius: 10,
                    color: Color(0xCCE11D48),
                  ),
                  const inset.BoxShadow(
                    offset: Offset.zero,
                    blurRadius: 15,
                    color: Color(0x80E11D48),
                    inset: true,
                  ),
                ] else if (isRunning) ...[
                  // 【改进 3】底部发散光微调：更加贴合底座宽度，增加凝聚感
                  inset.BoxShadow(
                    offset: const Offset(0, 4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    color: const Color(0xFFE11D48).withValues(alpha: 0.5),
                  ),
                ],
                // 3. 外部极细边缘微光
                const inset.BoxShadow(
                  offset: Offset(0, 1),
                  blurRadius: 1,
                  color: Color(0x08FFFFFF),
                ),
              ],
            ),
            padding: const EdgeInsets.all(5),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 【强制要求 1 & 3】高保真底部运行指示灯条：融合发散光，缩小间距
                if (isRunning && !_isPressed)
                  Positioned(
                    bottom: -2, // 稍微下移，增强透射感
                    left: 2,
                    right: 2,
                    height: 4,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFE11D48,
                              ).withValues(alpha: 0.8),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 核心键帽层 (The Keycap)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: const Cubic(0.175, 0.885, 0.32, 1.275),
                  transform: Matrix4.translationValues(
                    0,
                    _isPressed ? 0 : -8,
                    0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      if (!_isPressed)
                        const BoxShadow(
                          offset: Offset(0, 10),
                          blurRadius: 20,
                          color: Color(0xCC000000),
                        )
                      else
                        const BoxShadow(
                          offset: Offset(0, 2),
                          blurRadius: 4,
                          color: Color(0xE6000000),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x0DFFFFFF), Color(0x99141418)],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // 【核心改进 1 & 2】渐变边框绘制层：实现红光向两侧消散
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _KeycapBorderPainter(
                                  isPressed: _isPressed,
                                  isRunning: isRunning,
                                ),
                              ),
                            ),
                            // 全局鼠标追踪微光
                            if (widget.globalMousePosition != null)
                              Positioned.fill(
                                child: _GlobalMouseShimmer(
                                  localPos: _getLocalMousePos(),
                                ),
                              ),
                            // 排版内容
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _StatusIndicator(
                                        color: statusColor,
                                        label: statusLabel,
                                        isActive: isRunning,
                                      ),
                                    ],
                                  ),
                                  _GlowingTitle(
                                    title: widget.title,
                                    isPressed: _isPressed,
                                  ),
                                  Text(
                                    widget.subtitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF8B8F98),
                                      fontWeight: FontWeight.w400,
                                      height: 1.0,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.color,
    required this.label,
    required this.isActive,
  });
  final Color color;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isActive ? 0.6 : 0.4),
                blurRadius: isActive ? 12 : 8,
              ),
              const BoxShadow(
                color: Color(0x4DFFFFFF),
                blurRadius: 2,
                spreadRadius: -1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? color : const Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _GlowingTitle extends StatelessWidget {
  const _GlowingTitle({required this.title, required this.isPressed});
  final String title;
  final bool isPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: Duration(milliseconds: isPressed ? 50 : 400),
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w300,
        color: const Color(0xFFF3F4F6),
        letterSpacing: 1.5,
        shadows: isPressed
            ? [
                const Shadow(
                  offset: Offset(0, 0),
                  blurRadius: 8,
                  color: Color(0xE6FFFFFF),
                ),
                const Shadow(
                  offset: Offset(0, 0),
                  blurRadius: 20,
                  color: Color(0xFFE11D48),
                ),
                const Shadow(
                  offset: Offset(0, 0),
                  blurRadius: 40,
                  color: Color(0xCCE11D48),
                ),
              ]
            : [
                const Shadow(
                  offset: Offset(0, 4),
                  blurRadius: 12,
                  color: Color(0xCC000000),
                ),
              ],
      ),
      child: Text(title),
    );
  }
}

class _GlobalMouseShimmer extends StatelessWidget {
  const _GlobalMouseShimmer({required this.localPos});
  final Offset localPos;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return DecoratedBox(
            decoration: BoxDecoration(
              backgroundBlendMode: BlendMode.screen,
              gradient: RadialGradient(
                center: Alignment(
                  (localPos.dx / size.width) * 2 - 1,
                  (localPos.dy / size.height) * 2 - 1,
                ),
                radius: 450 / (size.shortestSide),
                colors: [
                  const Color(0xFFE11D48).withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 精确控制边框光效的绘制器
class _KeycapBorderPainter extends CustomPainter {
  const _KeycapBorderPainter({
    required this.isPressed,
    required this.isRunning,
  });
  final bool isPressed;
  final bool isRunning;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2; // 稍微加粗边框增强光感

    // 1. 基础边框
    paint.color = isPressed
        ? const Color(0xFFE11D48).withValues(alpha: 0.4)
        : const Color(0x08FFFFFF);
    canvas.drawRRect(rrect, paint);

    // 2. 状态驱动的渐变光效 (ShaderMask 逻辑转换)
    if (!isPressed) {
      // --- 待机/运行态共享的高光 ---
      final Path path = Path()..addRRect(rrect);
      final metrics = path.computeMetrics().first;
      final len = metrics.length;

      // 顶部冷灰高光 (HTML: rgba(255, 255, 255, 0.18))
      paint.shader = null;
      paint.color = const Color(0x2EFFFFFF);
      canvas.drawPath(metrics.extractPath(0, len * 0.25), paint);

      // 左侧冷灰幽光 (HTML: rgba(255, 255, 255, 0.08))
      paint.color = const Color(0x14FFFFFF);
      canvas.drawPath(metrics.extractPath(len * 0.75, len), paint);

      // --- 【核心改进】运行态红光渐变过渡 ---
      if (isRunning) {
        // 创建一个由底部向上衰减的线性渐变 Shader
        // 这个 Shader 会作用于整个 RRect 路径，但通过渐变控制可见度
        paint.shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFE11D48), // 底部最高亮
            const Color(0xFFE11D48).withValues(alpha: 0.4), // 拐角处开始衰减
            Colors.transparent, // 向上消散
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(rect);

        // 绘制整个下半部分的路径，Shader 会自然处理两侧向上的消散
        canvas.drawPath(metrics.extractPath(len * 0.4, len * 0.85), paint);
        paint.shader = null;
      }
    } else {
      // 按压态顶部强光
      final Path path = Path()..addRRect(rrect);
      final metrics = path.computeMetrics().first;
      paint.color = const Color(0xFFE11D48).withValues(alpha: 0.8);
      canvas.drawPath(metrics.extractPath(0, metrics.length * 0.25), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _KeycapBorderPainter oldDelegate) =>
      oldDelegate.isPressed != isPressed || oldDelegate.isRunning != isRunning;
}

class GlassCardGrid extends StatefulWidget {
  const GlassCardGrid({
    super.key,
    required this.currentSection,
    required this.sessionSnapshot,
    required this.onSectionChanged,
  });
  final AppShellSection currentSection;
  final AuthSessionSnapshot sessionSnapshot;
  final ValueChanged<AppShellSection> onSectionChanged;
  @override
  State<GlassCardGrid> createState() => _GlassCardGridState();
}

class _GlassCardGridState extends State<GlassCardGrid> {
  Offset? _mousePosition;

  static const Color _idleColor = Color(0xFFD97706);
  static const Color _lockedColor = Color(0xFFE11D48);

  final List<
    ({String title, String subtitle, AppShellSection section, bool vipOnly})
  >
  _cardConfigs = [
    (
      title: '解锁工具',
      subtitle: '一键解锁加密音乐',
      section: AppShellSection.unlockTool,
      vipOnly: false,
    ),
    (
      title: '音频转码',
      subtitle: '一键mp3/wav/aiff互转',
      section: AppShellSection.audioTranscode,
      vipOnly: true,
    ),
    (
      title: '首拼生成',
      subtitle: '一键生成中文歌曲首拼',
      section: AppShellSection.pinyinGenerator,
      vipOnly: true,
    ),
    (
      title: '曲库整理',
      subtitle: '曲目标题广告清理·查找删除重复歌曲',
      section: AppShellSection.cleanupDup,
      vipOnly: true,
    ),
    (
      title: '信息修改',
      subtitle: '曲目标题修改·批量更换封面',
      section: AppShellSection.metadataEdit,
      vipOnly: true,
    ),
    (
      title: 'U盘备份',
      subtitle: '一键备份U盘·一键恢复U盘',
      section: AppShellSection.usbBackup,
      vipOnly: true,
    ),
  ];

  bool _isLockedSection(int index) {
    final config = _cardConfigs[index];
    return config.vipOnly &&
        widget.sessionSnapshot.isUser &&
        !widget.sessionSnapshot.isVip;
  }

  Color _statusColorForCard(int index) {
    if (widget.currentSection == _cardConfigs[index].section) {
      return const Color(0xFF10B981);
    }
    if (_isLockedSection(index)) {
      return _lockedColor;
    }
    return _idleColor;
  }

  String _statusLabelForCard(int index) {
    if (widget.currentSection == _cardConfigs[index].section) {
      return '运行中';
    }
    if (_isLockedSection(index)) {
      return '请开通会员后使用';
    }
    return '待机';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) => setState(() => _mousePosition = event.position),
      onExit: (_) => setState(() => _mousePosition = null),
      child: SizedBox(
        height: AppLayoutContract.cardZoneHeight,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 第一行
              Expanded(
                child: Row(
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(
                        child: GlassCard(
                          title: _cardConfigs[i].title,
                          subtitle: _cardConfigs[i].subtitle,
                          isActive:
                              widget.currentSection == _cardConfigs[i].section,
                          onTap: () =>
                              widget.onSectionChanged(_cardConfigs[i].section),
                          globalMousePosition: _mousePosition,
                          statusColor: _statusColorForCard(i),
                          statusLabel: _statusLabelForCard(i),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 第二行
              Expanded(
                child: Row(
                  children: [
                    for (int i = 3; i < 6; i++) ...[
                      if (i > 3) const SizedBox(width: 16),
                      Expanded(
                        child: GlassCard(
                          title: _cardConfigs[i].title,
                          subtitle: _cardConfigs[i].subtitle,
                          isActive:
                              widget.currentSection == _cardConfigs[i].section,
                          onTap: () =>
                              widget.onSectionChanged(_cardConfigs[i].section),
                          globalMousePosition: _mousePosition,
                          statusColor: _statusColorForCard(i),
                          statusLabel: _statusLabelForCard(i),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
