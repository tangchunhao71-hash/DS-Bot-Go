import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

const refinementCaptureKey = ValueKey('refinement-capture');

Future<void> refinementFrames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openRefinement(
  WidgetTester tester,
  Widget page,
  FakeDsBotTransport fake, {
  double width = 390,
  double height = 844,
  double scale = 1,
  Brightness brightness = Brightness.light,
  List<Override> extra = const [],
  bool useDefaultTransport = true,
}) async {
  usePhoneView(tester);
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RepaintBoundary(
      key: refinementCaptureKey,
      child: goldenApp(
        home: page,
        brightness: brightness,
        overrides: [if (useDefaultTransport) ...dsBotOverrides(fake), ...extra],
      ),
    ),
  );
  await refinementFrames(tester);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> captureRefinement(WidgetTester tester, String name) async {
  final path = Platform.environment['DSH_UI_PREVIEW_DIR'];
  if (path == null || path.isEmpty) return;
  final imageContext = tester.element(find.byType(MaterialApp));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  // Animated providers may deliver their first frame through the binding's
  // fake frame clock. Keep advancing that clock while real decoding finishes.
  var decoded = images.isEmpty;
  final decoding = Future.wait([for (final image in images) precacheImage(image.image, imageContext)])
      .then((_) => decoded = true);
  for (var i = 0; i < 60 && !decoded; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(decoded, isTrue, reason: 'Preview image decoding did not complete within 60 bounded frames.');
  await decoding;
  await refinementFrames(tester, 3);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(refinementCaptureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(path)..createSync(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
