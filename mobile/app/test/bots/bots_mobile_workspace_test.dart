// Real-widget mobile scenarios for the team/conversation redesign. All data
// comes from the scripted transport; the optional PNG export is task-local.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_app/ui/bots/bots_page.dart';
import 'package:dsh_app/ui/chat/composer.dart';
import 'package:dsh_app/ui/chat/render/markdown_body.dart';
import 'package:dsh_app/ui/features/feature_kit.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

const _captureKey = ValueKey('mobile-workspace-preview');

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(
  WidgetTester tester,
  Widget page,
  FakeDsBotTransport fake, {
  double width = 390,
  double height = 844,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  usePhoneView(tester);
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: goldenApp(home: page, brightness: brightness, overrides: dsBotOverrides(fake)),
    ),
  );
  await _frames(tester);
  // Image decoding happens outside the fake frame clock, as in the shared
  // golden harness. Let the synthetic avatar finish before taking a preview.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 100));
}

// Export actual Flutter render output only when explicitly requested by the
// task runner. Normal CI runs have no screenshot side effects.
Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['DSH_UI_PREVIEW_DIR'];
  if (dir == null || dir.isEmpty) return;
  // Chips, tab fills and sheet chrome use short Material animations even
  // when the app's repeating animations are disabled by the harness.
  await _frames(tester, 3);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final output = Directory(dir)..createSync(recursive: true);
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${output.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Map<String, Object?> _questionTeam() => sampleTeam(
  working: false,
  questions: {
    'm1c': {
      'id': 'mobile-q1',
      'question': '演示脚本交给 Coder 吗？',
      'options': [
        {'label': '交给 Coder'},
        {'label': '我自己写'},
      ],
    },
  },
);

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('team search route filters names, roles and rooms; clearing and closing restore the roster', (
    tester,
  ) async {
    final fake = FakeDsBotTransport();
    await _open(tester, const BotsPage(), fake);
    expect(find.byKey(const ValueKey('team-main-m1')), findsOneWidget);
    await _capture(tester, 'team-390-light');
    expect(find.byWidgetPredicate((w) => w is Hero && w.tag == 'dsbot-search-bar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bots-team-search')));
    await _frames(tester);
    final search = find.byKey(const ValueKey('bot-search-input'));
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.enterText(search, '写手');
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-search-bot-b2')), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-search-bot-m1')), findsNothing);
    expect(find.byKey(const ValueKey('team-main-m1')), findsNothing);
    expect(find.byKey(const ValueKey('bot-search-room-r1')), findsNothing);
    await tester.enterText(search, '发布会');
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-search-room-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-search-bot-b2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bot-search-filter-bots')));
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-search-room-r1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bot-search-filter-rooms')));
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-search-room-r1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bot-search-filter-all')));
    await tester.enterText(search, 'no-such-agent');
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-search-room-r1')), findsNothing);
    expect(find.byKey(const ValueKey('bot-search-bot-b2')), findsNothing);
    await _capture(tester, 'team-search-empty');
    await tester.tap(find.byKey(const ValueKey('bot-search-clear')));
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-search-bot-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-search-room-r1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bot-search-close')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('team-main-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-room-r1')), findsOneWidget);
    expect(fake.endpoints.where((e) => !['hello', 'state', 'notices', 'avatar'].contains(e)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team attention opens its Bot without performing an approval or answer', (tester) async {
    final fake = FakeDsBotTransport(team: _questionTeam());
    await _open(tester, const BotsPage(), fake, width: 412, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('bots-team-attention')));
    await _frames(tester, 4);
    expect(find.byKey(const ValueKey('bots-team-attention-sheet')), findsOneWidget);
    await _capture(tester, 'team-attention-412-dark');
    await tester.tap(find.byKey(const ValueKey('team-attention-bot-m1')));
    await _frames(tester);
    expect(find.byType(BotChatPage), findsOneWidget);
    expect(fake.endpoints.where((e) => ['answer-question', 'view-reply', 'approval-answer'].contains(e)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team search remains reachable at 320dp with large text and a keyboard', (tester) async {
    await _open(tester, const BotsPage(), FakeDsBotTransport(), width: 320, scale: 2);
    await tester.tap(find.byKey(const ValueKey('bots-team-search')));
    await _frames(tester);
    final search = find.byKey(const ValueKey('bot-search-input'));
    await tester.enterText(search, 'Writer');
    tester.view.viewInsets = const FakeViewPadding(bottom: 560);
    await _frames(tester, 3);
    expect(find.byKey(const ValueKey('bot-search-bot-b2')), findsOneWidget);
    expect(tester.getRect(search).bottom, lessThanOrEqualTo(844 - 280));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'team-320-large-text-keyboard');
    await tester.tap(find.byKey(const ValueKey('bot-search-bot-b2')));
    await _frames(tester);
    expect(find.byType(BotChatPage), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-search-page')), findsNothing);
  });

  for (final width in [320.0, 390.0, 412.0]) {
    testWidgets('conversation ${width.toInt()}dp retains the composer above the keyboard', (tester) async {
      await _open(
        tester,
        const BotChatPage(botId: 'b2'),
        FakeDsBotTransport(),
        width: width,
        scale: width == 320 ? 2 : 1,
        brightness: width == 412 ? Brightness.dark : Brightness.light,
      );
      if (width == 390 || width == 412) await _capture(tester, 'chat-${width.toInt()}-reading');
      await tester.enterText(find.byType(TextField), '合成测试草稿，尚未发送');
      tester.view.viewInsets = const FakeViewPadding(bottom: 560);
      await _frames(tester, 3);
      final composer = tester.getRect(find.byType(Composer));
      expect(composer.bottom, lessThanOrEqualTo(844 - 280));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '合成测试草稿，尚未发送');
      expect(tester.takeException(), isNull);
      await _capture(tester, 'chat-${width.toInt()}-keyboard');
    });
  }

  testWidgets('a pending question is contextual and remains answerable at 320dp with large text', (tester) async {
    final fake = FakeDsBotTransport(team: _questionTeam());
    fake.handlers['answer-question'] = (_) => true;
    await _open(tester, const BotChatPage(botId: 'm1'), fake, width: 320, scale: 2);
    expect(find.text('交给 Coder'), findsNothing);
    expect(find.byType(Composer), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bot-pending-actions')));
    await _frames(tester, 4);
    expect(find.byKey(const ValueKey('bot-context-sheet')), findsOneWidget);
    final option = find.text('交给 Coder');
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bot-context-results-tab')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bot-context-pending-tab')));
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, '发送');
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.ensureVisible(submit);
    await _capture(tester, 'pending-question-320-large-text');
    await tester.tap(submit);
    await _frames(tester, 4);
    expect(fake.calls.singleWhere((call) => call.$1 == 'answer-question').$2, {
      'sessionId': 'm1c',
      'questionId': 'mobile-q1',
      'answer': {
        'selected': ['交给 Coder'],
      },
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('a busy answer survives tab changes and blocks dismissal until it settles', (tester) async {
    final gate = Completer<Object?>();
    final fake = FakeDsBotTransport(team: _questionTeam())..handlers['answer-question'] = (_) => gate.future;
    await _open(tester, const BotChatPage(botId: 'm1'), fake);
    await openBotPendingActions(tester);
    await tester.tap(find.text('交给 Coder'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await _frames(tester, 2);
    await tester.tap(find.byKey(const ValueKey('bot-context-results-tab')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bot-context-pending-tab')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '发送')).onPressed, isNull);
    final sheet = find.byKey(const ValueKey('bot-context-sheet'));
    await tester.tap(find.byKey(const ValueKey('bot-context-close')));
    await Navigator.of(tester.element(sheet)).maybePop();
    await _frames(tester, 2);
    expect(sheet, findsOneWidget);
    expect(fake.endpoints.where((e) => e == 'answer-question'), hasLength(1));
    gate.complete(true);
    await _frames(tester, 4);
    await tester.tap(find.byKey(const ValueKey('bot-context-close')));
    await _frames(tester, 4);
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty landscape conversation scrolls its intro above a short keyboard viewport', (tester) async {
    final fake = FakeDsBotTransport(team: sampleTeam(working: false))..chatItems = [];
    await _open(tester, const BotChatPage(botId: 'b2'), fake, width: 640, height: 360);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await _frames(tester, 3);
    expect(find.byType(Composer), findsOneWidget);
    expect(tester.getRect(find.byType(Composer)).bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'chat-empty-landscape-keyboard');
  });

  testWidgets('result panel retains and copies the complete reply including its final paragraph', (tester) async {
    final longText = [
      '# 合成结果',
      for (var i = 0; i < 20; i++) '第 $i 段：用于检查长结果滚动与复制，路径 `docs/launch.md` 仅为回复文字。',
      'SYNTHETIC_RESULT_END_4207',
    ].join('\n\n');
    final fake = FakeDsBotTransport(team: sampleTeam(working: false));
    fake.chatItems = [
      {'kind': 'bot', 'text': longText, 'time': todayAt(10, 15).millisecondsSinceEpoch},
    ];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _open(tester, const BotChatPage(botId: 'b2'), fake, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('bot-results')));
    await _frames(tester, 4);
    final sheet = find.byKey(const ValueKey('bot-context-sheet'));
    expect(sheet, findsOneWidget);
    final bodies = tester.widgetList<MarkdownBody>(find.descendant(of: sheet, matching: find.byType(MarkdownBody)));
    expect(bodies.any((body) => body.text == longText), isTrue);
    await _capture(tester, 'results-long-390-dark');
    await tester.tap(find.byKey(const ValueKey('bot-result-copy-0')));
    await tester.pump();
    expect(copied, longText);
    expect(copied, endsWith('SYNTHETIC_RESULT_END_4207'));
    expect(
      fake.endpoints.where((e) => ['send', 'answer-question', 'view-reply', 'approval-answer'].contains(e)),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('team loading and failed states render and retry to a populated team', (tester) async {
    final gate = Completer<Object?>();
    final data = sampleTeam();
    final fake = FakeDsBotTransport(team: data)..handlers['state'] = (_) => gate.future;
    await _open(tester, const BotsPage(), fake);
    expect(find.byType(QuietSpinner), findsOneWidget);
    await _capture(tester, 'team-loading');
    gate.completeError(const DshRemoteException('bot/unavailable', 'Synthetic temporary failure'));
    await _frames(tester);
    expect(find.text(appL10n.botsTeamLoadFailed), findsOneWidget);
    await _capture(tester, 'team-error');
    fake.handlers['state'] = (_) => data;
    await tester.tap(find.text(appL10n.commonRetry));
    await _frames(tester);
    expect(find.byKey(const ValueKey('team-main-m1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty team keeps a visible creation route and an empty conversation keeps its composer', (tester) async {
    final data = sampleTeam(working: false)
      ..['bots'] = <Object?>[]
      ..['rooms'] = <Object?>[]
      ..['mainBotIds'] = <Object?>[];
    await _open(tester, const BotsPage(), FakeDsBotTransport(team: data));
    expect(find.text(appL10n.botsNewBot), findsOneWidget);
    expect(find.byKey(const ValueKey('team-bot-m1')), findsNothing);
    await _capture(tester, 'team-empty');
    // Replacing the widget tree disposes the first transport/provider scope.
    await tester.pumpWidget(const SizedBox.shrink());
    final fake = FakeDsBotTransport(team: sampleTeam(working: false))..chatItems = [];
    await _open(tester, const BotChatPage(botId: 'b2'), fake);
    expect(find.byType(Composer), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
    await _capture(tester, 'chat-empty');
    expect(tester.takeException(), isNull);
  });
}
