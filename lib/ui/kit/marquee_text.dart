import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';


/// One line of text that scrolls when it doesn't fit, instead of being cut
/// with an ellipsis: it holds at the start, glides to the end, holds, and
/// jumps back. Text that fits is a plain [Text] with no ticker. With
/// animations off ([spaceAnimationsOn]) it falls back to the ellipsis.
class MarqueeText extends StatelessWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.animate,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Overrides [spaceAnimationsOn] (tests).
  final bool? animate;

  @override
  Widget build(BuildContext context) {
    if (!(animate ?? spaceAnimationsOn(context))) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final resolved = DefaultTextStyle.of(context).style.merge(style);
        final tp = TextPainter(
          text: TextSpan(text: text, style: resolved),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final textWidth = tp.width;
        final textHeight = tp.height;
        tp.dispose();
        if (!c.maxWidth.isFinite || textWidth <= c.maxWidth + 0.5) {
          return Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: textAlign,
            style: style,
          );
        }
        return _MarqueeScroller(
          text: text,
          style: style,
          width: c.maxWidth,
          height: textHeight,
          overflow: textWidth - c.maxWidth,
        );
      },
    );
  }
}

class _MarqueeScroller extends StatefulWidget {
  const _MarqueeScroller({
    required this.text,
    required this.style,
    required this.width,
    required this.height,
    required this.overflow,
  });

  final String text;
  final TextStyle? style;
  final double width;
  final double height;
  final double overflow;

  @override
  State<_MarqueeScroller> createState() => _MarqueeScrollerState();
}

class _MarqueeScrollerState extends State<_MarqueeScroller>
    with SingleTickerProviderStateMixin {
  static const _holdStart = 1.2;
  static const _holdEnd = 1.0;
  static const _speed = 30.0; // px/s
  static const _fade = 10.0; // px of soft edge

  late final AnimationController _c = AnimationController(vsync: this);

  /// Overscroll past the text's end, so the last letter clears the fade.
  double get _travel => widget.overflow + _fade;
  double get _scroll => math.max(0.6, _travel / _speed);
  double get _total => _holdStart + _scroll + _holdEnd;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_MarqueeScroller old) {
    super.didUpdateWidget(old);
    if (old.overflow != widget.overflow) _start();
  }

  void _start() {
    _c.duration = Duration(milliseconds: (_total * 1000).round());
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _offset(double v) {
    final t = v * _total;
    if (t <= _holdStart) return 0;
    if (t >= _holdStart + _scroll) return _travel;
    final k = (t - _holdStart) / _scroll;
    return _travel * Curves.easeInOut.transform(k);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: 1,
      softWrap: false,
      style: widget.style,
    );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          child: text,
          builder: (context, child) {
            final dx = _offset(_c.value);
            final left = dx > 0.5 ? _fade / widget.width : 0.0;
            final right = dx < _travel - 0.5 ? _fade / widget.width : 0.0;
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                colors: const [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0, left, 1 - right, 1],
              ).createShader(r),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(-dx, 0),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chamfered shape
// ─────────────────────────────────────────────────────────────────────────────
