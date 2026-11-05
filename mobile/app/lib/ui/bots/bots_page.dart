// The team is the mobile entry point: find a Bot, see what needs attention,
// and open its conversation. Work, unread messages and requests remain
// distinct signals; requests are reviewed in the conversation they belong to.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bot_layout_state.dart';
import '../../state/bots_state.dart';
import '../common/fluid_bits.dart';
import '../common/list_page_row.dart';
import '../features/feature_kit.dart';
import '../features/feature_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_avatar.dart';
import 'bot_chat_page.dart';
import 'bot_format.dart';
import 'bot_search_page.dart';
import 'bot_sections.dart';
import 'bot_workspace.dart';
import 'bot_workspace_settings_page.dart';
import 'install_card.dart';
import 'new_bot_page.dart';
import 'new_room_sheet.dart';
import 'room_chat_page.dart';
import 'team_attention_sheet.dart';

class BotsPage extends ConsumerStatefulWidget {
  const BotsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const BotsPage());

  @override
  ConsumerState<BotsPage> createState() => _BotsPageState();
}

class _BotsPageState extends ConsumerState<BotsPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    ref.listen(dsBotProvider.select((value) => value.host), (previous, next) {
      if (previous != next && _scroll.hasClients) _scroll.jumpTo(0);
    });
    return BotWorkspace(
      child: status.ready && team != null
          ? _TeamScaffold(status: status, team: team, scroll: _scroll)
          : AppPage.list(
              title: 'DS Bot',
              subtitle: Text(status.hostLabel),
              children: [
                switch (status.availability) {
                  DsBotAvailability.offline => const FeatureOffline(),
                  DsBotAvailability.relay => FeatureMessage(
                    icon: AppIcons.disconnected,
                    title: l10n.botsRelayUnavailable,
                    body: l10n.botsUseSsh,
                  ),
                  DsBotAvailability.missing || DsBotAvailability.outdated => DsBotInstallCard(status: status),
                  DsBotAvailability.failed => FeatureMessage(
                    icon: AppIcons.error,
                    title: l10n.botsTeamLoadFailed,
                    body: status.error,
                    action: (l10n.commonRetry, () => ref.read(dsBotProvider.notifier).retry()),
                  ),
                  _ => QuietSpinner(label: l10n.botsTeamLoading),
                },
              ],
            ),
    );
  }
}

enum _CreateTeamAction { bot, room }

class _TeamScaffold extends ConsumerWidget {
  const _TeamScaffold({required this.status, required this.team, required this.scroll});

