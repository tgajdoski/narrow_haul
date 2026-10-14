part of '../narrow_haul_game.dart';

/// Screens and overlays, briefing, Garage, back, pause, settings, result-screen ad hooks.
extension GameNavigation on NarrowHaulGame {
  /// Leaves the result screen via [then] (next mission / menu), showing an
  /// interstitial first only when pacing allows. Never on the daily's first
  /// clear or a rank-up, which are moments to celebrate, not interrupt.
  Future<void> leaveResults(Future<void> Function() then) async {
    if (_leavingResults) return; // a button tap and the back key can race
    _leavingResults = true;
    try {
      final rankedUp = lastRunReward?.rankedUp ?? false;
      if (!_lastWinDailyFirst && !rankedUp) {
        await MonetizationService.instance.maybeShowInterstitial();
      }
      await then();
    } finally {
      _leavingResults = false;
    }
  }

  /// 2× coins on the result screen is offered once, when the run paid any.
  bool get canDoubleCurrency =>
      runState == RunState.won &&
      !_currencyDoubled &&
      (lastRunReward?.currency ?? 0) > 0;

  /// Rewarded "2× coins": pays the run's currency a second time.
  Future<void> doubleRunCurrency() async {
    final reward = lastRunReward;
    if (!canDoubleCurrency || reward == null) return;
    _currencyDoubled = true;
    await ProgressService.instance.addCosmeticCurrency(reward.currency);
    lastRunReward = reward.withCurrency(reward.currency * 2);
  }

  /// Rewarded "continue": offered once per attempt after a mistake (not a
  /// meltdown running out), when a safe point from before the crash exists.
  /// After two crashes in a row on a cave level, the game-over screen offers
  /// a Demolition Charge for a rewarded ad (once per level visit).
  bool get canOfferAmmo =>
      runState == RunState.gameOver &&
      !isChallengeMode &&
      !demoMode &&
      !_ammoOffered &&
      currentLevelDef is CaveLevelDef &&
      crashStreak.levelId == currentLevelDef.saveId &&
      crashStreak.count >= 2;

  /// Rewarded: one Demolition Charge into the carried stock (it's on the
  /// rack from the next attempt).
  Future<void> grantRewardedCharge() async {
    _ammoOffered = true;
    _ammoOfferedLevel = currentLevelDef.saveId;
    await ProgressService.instance.addAmmo(kDemoCharge.id, 1);
  }

  Future<void> restartLevel() {
    _logQuit('restart');
    _leaveDemo();
    overlays.removeAll([OverlayIds.gameOver, OverlayIds.pause, OverlayIds.settings]);
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    return loadCurrentLevel(retry: true);
  }

