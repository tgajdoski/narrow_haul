import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where feedback and ideas go: the same mailbox as the website's support
/// page (`website/index.html`, `SITE.email`).
const kFeedbackEmail = 'contact@zafrk.com';

/// The pre-filled mail: a blank space to write in, then the details that
/// help answer it (version, OS, the mission and rank the player is on).
@visibleForTesting
Uri feedbackMailUri({
  required String version,
  required String os,
  required String levelId,
  required String rank,
}) {
  final body =
      '\n\n\n'
      '— please keep for the developer —\n'
      'App $version · $os\n'
      'Mission $levelId · $rank';
  // Uri(queryParameters:) encodes spaces as '+', which mail apps show
  // literally, so build the query by hand.
  return Uri.parse(
    'mailto:$kFeedbackEmail'
    '?subject=${Uri.encodeComponent('Narrow Haul feedback')}'
    '&body=${Uri.encodeComponent(body)}',
  );
}

/// Opens the mail app with a feedback mail. Without one, a SnackBar shows
/// the address with a Copy action. [source] goes to analytics.
Future<void> openFeedbackMail(
  BuildContext context, {
  required String levelId,
  required String source,
}) async {
  Analytics.log('feedback_opened', {'source': source});
  final messenger = ScaffoldMessenger.maybeOf(context);
  var version = '?';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version}+${info.buildNumber}';
  } catch (_) {}
  final uri = feedbackMailUri(
    version: version,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    levelId: levelId,
    rank: rankTitle(CareerService.xp),
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (opened || messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: const Text('No mail app found. Write to $kFeedbackEmail'),
      action: SnackBarAction(
        label: 'Copy',
        onPressed: () =>
            Clipboard.setData(const ClipboardData(text: kFeedbackEmail)),
      ),
    ),
  );
}
