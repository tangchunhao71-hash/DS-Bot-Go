// A Bot's own chat: the whole conversation across its parts as DS Bot lays
// it out, the reply it is writing, its cards (a question, a view, a model to
// pick, a DSH approval) and the chat's composer.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/settings_state.dart';
import '../../state/bots_state.dart';
import '../chat/composer.dart';
import '../chat/model_sheet.dart';
import '../common/status_dot.dart';
import '../common/typing_indicator.dart';
import '../features/feature_kit.dart';
import '../features/feature_widgets.dart';
import '../shell/page_frame.dart';
import 'bot_stop_guard.dart';
import 'bot_action_scope.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_draft_send.dart';
import 'bot_avatar.dart';
import 'unavailable_message.dart';
import 'bot_chat_kit.dart';
import 'bot_context_sheet.dart';
import 'bot_details_page.dart';
import 'bot_format.dart';

class BotChatPage extends ConsumerStatefulWidget {
  const BotChatPage({super.key, required this.botId});

  final String botId;

  static Route<void> route(String botId) => MaterialPageRoute<void>(builder: (_) => BotChatPage(botId: botId));

  @override
  ConsumerState<BotChatPage> createState() => _BotChatPageState();
}

class _BotChatPageState extends ConsumerState<BotChatPage> {
  late final BotStopGuard _stopGuard;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scrolled = ValueNotifier(0.0);
  late final DsBotViewingController _viewing;
  bool _contextOpen = false;

  @override
  void initState() {
    super.initState();
    _stopGuard = BotStopGuard(ref);
    _viewing = ref.read(dsBotViewingProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewing.set(widget.botId);
    });
  }

  @override
  void dispose() {
    _stopGuard.dispose();
    _viewing.leave(widget.botId);
    _input.dispose();
    _focus.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  Future<void> _send(BotActionScope target, String part) async {
    if (!mounted || target.botId != widget.botId || !target.current(context, ref)) return;
    final status = ref.read(dsBotProvider);
    if (!status.ready || status.team?.bot(widget.botId)?.sessionId != part) return;
    await sendBotDraft(
      context,
      ref,
      _input,
      botId: widget.botId,
      send: (text) => ref.read(botChatProvider(widget.botId).notifier).send(text),
    );
  }

  Future<void> _openContext(BotContextTab tab) async {
    if (_contextOpen) return;
    _contextOpen = true;
    _focus.unfocus();
    try {
      await showBotContext(context, ref, widget.botId, initialTab: tab);
    } finally {
      _contextOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    final bot = team?.bot(widget.botId);
    final mobileUnavailable =
        status.availability == DsBotAvailability.missing || status.availability == DsBotAvailability.outdated;
    if (team == null || bot == null || mobileUnavailable) {
      return AppPage.list(
        title: 'Bot',
        children: [DsBotUnavailableMessage(status: status, goneIcon: AppIcons.bot, goneTitle: l10n.botsBotGone)],
      );
    }
    final chat = ref.watch(botChatProvider(widget.botId));
    final work = status.live.bots[bot.id];
    final ownTurn = work != null && work.roomId == null;
    final question = team.questionOf(bot);
    final view = team.viewOf(bot);
    final api = ref.read(dsBotProvider.notifier).api;
    final (String label, StatusTone tone) = switch (()) {
      _ when question != null || view != null => (l10n.commonWaitingAnswer, StatusTone.warn),
      _ when bot.waiting => (l10n.botsWaitingModel, StatusTone.warn),
      _ when work != null => (
        [
          workPhrase(work, activity: status.live.activity[bot.id]) ?? l10n.botsThinking,
          ?team.room(work.roomId)?.name,
        ].join(' · '),
        StatusTone.busy,
      ),
      _ => (l10n.botsIdle, StatusTone.ok),
    };
    final rows = transcriptRows(chat.items, pending: chat.pending, streaming: ownTurn ? chat.streaming : null);
    final topInset = BotChatHeader.heightOf(context);
    final rooms = {for (final room in team.rooms) room.id: room.name};
    final readOnly = status.readOnly != null;
    final sendTarget = BotActionScope(ref, botId: bot.id);

    return BotChatFrame(
      header: BotChatHeader(
        face: BotAvatar(bot: bot, size: BotChatHeader.faceSize),
        title: bot.name,
        status: label,
        tone: tone,
        scrolledUnder: _scrolled,
        onDetails: () => Navigator.of(context).push(BotDetailsPage.route(bot.id)),
        onContext: () => _openContext(BotContextTab.pending),
      ),
      body: chat.loading && chat.items.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: topInset),
              child: const SingleChildScrollView(child: QuietSpinner()),
            )
          : chat.error != null && chat.items.isEmpty && chat.pending.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: topInset),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: FeatureMessage(
                  icon: AppIcons.error,
                  title: l10n.botsMessagesReadFailed,
                  body: chat.error,
                  action: (l10n.commonRetry, () => ref.read(botChatProvider(widget.botId).notifier).reload()),
                ),
              ),
            )
          : BotTranscript(
              rows: rows,
              topInset: topInset,
              scrolledUnder: _scrolled,
              hasEarlier: chat.hasEarlier,
              loadingEarlier: chat.loadingEarlier,
              onEarlier: () => ref.read(botChatProvider(widget.botId).notifier).loadEarlier(),
              empty: _Intro(bot: bot),
              rowBuilder: (context, row) => Padding(
                padding: rowPadding(row),
                child: switch (row) {
                  BotTimeRow(:final time) => BotTimeLine(time),
                  BotPendingRow(:final pending) => BotUserMessage(text: pending.text, pending: true),
                  BotStreamingRow(:final text) =>
                    text.isEmpty
                        ? const Align(alignment: Alignment.centerLeft, child: _Thinking())
                        : BotReplyText(text: text, streaming: true, bubble: true),
                  BotTypingRow() => const SizedBox.shrink(),
                  BotItemRow(:final item) => switch (item.kind) {
                    DsBotItemKind.user => BotUserMessage(text: item.text, images: item.images),
                    DsBotItemKind.bot => BotReplyText(text: item.text, bubble: true),
                    DsBotItemKind.event => BotEventLine(
                      text: chatEventText(item, roomName: rooms[item.roomId]),
                      icon: AppIcons.swap,
                    ),
                    DsBotItemKind.answer => BotEventLine(text: l10n.botsAnsweredQuestion, icon: AppIcons.done),
                    DsBotItemKind.divider => BotEventLine(text: l10n.botsEarlierMessages, icon: AppIcons.history),
                    DsBotItemKind.unknown => const SizedBox.shrink(),
                  },
                },
              ),
            ),
      bottom: [
        BotContextBar(botId: bot.id, onOpen: _openContext),
        BotErrorSlot(
          error: chat.items.isNotEmpty || chat.pending.isNotEmpty ? chat.error : null,
          onDismiss: () => ref.read(botChatProvider(widget.botId).notifier).dismissError(),
        ),
        Composer(
          hardwareEnterSends: ref.watch(settingsProvider.select((s) => s.hardwareEnterSends)),
          controller: _input,
          focusNode: _focus,
          connected: api != null && !readOnly,
          running: ownTurn,
          onSend: () => _send(sendTarget, bot.sessionId),
          onStop: _stopGuard.action(botId: bot.id),
          placeholder: l10n.botsComposerHint(bot.name),
        ),
      ],
    );
  }
}