  Future<void> nextLevel() async {
    if (!isChallengeMode) {
      final next = levelIndex < LevelRegistry.totalLevels - 1
          ? levelIndex + 1
          : 0;
      // A mission never flown: brief it over the hangar (Back stays there).
      if (needsBriefing(next)) {
        backToMenu();
        openBriefing(next);
        return;
      }
    }
    overlays.removeAll([OverlayIds.levelComplete, OverlayIds.rankUp, OverlayIds.story]);
    _resetInputState();
    CosmeticsService.clearTrials(); // a trial lasts until its level is won
    if (!isChallengeMode) {
      if (levelIndex < LevelRegistry.totalLevels - 1) {
        levelIndex++;
      } else {
        levelIndex = 0;
      }
    }
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  void backToMenu() {
    PerfMonitor.flightEnded(demoMode ? 'demo' : 'quit');
    // Back online since launch? Ads and store products come back here.
    MonetizationService.instance.refreshIfNeeded();
    _logQuit('menu');
    _leaveDemo();
    overlays.removeAll([OverlayIds.gameOver, OverlayIds.pause, OverlayIds.settings]);
    CosmeticsService.clearTrials();
    // Quitting mid-flight still counts the time flown.
    _recordPlaytime();
    overlays.removeAll([OverlayIds.levelComplete, OverlayIds.rankUp, OverlayIds.story]);
    _recordSpentFuel();
    _resetInputState();
    _clearLevel();
    _resetChallenge();
    _countdown = null;
    _countdownHud?.text = null;
    runState = RunState.menu;
    pauseEngine();
    overlays.add(OverlayIds.menu);
    MusicService.play(MusicService.menuTrack, MusicService.menuVolume);
  }

  /// A flight abandoned mid-air (restart or menu from the pause screen).
  void _logQuit(String reason) {
    if (runState != RunState.playing || demoMode || currentLevel == null) {
      return;
    }
    Analytics.levelQuit(
      levelId: currentLevelDef.saveId,
      reason: reason,
      seconds: elapsedSeconds,
      launched: ship?.launched ?? false,
    );
  }

  /// Hangar → a sub-screen ('levelSelect', 'cosmetics', 'settings'…).
  void openScreen(String key) {
    MonetizationService.instance.refreshIfNeeded();
    overlays.remove(OverlayIds.menu);
    overlays.add(key);
  }

  /// Pause menu → Settings.
  void openSettingsFromPause() {
    overlays.remove(OverlayIds.pause);
    overlays.add(OverlayIds.settings);
  }

  /// Settings → wherever it was opened from (pause menu or hangar).
  void closeSettings() {
    overlays.remove(OverlayIds.settings);
    overlays.add(isPaused ? OverlayIds.pause : OverlayIds.menu);
  }

  /// The rank-up card over the results screen.
  void showRankUp() => overlays.add(OverlayIds.rankUp);

  void closeRankUp() => overlays.remove(OverlayIds.rankUp);

  /// After the result screen's entrance: the world's story outro, the first
  /// time its last mission is delivered (never in a daily). Returns false
  /// when there's none, so the caller shows the rank-up card instead.
  bool showStoryOutroIfDue() {
    if (isChallengeMode || runState != RunState.won) return false;
    final (world, inWorld) = LevelRegistry.worldOf(levelIndex);
    if (inWorld != world.levels.length - 1) return false;
    final key = 'outro_${world.id}';
    if (worldStoryFor(world.id) == null || ProgressService.instance.storySeen(key)) {
      return false;
    }
    storyOutroWorld = world;
    overlays.add(OverlayIds.story);
    return true;
  }

  /// Outro read → the rank-up card if this run earned one.
  void closeStoryOutro() {
    overlays.remove(OverlayIds.story);
    storyOutroWorld = null;
    if (overlays.isActive(OverlayIds.levelComplete) && (lastRunReward?.rankedUp ?? false)) {
      showRankUp();
    }
  }

  /// A sub-screen → back to the hangar (or to the briefing the Garage was
  /// opened from).
  void closeScreen(String key) {
    MonetizationService.instance.refreshIfNeeded();
    overlays.remove(key);
    final back = _garageReturn;
    _garageReturn = null;
    if (key == OverlayIds.cosmetics && back != null) {
      overlays.add(back.under);
      briefingLevel = back.level;
      briefingDaily = false;
      overlays.add(OverlayIds.briefing);
      return;
    }
    overlays.add(OverlayIds.menu);
  }

  /// Briefing → Garage (change tow gear or kit); closing it comes back to
  /// the same briefing.
  void openGarageFromBriefing({String? tab}) {
    garageTab = tab;
    final under = overlays.isActive(OverlayIds.levelSelect)
        ? OverlayIds.levelSelect
        : OverlayIds.menu;
    _garageReturn = (under: under, level: briefingLevel);
    MonetizationService.instance.refreshIfNeeded();
    overlays.removeAll([OverlayIds.briefing, under]);
    overlays.add(OverlayIds.cosmetics);
  }

  String? takeGarageTab() {
    final tab = garageTab;
    garageTab = null;
    return tab;
  }

  /// LAUNCH and NEXT MISSION brief a mission first only when it's new: no
  /// stars yet and not briefed this session, so a crash → hangar → LAUNCH
  /// loop doesn't brief it every time. The star chart always briefs.
  bool needsBriefing(int index) {
    final id = LevelRegistry.defAt(index).saveId;
    return ProgressService.instance.getStarsById(id) == 0 &&
        !_briefed.contains(id);
  }

  /// Star chart / LAUNCH / NEXT MISSION → the mission briefing popup (over
  /// the map or the hangar).
  void openBriefing(int index) {
    briefingLevel = index;
    briefingDaily = false;
    _briefed.add(LevelRegistry.defAt(index).saveId);
    overlays.add(OverlayIds.briefing);
  }

  /// Hangar Daily → today's challenge briefing (over the hangar).
  void openDailyBriefing() {
    briefingLevel = DailyChallengeConfig.peekToday(NarrowHaulGame.unlockedLevelIndices()).$1;
    briefingDaily = true;
    overlays.add(OverlayIds.briefing);
  }

  void closeBriefing() => overlays.remove(OverlayIds.briefing);

  /// Android back / system back. Returns false only on the main menu, where
  /// the app may close; everywhere else it steps back one screen.
  bool handleBack() {
    final active = overlays.activeOverlays;
    final covered = creditsVisible.value || introVisible.value;
    // The briefing pops over the hangar too, so it goes before the
    // hangar's "let the app close" check.
    if (!covered && active.contains(OverlayIds.briefing)) {
      AudioService.playUi(UiSound.back);
      closeBriefing();
      return true;
    }
    if (!covered && active.contains(OverlayIds.menu)) return false;
    AudioService.playUi(UiSound.back);
    if (covered) {
      creditsVisible.value = false;
      introVisible.value = false;
    } else if (active.contains(OverlayIds.rankUp)) {
      closeRankUp();
    } else if (active.contains(OverlayIds.story)) {
      closeStoryOutro();
    } else if (active.contains(OverlayIds.settings)) {
      closeSettings();
    } else if (active.contains(OverlayIds.pause)) {
      resumeGame();
    } else if (active.contains(OverlayIds.levelComplete)) {
      leaveResults(() async => backToMenu());
    } else if (active.contains(OverlayIds.gameOver) || active.contains(OverlayIds.demo)) {
      backToMenu();
    } else if (_garageReturn != null && active.contains(OverlayIds.cosmetics)) {
      closeScreen(OverlayIds.cosmetics);
    } else if (OverlayIds.subScreens
        .any(active.contains)) {
      overlays.removeAll(OverlayIds.subScreens);
      overlays.add(OverlayIds.menu);
    } else if (runState == RunState.playing) {
      pauseGame();
    }
    // Otherwise (crash explosion / delivery celebration): swallow it.
    return true;
  }

  void pauseGame() {
    if (runState != RunState.playing || isPaused || ship == null) return;
    isPaused = true;
    _motion.setActive(false);
    _resetInputState();
    ship?.setInput(rotate: 0, thrust: false);
    pauseEngine();
    overlays.add(OverlayIds.pause);
  }

  void resumeGame() {
    if (!isPaused) return;
    isPaused = false;
    overlays.removeAll([OverlayIds.pause, OverlayIds.settings]);
    resumeEngine();
  }

  /// Pushes persisted settings into the running systems.
  void applySettings() {
    final p = ProgressService.instance;
    AudioService.setEnabled(p.soundEnabled);
    MusicService.setEnabled(p.musicEnabled);
    _hudControls?.leftHanded = p.leftHanded;
    _minimap?.refreshLayout();
  }

  /// The cloud save brought progress from another device: redraw the
  /// hangar so its stars, coins and rank show it.
  void _onCloudSaveMerged() {
    if (!overlays.isActive(OverlayIds.menu)) return;
    overlays
      ..remove(OverlayIds.menu)
      ..add(OverlayIds.menu);
  }
}
