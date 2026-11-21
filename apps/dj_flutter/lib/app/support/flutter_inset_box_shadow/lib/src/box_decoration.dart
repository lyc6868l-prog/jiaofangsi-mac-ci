import 'package:flutter/painting.dart' hide BoxShadow, BoxDecoration;
import 'package:flutter/painting.dart' as painting;
import './box_shadow.dart';

class BoxDecoration extends painting.BoxDecoration {
  const BoxDecoration({
    super.color,
    super.image,
    super.border,
    super.borderRadius,
    List<BoxShadow>? boxShadow,
    super.gradient,
    super.backgroundBlendMode,
    super.shape = BoxShape.rectangle,
  }) : super(boxShadow: boxShadow);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _InsetBoxDecorationPainter(this, onChanged);
  }
}

class _InsetBoxDecorationPainter extends BoxPainter {
  _InsetBoxDecorationPainter(this._decoration, VoidCallback? onChanged)
      : super(onChanged);
  final BoxDecoration _decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final Rect rect = offset & configuration.size!;
    final TextDirection? textDirection = configuration.textDirection;

    if (_decoration.boxShadow != null) {
      for (final painting.BoxShadow shadow in _decoration.boxShadow!) {
        if (shadow is BoxShadow && shadow.inset) continue;
        final Paint paint = shadow.toPaint();
        final Rect bounds =
            rect.shift(shadow.offset).inflate(shadow.spreadRadius);
        _paintBox(canvas, bounds, paint, textDirection);
      }
    }

    final Paint backgroundPaint = Paint();
    if (_decoration.backgroundBlendMode != null) {
      backgroundPaint.blendMode = _decoration.backgroundBlendMode!;
    }
    if (_decoration.color != null) {
      backgroundPaint.color = _decoration.color!;
    }
    if (_decoration.gradient != null) {
      backgroundPaint.shader = _decoration.gradient!
          .createShader(rect, textDirection: textDirection);
    }
    _paintBox(canvas, rect, backgroundPaint, textDirection);

    if (_decoration.boxShadow != null) {
      for (final painting.BoxShadow shadow in _decoration.boxShadow!) {
        if (shadow is! BoxShadow || !shadow.inset) continue;
        canvas.save();
        final RRect clipRRect =
            (_decoration.borderRadius?.resolve(textDirection) ??
                    BorderRadius.zero)
                .toRRect(rect);
        canvas.clipRRect(clipRRect);
        final Paint innerPaint = Paint()
          ..color = shadow.color
          ..colorFilter = ColorFilter.mode(shadow.color, BlendMode.srcIn)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma);
        final Rect innerRect = rect.deflate(shadow.spreadRadius);
        final RRect innerRRect =
            (_decoration.borderRadius?.resolve(textDirection) ??
                    BorderRadius.zero)
                .toRRect(innerRect);
        canvas.drawDRRect(
          RRect.fromRectAndRadius(
              rect.inflate(shadow.blurRadius).shift(shadow.offset).inflate(20),
              Radius.zero),
          innerRRect.shift(shadow.offset),
          innerPaint,
        );
        canvas.restore();
      }
    }
    _decoration.border?.paint(canvas, rect,
        shape: _decoration.shape,
        borderRadius: _decoration.borderRadius?.resolve(textDirection),
        textDirection: textDirection);
  }

  void _paintBox(
      Canvas canvas, Rect rect, Paint paint, TextDirection? textDirection) {
    if (_decoration.shape == BoxShape.circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
    } else {
      if (_decoration.borderRadius == null) {
        canvas.drawRect(rect, paint);
      } else {
        canvas.drawRRect(
            _decoration.borderRadius!.resolve(textDirection).toRRect(rect),
            paint);
      }
    }
  }
}
