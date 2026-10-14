
import 'package:flutter/material.dart';

import 'shapes.dart';


class ChamferBorder extends ShapeBorder {
  const ChamferBorder({this.cut = 12});
  final double cut;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      chamferPath(rect, cut);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      chamferPath(rect, cut);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ChamferBorder(cut: cut * t);
}

/// A [ChamferBorder] that also strokes its outline.
extension ChamferSides on ChamferBorder {
  ShapeBorder copyWithSide(BorderSide side) => _SidedChamfer(cut, side);
}

class _SidedChamfer extends ChamferBorder {
  const _SidedChamfer(double cut, this.side) : super(cut: cut);
  final BorderSide side;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
      chamferPath(rect.deflate(side.width / 2), cut),
      Paint()
        ..color = side.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width,
    );
  }
}
