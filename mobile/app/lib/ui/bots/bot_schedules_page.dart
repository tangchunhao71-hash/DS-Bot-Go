import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/schedule_editor_state.dart' show deviceTimeZoneProvider;
import '../common/app_dialog.dart';
import '../features/feature_kit.dart';
import '../features/feature_widgets.dart';
import '../features/schedule_editor/schedule_pickers.dart' show zoneLabel;
import '../features/schedule_editor/time_zones.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_action_scope.dart';
import 'bot_avatar.dart';
import 'bot_schedule_form.dart';
import 'bot_workspace.dart';
import 'unavailable_message.dart';

/// The host's existing DS Bot schedule service. Viewing never creates a task.
class BotSchedulesPage extends ConsumerStatefulWidget {
  const BotSchedulesPage({super.key, this.botId, this.roomId}) : assert(botId == null || roomId == null);

  final String? botId;
  final String? roomId;

  static Route<void> route({String? botId, String? roomId}) => MaterialPageRoute<void>(
    builder: (_) => BotSchedulesPage(botId: botId, roomId: roomId),
  );

  @override
  ConsumerState<BotSchedulesPage> createState() => _BotSchedulesPageState();
}

class _BotSchedulesPageState extends ConsumerState<BotSchedulesPage> {
  BotActionScope? _scope;
  DsBotSchedules? _view;
  String? _error;
  bool _unsupported = false;
  bool _loading = false;
  bool _mutating = false;
  bool _retired = false;
  ProviderSubscription<DsBotStatus>? _status;
  StreamSubscription<DsBotFeedEvent>? _feed;

  bool get _current {
    if (!mounted || _retired || _scope?.connected(context, ref) != true) return false;
    final status = ref.read(dsBotProvider);
    return status.ready &&
        (widget.botId == null || status.team?.bot(widget.botId) != null) &&
        (widget.roomId == null || status.team?.room(widget.roomId!) != null);
  }

  bool get _writable => _current && _scope!.current(context, ref);

  @override
  void initState() {
    super.initState();
    _status = ref.listenManual(dsBotProvider, (_, next) {
      if (_scope == null) {
        if (next.ready) _bind(next);
      } else if (!_current) {
        _retire();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scope == null) _bind(ref.read(dsBotProvider));
    });
  }

  void _bind(DsBotStatus status) {
    if (!mounted || _scope != null || !status.ready) return;
    final scope = BotActionScope(ref, botId: widget.botId, roomId: widget.roomId);
    if (scope.api == null) return;
    _scope = scope;
    final boot = status.hello?.boot;
    _feed = ref.read(dsBotProvider.notifier).events.listen((event) {
      if (event case DsBotFeedHello(boot: final next?)
          when boot != null && boot.isNotEmpty && next.isNotEmpty && next != boot) {
        _retire();
      }
    });
    if (!_current) {
      _retire();
    } else {
      unawaited(_load());
    }
  }

