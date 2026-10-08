import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/services/audio_service.dart';
import 'fonts.dart';

/// One of the kids who helped build the game.
class DeliveredByCrew {
  const DeliveredByCrew(this.name, this.photo);

  final String name;

  /// Square head shot, made by `tool/store/make_credits.sh`. The circle is
  /// applied here, so the file stays a plain JPEG.
  final String photo;
}

/// The "Delivered by" crew, in pop-in order. Adding someone is one line here
/// plus one crop box in `tool/store/make_credits.sh`.
const kDeliveredBy = [
  DeliveredByCrew('Mila', 'assets/credits/mila.jpg'),
  DeliveredByCrew('Mare', 'assets/credits/mare.jpg'),
  DeliveredByCrew('Nina', 'assets/credits/nina.jpg'),
];

const _backdrop = Color(0xFF0B132B); // native splash colour: seamless hand-off
const _accent = Color(0xFF00B4D8);

// Timeline (seconds).
const _titleEnd = 0.4;
const _firstPop = 0.5;
const _popEvery = 0.45;
const _popLength = 0.65;
const _nameDelay = 0.2;
const _nameLength = 0.35;
const _hold = Duration(milliseconds: 600);
const _fadeOut = Duration(milliseconds: 350);

/// "DELIVERED BY" credits: the title, then each crew photo pops in a glowing
/// ring with its name. Shown on the first launch (it covers the game while it
/// loads) and from Settings. It leaves once the animation has played and
/// [ready] has completed; a tap skips ahead, but only after [ready].
class DeliveredByScreen extends StatefulWidget {
  const DeliveredByScreen({
    super.key,
    required this.ready,
    required this.onDone,
    this.crew = kDeliveredBy,
  });

  final Future<void> ready;
  final VoidCallback onDone;
  final List<DeliveredByCrew> crew;

  /// Length of the entrance animation for [count] people.
  static Duration entranceFor(int count) => Duration(
    milliseconds:
        ((_firstPop + _popEvery * math.max(0, count - 1) + _popLength) * 1000)
            .round(),
  );

  @override
  State<DeliveredByScreen> createState() => _DeliveredByScreenState();
}

class _DeliveredByScreenState extends State<DeliveredByScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: DeliveredByScreen.entranceFor(widget.crew.length),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: _fadeOut,
  );
  bool _ready = false;
  bool _leaving = false;
  bool _precached = false;
  int _popsPlayed = 0;

  double get _seconds => _intro.value * _intro.duration!.inMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _intro
      ..addListener(_popSounds)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _maybeLeave(afterHold: true);
      })
      ..forward();
    widget.ready.then((_) {
      if (!mounted) return;
      _ready = true;
      _maybeLeave(afterHold: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final c in widget.crew) {
      precacheImage(AssetImage(c.photo), context, onError: (_, _) {});
    }
  }

  /// A soft click as each photo lands (silent until audio has loaded).
  void _popSounds() {
    while (_popsPlayed < widget.crew.length &&
        _seconds >= _firstPop + _popEvery * _popsPlayed) {
      _popsPlayed++;
      AudioService.playTap();
    }
  }

  Future<void> _maybeLeave({bool afterHold = false}) async {
    if (_leaving || !_ready || !_intro.isCompleted) return;
    if (afterHold) {
      await Future<void>.delayed(_hold);
      if (!mounted || _leaving) return;
    }
    _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _exit.forward();
    if (mounted) widget.onDone();
  }

  void _onTap() {
    if (!_ready) return; // the game underneath isn't there yet
    _leave();
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  /// 0→1 progress of the segment [start, start+length] seconds.
  double _seg(double start, double length) =>
      ((_seconds - start) / length).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: FadeTransition(
        opacity: ReverseAnimation(_exit),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: _backdrop,
            gradient: RadialGradient(
              radius: 1.1,
              colors: [Color(0xFF15224A), _backdrop, Color(0xFF050816)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: CustomPaint(
            painter: const _StarsPainter(),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final avatar = (box.maxHeight * 0.26).clamp(90.0, 160.0);
                  return AnimatedBuilder(
                    animation: _intro,
                    builder: (context, _) => _content(context, avatar),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, double avatar) {
    final title = Curves.easeOutCubic.transform(_seg(0, _titleEnd));
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: title,
              child: Transform.translate(
                offset: Offset(0, -16 * (1 - title)),
                child: Text(
                  'DELIVERED BY',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: kDisplayFont,
                    color: _accent,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            SizedBox(height: avatar * 0.22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.crew.length; i++)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: avatar * 0.16),
                    child: _member(context, widget.crew[i], i, avatar),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _member(BuildContext context, DeliveredByCrew c, int i, double size) {
    final start = _firstPop + _popEvery * i;
    final pop = _seg(start, _popLength);
    final scale = pop == 0 ? 0.0 : Curves.elasticOut.transform(pop);
    final ping = _seg(start, _popLength * 0.8);
    final name = Curves.easeOut.transform(
      _seg(start + _nameDelay, _nameLength),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: size * 1.3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Hook-up "ping": a ring that expands and fades as it lands.
              if (ping > 0 && ping < 1)
                Container(
                  width: size * (1.0 + 0.3 * ping),
                  height: size * (1.0 + 0.3 * ping),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.7 * (1 - ping)),
                      width: 2,
                    ),
                  ),
                ),
              Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent,
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.45),
                        blurRadius: size * 0.18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      c.photo,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: _backdrop),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Opacity(
          opacity: name,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - name)),
            child: Text(
              c.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: kDisplayFont,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A faint fixed starfield (seeded, so it's the same every time).
class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 70; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      paint.color = Colors.white.withValues(
        alpha: 0.08 + rnd.nextDouble() * 0.22,
      );
      canvas.drawCircle(p, 0.6 + rnd.nextDouble() * 0.9, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter oldDelegate) => false;
}
