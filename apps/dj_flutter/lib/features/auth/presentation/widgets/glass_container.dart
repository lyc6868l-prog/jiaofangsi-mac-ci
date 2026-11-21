import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatefulWidget {
  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;

  const GlassContainer({
    super.key,
    required this.child,
    required this.width,
    this.padding = const EdgeInsets.all(40.0),
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with TickerProviderStateMixin {
  late AnimationController _orb1Controller;
  late AnimationController _orb2Controller;
  late AnimationController _orb3Controller;
  late AnimationController _innerBeforeController;
  late AnimationController _innerAfterController;

  @override
  void initState() {
    super.initState();
    _orb1Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    _orb2Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);

    _orb3Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);

    _innerBeforeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _innerAfterController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    _orb3Controller.dispose();
    _innerBeforeController.dispose();
    _innerAfterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          const BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.9),
            blurRadius: 60,
            offset: Offset(0, 20),
          ),
          BoxShadow(
            color: const Color(0xFFE11D48).withValues(alpha: 0.05),
            blurRadius: 40,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(10, 10, 14, 0.95),
                  Color.fromRGBO(5, 5, 6, 0.98),
                ],
              ),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Stack(
              children: [
                _buildGridBackground(),
                _buildHaloOrbs(),
                _buildInnerReflections(),
                _buildBorder(),
                Padding(padding: widget.padding, child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridBackground() {
    return Positioned.fill(child: CustomPaint(painter: _GridPainter()));
  }

  Widget _buildHaloOrbs() {
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _orb1Controller,
            builder: (context, child) {
              final double t = _orb1Controller.value;
              final double translateX = _interpolateKeyframes(t, [
                0.0,
                60.0,
                -40.0,
                30.0,
              ]);
              final double translateY = _interpolateKeyframes(t, [
                0.0,
                -40.0,
                50.0,
                60.0,
              ]);
              final double scale = _interpolateKeyframes(t, [
                0.8,
                1.1,
                0.9,
                1.2,
              ]);
              final double opacity = _interpolateKeyframes(t, [
                0.5,
                0.8,
                1.0,
                0.6,
              ]);

              return Positioned(
                top: widget.width * 0.1 + translateY,
                left: widget.width * 0.15 + translateX,
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: _buildOrb(175, const Color(0xFFE11D48), 0.15),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _orb2Controller,
            builder: (context, child) {
              final double t = _orb2Controller.value;
              final double translateX = _interpolateKeyframes(t, [
                0.0,
                60.0,
                -40.0,
                30.0,
              ]);
              final double translateY = _interpolateKeyframes(t, [
                0.0,
                -40.0,
                50.0,
                60.0,
              ]);
              final double scale = _interpolateKeyframes(t, [
                0.8,
                1.1,
                0.9,
                1.2,
              ]);
              final double opacity = _interpolateKeyframes(t, [
                0.5,
                0.8,
                1.0,
                0.6,
              ]);

              return Positioned(
                bottom: widget.width * 0.1 - translateY,
                right: widget.width * 0.1 - translateX,
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: _buildOrb(225, const Color(0xFF9F1239), 0.15),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _orb3Controller,
            builder: (context, child) {
              final double t = _orb3Controller.value;
              final double translateX = _interpolateKeyframes(t, [
                0.0,
                60.0,
                -40.0,
                30.0,
              ]);
              final double translateY = _interpolateKeyframes(t, [
                0.0,
                -40.0,
                50.0,
                60.0,
              ]);
              final double scale = _interpolateKeyframes(t, [
                0.8,
                1.1,
                0.9,
                1.2,
              ]);
              final double opacity = _interpolateKeyframes(t, [
                0.5,
                0.8,
                1.0,
                0.6,
              ]);

              return Positioned(
                top: widget.width * 0.4 + translateY,
                left: widget.width * 0.4 + translateX,
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: _buildOrb(150, const Color(0xFFF43F5E), 0.1),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(double radius, Color color, double alpha) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.7),
            color.withValues(alpha: alpha * 0.3),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.4, 0.7, 1.0],
        ),
      ),
    );
  }

  Widget _buildInnerReflections() {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _innerBeforeController,
          builder: (context, child) {
            final double t = _innerBeforeController.value;
            final double offsetX = -20 + t * 50;
            final double offsetY = -10 + t * 30;
            final double scale = 0.9 + t * 0.3;
            final double opacity = 0.5 + t * 0.5;

            return Positioned(
              top: -50 + offsetY,
              left: widget.width * 0.1 + offsetX,
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 250,
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(75),
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFE11D48).withValues(alpha: 0.1),
                          const Color(0xFFE11D48).withValues(alpha: 0.05),
                          const Color(0xFFE11D48).withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: _innerAfterController,
          builder: (context, child) {
            final double t = _innerAfterController.value;
            final double offsetX = 30 - t * 50;
            final double offsetY = 20 - t * 30;
            final double scale = 0.9 + t * 0.3;
            final double opacity = 0.5 + t * 0.5;

            return Positioned(
              bottom: -50 + offsetY,
              right: widget.width * 0.1 + offsetX,
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(75),
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFBE123C).withValues(alpha: 0.08),
                          const Color(0xFFBE123C).withValues(alpha: 0.04),
                          const Color(0xFFBE123C).withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBorder() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color.fromRGBO(255, 255, 255, 0.05),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Color.fromRGBO(255, 255, 255, 0.1),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _interpolateKeyframes(double t, List<double> values) {
    if (values.length != 4) return values.first;
    if (t < 0.33) {
      return values[0] + (values[1] - values[0]) * (t / 0.33);
    } else if (t < 0.66) {
      return values[1] + (values[2] - values[1]) * ((t - 0.33) / 0.33);
    } else {
      return values[2] + (values[3] - values[2]) * ((t - 0.66) / 0.34);
    }
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.015)
      ..strokeWidth = 1.0;

    const step = 32.0;

    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