  void _retire() {
    if (!mounted || _retired) return;
    setState(() {
      _retired = true;
      _view = null;
      _loading = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _status?.close();
    unawaited(_feed?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (!_current || _loading || _mutating) return;
    setState(() {
      _loading = true;
      _error = null;
      _unsupported = false;
    });
    try {
      final view = await _scope!.api!.schedules();
      if (_current) setState(() => _view = view);
    } catch (error) {
      if (_current) {
        setState(() {
          _unsupported = error is DshRemoteException && error.code == 'bot/schedules-unsupported';
          _error = describeDsBotError(error);
        });
      }
    } finally {
      if (mounted && _current) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (!_writable || _loading || _mutating || _view?.available != true) return;
    final origin = ref.read(dsBotProvider);
    final api = _scope!.api!;
    setState(() {
      _mutating = true;
      _error = null;
    });
    DsBotSchedules? result;
    try {
      result = await Navigator.of(context).push<DsBotSchedules>(
        MaterialPageRoute(
          builder: (_) => BotScheduleForm(origin: origin, api: api, botId: widget.botId, roomId: widget.roomId),
        ),
      );
      if (_current && result != null) setState(() => _view = result);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
    // Cancellation can also mean an unconfirmed write. Re-read, never replay.
    if (_current && result == null) await _load();
  }

  bool _has(DsBotSchedule task) =>
      _view?.tasks.any((item) => item.id == task.id && item.sessionId == task.sessionId) == true;

  Future<void> _delete(DsBotSchedule task) async {
    if (!_writable || _loading || _mutating || !_has(task)) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      final accepted = await showAppDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(context.l10n.featuresScheduleDeleteTitle),
          content: SingleChildScrollView(child: Text('${task.title}\n\n${context.l10n.botsScheduleDeleteHint}')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(context.l10n.commonCancel)),
            FilledButton(
              key: const ValueKey('bot-schedule-delete-confirm'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(context.l10n.commonDelete),
            ),
          ],
        ),
      );
      if (accepted != true || !_writable || !_has(task)) return;
      final view = await _scope!.api!.deleteSchedule(sessionId: task.sessionId, id: task.id);
      if (_current) setState(() => _view = view);
    } catch (error) {
      if (_current) {
        setState(() {
          _view = null;
          _error = describeDsBotError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(dsBotProvider);
    final zone = ref.watch(deviceTimeZoneProvider).value ?? 'UTC';
    return PopScope(
      canPop: !_mutating || !_current,
      child: BotWorkspace(
        child: Builder(
          builder: (context) {
            final l10n = context.l10n;
            final owner = widget.botId != null
                ? status.team?.bot(widget.botId)?.name
                : widget.roomId != null
                ? status.team?.room(widget.roomId!)?.name
                : null;
            final tasks = [
              for (final task in _view?.tasks ?? const <DsBotSchedule>[])
                if ((widget.botId == null || task.botId == widget.botId) &&
                    (widget.roomId == null || (task.botId == null && task.roomId == widget.roomId)))
                  task,
            ];
            return AppPage.list(
              key: const ValueKey('bot-schedules-page'),
              title: l10n.botsSchedules,
              subtitle: Text([status.hostLabel, ?owner].join(' · ')),
              actions: [
                IconButton(
                  key: const ValueKey('bot-schedules-reload'),
                  tooltip: l10n.commonRetry,
                  onPressed: _current && !_loading && !_mutating ? _load : null,
                  icon: const Icon(AppIcons.refresh),
                ),
              ],
              children: [
                if (_retired)
                  FeatureMessage(
                    key: const ValueKey('bot-schedules-retired'),
                    icon: AppIcons.disconnected,
                    title: l10n.botsScheduleChanged,
                  )
                else if (!status.ready)
                  DsBotUnavailableMessage(
                    status: status,
                    goneIcon: AppIcons.scheduled,
                    goneTitle: l10n.botsSchedulesLoadFailed,
                  )
                else if (_scope == null || (_loading && _view == null))
                  const QuietSpinner()
                else if (_unsupported)
                  FeatureMessage(
                    key: const ValueKey('bot-schedules-unsupported'),
                    icon: AppIcons.disconnected,
                    title: l10n.botsSchedulesUnsupported,
                    body: l10n.botsSchedulesUnsupportedHint,
                  )
                else if (_view?.available == false)
                  FeatureMessage(
                    key: const ValueKey('bot-schedules-unavailable'),
                    icon: AppIcons.scheduled,
                    title: l10n.botsSchedulesUnavailable,
                    body: l10n.botsSchedulesUnavailableHint,
                  )
                else ...[
                  if (_error != null)
                    FeatureMessage(
                      icon: AppIcons.error,
                      title: l10n.botsSchedulesLoadFailed,
                      body: _error,
                      action: (l10n.commonRetry, _load),
                    ),
                  if (_view != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('bot-schedule-create'),
                            onPressed:
                                _writable &&
                                    !_loading &&
                                    !_mutating &&
                                    (status.team!.bots.isNotEmpty || status.team!.rooms.isNotEmpty)
                                ? _create
                                : null,
                            icon: const Icon(AppIcons.add, size: 18),
                            label: Text(l10n.botsSchedulesNew),
                          ),
                          if (widget.botId != null || widget.roomId != null)
                            TextButton(
                              onPressed: () => Navigator.of(context).push(BotSchedulesPage.route()),
                              child: Text(l10n.botsSchedulesAll),
                            ),
                        ],
                      ),
                    ),
                    if (status.readOnly != null) FeatureNote('${status.readOnly}'),
                    if (tasks.isEmpty)
                      FeatureMessage(icon: AppIcons.scheduled, title: l10n.botsSchedulesNone)
                    else
                      for (final task in tasks)
                        _TaskTile(
                          key: ValueKey('bot-schedule-${task.sessionId}-${task.id}'),
                          task: task,
                          team: status.team!,
                          zone: zone,
                          onDelete: _writable && !_loading && !_mutating ? () => _delete(task) : null,
                        ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({super.key, required this.task, required this.team, required this.zone, required this.onDelete});
  final DsBotSchedule task;
  final DsBotTeam team;
  final String zone;
  final VoidCallback? onDelete;

  String _date(BuildContext context, DateTime at) =>
      DateFormat.yMMMd(context.l10n.localeName).add_Hm().format(inZone(at, zone) ?? at.toUtc());

  String _timing(BuildContext context) {
    final l = context.l10n;
    final clock = (task.time ?? '').split(':').take(2).join(':');
    final suffix = task.timeZone == null ? '' : ' · ${zoneLabel(task.timeZone!)}';
    return switch (task.kind) {
      'at' ||
      'after' => '${l.featuresRepeatOnce}${task.scheduledAt == null ? '' : ' · ${_date(context, task.scheduledAt!)}'}',
      'daily' => '${l.featuresRepeatDaily} $clock$suffix',
      'weekly' =>
        '${l.featuresRepeatWeekly} · ${task.weekdays.where((d) => d >= 1 && d <= 7).map((d) => DateFormat.E(l.localeName).format(DateTime.utc(2024, 1, d))).join(l.botsListSeparator)} $clock$suffix',
      'every' =>
        task.everySeconds == null
            ? l.featuresRepeatInterval
            : task.everySeconds! % 60 == 0
            ? l.featuresRuleIntervalMinutes(task.everySeconds! ~/ 60)
            : '${l.featuresRepeatInterval} ${task.everySeconds} ${l.featuresIntervalSeconds}',
      'cron' => '${l.botsScheduleCron(task.expression ?? '')}$suffix',
      _ => task.kind,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = BotWorkspacePalette.of(context);
    final bot = team.bot(task.botId);
    final room = task.roomId == null ? null : team.room(task.roomId!);
    final finished = task.status != 'active';
    final at = task.scheduledAt;
    final next = finished
        ? context.l10n.botsScheduleFinished
        : at == null
        ? ''
        : task.state == 'overdue'
        ? context.l10n.botsScheduleOverdue(_date(context, at))
        : context.l10n.botsScheduleNext(_date(context, at));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (bot != null) BotAvatar(bot: bot, size: 28),
                  if (bot == null && room != null) RoomAvatar(room: room, team: team, size: 28),
                  const SizedBox(width: 8),
                  Expanded(child: Text(bot?.name ?? room?.name ?? '', style: Theme.of(context).textTheme.labelLarge)),
                  IconButton(
                    key: ValueKey('bot-schedule-delete-${task.id}'),
                    tooltip: context.l10n.commonDelete,
                    onPressed: onDelete,
                    icon: Icon(
                      AppIcons.delete,
                      size: 19,
                      color: onDelete == null ? palette.muted : DshColors.of(context).danger,
                    ),
                  ),
                ],
              ),
              Text(task.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(_timing(context), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted)),
              if (next.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  next,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: task.state == 'overdue' ? DshColors.of(context).warning : palette.muted),
                ),
              ],
              if (task.prompt.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(task.prompt, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
