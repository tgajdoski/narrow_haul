import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/rank_insignia.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Rank insignia (wings / epaulette bars).
class RankBadge extends StatelessWidget {
  const RankBadge({
    super.key,
    required this.kind,
    required this.size,
    this.dimmed = false,
  });
  final InsigniaKind kind;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.3 : 1,
      child: CustomPaint(
        size: Size(size, size),
        painter: _InsigniaPainter(kind),
      ),
    );
  }
}

class _InsigniaPainter extends CustomPainter {
  _InsigniaPainter(this.kind);
  final InsigniaKind kind;

  @override
  void paint(Canvas canvas, Size size) =>
      paintInsignia(canvas, Offset.zero & size, kind);

  @override
  bool shouldRepaint(_InsigniaPainter old) => old.kind != kind;
}

/// Badge + rank title + segmented XP gauge toward the next rank.
class CareerProgress extends StatelessWidget {
  const CareerProgress({
    super.key,
    required this.xp,
    this.badgeSize = 40,
    this.compact = false,
  });
  final int xp;
  final double badgeSize;

  /// One-line form for the hangar top bar (no XP numbers).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rank = rankFor(xp);
    final next = nextRank(rank);
    final (into, step) = stepProgress(xp);
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        RankBadge(kind: rank.insignia, size: badgeSize),
        const SizedBox(width: 10),
        Flexible(
          fit: compact ? FlexFit.loose : FlexFit.tight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rankTitle(xp).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hudLabel(
                  compact ? 11.5 : 12.5,
                  color: SpaceColors.gold,
                  spacing: 1.6,
                ),
              ),
              SizedBox(height: compact ? 4 : 5),
              SizedBox(
                width: compact ? 120 : null,
                child: HoloGauge(
                  value: progressToNext(xp),
                  height: compact ? 4 : 6,
                  segments: compact ? 16 : 24,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  next != null
                      ? '$into / $step XP  ·  next: ${next.title}'
                      : '$into / $step XP  ·  next: ★${prestigeStars(xp) + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class StarIcon extends StatelessWidget {
  const StarIcon({super.key, required this.filled, required this.size});
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _StarPainter(filled: filled),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.filled});
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width / 2;
    final inner = outer * 0.4;

    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -math.pi / 2 + (i * 2 * math.pi / 5);
      final innerAngle = outerAngle + math.pi / 5;
      final ox = cx + outer * math.cos(outerAngle);
      final oy = cy + outer * math.sin(outerAngle);
      final ix = cx + inner * math.cos(innerAngle);
      final iy = cy + inner * math.sin(innerAngle);
      i == 0 ? path.moveTo(ox, oy) : path.lineTo(ox, oy);
      path.lineTo(ix, iy);
    }
    path.close();

    if (filled) {
      if (size.width >= 16) {
        canvas.drawPath(
          path,
          Paint()
            ..color = SpaceColors.gold.withValues(alpha: 0.55)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.12),
        );
      }
      canvas.drawPath(path, Paint()..color = SpaceColors.gold);
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x6600B4D8),
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.filled != filled;
}
