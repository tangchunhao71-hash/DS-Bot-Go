import 'dart:async';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/bots_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/schedule_editor_state.dart' show deviceTimeZoneProvider;
import 'package:dsh_app/ui/bots/bot_schedule_form.dart';
import 'package:dsh_app/ui/bots/bot_schedules_page.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show fakeConnection, loadTestFonts;
import 'refinement_harness.dart';
import 'support.dart';

class _Host extends ActiveHostController {
  @override
  HostRef build() => HostRef.local;
  @override
  void select(HostRef value) => state = value;
}

Map<String, Object?> schedule(String id, {bool room = false, String kind = 'daily'}) => {
  'id': id,
  'sessionId': room ? 'r1' : 'm1c',
  if (room) 'roomId': 'r1' else 'botId': 'm1',
  'kind': kind,
  'status': 'active',
  'state': 'scheduled',
  'title': 'Synthetic task $id',
  'prompt': 'SYNTHETIC instruction $id',
  'scheduledAt': '2030-01-01T01:00:00.000Z',
  'time': '09:00:00',
  'timeZone': 'Asia/Shanghai',
  'weekdays': [1, 5],
  'expression': '0 9 * * 1-5',
  'everySeconds': 3600,
};

Map<String, Object?> scheduleView({bool available = true, List<Object?> tasks = const []}) => {
  'available': available,
  'tasks': tasks,
};

