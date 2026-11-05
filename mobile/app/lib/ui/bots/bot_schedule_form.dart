import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/schedule_editor_state.dart' show deviceTimeZoneProvider;
import '../common/list_page_row.dart';
import '../features/feature_widgets.dart';
import '../features/schedule_editor/schedule_pickers.dart' show showZoneSheet, zoneLabel;
import '../features/schedule_editor/time_zones.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_workspace.dart';

/// Creates one task through the existing DS Bot endpoint. There is no edit
/// operation: this form never deletes or replaces an existing task.
class BotScheduleForm extends ConsumerStatefulWidget {
  const BotScheduleForm({super.key, required this.origin, required this.api, this.botId, this.roomId});
  final DsBotStatus origin;
  final DsBotApi api;
  final String? botId;
  final String? roomId;

  @override
  ConsumerState<BotScheduleForm> createState() => _BotScheduleFormState();
}

class _BotScheduleFormState extends ConsumerState<BotScheduleForm> {
  final _title = TextEditingController();
  final _prompt = TextEditingController();
  final _minutes = TextEditingController(text: '60');
  late String _target;
  String _kind = 'daily';
  String? _zone;
  String? _deviceZone;
  bool _zonePicked = false;
  DateTime _date = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  final _weekdays = <int>{1, 2, 3, 4, 5};
  bool _saving = false;
  bool _uncertain = false;
  bool _retired = false;
  String? _error;
  ProviderSubscription<DsBotStatus>? _status;
  StreamSubscription<DsBotFeedEvent>? _feed;

  bool get _room => _target.startsWith('r:');
  String get _id => _target.length > 2 ? _target.substring(2) : '';

  bool get _current {
    if (!mounted || _retired) return false;
    final status = ref.read(dsBotProvider);
    if (!status.ready ||
        !identical(widget.api, ref.read(dsBotProvider.notifier).api) ||
        status.host != widget.origin.host ||
        status.hello?.boot != widget.origin.hello?.boot) {
      return false;
    }
    if (_id.isEmpty) return true;
    if (_room) return status.team?.room(_id) != null;
    final bot = status.team?.bot(_id);
    return bot != null && bot.sessionId == widget.origin.team?.bot(_id)?.sessionId;
  }

