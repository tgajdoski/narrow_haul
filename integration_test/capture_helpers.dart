// Frame capture shared by the integration tests that save screenshots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class Capture {
  Capture(this.tester, this.dir);

  final WidgetTester tester;
  final Directory dir;

  /// Pumps live frames for [seconds] of wall-clock time.
  Future<void> wait(double seconds) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Saves the current frame as `<dir>/<name>.png`. [outputWidth] sets the
  /// image width in pixels (height follows the surface aspect); by default
  /// the frame is saved at 1 px per logical pixel.
  Future<void> shot(String name, {int? outputWidth}) async {
    await tester.pump();
    final view = tester.binding.renderViews.first;
    final logical = view.size;
    final scale = outputWidth == null ? 1.0 : outputWidth / logical.width;
    // A surface set with setSurfaceSize that is larger than the window gets
    // scaled down into it at the root layer, so render the first full-size
    // repaint boundary below the root instead.
    final boundary = _fullScreenBoundary(view);
    final ui.Image img;
    if (boundary != null) {
      img = await boundary.toImage(pixelRatio: scale);
    } else {
      // Layer space is physical pixels.
      final dpr = view.flutterView.devicePixelRatio;
      final layer = view.debugLayer! as OffsetLayer;
      img = await layer.toImage(Offset.zero & (logical * dpr), pixelRatio: scale / dpr);
    }
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  static RenderRepaintBoundary? _fullScreenBoundary(RenderView view) {
    final queue = <RenderObject>[view];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (node is RenderRepaintBoundary && node.size == view.size) return node;
      node.visitChildren(queue.add);
    }
    return null;
  }
}
