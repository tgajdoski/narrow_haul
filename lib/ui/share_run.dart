import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:share_plus/share_plus.dart';

/// The game's site: one link for both stores (the iPhone smart banner and
/// the store badges take it from there), with a preview image for chats.
const kShareUrl = 'https://zafrk.com/narrow-haul/';

/// What the pilot sends a friend after a delivery. A daily names the tier's
/// shared board ("every Line pilot flies this one today"), so it reads as a
/// challenge; a career run names the mission and what it carried.
String shareRunText({
  required String mission,
  required String world,
  required int stars,
  required String time,
  required int fuelPct,
  String? cargo,
  String? badge,
  String? dailyTier,
}) {
  final starText = stars > 0 ? '${'★' * stars}${'☆' * (3 - stars)} · ' : '';
  final result = '$starText$time · $fuelPct% fuel left';
  final extra = badge == null ? '' : ' $badge.';
  if (dailyTier != null) {
    return "Today's Narrow Haul dispatch ($dailyTier pilots): "
        'delivered in $result.$extra Can you beat it? $kShareUrl';
  }
  final what = cargo == null ? 'Delivered' : 'Hauled ${cargo.toLowerCase()}';
  return '$what through "$mission" ($world) in Narrow Haul: '
      '$result.$extra $kShareUrl';
}

/// Opens the system share sheet with [text]. [origin] is the tapped
/// button's box, which the iPad's popover needs. Without a share sheet the
/// text goes to the clipboard and a SnackBar says so.
Future<void> shareRun(
  BuildContext context,
  String text, {
  required String levelId,
  required bool daily,
}) async {
  Analytics.runShared(levelId, daily: daily);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  try {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Narrow Haul', sharePositionOrigin: origin),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(
      const SnackBar(content: Text('Copied to the clipboard')),
    );
  }
}
