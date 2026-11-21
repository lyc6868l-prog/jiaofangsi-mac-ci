import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedHalo extends StatefulWidget {
  final Color color;
  final double size;
  final double? height;
  final Duration duration;
  final Duration delay;
  final bool reverse;
  final Alignment alignment;
  final bool useBottomRight;

  const AnimatedHalo({
    super.key,
    required this.color,
    required this.size,
    this.height,
    required this.duration,
    this.delay = Duration.zero,
    this.reverse = false,
    required this.alignment,
    this.useBottomRight = false,
  });

  @override
  State<AnimatedHalo> createState() => _AnimatedHaloState();
}

class _AnimatedHaloState extends State<AnimatedHalo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _translateX;
  late Animation<double> _translateY;
  late Animation<double> _scale;
  late Animation<double> _rotation;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.repeat(reverse: widget.reverse);
      }
    });

    _translateX =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 60), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 60, end: -40), weight: 33),
          TweenSequenceItem(tween: Tween(begin: -40, end: 30), weight: 34),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.4, 0, 0.2, 1),
          ),
        );

    _translateY =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -40), weight: 33),
          TweenSequenceItem(tween: Tween(begin: -40, end: 50), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 50, end: 60), weight: 34),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.4, 0, 0.2, 1),
          ),
        );

    _scale =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.1), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 1.1, end: 0.9), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.2), weight: 34),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.4, 0, 0.2, 1),
          ),
        );

    _rotation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 120), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 120, end: 240), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 240, end: 360), weight: 34),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.4, 0, 0.2, 1),
          ),
        );

    _opacity =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.8), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 33),
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 34),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.4, 0, 0.2, 1),
          ),
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double orbHeight = widget.height ?? widget.size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: widget.useBottomRight ? null : widget.alignment.y * 50,
          bottom: widget.useBottomRight ? widget.alignment.y * 10 : null,
          left: widget.useBottomRight ? null : widget.alignment.x * 50,
          right: widget.useBottomRight ? widget.alignment.x * 10 : null,
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(
                _translateX.value,
                _translateY.value,
                0.0,
                1.0,
              )
              ..scaleByDouble(_scale.value, _scale.value, 1.0, 1.0)
              ..rotateZ(_rotation.value * math.pi / 180),
            alignment: Alignment.center,
            child: Opacity(
              opacity: _opacity.value,
              child: Container(
                width: widget.size,
                height: orbHeight,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ColorFilter.mode(
                      widget.color.withValues(alpha: 0.3),
                      BlendMode.screen,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
