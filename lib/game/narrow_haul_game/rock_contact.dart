part of '../narrow_haul_game.dart';

/// Forgiving rock touches (scrape / touchdown) and the shield warning glow.
extension GameRockContact on NarrowHaulGame {
  /// A slow rock touch ([classifyHullContact]): the shield flares (plus a
  /// dust puff on a touchdown), a soft knock, and the first time ever, a
  /// hint that slow touches are safe.
  void _onRockTouch(Vector2 point, Vector2 normal, HullContact kind) {
    if (runState != RunState.playing || demoMode) return;
    if (kind == HullContact.touchdown &&
        salvage.effect == SalvageEffect.fuelLeak) {
      salvage.patchLeak();
      _comms?.say(
        const CommsLine(id: 'salvage_patch', callsign: 'TOWER', text: 'Leak patched. Nice.'),
        urgent: true,
      );
    }
    scrapesThisRun++;
    if (_scrapeFxCooldown > 0) return;
    _scrapeFxCooldown = 0.2;
    final touchdown = kind == HullContact.touchdown;
    final s = ship;
    if (s != null) {
      world.add(
        ShieldFlash(ship: s, rockNormal: normal, strength: touchdown ? 0.55 : 1),
      );
    }
    if (touchdown) {
      world.add(
        DustPuff(
          center: Offset(point.x, point.y),
          normal: Offset(normal.x, normal.y),
          seed: scrapesThisRun,
        ),
      );
    }
    if (_scrapeSoundCooldown <= 0) {
      _scrapeSoundCooldown = NarrowHaulGame._scrapeSoundGap;
      AudioService.playScrape(touchdown: touchdown);
    }
    touchdown ? Haptics.medium() : Haptics.light();
    final progress = ProgressService.instance;
    if (!progress.scrapeHintSeen) {
      progress.markScrapeHintSeen();
      _comms?.say(
        const CommsLine(
          id: 'scrape',
          callsign: 'TOWER',
          text: 'Shields take slow touches. Hit the rock fast and you crash.',
        ),
        urgent: true,
      );
    }
  }

  /// The shield glows toward rock within 1 m, cyan while the ship's speed
  /// into it would only scrape, amber→red when it would crash
  /// ([kScrapeMaxSpeed]); one light buzz when a crash-speed approach is
  /// about to land.
  void _updateRockWarning(ShipBody s, double dt) {
    if (_scrapeFxCooldown > 0) _scrapeFxCooldown -= dt;
    if (_scrapeSoundCooldown > 0) _scrapeSoundCooldown -= dt;
    final glow = _shieldGlow;
    if (glow == null) return;
    if (_proximityBuzzCooldown > 0) _proximityBuzzCooldown -= dt;
    final near = s.launched && !demoMode ? probeRockNearby(world, s) : null;
    if (near == null || near.gap > 1.0) {
      glow.hide();
      return;
    }
    final closeness = 1 - (near.gap / 1.0).clamp(0.0, 1.0);
    // Coming down upright onto flat ground is a touchdown, which is safe
    // at a higher speed than a scrape.
    final up = s.localAccel.length2 > 1e-4
        ? -(s.localAccel.normalized())
        : near.normal;
    final nose = s.body.worldVector(Vector2(0, -1));
    final landing =
        nose.dot(up) >= math.cos(kTouchdownMaxTilt) &&
        near.normal.dot(up) >= math.cos(kTouchdownMaxSlope);
    final limit = landing ? kTouchdownMaxSpeed : kScrapeMaxSpeed;
    // Machinery, turrets and well cores crash at any speed: always red.
    final danger = near.lethal
        ? 1.0
        : ((near.approach - 0.6 * limit) / (0.6 * limit)).clamp(0.0, 1.0);
    glow.show(-near.normal, closeness * closeness, danger);
    if (danger >= 1 &&
        near.approach > 0.05 &&
        near.gap < 0.5 &&
        _proximityBuzzCooldown <= 0) {
      _proximityBuzzCooldown = 1.0;
      Haptics.light();
    }
  }
}