/// Picks [bot]'s model in the chat's model sheet and saves it.
Future<void> pickBotModel(
  BuildContext context,
  WidgetRef ref,
  DsBot bot, {
  BotActionScope? scope,
  bool Function()? isCurrent,
}) {
  final target = scope ?? BotActionScope(ref, botId: bot.id);
  if (!target.current(context, ref)) return Future.value();
  final hub = ref.read(dsBotProvider.notifier);
  final api = target.api;
  bool current() => target.current(context, ref) && (isCurrent?.call() ?? true);

  if (!current()) return Future.value();
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModelSheet(
    context,
    current: botModelSelection(bot),
    onSelected: (selection) async {
      // A modal can outlive a host switch, reconnect, or removal of this Bot.
      // Check before any write; never redirect an old choice through hub.api.
      if (!current()) return;
      try {
        await api!.updateBot(
          bot.id,
          model: '${selection.provider}/${selection.model}',
          // A model without levels clears the previous Bot override.
          // Omission means "keep" to DS Bot, not "use the default".
          effort: selection.reasoningEffort ?? '',
        );
        if (current()) await hub.refresh();
      } catch (error) {
        if (current()) messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
      }
    },
  );
}

/// A Bot's model as the model sheet names it.
ModelSelection? botModelSelection(DsBot bot) {
  final ref = bot.modelRef;
  if (ref == null) return null;
  final slash = ref.indexOf('/');
  if (slash <= 0) return null;
  return ModelSelection(
    provider: ref.substring(0, slash),
    model: ref.substring(slash + 1),
    reasoningEffort: bot.effort,
  );
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: SizedBox(height: 14, child: TypingIndicator(color: DshColors.of(context).textTertiary)),
  );
}

/// The empty chat: the Bot's face, name and role.
class _Intro extends StatelessWidget {
  const _Intro({required this.bot});

  final DsBot bot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BotAvatar(bot: bot, size: 64),
        const SizedBox(height: 12),
        Text(bot.name, style: theme.textTheme.titleLarge),
        if (bot.role.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(bot.role, style: theme.textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary)),
        ],
      ],
    );
  }
}
