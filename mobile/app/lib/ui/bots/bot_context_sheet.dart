// Mobile counterpart of a contextual side panel: the conversation keeps its
// reading space, and the person opens actions or completed replies on demand.
// This uses the existing DS Bot contracts; a reply is not a downloaded file.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/connection_state.dart';
import '../chat/widgets/approval_card.dart';
import '../chat/widgets/message_actions.dart';
import '../common/app_sheet.dart';
import '../features/feature_kit.dart';
import '../features/feature_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_action_scope.dart';
import 'bot_chat_kit.dart';
import 'bot_chat_page.dart' show pickBotModel;
import 'bot_format.dart';
import 'bot_pending_card.dart';
import 'bot_workspace.dart';

enum BotContextTab { pending, results }

Future<void> showBotContext(
  BuildContext context,
  WidgetRef ref,
  String botId, {
  BotContextTab initialTab = BotContextTab.pending,
}) async {
  final origin = ref.read(dsBotProvider);
  final api = ref.read(dsBotProvider.notifier).api;
  final bot = origin.team?.bot(botId);
  if (!origin.ready || bot == null || api == null) return;
  final client = ref.read(activeConnectionProvider).value?.client;
  await showAppSheet<void>(
    context,
    heightFactor: 0.88,
    glass: false,
    dismissal: SheetDismissal.button,
    builder: (_) => BotWorkspace(
      child: _BotContextSheet(origin: origin, api: api, bot: bot, client: client, initialTab: initialTab),
    ),
  );
}

/// Always a small entry above the composer, regardless of how many cards the
/// Bot leaves. Counts come from the same state and pending requests as the panel.
class BotContextBar extends ConsumerWidget {
  const BotContextBar({super.key, required this.botId, required this.onOpen});

