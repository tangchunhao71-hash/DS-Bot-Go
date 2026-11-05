import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

class _Transport implements DsBotTransport {
  final calls = <(String, Map<String, Object?>)>[];
  FutureOr<Object?> Function(String, Map<String, Object?>) answer = (_, _) => null;

  @override
  Future<Object?> call(String endpoint, Map<String, Object?> payload, {Duration? timeout}) async {
    calls.add((endpoint, payload));
    return answer(endpoint, payload);
  }

  @override
  Stream<DsBotSseEvent> openFeed() => const Stream.empty();
  @override
  Future<void> close() async {}
}

Map<String, Object?> _view() => {
  'available': true,
  'tasks': [
    {
      'id': 'task-1',
      'sessionId': 'original-session',
      'botId': 'bot-1',
      'title': 'Synthetic weekly task',
      'prompt': 'Synthetic prompt, never sent',
      'kind': 'weekly',
      'status': 'active',
      'state': 'idle',
      'time': '09:30',
      'timeZone': 'Asia/Shanghai',
      'weekdays': [1, 5],
      'scheduledAt': '2030-01-07T01:30:00.000Z',
    },
    {
      'id': 'task-2',
      'sessionId': 'room-session',
      'roomId': 'room-1',
      'title': 'Existing cron task',
      'prompt': 'Synthetic room prompt',
      'kind': 'cron',
      'status': 'active',
      'expression': '0 9 * * 1',
      'everySeconds': 1800,
    },
  ],
};

void main() {
  late _Transport transport;
  late DsBotApi api;
  setUp(() {
    transport = _Transport();
    api = DsBotApi(transport);
  });
  tearDown(() => api.close());

  test('avatar replacement and explicit clear preserve the desktop update-bot contract', () async {
    const image = 'data:image/gif;base64,R0lGODlh';
    await api.setAvatar('bot-1', shape: 'moon', image: image);
    await api.setAvatar('bot-1', shape: 'moon');
    await api.setAvatar('bot-1', clear: true);
    expect(
      [
        for (final call in transport.calls) [call.$1, call.$2],
      ],
      [
        [
          'update-bot',
          {
            'id': 'bot-1',
            'avatar': {'shape': 'moon', 'image': image},
          },
        ],
        [
          'update-bot',
          {
            'id': 'bot-1',
            'avatar': {'shape': 'moon'},
          },
        ],
        [
          'update-bot',
          {'id': 'bot-1', 'avatar': null},
        ],
      ],
    );
    for (final invalid in <void Function()>[
      () => api.setAvatar(''),
      () => api.setAvatar('bot-1'),
      () => api.setAvatar('bot-1', clear: true, shape: 'moon'),
      () => api.setAvatar('bot-1', shape: '../unknown'),
      () => api.setAvatar('bot-1', image: 'https://example.invalid/photo.png'),
      () => api.setAvatar('bot-1', image: 'data:image/svg+xml;base64,QQ=='),
      () => api.setAvatar('bot-1', image: 'data:image/gif;base64,${'A' * 160000}'),
    ]) {
      expect(invalid, throwsArgumentError);
    }
    expect(transport.calls, hasLength(3));
  });

  test('schedule view retains desktop task identity, timing, room and unavailable state', () async {
    transport.answer = (_, _) => _view();
    final view = await api.schedules();
    expect(view.available, isTrue);
    final task = view.tasks.first;
    expect((task.id, task.sessionId, task.botId, task.roomId), ('task-1', 'original-session', 'bot-1', null));
    expect((task.kind, task.time, task.timeZone), ('weekly', '09:30', 'Asia/Shanghai'));
    expect(task.weekdays, [1, 5]);
    expect(task.scheduledAt, DateTime.utc(2030, 1, 7, 1, 30));
    expect((view.tasks.last.roomId, view.tasks.last.expression), ('room-1', '0 9 * * 1'));
    transport.answer = (_, _) => {'available': false, 'tasks': []};
    final unavailable = await api.schedules();
    expect(unavailable.available, isFalse);
    expect(unavailable.tasks, isEmpty);
    for (final bad in [
      null,
      {},
      {'available': true},
      {
        'available': true,
        'tasks': [null],
      },
    ]) {
      transport.answer = (_, _) => bad;
      await expectLater(api.schedules(), throwsA(isA<DshProtocolException>()));
    }
  });

  test('create and delete send one exact call and parse the returned view without another read', () async {
    transport.answer = (_, _) => _view();
    final created = await api.createSchedule(
      target: 'bot-1',
      title: '  Weekly task  ',
      prompt: '  Synthetic prompt  ',
      when: {
        'kind': 'weekly',
        'time': '09:30',
        'timeZone': 'Asia/Shanghai',
        'weekdays': [1, 5],
      },
    );
    expect(created.tasks, hasLength(2));
    final deleted = await api.deleteSchedule(sessionId: 'original-session', id: 'task-1');
    expect(deleted.tasks, hasLength(2));
    expect(
      [
        for (final call in transport.calls) [call.$1, call.$2],
      ],
      [
        [
          'schedule-create',
          {
            'target': 'bot-1',
            'title': 'Weekly task',
            'prompt': 'Synthetic prompt',
            'when': {
              'kind': 'weekly',
              'time': '09:30',
              'timeZone': 'Asia/Shanghai',
              'weekdays': [1, 5],
            },
          },
        ],
        [
          'schedule-delete',
          {'sessionId': 'original-session', 'id': 'task-1'},
        ],
      ],
    );
    expect(() => api.createSchedule(target: 'bot-1', title: ' ', prompt: 'p', when: {}), throwsArgumentError);
    expect(() => api.deleteSchedule(sessionId: '', id: 'task-1'), throwsArgumentError);
    expect(transport.calls, hasLength(2));
  });

  test('old connection rejections are unsupported; unknown write outcomes are never replayed', () async {
    for (final code in ['bot/forbidden', 'bot/not-found', 'bot/unknown-endpoint', 'METHOD_NOT_ALLOWED']) {
      transport.answer = (_, _) => throw DshRemoteException(code, 'synthetic old component');
      await expectLater(
        api.schedules(),
        throwsA(isA<DshRemoteException>().having((e) => e.code, 'code', 'bot/schedules-unsupported')),
      );
    }
    transport.calls.clear();
    transport.answer = (_, _) => throw TimeoutException('synthetic completion unknown');
    await expectLater(
      api.createSchedule(target: 'bot-1', title: 'Task', prompt: 'Prompt', when: {'kind': 'every', 'minutes': 30}),
      throwsA(isA<TimeoutException>()),
    );
    expect(transport.calls.map((e) => e.$1), ['schedule-create']);
    transport.answer = (_, _) => {'available': true};
    await expectLater(
      api.deleteSchedule(sessionId: 'original-session', id: 'task-1'),
      throwsA(isA<DshProtocolException>()),
    );
    expect(transport.calls.map((e) => e.$1), ['schedule-create', 'schedule-delete']);
  });
}
