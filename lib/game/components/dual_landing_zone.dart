import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Called when ship and pod are both on the pad. Returns whether the
/// delivery was accepted; a refused one (crash in progress, demo) leaves the
/// zone armed so a later landing still counts.
typedef LandingCompleteCallback = bool Function();

/// Landing strip: win when **both** cargo and ship are inside the pad sensors.
/// The sensors cover the drawn pad box plus [kPadSensorDrop] below it, down
/// into the pad's floor, so whatever rests on that floor counts.
class DualLandingZone extends Component {
  DualLandingZone({
    required this.padCenter,
    required this.halfWidth,
    required this.halfHeight,
    required this.onBothLanded,
  });

  final Vector2 padCenter;
  final double halfWidth;
  final double halfHeight;
  final LandingCompleteCallback onBothLanded;

  _PadSensor? _cargoSensor;
  _PadSensor? _shipSensor;
  bool _fired = false;

  bool get cargoInside => _cargoSensor?.inside ?? false;
  bool get shipInside => _shipSensor?.inside ?? false;

  /// Re-arms the zone (continue after a crash rewinds the flight).
  void reset() => _fired = false;

  /// Re-checks a landing that was refused while it happened (e.g. right
  /// after "continue", when nothing new enters the sensors).
  void recheck() => _sync();

  void _sync() {
    if (_fired) return;
    if (cargoInside && shipInside) _fired = onBothLanded();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await add(
      _cargoSensor = _PadSensor(
        padCenter: padCenter,
        halfWidth: halfWidth,
        halfHeight: halfHeight,
        filter: filterGoalCargo(),
        onEnter: _sync,
        isCargo: true,
      ),
    );
    await add(
      _shipSensor = _PadSensor(
        padCenter: padCenter,
        halfWidth: halfWidth,
        halfHeight: halfHeight,
        filter: filterGoalShip(),
        onEnter: _sync,
        isCargo: false,
      ),
    );
  }
}

class _PadSensor extends BodyComponent with ContactCallbacks {
  _PadSensor({
    required this.padCenter,
    required this.halfWidth,
    required this.halfHeight,
    required this.filter,
    required this.onEnter,
    required this.isCargo,
  }) : super(renderBody: false);

  final Vector2 padCenter;
  final double halfWidth;
  final double halfHeight;
  final Filter filter;
  final void Function() onEnter;
  final bool isCargo;

  /// Fixtures of the tracked body overlapping the sensor. A count, not a
  /// flag: the ship's hull has several fixtures, and one leaving must not
  /// clear the others.
  int _touching = 0;
  bool get inside => _touching > 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    body.userData = this;
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = padCenter + Vector2(0, kPadSensorDrop / 2)
      ..type = BodyType.static;
    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(halfWidth, halfHeight + kPadSensorDrop / 2),
        isSensor: true,
        filter: filter,
      ),
    );
    return b;
  }

  bool _tracks(Object other) => isCargo ? other is CargoTag : other is ShipTag;

  @override
  void beginContact(Object other, Contact contact) {
    if (!_tracks(other)) return;
    _touching++;
    onEnter();
  }

  @override
  void endContact(Object other, Contact contact) {
    if (!_tracks(other)) return;
    if (_touching > 0) _touching--;
  }
}