FakeDsBotTransport schedulesFake({Map<String, Object?>? team, List<Object?> tasks = const []}) =>
    FakeDsBotTransport(team: team ?? sampleTeam(working: false))
      ..handlers['schedules'] = (_) => scheduleView(tasks: tasks);

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> open(
    WidgetTester tester,
    FakeDsBotTransport fake, {
    FakeDsBotTransport? next,
    Widget page = const BotSchedulesPage(),
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    await openRefinement(
      tester,
      page,
      fake,
      width: width,
      scale: scale,
      brightness: brightness,
      useDefaultTransport: next == null,
      extra: [
        deviceTimeZoneProvider.overrideWith((_) async => 'Asia/Shanghai'),
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
          dsBotApiFactoryProvider.overrideWithValue((connection) => DsBotApi(connection.isLocal ? fake : next)),
        ],
      ],
    );
    return ProviderScope.containerOf(tester.element(find.byType(BotSchedulesPage)));
  }

  Future<VoidCallback> fillForm(WidgetTester tester, {String kind = 'daily'}) async {
    await tester.tap(find.byKey(const ValueKey('bot-schedule-create')));
    await refinementFrames(tester);
    expect(find.byType(BotScheduleForm), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bot-schedule-title')), ' Synthetic new task ');
    await tester.enterText(find.byKey(const ValueKey('bot-schedule-prompt')), ' SYNTHETIC run instruction ');
    FocusManager.instance.primaryFocus?.unfocus();
    await refinementFrames(tester, 2);
    final kindChip = find.byKey(ValueKey('bot-schedule-kind-$kind'));
    await tester.ensureVisible(kindChip);
    await tester.pump();
    await tester.tap(kindChip);
    await tester.pump();
    if (kind == 'every') {
      await tester.enterText(find.byKey(const ValueKey('bot-schedule-minutes')), '30');
    }
    if (kind == 'at') {
      final dateRow = find.byKey(const ValueKey('bot-schedule-date'));
      await tester.ensureVisible(dateRow);
      await tester.pump();
      await tester.tap(dateRow);
      await refinementFrames(tester, 3);
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).onDateChanged(tomorrow);
      await tester.pump();
      final ok = MaterialLocalizations.of(tester.element(find.byType(DatePickerDialog))).okButtonLabel;
      await tester.tap(find.text(ok));
      await refinementFrames(tester, 3);
    }
    final save = find.byKey(const ValueKey('bot-schedule-save'));
    await tester.ensureVisible(save);
    await refinementFrames(tester, 2);
    return tester.widget<FilledButton>(save).onPressed!;
  }

  testWidgets('list and owner filters retain the host task, prompt, timing and cron without writing', (tester) async {
    final fake = schedulesFake(
      tasks: [
        schedule('one'),
        schedule('room', room: true),
        schedule('cron', kind: 'cron'),
      ],
    );
    await open(tester, fake);
    expect(find.text('Synthetic task one'), findsOneWidget);
    expect(find.text('SYNTHETIC instruction one'), findsOneWidget);
    expect(find.textContaining('0 9 * * 1-5'), findsOneWidget);
    expect(fake.endpoints.where((e) => e.startsWith('schedule-')), isEmpty);
    await captureRefinement(tester, 'schedules-list-light');
    await tester.pumpWidget(const SizedBox.shrink());
    await open(
      tester,
      schedulesFake(tasks: [schedule('one'), schedule('room', room: true)]),
      page: const BotSchedulesPage(roomId: 'r1'),
    );
    expect(find.text('Synthetic task room'), findsOneWidget);
    expect(find.text('Synthetic task one'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['service-off', 'old-bridge', 'failure']) {
    testWidgets('$mode stays distinct from a successful empty task list', (tester) async {
      final fake = schedulesFake();
      fake.handlers['schedules'] = (_) => switch (mode) {
        'service-off' => scheduleView(available: false),
        'old-bridge' => throw const DshRemoteException('bot/forbidden', 'not in old bridge allowlist'),
        _ => throw const DshRemoteException('bot/failed', 'Synthetic failure'),
      };
      await open(tester, fake);
      expect(find.text(appL10n.botsSchedulesNone), findsNothing);
      expect(find.byKey(const ValueKey('bot-schedule-create')), findsNothing);
      expect(
        find.text(switch (mode) {
          'service-off' => appL10n.botsSchedulesUnavailable,
          'old-bridge' => appL10n.botsSchedulesUnsupported,
          _ => appL10n.botsSchedulesLoadFailed,
        }),
        findsOneWidget,
      );
      await captureRefinement(tester, 'schedules-$mode');
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in ['at', 'daily', 'weekly', 'every']) {
    testWidgets('$kind create sends one existing-contract write with an explicit zone', (tester) async {
      final fake = schedulesFake();
      fake.handlers['schedule-create'] = (_) => scheduleView(tasks: [schedule('created')]);
      await open(
        tester,
        fake,
        page: const BotSchedulesPage(botId: 'm1'),
        width: kind == 'weekly' ? 320 : 390,
        scale: kind == 'weekly' ? 2 : 1,
      );
      final submit = await fillForm(tester, kind: kind);
      if (kind == 'weekly') await captureRefinement(tester, 'schedule-weekly-form-320-large');
      submit();
      await refinementFrames(tester);
      final calls = fake.calls.where((call) => call.$1 == 'schedule-create').toList();
      expect(calls, hasLength(1));
      expect(calls.single.$2['target'], 'm1');
      expect(calls.single.$2['title'], 'Synthetic new task');
      expect(calls.single.$2['prompt'], 'SYNTHETIC run instruction');
      final when = calls.single.$2['when'] as Map;
      expect(when['kind'], kind);
      if (kind == 'at') {
        expect(DateTime.parse(when['at'] as String).isUtc, isTrue);
        expect(DateTime.parse(when['at'] as String).isAfter(DateTime.now()), isTrue);
      } else if (kind == 'every') {
        expect(when['minutes'], 30);
      } else {
        expect(when['time'], '09:00');
        expect(when['timeZone'], 'Asia/Shanghai');
        if (kind == 'weekly') expect(when['weekdays'], [1, 2, 3, 4, 5]);
      }
      expect(find.byType(BotScheduleForm), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('room creation targets the real room, and busy prevents duplicate Save and back', (tester) async {
    final gate = Completer<Object?>();
    final fake = schedulesFake()..handlers['schedule-create'] = (_) => gate.future;
    await open(tester, fake, page: const BotSchedulesPage(roomId: 'r1'));
    final submit = await fillForm(tester);
    submit();
    submit();
    await refinementFrames(tester, 2);
    expect(fake.calls.where((c) => c.$1 == 'schedule-create'), hasLength(1));
    expect(fake.calls.singleWhere((c) => c.$1 == 'schedule-create').$2['target'], 'r1');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bot-schedule-save'))).onPressed, isNull);
    await Navigator.of(tester.element(find.byType(BotScheduleForm))).maybePop();
    await tester.pump();
    expect(find.byType(BotScheduleForm), findsOneWidget);
    gate.complete(scheduleView(tasks: [schedule('created', room: true)]));
    await refinementFrames(tester);
    expect(find.byType(BotScheduleForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain creation locks even a captured Save callback instead of replaying the write', (tester) async {
    final fake = schedulesFake()
      ..handlers['schedule-create'] = (_) => throw TimeoutException('Synthetic lost response');
    await open(tester, fake);
    final submit = await fillForm(tester);
    submit();
    await refinementFrames(tester);
    expect(find.text(appL10n.botsScheduleSaveUncertain), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bot-schedule-save'))).onPressed, isNull);
    submit();
    await refinementFrames(tester);
    expect(fake.calls.where((c) => c.$1 == 'schedule-create'), hasLength(1));
    await Navigator.of(tester.element(find.byType(BotScheduleForm))).maybePop();
    await refinementFrames(tester);
    expect(fake.endpoints.where((e) => e == 'schedules').length, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only view cannot create or delete, and a host ABA retires an open draft', (tester) async {
    final team = sampleTeam(working: false)..['readOnly'] = 'Synthetic read-only';
    final readonly = schedulesFake(team: team, tasks: [schedule('one')]);
    await open(tester, readonly);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bot-schedule-create'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('bot-schedule-delete-one'))).onPressed, isNull);
    expect(readonly.endpoints.where((e) => e.startsWith('schedule-')), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    final old = schedulesFake(), next = schedulesFake();
    final container = await open(tester, old, next: next);
    final submit = await fillForm(tester);
    container.read(activeHostProvider.notifier).select(const HostRef.ssh('next'));
    await refinementFrames(tester);
    container.read(activeHostProvider.notifier).select(HostRef.local);
    await refinementFrames(tester);
    submit();
    await refinementFrames(tester);
    expect([...old.endpoints, ...next.endpoints].where((e) => e == 'schedule-create'), isEmpty);
    expect(find.text(appL10n.botsScheduleChanged), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires confirmation, sends once, and an uncertain failure can only reload', (tester) async {
    final fake = schedulesFake(tasks: [schedule('one')]);
    fake.handlers['schedule-delete'] = (_) => throw TimeoutException('Synthetic lost delete response');
    await open(tester, fake);
    await tester.tap(find.byKey(const ValueKey('bot-schedule-delete-one')));
    await refinementFrames(tester, 3);
    expect(fake.endpoints.where((e) => e == 'schedule-delete'), isEmpty);
    await tester.tap(find.text(appL10n.commonCancel));
    await refinementFrames(tester, 3);
    expect(fake.endpoints.where((e) => e == 'schedule-delete'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('bot-schedule-delete-one')));
    await refinementFrames(tester, 3);
    await tester.tap(find.byKey(const ValueKey('bot-schedule-delete-confirm')));
    await refinementFrames(tester);
    expect(fake.calls.singleWhere((c) => c.$1 == 'schedule-delete').$2, {'sessionId': 'm1c', 'id': 'one'});
    expect(find.byKey(const ValueKey('bot-schedule-delete-one')), findsNothing);
    fake.handlers['schedules'] = (_) => scheduleView();
    await tester.tap(find.text(appL10n.commonRetry));
    await refinementFrames(tester);
    expect(find.text(appL10n.botsSchedulesNone), findsOneWidget);
    expect(fake.endpoints.where((e) => e == 'schedule-delete'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
