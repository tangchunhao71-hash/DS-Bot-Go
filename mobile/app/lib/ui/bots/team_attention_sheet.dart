// A mobile index of requests. Selecting one only opens its conversation;
// all answers and approvals keep their existing identity and permission guards.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../common/app_sheet.dart';
import '../theme/app_icons.dart';
import 'bot_avatar.dart';
import 'bot_chat_page.dart';
import 'bot_workspace.dart';
import 'room_chat_page.dart';

enum TeamAttentionReason { approval, question, view, model }

/// One destination, even when it holds more than one request. The count on
/// the team page is a count of conversations, not a count of individual tasks.
class TeamAttentionEntry {
  const TeamAttentionEntry({required this.id, required this.reason, this.isRoom = false});

  final String id;
  final bool isRoom;
  final TeamAttentionReason reason;

  String label(BuildContext context) => switch (reason) {
    TeamAttentionReason.approval => context.l10n.commonWaitingApproval,
    TeamAttentionReason.question || TeamAttentionReason.view => context.l10n.commonWaitingAnswer,
    TeamAttentionReason.model => context.l10n.botsChooseModelStart,
  };
}

/// Only expose destinations that still exist and whose request can be
/// reached in the current conversation. Old parts and unanswerable group
/// approvals must not create phantom work on the home page.
List<TeamAttentionEntry> teamAttentionEntries(DsBotStatus status) {
  final team = status.team;
  if (!status.ready || team == null) return const [];
  final bots = [
    for (final id in team.mainBotIds) ?team.bot(id),
    for (final bot in team.bots)
      if (!team.isMain(bot.id)) bot,
  ];
  final entries = <TeamAttentionEntry>[
    for (final bot in bots)
      if (status.live.approvals.any(
        (approval) => approval.roomId == null && approval.botId == bot.id && approval.sessionId == bot.sessionId,
      ))
        TeamAttentionEntry(id: bot.id, reason: TeamAttentionReason.approval)
      else if (team.questionOf(bot) != null)
        TeamAttentionEntry(id: bot.id, reason: TeamAttentionReason.question)
      else if (team.viewOf(bot) != null)
        TeamAttentionEntry(id: bot.id, reason: TeamAttentionReason.view)
      else if (bot.waiting)
        TeamAttentionEntry(id: bot.id, reason: TeamAttentionReason.model),
    for (final room in team.rooms)
      if (status.live.approvals.any((approval) => approval.roomId == room.id && approval.answerable))
        TeamAttentionEntry(id: room.id, reason: TeamAttentionReason.approval, isRoom: true),
  ];
  // Group approvals with other approval requests while keeping roster order
  // within each kind of request.
  return [for (final reason in TeamAttentionReason.values) ...entries.where((entry) => entry.reason == reason)];
}

Future<void> showTeamAttentionSheet(BuildContext context) async {
  FocusScope.of(context).unfocus();
  final navigator = Navigator.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final origin = container.read(dsBotProvider);
  final api = container.read(dsBotProvider.notifier).api;
  final selected = await showAppSheet<TeamAttentionEntry>(
    context,
    heightFactor: 0.72,
    glass: false,
    dismissal: SheetDismissal.button,
    builder: (_) => BotWorkspace(
      child: TeamAttentionSheet(origin: origin, api: api),
    ),
  );
  if (!context.mounted || selected == null) return;
  final current = container.read(dsBotProvider);
  if (!current.ready ||
      current.host != origin.host ||
      current.hello?.boot != origin.hello?.boot ||
      !identical(api, container.read(dsBotProvider.notifier).api)) {
    return;
  }
  if (selected.isRoom) {
    if (current.team?.room(selected.id) != null) await navigator.push(RoomChatPage.route(selected.id));
  } else {
    if (current.team?.bot(selected.id) != null) await navigator.push(BotChatPage.route(selected.id));
  }
}

class TeamAttentionSheet extends ConsumerWidget {
  const TeamAttentionSheet({super.key, this.origin, this.api});

  final DsBotStatus? origin;
  final DsBotApi? api;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    final sameOrigin =
        origin == null ||
        (status.host == origin!.host &&
            status.hello?.boot == origin!.hello?.boot &&
            identical(api, ref.read(dsBotProvider.notifier).api));
    final entries = sameOrigin ? teamAttentionEntries(status) : const <TeamAttentionEntry>[];
    return Material(
      key: const ValueKey('bots-team-attention-sheet'),
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          SheetHeader(l10n.botsTeamAttention),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              l10n.botsTeamAttentionHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.muted),
            ),
          ),
          Divider(height: 1, color: palette.line),
          Expanded(
            child: entries.isEmpty || team == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        !sameOrigin
                            ? l10n.botsRelayLimitConnectionChanged
                            : status.ready
                            ? l10n.botsTeamAllClear
                            : l10n.commonNotConnected,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.muted),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 80, endIndent: 20, color: palette.line),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final bot = entry.isRoom ? null : team.bot(entry.id)!;
                      final room = entry.isRoom ? team.room(entry.id)! : null;
                      return ListTile(
                        key: ValueKey('team-attention-${entry.isRoom ? 'room' : 'bot'}-${entry.id}'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        leading: room == null
                            ? BotAvatar(bot: bot!, size: 44)
                            : RoomAvatar(room: room, team: team, size: 44),
                        title: Text(bot?.name ?? room!.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(entry.label(context)),
                        trailing: Icon(AppIcons.forward, size: 18, color: palette.muted),
                        onTap: () => Navigator.of(context).pop(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
