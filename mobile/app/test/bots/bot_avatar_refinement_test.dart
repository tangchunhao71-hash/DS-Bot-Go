import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dsh_app/state/bots_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/ui/bots/bot_avatar_editor.dart';
import 'package:dsh_app/ui/bots/bot_character.dart';
import 'package:dsh_app/ui/bots/bot_details_page.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show fakeConnection, loadTestFonts;
import '../shell/golden_harness.dart' show goldenApp;
import 'refinement_harness.dart';
import 'support.dart';

// A self-authored 1x1 GIF89a with two black/white frames (100ms each).
// No photograph or gallery data is needed for animation-preservation tests.
Uint8List twoFrameGif() => Uint8List.fromList([
  ...ascii.encode('GIF89a'),
  1,
  0,
  1,
  0,
  0x80,
  0,
  0,
  0,
  0,
  0,
  255,
  255,
  255,
  for (final color in [0x44, 0x4c]) ...[
    0x21,
    0xf9,
    4,
    0,
    10,
    0,
    0,
    0,
    0x2c,
    0,
    0,
    0,
    0,
    1,
    0,
    1,
    0,
    0,
    2,
    2,
    color,
    1,
    0,
  ],
  0x3b,
]);

class _Host extends ActiveHostController {
  @override
  HostRef build() => HostRef.local;
  @override
  void select(HostRef value) => state = value;
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('native identity has all 20 DS shapes and matches independent default-shape vectors', () {
    expect(botCharacters, hasLength(20));
    for (final entry in {
      '': 'star',
      'm1': 'moon',
      'b2': 'acorn',
      'synthetic-bot': 'bunny',
      '测试-bot': 'bunny',
      '🚀': 'moon',
    }.entries) {
      expect(botDefaultShape(entry.key), entry.value);
    }
    final data = sampleTeam(working: false);
    ((data['bots'] as List).first as Map)['avatar'] = {'shape': 'future-unknown-shape'};
    expect(botShapeOf(DsBotTeam.fromJson(data).bot('m1')!), 'moon');
    ((data['bots'] as List).first as Map)['avatar'] = {'shape': 'whale'};
    expect(botShapeOf(DsBotTeam.fromJson(data).bot('m1')!), 'whale');
  });

