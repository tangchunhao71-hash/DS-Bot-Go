import 'errors.dart';
import 'json.dart';

/// The existing DS Bot schedule channel, backed by DSH Automation tasks.
class DsBotSchedules {
  const DsBotSchedules({required this.available, this.tasks = const []});

  factory DsBotSchedules.fromJson(Object? value) {
    final map = asMap(value);
    final available = asBool(map?['available']);
    final items = asList(map?['tasks']);
    if (available == null || items == null) {
      throw DshProtocolException('DS Bot schedules: invalid task view');
    }
    final tasks = items.map(DsBotSchedule.fromJson).toList(growable: false);
    if (tasks.any((task) => task.id.isEmpty || task.sessionId.isEmpty)) {
      throw DshProtocolException('DS Bot schedules: missing task identity');
    }
    return DsBotSchedules(available: available, tasks: tasks);
  }

  final bool available;
  final List<DsBotSchedule> tasks;
}

class DsBotSchedule {
  const DsBotSchedule({
    required this.id,
    required this.sessionId,
    required this.title,
    required this.prompt,
    required this.kind,
    required this.status,
    this.botId,
    this.roomId,
    this.state,
    this.time,
    this.timeZone,
    this.expression,
    this.scheduledAt,
    this.everySeconds,
    this.weekdays = const [],
  });

  factory DsBotSchedule.fromJson(Object? value) {
    final map = asMapOrEmpty(value);
    final at = map['scheduledAt'];
    return DsBotSchedule(
      id: asString(map['id']) ?? '',
      sessionId: asString(map['sessionId']) ?? '',
      title: asString(map['title']) ?? '',
      prompt: asString(map['prompt']) ?? '',
      kind: asString(map['kind']) ?? '',
      status: asString(map['status']) ?? '',
      botId: asString(map['botId']),
      roomId: asString(map['roomId']),
      state: asString(map['state']),
      time: asString(map['time']),
      timeZone: asString(map['timeZone']),
      expression: asString(map['expression']),
      scheduledAt: at is String ? DateTime.tryParse(at) : asEpochMs(at),
      everySeconds: asInt(map['everySeconds']),
      weekdays: [for (final day in asListOrEmpty(map['weekdays'])) ?asInt(day)],
    );
  }

  final String id;
  final String sessionId;
  final String title;
  final String prompt;
  final String kind;
  final String status;
  final String? botId;
  final String? roomId;
  final String? state;
  final String? time;
  final String? timeZone;
  final String? expression;
  final DateTime? scheduledAt;
  final int? everySeconds;
  final List<int> weekdays;
}