  final String botId;
  final ValueChanged<BotContextTab> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dsBotProvider);
    final bot = status.team?.bot(botId);
    if (bot == null) return const SizedBox.shrink();
    final client = ref.watch(activeConnectionProvider.select((c) => c.value?.client));
    final question = status.team?.questionOf(bot);
    final view = status.team?.viewOf(bot);
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    return _ApprovalInbox(
      client: client,
      sessionId: bot.sessionId,
      builder: (context, requests) {
        final pending = (bot.waiting ? 1 : 0) + (question != null || view != null ? 1 : 0) + requests.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextButton.icon(
                    key: const ValueKey('bot-pending-actions'),
                    onPressed: () => onOpen(BotContextTab.pending),
                    style: TextButton.styleFrom(
                      foregroundColor: pending > 0 ? DshColors.of(context).warning : palette.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      minimumSize: const Size(0, 44),
                    ),
                    icon: Icon(pending > 0 ? AppIcons.toConfirm : AppIcons.allRead, size: 18),
                    label: Text(
                      pending > 0 ? l10n.botsPendingActionCount(pending) : l10n.botsNoPendingActions,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                SizedBox(height: 18, child: VerticalDivider(width: 1, color: palette.line)),
                Expanded(
                  flex: 2,
                  child: TextButton.icon(
                    key: const ValueKey('bot-results'),
                    onPressed: () => onOpen(BotContextTab.results),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.ink,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(AppIcons.document, size: 18),
                    label: Text(l10n.botsResults, style: Theme.of(context).textTheme.labelMedium),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BotContextSheet extends ConsumerStatefulWidget {
  const _BotContextSheet({
    required this.origin,
    required this.api,
    required this.bot,
    required this.client,
    required this.initialTab,
  });

  final DsBotStatus origin;
  final DsBotApi api;
  final DsBot bot;
  final DshClient? client;
  final BotContextTab initialTab;

  @override
  ConsumerState<_BotContextSheet> createState() => _BotContextSheetState();
}

class _BotContextSheetState extends ConsumerState<_BotContextSheet> {
  late BotContextTab _tab = widget.initialTab;
  bool _retired = false;
  int _inFlight = 0;
  final _approvalInFlight = <String>{};
  ProviderSubscription<DsBotStatus>? _status;
  StreamSubscription<DsBotFeedEvent>? _feed;

  bool _sameTarget() {
    if (!mounted || _retired) return false;
    final status = ref.read(dsBotProvider);
    return identical(widget.api, ref.read(dsBotProvider.notifier).api) &&
        status.host == widget.origin.host &&
        status.hello?.boot == widget.origin.hello?.boot &&
        status.ready &&
        status.team?.bot(widget.bot.id)?.sessionId == widget.bot.sessionId;
  }

  void _retire() {
    if (mounted && !_retired) setState(() => _retired = true);
  }

  void _busyChanged(bool busy) {
    if (!mounted) return;
    setState(() {
      _inFlight += busy ? 1 : -1;
      if (_inFlight < 0) _inFlight = 0;
    });
  }

  @override
  void initState() {
    super.initState();
    if (!_sameTarget()) _retired = true;
    // Remember a transient A -> B -> A change, rather than making an old
    // question or approval writable again when a former target comes back.
    _status = ref.listenManual(dsBotProvider, (_, _) {
      if (!_sameTarget()) _retire();
    });
    final boot = widget.origin.hello?.boot;
    _feed = ref.read(dsBotProvider.notifier).events.listen((event) {
      if (event case DsBotFeedHello(boot: final next?)
          when boot != null && boot.isNotEmpty && next.isNotEmpty && next != boot) {
        _retire();
      }
    });
  }

  @override
  void dispose() {
    _status?.close();
    unawaited(_feed?.cancel());
    super.dispose();
  }

  Future<void> _respondApproval(ApprovalRequest request, ApprovalDecision decision) async {
    final client = widget.client;
    bool current() =>
        _sameTarget() &&
        ref.read(dsBotProvider).readOnly == null &&
        identical(client, ref.read(activeConnectionProvider).value?.client) &&
        _requests(client, widget.bot.sessionId).any((r) => r.eventId == request.eventId);
    if (client == null || !current() || !_approvalInFlight.add(request.eventId)) return;
    _busyChanged(true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await client.respondApproval(request, decision);
    } catch (error) {
      if (current()) {
        messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
      }
    } finally {
      _approvalInFlight.remove(request.eventId);
      _busyChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(dsBotProvider);
    final current = _sameTarget();
    final bot = current ? status.team?.bot(widget.bot.id) : null;
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    final busy = current && _inFlight > 0;
    return PopScope(
      canPop: !busy,
      child: ColoredBox(
        key: const ValueKey('bot-context-sheet'),
        color: palette.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(l10n.botsContextTitle, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ),
                  SheetIconButton(
                    key: const ValueKey('bot-context-close'),
                    icon: AppIcons.close,
                    tooltip: l10n.commonClose,
                    onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            if (!current || bot == null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FeatureMessage(
                    key: const ValueKey('bot-context-retired'),
                    icon: AppIcons.disconnected,
                    title: l10n.botsContextChanged,
                    body: l10n.botsContextReopen,
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    for (final (tab, label, key) in [
                      (BotContextTab.pending, l10n.botsPendingActions, 'bot-context-pending-tab'),
                      (BotContextTab.results, l10n.botsResults, 'bot-context-results-tab'),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: TextButton(
                            key: ValueKey(key),
                            onPressed: () => setState(() => _tab = tab),
                            style: TextButton.styleFrom(
                              foregroundColor: _tab == tab ? palette.ink : palette.muted,
                              backgroundColor: _tab == tab ? palette.subtle : Colors.transparent,
                              minimumSize: const Size(0, 44),
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab.index,
                  children: [
                    _ApprovalInbox(
                      client: widget.client,
                      sessionId: bot.sessionId,
                      builder: (context, requests) => _pending(status, bot, requests),
                    ),
                    _results(bot),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pending(DsBotStatus status, DsBot bot, List<ApprovalRequest> requests) {
    final l10n = context.l10n;
    final question = status.team?.questionOf(bot);
    final view = status.team?.viewOf(bot);
    final readOnly = status.readOnly != null;
    final empty = !bot.waiting && question == null && view == null && requests.isEmpty;
    return ListView(
      key: const PageStorageKey('bot-context-pending-list'),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        if (readOnly) FeatureNote('${status.readOnly}'),
        if (bot.waiting && !readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BotModelCard(
              name: bot.name,
              onPick: () {
                if (!_sameTarget()) return;
                unawaited(
                  pickBotModel(
                    context,
                    ref,
                    bot,
                    scope: BotActionScope(ref, botId: bot.id),
                    isCurrent: _sameTarget,
                  ),
                );
              },
            ),
          ),
        if (question != null || view != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BotPendingCard(
              key: ValueKey((
                status.host,
                status.hello?.boot,
                widget.api,
                bot.id,
                bot.sessionId,
                question != null,
                question?.id ?? view?.id,
              )),
              api: widget.api,
              origin: status,
              bot: bot,
              question: question,
              view: view,
              onBusyChanged: _busyChanged,
            ),
          ),
        if (!readOnly)
          for (final request in requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ApprovalCard(key: ValueKey(request.eventId), request: request, onRespond: _respondApproval),
            ),
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: FeatureMessage(icon: AppIcons.allRead, title: l10n.botsNoPendingActions),
          ),
      ],
    );
  }

  Widget _results(DsBot bot) {
    final chat = ref.watch(botChatProvider(bot.id));
    if (chat.loading && chat.items.isEmpty) return const QuietSpinner();
    if (chat.error != null && chat.items.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: FeatureMessage(
          icon: AppIcons.error,
          title: context.l10n.botsMessagesReadFailed,
          body: chat.error,
          action: (context.l10n.commonRetry, () => ref.read(botChatProvider(bot.id).notifier).reload()),
        ),
      );
    }
    final results = [
      for (final item in chat.items.reversed)
        if (item.kind == DsBotItemKind.bot && !item.live && item.text.trim().isNotEmpty) item,
    ];
    if (results.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: FeatureMessage(icon: AppIcons.document, title: context.l10n.botsNoCompletedReplies),
      );
    }
    final palette = BotWorkspacePalette.of(context);
    return ListView.separated(
      key: const PageStorageKey('bot-context-results-list'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Divider(height: 1, color: palette.line),
      ),
      itemBuilder: (context, index) {
        final result = results[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.botsResultFrom(bot.name),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: palette.muted),
                  ),
                ),
                if (result.time case final time?)
                  Text(shortTime(time), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.muted)),
                IconButton(
                  key: ValueKey('bot-result-copy-$index'),
                  onPressed: () => copyMessage(context, result.text),
                  tooltip: context.l10n.commonCopy,
                  icon: const Icon(AppIcons.copy, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BotReplyText(text: result.text, bubble: true),
          ],
        );
      },
    );
  }
}

List<ApprovalRequest> _requests(DshClient? client, String sessionId) => [
  for (final event in client?.mux.pendingRequests ?? const <HostEvent>[])
    if (event is ApprovalRequestedEvent && event.request.sessionId == sessionId) event.request,
];

/// The mux owns approval state. Listen for its changes, without introducing a
/// second source of truth or loading another host/session to draw a counter.
class _ApprovalInbox extends StatefulWidget {
  const _ApprovalInbox({required this.client, required this.sessionId, required this.builder});

  final DshClient? client;
  final String sessionId;
  final Widget Function(BuildContext context, List<ApprovalRequest> requests) builder;

  @override
  State<_ApprovalInbox> createState() => _ApprovalInboxState();
}

class _ApprovalInboxState extends State<_ApprovalInbox> {
  StreamSubscription<HostEvent>? _sub;

  void _attach() {
    unawaited(_sub?.cancel());
    _sub = widget.client?.hostEvents.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(_ApprovalInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client)) _attach();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _requests(widget.client, widget.sessionId));
}