  final DsBotStatus status;
  final DsBotTeam team;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = BotWorkspacePalette.of(context);
    final l10n = context.l10n;
    final readOnly = status.readOnly != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(Theme.of(context).brightness),
      child: Scaffold(
        backgroundColor: palette.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSpace.readingWidth),
              child: Column(
                children: [
                  Padding(
                    key: const ValueKey('bots-team-header'),
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: l10n.commonBack,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(AppIcons.back, size: 22),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                namesRoute: true,
                                child: Text(
                                  'DS Bot',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Tooltip(
                                message: _summary(status),
                                child: Text(
                                  '${status.hostLabel} · ${status.feedConnected ? l10n.botsTeamConnected : l10n.botsTeamRefreshing}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          key: const ValueKey('bots-workspace-settings'),
                          tooltip: l10n.commonSettings,
                          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                          padding: EdgeInsets.zero,
                          icon: const Icon(AppIcons.settings, size: 22),
                          onPressed: () => Navigator.of(context).push(BotWorkspaceSettingsPage.route()),
                        ),
                        PopupMenuButton<_CreateTeamAction>(
                          key: const ValueKey('team-create-menu'),
                          tooltip: l10n.commonCreate,
                          enabled: !readOnly,
                          icon: const Icon(AppIcons.add, size: 24),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: _CreateTeamAction.bot, child: Text(l10n.botsNewBot)),
                            PopupMenuItem(
                              value: _CreateTeamAction.room,
                              enabled: team.bots.length >= 2,
                              child: Text(l10n.botsNewGroup),
                            ),
                          ],
                          onSelected: (action) {
                            final current = ref.read(dsBotProvider);
                            if (!current.ready ||
                                current.readOnly != null ||
                                current.host != status.host ||
                                current.hello?.boot != status.hello?.boot) {
                              return;
                            }
                            switch (action) {
                              case _CreateTeamAction.bot:
                                Navigator.of(context).push(NewBotPage.route());
                              case _CreateTeamAction.room:
                                if ((current.team?.bots.length ?? 0) >= 2) showNewRoomSheet(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CustomScrollView(
                      key: const ValueKey('bots-team-scroll'),
                      controller: scroll,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: AppMotion.scrollPhysics(context),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _Team(status: status, team: team),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.background,
                      border: Border(top: BorderSide(color: palette.line)),
                    ),
                    child: Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 8), child: const _TeamSearch()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「本机 · 4 个 Bot · 2 个群聊」.
String _summary(DsBotStatus status) {
  final team = status.team;
  if (!status.ready || team == null) return status.hostLabel;
  return [
    status.hostLabel,
    appL10n.botsBotCount(team.bots.length),
    if (team.rooms.isNotEmpty) appL10n.botsRoomCount(team.rooms.length),
  ].join(' · ');
}

class _Team extends ConsumerWidget {
  const _Team({required this.status, required this.team});

  final DsBotStatus status;
  final DsBotTeam team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final inbox = ref.watch(dsBotInboxProvider);
    final layout = ref.watch(botLayoutProvider(status.host));
    final readOnly = status.readOnly != null;
    DateTime? latest(String id) => inbox.latest[id]?.time;
    int newest(DateTime? a, DateTime? b) => (b ?? DateTime(0)).compareTo(a ?? DateTime(0));
    final mains = [for (final id in team.mainBotIds) ?team.bot(id)];
    final others = [
      for (final bot in team.bots)
        if (!team.isMain(bot.id)) bot,
    ]..sort((a, b) => newest(latest(a.id) ?? a.createdAt, latest(b.id) ?? b.createdAt));
    final rooms = [...team.rooms]..sort((a, b) => newest(latest(a.id) ?? a.createdAt, latest(b.id) ?? b.createdAt));
    var index = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(BotWorkspacePalette.contentInset, 4, BotWorkspacePalette.contentInset, 20),
          child: _TeamAttention(status: status),
        ),
        if (team.bots.isEmpty && team.rooms.isEmpty)
          FeatureMessage(
            icon: AppIcons.bot,
            title: l10n.botsTeamEmpty,
            action: readOnly ? null : (l10n.botsNewBot, () => Navigator.of(context).push(NewBotPage.route())),
          ),
        for (final section in layout.order) ...[
          BotSection(
            key: ValueKey((status.host, section)),
            host: status.host,
            section: section,
            count: switch (section) {
              BotTeamSection.main => mains.length,
              BotTeamSection.members => others.length,
              BotTeamSection.rooms => rooms.length,
            },
            child: switch (section) {
              BotTeamSection.main =>
                mains.isEmpty ? const SizedBox.shrink() : _MainBots(bots: mains, status: status, inbox: inbox),
              BotTeamSection.members => _RosterList(
                children: [
                  for (final bot in others)
                    FadeSlideIn(
                      index: index++,
                      child: BotRow(
                        key: ValueKey('team-bot-${bot.id}'),
                        bot: bot,
                        team: team,
                        live: status.live,
                        inbox: inbox,
                      ),
                    ),
                ],
              ),
              BotTeamSection.rooms => _RosterList(
                children: [
                  for (final room in rooms)
                    FadeSlideIn(
                      index: index++,
                      child: RoomRow(
                        key: ValueKey('team-room-${room.id}'),
                        room: room,
                        team: team,
                        live: status.live,
                        inbox: inbox,
                      ),
                    ),
                ],
              ),
            },
          ),
          const SizedBox(height: 12),
        ],
        if (readOnly) FeatureNote('${status.readOnly}'),
      ],
    );
  }
}

class _MainBots extends StatelessWidget {
  const _MainBots({required this.bots, required this.status, required this.inbox});

  final List<DsBot> bots;
  final DsBotStatus status;
  final DsBotInbox inbox;

  @override
  Widget build(BuildContext context) {
    final palette = BotWorkspacePalette.of(context);
    final l10n = context.l10n;
    final live = status.live;
    final requests = teamAttentionEntries(status);
    final scale = MediaQuery.textScalerOf(context);
    // Paragraphs round fractional font metrics up. At 2x, the state label is
    // 28.6dp by formula and 29dp in layout; budgeting the fraction clips it.
    // Keep complete text pixels and a little air below the last label.
    final nameHeight = (scale.scale(14) * 1.25 * 2).ceilToDouble();
    final stateHeight = (scale.scale(11) * 1.3).ceilToDouble();
    final height = 64 + 10 + nameHeight + 6 + stateHeight + 12 + 4;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: bots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final bot = bots[index];
          final unread = inbox.unreadOf(bot.id);
          final request = requests.where((entry) => !entry.isRoom && entry.id == bot.id).firstOrNull;
          final doing = workPhrase(live.bots[bot.id], activity: live.activity[bot.id]);
          final state = request?.label(context) ?? doing ?? (bot.role.isEmpty ? l10n.botsMainBot : bot.role);
          return SizedBox(
            width: 96,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('team-main-${bot.id}'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(BotChatPage.route(bot.id)),
                child: Semantics(
                  label: [
                    bot.name,
                    l10n.botsMainBot,
                    state,
                    if (unread > 0) l10n.botsUnreadCount(unread),
                  ].join(l10n.botsListSeparator),
                  button: true,
                  onTap: () => Navigator.of(context).push(BotChatPage.route(bot.id)),
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: 64,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            BotAvatar(bot: bot, size: 64, working: live.isWorking(bot.id)),
                            if (unread > 0) Positioned(right: -4, top: -2, child: UnreadBadge(unread)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              bot.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontSize: 14, height: 1.25, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 4),
                          BotTag(l10n.botsMainTag),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(fontSize: 11, height: 1.3, color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TeamSearch extends StatelessWidget {
  const _TeamSearch();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    return Semantics(
      key: const ValueKey('bots-team-search'),
      button: true,
      label: l10n.botsTeamSearch,
      onTap: () => showBotSearch(context),
      excludeSemantics: true,
      child: Hero(
        tag: 'dsbot-search-bar',
        child: Material(
          color: palette.subtle,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showBotSearch(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(AppIcons.search, size: 21, color: palette.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.botsTeamSearch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamAttention extends StatelessWidget {
  const _TeamAttention({required this.status});

  final DsBotStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    final items = teamAttentionEntries(status);
    final waiting = items.isNotEmpty;
    return Material(
      key: const ValueKey('bots-team-attention'),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: waiting ? () => showTeamAttentionSheet(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          child: Row(
            children: [
              Icon(
                waiting ? AppIcons.toConfirm : AppIcons.allRead,
                size: 21,
                color: waiting ? palette.ink : palette.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  waiting ? l10n.botsTeamAttentionCount(items.length) : l10n.botsTeamAllClear,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: waiting ? palette.ink : palette.muted,
                    fontWeight: waiting ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (waiting) ...[const SizedBox(width: 8), Icon(AppIcons.forward, size: 18, color: palette.muted)],
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterList extends StatelessWidget {
  const _RosterList({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = BotWorkspacePalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: 76, endIndent: 16, color: palette.line),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A Bot: avatar (with a dot while it works), name with a 「主」 tag, its last
/// words or what it is doing, the time and an unread count.
class BotRow extends StatelessWidget {
  const BotRow({super.key, required this.bot, required this.team, required this.live, required this.inbox});

  final DsBot bot;
  final DsBotTeam team;
  final DsBotLive live;
  final DsBotInbox inbox;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final work = live.bots[bot.id];
    final doing = workPhrase(work, activity: live.activity[bot.id]);
    final notice = inbox.latest[bot.id];
    final unread = inbox.unreadOf(bot.id);
    final question = team.questionOf(bot) != null || team.viewOf(bot) != null;
    final approval = live.approvals.any(
      (entry) => entry.roomId == null && entry.botId == bot.id && entry.sessionId == bot.sessionId,
    );
    final String subtitle;
    Color? subtitleColor;
    if (approval) {
      subtitle = l10n.commonWaitingApproval;
      subtitleColor = DshColors.of(context).warning;
    } else if (question) {
      subtitle = l10n.commonWaitingAnswer;
      subtitleColor = DshColors.of(context).warning;
    } else if (doing != null) {
      final room = team.room(work?.roomId);
      subtitle = room == null ? doing : '$doing · ${room.name}';
      subtitleColor = DshColors.of(context).info;
    } else if (bot.waiting) {
      subtitle = l10n.botsChooseModelStart;
      subtitleColor = DshColors.of(context).warning;
    } else if (notice != null && notice.roomId == null && notice.text.isNotEmpty) {
      subtitle = notice.text;
    } else {
      subtitle = bot.role.isEmpty ? l10n.botsNoChats : bot.role;
    }
    void open() => Navigator.of(context).push(BotChatPage.route(bot.id));
    return Semantics(
      button: true,
      onTap: open,
      label: [
        bot.name,
        if (team.isMain(bot.id)) l10n.botsMainBot,
        subtitle,
        if (unread > 0) l10n.botsUnreadCount(unread),
      ].join(l10n.botsListSeparator),
      excludeSemantics: true,
      child: ListPageRow(
        leading: BotAvatar(bot: bot, size: 48, working: work != null),
        leadingWidth: 48,
        title: bot.name,
        titleStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        titleMaxLines: 2,
        badge: team.isMain(bot.id) ? BotTag(l10n.botsMainTag) : null,
        subtitle: subtitle,
        subtitleColor: subtitleColor,
        subtitleMaxLines: 2,
        meta: notice == null ? null : shortTime(notice.time),
        trailing: unread > 0 ? UnreadBadge(unread) : null,
        chevron: false,
        onTap: open,
      ),
    );
  }
}

/// A group chat: members stacked, its name, the last line or who works.
class RoomRow extends StatelessWidget {
  const RoomRow({super.key, required this.room, required this.team, required this.live, required this.inbox});

  final DsBotRoom room;
  final DsBotTeam team;
  final DsBotLive live;
  final DsBotInbox inbox;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final working = live.rooms[room.id] ?? const <DsBotWork>[];
    final notice = inbox.latest[room.id];
    final unread = inbox.unreadOf(room.id);
    final waiting = live.approvals.any((a) => a.roomId == room.id && a.answerable);
    final String subtitle;
    Color? subtitleColor;
    if (waiting) {
      subtitle = l10n.botsMemberNeedsApproval;
      subtitleColor = DshColors.of(context).warning;
    } else if (working.isNotEmpty) {
      final names = [for (final w in working) team.bot(w.botId)?.name ?? 'Bot'];
      subtitle = names.length == 1
          ? l10n.botsNamedWorking(names.first)
          : l10n.botsNamesWorking(names.take(2).join(l10n.botsNameSeparator));
      subtitleColor = DshColors.of(context).info;
    } else {
      final preview = roomPreview(room, team);
      subtitle = preview.isEmpty ? l10n.botsMemberCount(room.members.length) : preview;
    }
    void open() => Navigator.of(context).push(RoomChatPage.route(room.id));
    return Semantics(
      button: true,
      onTap: open,
      label: [room.name, subtitle, if (unread > 0) l10n.botsUnreadCount(unread)].join(l10n.botsListSeparator),
      excludeSemantics: true,
      child: ListPageRow(
        leading: RoomAvatar(room: room, team: team, size: 48),
        leadingWidth: 48,
        title: room.name,
        titleStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        titleMaxLines: 2,
        subtitle: subtitle,
        subtitleColor: subtitleColor,
        subtitleMaxLines: 2,
        meta: notice == null ? null : shortTime(notice.time),
        trailing: unread > 0 ? UnreadBadge(unread) : null,
        chevron: false,
        onTap: open,
      ),
    );
  }
}

/// Count of unread messages: a primary capsule, round for one digit.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});

  final int count;

  static const height = 20.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: height, minHeight: height, maxHeight: height),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: scheme.primary, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            widthFactor: 1,
            child: RollingCount(
              count > 99 ? '99+' : '$count',
              textScaler: TextScaler.noScaling,
              style: AppType.tabular(
                Theme.of(context).textTheme.labelSmall!
                    .copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small quiet tag after a name (「主」「管理员」).
class BotTag extends StatelessWidget {
  const BotTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
        shape: const RoundedSuperellipseBorder(borderRadius: AppShape.radiusXs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          textScaler: TextScaler.noScaling,
          style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary, height: 1.2),
        ),
      ),
    );
  }
}