  testWidgets('GIF validation keeps both frames and every original byte, while static images stay bounded', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gif = twoFrameGif();
      final original = await ui.instantiateImageCodec(gif);
      expect(original.frameCount, 2);
      original.dispose();
      final prepared = await prepareBotAvatarImage(gif);
      expect(prepared.isGif, isTrue);
      expect(prepared.bytes, orderedEquals(gif));
      expect(prepared.dataUrl, 'data:image/gif;base64,${base64Encode(gif)}');
      final decoded = await ui.instantiateImageCodec(prepared.bytes);
      expect(decoded.frameCount, 2);
      decoded.dispose();
      final png = await prepareBotAvatarImage(base64Decode(tinyPhoto.split(',').last));
      expect(png.isGif, isFalse);
      expect(png.dataUrl.length, lessThanOrEqualTo(botAvatarMaxDataUrlLength));
      final codec = await ui.instantiateImageCodec(png.bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, frame.image.height);
      expect(frame.image.width, lessThanOrEqualTo(160));
      frame.image.dispose();
      codec.dispose();
      final oversized = Uint8List(botAvatarMaxBytes + 1)..setRange(0, gif.length, gif);
      await expectLater(
        prepareBotAvatarImage(oversized),
        throwsA(isA<BotAvatarImageException>().having((e) => e.issue, 'issue', BotAvatarImageIssue.gifTooLarge)),
      );
    });
  });

  testWidgets('working native motion stops for reduced motion, TickerMode and app background', (tester) async {
    Future<void> render({bool ticker = true, bool reduced = false}) async {
      await tester.pumpWidget(
        goldenApp(
          brightness: Brightness.light,
          animations: !reduced,
          home: Scaffold(
            body: TickerMode(
              enabled: ticker,
              child: const BotCharacter(shape: 'moon', color: 'blue', seed: 'm1', size: 96, working: true),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    await render();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await render(reduced: true);
    expect(tester.binding.transientCallbackCount, 0);
    await render(ticker: false);
    expect(tester.binding.transientCallbackCount, 0);
    await render();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<ProviderContainer> openEditor(
    WidgetTester tester,
    FakeDsBotTransport old, {
    required Future<Uint8List?> Function() picker,
    FakeDsBotTransport? next,
  }) async {
    await openRefinement(
      tester,
      const BotDetailsPage(botId: 'm1'),
      old,
      useDefaultTransport: next == null,
      extra: [
        botAvatarImagePickerProvider.overrideWithValue(picker),
        if (next != null) ...[
          activeHostProvider.overrideWith(_Host.new),
          activeConnectionProvider.overrideWith((ref) {
            final host = ref.watch(activeHostProvider);
            return AsyncData(
              HostConnection(
                client: fakeConnection.client,
                label: host.id,
                isLocal: host.isLocal,
                kind: host.kind,
                hostId: host.id,
              ),
            );
          }),
          dsBotApiFactoryProvider.overrideWithValue((c) => DsBotApi(c.isLocal ? old : next)),
        ],
      ],
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(BotDetailsPage)));
    await tester.tap(find.byKey(const ValueKey('bot-avatar-edit')));
    await refinementFrames(tester);
    expect(find.byKey(const ValueKey('bot-avatar-editor')), findsOneWidget);
    return container;
  }

  testWidgets('picking a GIF only previews it; explicit Save writes once and stays busy until settled', (tester) async {
    final pending = Completer<Object?>();
    final gif = twoFrameGif();
    final fake = FakeDsBotTransport(team: sampleTeam(working: false))..handlers['update-bot'] = (_) => pending.future;
    await openEditor(tester, fake, picker: () async => gif);
    await tester.tap(find.byKey(const ValueKey('bot-avatar-pick-image')));
    final save = find.byKey(const ValueKey('bot-avatar-save'));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
      if (tester.widget<FilledButton>(save).onPressed != null) break;
    }
    expect(fake.endpoints.where((e) => e == 'update-bot'), isEmpty);
    await captureRefinement(tester, 'avatar-gif-local-preview');
    final submit = tester.widget<FilledButton>(save).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(fake.endpoints.where((e) => e == 'update-bot'), hasLength(1));
    final payload = fake.calls.singleWhere((c) => c.$1 == 'update-bot').$2;
    expect(jsonEncode(payload), contains('data:image/gif;base64,${base64Encode(gif)}'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('bot-avatar-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-avatar-editor')), findsOneWidget);
    pending.complete(true);
    await refinementFrames(tester);
    expect(find.byKey(const ValueKey('bot-avatar-editor')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picker result after host ABA cannot be saved into either host', (tester) async {
    final image = Completer<Uint8List?>();
    final old = FakeDsBotTransport(team: sampleTeam(working: false));
    final next = FakeDsBotTransport(team: sampleTeam(working: false));
    final container = await openEditor(tester, old, next: next, picker: () => image.future);
    await tester.tap(find.byKey(const ValueKey('bot-avatar-pick-image')));
    await tester.pump();
    container.read(activeHostProvider.notifier).select(const HostRef.ssh('next'));
    await refinementFrames(tester);
    container.read(activeHostProvider.notifier).select(HostRef.local);
    await refinementFrames(tester);
    image.complete(twoFrameGif());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await refinementFrames(tester);
    expect([...old.endpoints, ...next.endpoints].where((e) => e == 'update-bot'), isEmpty);
    final save = find.byKey(const ValueKey('bot-avatar-save'));
    if (save.evaluate().isNotEmpty) expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