  bool get _writable => _current && ref.read(dsBotProvider).readOnly == null && _id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final team = widget.origin.team!;
    _target = widget.botId != null
        ? 'b:${widget.botId}'
        : widget.roomId != null
        ? 'r:${widget.roomId}'
        : team.bots.isNotEmpty
        ? 'b:${team.bots.first.id}'
        : team.rooms.isNotEmpty
        ? 'r:${team.rooms.first.id}'
        : '';
    if (!_current) _retired = true;
    _status = ref.listenManual(dsBotProvider, (_, _) {
      if (!_current) _retire();
    });
    final boot = widget.origin.hello?.boot;
    _feed = ref.read(dsBotProvider.notifier).events.listen((event) {
      if (event case DsBotFeedHello(boot: final next?)
          when boot != null && boot.isNotEmpty && next.isNotEmpty && next != boot) {
        _retire();
      }
    });
    unawaited(_loadZone());
  }

  void _retire() {
    if (mounted && !_retired) setState(() => _retired = true);
  }

  Future<void> _loadZone() async {
    try {
      final zone = await ref.read(deviceTimeZoneProvider.future);
      if (!mounted || _zonePicked) return;
      setState(() {
        _deviceZone = zone;
        _zone = isKnownZone(zone) ? zone : null;
        final initial = inZone(DateTime.now().add(const Duration(hours: 1)), zone);
        if (initial != null) _date = DateTime(initial.year, initial.month, initial.day);
      });
    } catch (_) {
      // The user can choose an explicit IANA zone if device detection fails.
      // Never silently schedule a local wall-clock time in UTC.
    }
  }

  @override
  void dispose() {
    _status?.close();
    unawaited(_feed?.cancel());
    _title.dispose();
    _prompt.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String get _clock => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  String? _validate() {
    final l = context.l10n;
    if (_title.text.trim().isEmpty || _title.text.trim().length > 120 || _prompt.text.trim().isEmpty) {
      return l.featuresScheduleInvalidPrompt;
    }
    if (!_writable) return l.botsScheduleChanged;
    if (_kind == 'every') {
      final minutes = int.tryParse(_minutes.text);
      return minutes == null || minutes < 1 || minutes > 10080 ? l.botsScheduleIntervalInvalid : null;
    }
    if (_zone == null || !isKnownZone(_zone!)) return l.featuresZoneUnavailable;
    if (_kind == 'weekly' && _weekdays.isEmpty) return l.botsScheduleWeekdaysRequired;
    if (_kind == 'at') {
      final at = zonedInstant(_zone!, _date.year, _date.month, _date.day, _time.hour, _time.minute);
      if (at == null) return l.featuresTimeDoesNotExist;
      if (!at.isAfter(DateTime.now())) return l.botsScheduleFutureTime;
    }
    return null;
  }

  Map<String, Object?> _when() => switch (_kind) {
    'every' => {'kind': 'every', 'minutes': int.parse(_minutes.text)},
    'at' => {
      'kind': 'at',
      'at': zonedInstant(
        _zone!,
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      )!.toUtc().toIso8601String(),
    },
    _ => {
      'kind': _kind,
      'time': _clock,
      'timeZone': _zone!,
      if (_kind == 'weekly') 'weekdays': _weekdays.toList()..sort(),
    },
  };

  Future<void> _save() async {
    if (_saving || _uncertain || !_writable) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final when = _when();
    final target = _id;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final view = await widget.api.createSchedule(
        target: target,
        title: _title.text.trim(),
        prompt: _prompt.text.trim(),
        when: when,
      );
      if (mounted && _current) Navigator.of(context).pop(view);
    } catch (failure) {
      if (_current) {
        // A task may exist even if the response or subsequent catalog read
        // failed. Only explicit pre-write validation/refusal permits retry.
        final refused =
            failure is ArgumentError ||
            (failure is DshRemoteException &&
                const {'bot/invalid', 'bot/read-only', 'bot/schedules-unsupported'}.contains(failure.code));
        setState(() {
          _uncertain = !refused;
          _error = refused ? describeDsBotError(failure) : context.l10n.botsScheduleSaveUncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(BuildContext page) async {
    final today = inZone(DateTime.now(), _zone ?? 'UTC') ?? DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final date = await showDatePicker(
      context: page,
      initialDate: _date.isBefore(first) ? first : _date,
      firstDate: first,
      lastDate: DateTime(first.year + 2, 12, 31),
    );
    if (date != null && _current && !_saving) setState(() => _date = date);
  }

  Future<void> _pickTime(BuildContext page) async {
    final time = await showTimePicker(context: page, initialTime: _time);
    if (time != null && _current && !_saving) setState(() => _time = time);
  }

  Future<void> _pickZone(BuildContext page) async {
    final zone = await showZoneSheet(page, selected: _zone ?? 'UTC', device: _deviceZone ?? 'UTC');
    if (zone != null && _current && !_saving) {
      setState(() {
        _zonePicked = true;
        _zone = zone;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(dsBotProvider);
    final team = widget.origin.team!;
    return PopScope(
      canPop: !_saving || !_current,
      child: BotWorkspace(
        child: Builder(
          builder: (context) {
            final l = context.l10n;
            final palette = BotWorkspacePalette.of(context);
            final lockedTarget = widget.botId != null || widget.roomId != null;
            return AppPage.list(
              key: const ValueKey('bot-schedule-form'),
              title: l.botsSchedulesNew,
              subtitle: Text(widget.origin.hostLabel),
              children: [
                if (!_current)
                  FeatureNote(l.botsScheduleChanged)
                else if (status.readOnly != null)
                  FeatureNote('${status.readOnly}'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: const ValueKey('bot-schedule-target'),
                        initialValue: _target.isEmpty ? null : _target,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l.botsScheduleTarget),
                        items: [
                          for (final bot in team.bots)
                            DropdownMenuItem(
                              value: 'b:${bot.id}',
                              child: Text(bot.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          for (final room in team.rooms)
                            DropdownMenuItem(
                              value: 'r:${room.id}',
                              child: Text(
                                '${room.name} · ${l.botsGroupChat}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: lockedTarget || _saving || !_current
                            ? null
                            : (value) {
                                if (value != null) setState(() => _target = value);
                              },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const ValueKey('bot-schedule-title'),
                        controller: _title,
                        enabled: !_saving && _writable,
                        maxLength: 120,
                        decoration: InputDecoration(labelText: l.commonName),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('bot-schedule-prompt'),
                        controller: _prompt,
                        enabled: !_saving && _writable,
                        minLines: 4,
                        maxLines: 8,
                        decoration: InputDecoration(labelText: l.botsSchedulePrompt, alignLabelWithHint: true),
                      ),
                      const SizedBox(height: 24),
                      Text(l.featuresRepeat, style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (kind, label) in [
                            ('at', l.featuresRepeatOnce),
                            ('daily', l.featuresRepeatDaily),
                            ('weekly', l.featuresRepeatWeekly),
                            ('every', l.featuresRepeatInterval),
                          ])
                            ChoiceChip(
                              key: ValueKey('bot-schedule-kind-$kind'),
                              label: Text(label),
                              selected: _kind == kind,
                              onSelected: _saving || !_current ? null : (_) => setState(() => _kind = kind),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_kind == 'weekly')
                        Wrap(
                          spacing: 4,
                          runSpacing: 8,
                          children: [
                            for (var day = 1; day <= 7; day++)
                              FilterChip(
                                key: ValueKey('bot-schedule-weekday-$day'),
                                label: Text(DateFormat.E(l.localeName).format(DateTime.utc(2024, 1, day))),
                                selected: _weekdays.contains(day),
                                onSelected: _saving || !_current
                                    ? null
                                    : (selected) =>
                                          setState(() => selected ? _weekdays.add(day) : _weekdays.remove(day)),
                              ),
                          ],
                        ),
                      if (_kind == 'every')
                        TextField(
                          key: const ValueKey('bot-schedule-minutes'),
                          controller: _minutes,
                          enabled: !_saving && _writable,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: l.featuresCronMinute,
                            helperText: l.botsScheduleIntervalInvalid,
                          ),
                        )
                      else ...[
                        if (_kind == 'at')
                          ListPageRow(
                            key: const ValueKey('bot-schedule-date'),
                            icon: AppIcons.scheduled,
                            title: l.featuresDate,
                            subtitle: DateFormat.yMMMd(l.localeName).format(_date),
                            onTap: !_saving && _current ? () => _pickDate(context) : null,
                          ),
                        ListPageRow(
                          key: const ValueKey('bot-schedule-time'),
                          icon: AppIcons.time,
                          title: l.featuresTime,
                          subtitle: _clock,
                          onTap: !_saving && _current ? () => _pickTime(context) : null,
                        ),
                        ListPageRow(
                          key: const ValueKey('bot-schedule-zone'),
                          title: l.featuresTimeZone,
                          subtitle: _zone == null ? l.featuresZoneUnavailable : zoneLabel(_zone!),
                          subtitleMaxLines: 2,
                          onTap: !_saving && _current ? () => _pickZone(context) : null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        l.botsScheduleDeliveryHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: 16),
                        Text(
                          error,
                          key: const ValueKey('bot-schedule-error'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DshColors.of(context).danger),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('bot-schedule-save'),
                        onPressed: !_saving && !_uncertain && _writable && (_kind == 'every' || _zone != null)
                            ? _save
                            : null,
                        child: _saving
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(l.commonSave),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
