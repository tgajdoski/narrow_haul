import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

typedef LandingCompleteCallback = void Function();

/// Landing strip: win when **both** cargo and ship are inside the pad sensors.
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

  bool _cargoInside = false;
  bool _shipInside = false;
  bool _fired = false;

  void _sync() {
    if (_fired) return;
    if (_cargoInside && _shipInside) {
      _fired = true;
      onBothLanded();
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await add(
      _PadSensor(
        padCenter: padCenter,
        halfWidth: halfWidth,
        halfHeight: halfHeight,
        filter: filterGoalCargo(),
        onEnter: () {
          _cargoInside = true;
          _sync();
        },
        onExit: () => _cargoInside = false,
        isCargo: true,
      ),
    );
    await add(
      _PadSensor(
        padCenter: padCenter,
        halfWidth: halfWidth,
        halfHeight: halfHeight,
        filter: filterGoalShip(),
        onEnter: () {
          _shipInside = true;
          _sync();
        },
        onExit: () => _shipInside = false,
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
    required this.onExit,
    required this.isCargo,
  }) : super(renderBody: false);

  final Vector2 padCenter;
  final double halfWidth;
  final double halfHeight;
  final Filter filter;
  final void Function() onEnter;
  final void Function() onExit;
  final bool isCargo;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    body.userData = this;
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = padCenter
      ..type = BodyType.static;
    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(halfWidth, halfHeight),
        isSensor: true,
        filter: filter,
      ),
    );
    return b;
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (isCargo && other is CargoTag) onEnter();
    if (!isCargo && other is ShipTag) onEnter();
  }

  @override
  void endContact(Object other, Contact contact) {
    if (isCargo && other is CargoTag) onExit();
    if (!isCargo && other is ShipTag) onExit();
  }
}
