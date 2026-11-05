import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../features/feature_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_avatar.dart';
import 'bot_chat_page.dart';
import 'bot_workspace.dart';
import 'room_chat_page.dart';

/// Observed mobile search: a dedicated result surface, filters above the list,
/// and the original bottom capsule making room for a separate close control.
/// Only the existing team roster is searched; this does not invent file search.
Future<void> showBotSearch(BuildContext context) async {
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: AppMotion.of(context, const Duration(milliseconds: 280)),
      reverseTransitionDuration: AppMotion.of(context, const Duration(milliseconds: 200)),
      pageBuilder: (_, _, _) => const BotSearchPage(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

enum _SearchKind { all, bots, rooms }

class BotSearchPage extends ConsumerStatefulWidget {
  const BotSearchPage({super.key});

  @override
  ConsumerState<BotSearchPage> createState() => _BotSearchPageState();
}

class _BotSearchPageState extends ConsumerState<BotSearchPage> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final DsBotStatus _origin;
  DsBotApi? _api;
  _SearchKind _kind = _SearchKind.all;
  bool _retired = false;
  bool _focusedInitially = false;
  Animation<double>? _entry;
  ProviderSubscription<DsBotStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _origin = ref.read(dsBotProvider);
    _api = ref.read(dsBotProvider.notifier).api;
    _subscription = ref.listenManual(dsBotProvider, (_, next) {
      if (!_sameTarget(next) && !_retired && mounted) {
        _focus.unfocus();
        setState(() => _retired = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final entry = ModalRoute.of(context)?.animation;
    if (identical(entry, _entry)) return;
    _entry?.removeStatusListener(_entryChanged);
    _entry = entry;
    _entry?.addStatusListener(_entryChanged);
    if (_entry == null || _entry!.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusAfterEntry());
    }
  }

  void _entryChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _focusAfterEntry();
  }

  void _focusAfterEntry() {
    if (!mounted || _retired || _focusedInitially || ModalRoute.of(context)?.isCurrent != true) return;
    _focusedInitially = true;
    _focus.requestFocus();
  }

  bool _sameTarget(DsBotStatus status) =>
      !_retired &&
      status.ready &&
      status.host == _origin.host &&
      status.hello?.boot == _origin.hello?.boot &&
      identical(_api, ref.read(dsBotProvider.notifier).api);

  void _changed() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  @override
  void dispose() {
    _subscription?.close();
    _entry?.removeStatusListener(_entryChanged);
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _open(String id, {required bool room}) {
    final status = ref.read(dsBotProvider);
    if (!_sameTarget(status) || (room ? status.team?.room(id) == null : status.team?.bot(id) == null)) return;
    _focus.unfocus();
    Navigator.of(context).pushReplacement(room ? RoomChatPage.route(id) : BotChatPage.route(id));
  }

  @override
  Widget build(BuildContext context) => BotWorkspace(child: Builder(builder: _body));

  Widget _body(BuildContext context) {
    final palette = BotWorkspacePalette.of(context);
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final current = _sameTarget(status);
    final team = current ? status.team : null;
    final query = _query.text.trim().toLowerCase();
    bool matches(String name, [String role = '']) =>
        query.isEmpty || name.toLowerCase().contains(query) || role.toLowerCase().contains(query);
    final bots = team == null || _kind == _SearchKind.rooms
        ? <DsBot>[]
        : [
            for (final id in team.mainBotIds)
              if (team.bot(id) case final bot? when matches(bot.name, bot.role)) bot,
            for (final bot in team.bots)
              if (!team.isMain(bot.id) && matches(bot.name, bot.role)) bot,
          ];
    final rooms = team == null || _kind == _SearchKind.bots
        ? <DsBotRoom>[]
        : [
            for (final room in team.rooms)
              if (matches(room.name)) room,
          ];
    return Scaffold(
      key: const ValueKey('bot-search-page'),
      backgroundColor: palette.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpace.readingWidth),
            child: Column(
              children: [
                SizedBox(
                  height: (MediaQuery.textScalerOf(context).scale(14) * 1.4 + 40).clamp(64.0, 160.0),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    children: [
                      for (final (kind, label) in [
                        (_SearchKind.all, l10n.botsSearchAll),
                        (_SearchKind.bots, 'Bot'),
                        (_SearchKind.rooms, l10n.botsGroupChat),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('bot-search-filter-${kind.name}'),
                            label: Text(label),
                            selected: _kind == kind,
                            showCheckmark: false,
                            selectedColor: palette.ink,
                            backgroundColor: palette.subtle,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            labelStyle: TextStyle(color: _kind == kind ? palette.background : palette.ink),
                            onSelected: (_) {
                              _kind = kind;
                              _changed();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: !current
                      ? SingleChildScrollView(
                          child: FeatureMessage(
                            icon: AppIcons.disconnected,
                            title: l10n.botsContextChanged,
                            body: l10n.botsContextReopen,
                          ),
                        )
                      : bots.isEmpty && rooms.isEmpty
                      ? SingleChildScrollView(
                          child: FeatureMessage(
                            icon: AppIcons.search,
                            title: l10n.botsTeamNoSearchResults,
                            body: l10n.botsTeamSearchEmpty,
                          ),
                        )
                      : ListView(
                          key: const ValueKey('bot-search-results'),
                          controller: _scroll,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                          children: [
                            for (final bot in bots)
                              ListTile(
                                key: ValueKey('bot-search-bot-${bot.id}'),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                leading: BotAvatar(bot: bot, size: 48),
                                title: Text(
                                  bot.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                subtitle: bot.role.isEmpty
                                    ? null
                                    : Text(bot.role, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Text('Bot', style: TextStyle(color: palette.muted)),
                                onTap: () => _open(bot.id, room: false),
                              ),
                            for (final room in rooms)
                              ListTile(
                                key: ValueKey('bot-search-room-${room.id}'),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                leading: RoomAvatar(room: room, team: team!, size: 48),
                                title: Text(
                                  room.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                trailing: Text(l10n.botsGroupChat, style: TextStyle(color: palette.muted)),
                                onTap: () => _open(room.id, room: true),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Hero(
                          tag: 'dsbot-search-bar',
                          createRectTween: (begin, end) => RectTween(begin: begin, end: end),
                          flightShuttleBuilder: (_, _, _, _, _) => Material(
                            color: palette.subtle,
                            shape: StadiumBorder(side: BorderSide(color: palette.line)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const Icon(AppIcons.search, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(l10n.botsTeamSearch, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          child: Material(
                            color: palette.subtle,
                            shape: StadiumBorder(side: BorderSide(color: palette.line)),
                            child: TextField(
                              key: const ValueKey('bot-search-input'),
                              controller: _query,
                              focusNode: _focus,
                              enabled: current,
                              onChanged: (_) => _changed(),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _focus.unfocus(),
                              decoration: InputDecoration(
                                hintText: l10n.botsTeamSearch,
                                prefixIcon: const Icon(AppIcons.search, size: 22),
                                suffixIcon: _query.text.isEmpty
                                    ? null
                                    : IconButton(
                                        key: const ValueKey('bot-search-clear'),
                                        tooltip: l10n.commonClear,
                                        icon: const Icon(AppIcons.close, size: 18),
                                        onPressed: () {
                                          _query.clear();
                                          _changed();
                                        },
                                      ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        key: const ValueKey('bot-search-close'),
                        tooltip: l10n.commonClose,
                        style: IconButton.styleFrom(backgroundColor: palette.subtle, minimumSize: const Size(48, 48)),
                        icon: const Icon(AppIcons.close, size: 25),
                        onPressed: () {
                          _focus.unfocus();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
