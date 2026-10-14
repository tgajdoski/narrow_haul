import 'dart:async';

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/reminder_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Shows the reminder question over the hangar when it's due
/// ([ReminderService.takeAsk]: after the Training Grounds or a daily, at
/// most twice). Only *Yes* brings up the OS permission prompt, so a "no"
/// here never burns iOS's one system prompt.
void maybeAskForReminders(BuildContext context) {
  if (!ReminderService.takeAsk()) return;
  showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    pageBuilder: (ctx, _, _) => _ReminderAsk(onDone: () => Navigator.of(ctx).pop()),
  );
}

class _ReminderAsk extends StatelessWidget {
  const _ReminderAsk({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return HoloDialog(
      title: 'Radio calls',
      maxWidth: 460,
      footer: Row(
        children: [
          Expanded(
            child: HoloButton(
              label: 'Not now',
              variant: HoloVariant.ghost,
              sound: UiSound.back,
              onPressed: () {
                Analytics.reminderOptIn(on: false, where: 'ask');
                onDone();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: HoloButton.primary(
              label: 'Yes, call me',
              icon: Icons.notifications_active_outlined,
              height: 46,
              fontSize: 14,
              onPressed: () {
                onDone();
                unawaited(ReminderService.enable(where: 'ask'));
              },
            ),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.settings_input_antenna_rounded, color: SpaceColors.cyan, size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Want OPS to call when the daily dispatch is posted or a relief '
              'run is waiting? At most once a day, never while you fly. '
              'You can switch it off in Settings.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
