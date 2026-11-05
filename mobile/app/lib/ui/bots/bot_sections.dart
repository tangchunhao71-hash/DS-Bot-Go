import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bot_layout_state.dart';
import '../../state/bots_state.dart';
import '../../state/hosts_state.dart';
import '../common/app_sheet.dart';
import '../common/expand_reveal.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_sheets.dart';
import 'bot_workspace.dart';

String botSectionDefaultTitle(BuildContext context, BotTeamSection section) => switch (section) {
  BotTeamSection.main => context.l10n.botsMainBot,
  BotTeamSection.members => context.l10n.botsTeamMembers,
  BotTeamSection.rooms => context.l10n.botsGroupChat,
};

enum _SectionAction { rename, restoreName, moveUp, moveDown, toggle }

/// One mobile presentation section. Its header is also the editor, so changes
/// are visible where they apply without changing the connected host's roster.
class BotSection extends ConsumerStatefulWidget {
  const BotSection({super.key, required this.host, required this.section, required this.count, this.child});

  final HostRef host;
  final BotTeamSection section;
  final int count;
  final Widget? child;

  @override
  ConsumerState<BotSection> createState() => _BotSectionState();
}

class _BotSectionState extends ConsumerState<BotSection> {
  final _menu = GlobalKey<PopupMenuButtonState<_SectionAction>>();

  bool _current(HostRef host) => mounted && widget.host == host && ref.read(dsBotProvider).host == host;

  Future<void> _perform(_SectionAction action) async {
    final host = widget.host;
    final section = widget.section;
    if (!_current(host)) return;
    final layout = ref.read(botLayoutProvider(host));
    if (!layout.loaded) return;
    final controller = ref.read(botLayoutProvider(host).notifier);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final bool saved;
    switch (action) {
      case _SectionAction.rename:
        final text = await showTextEditSheet(
          context,
          title: l10n.botsSectionRename,
          initial: layout.titles[section] ?? botSectionDefaultTitle(context, section),
          hint: l10n.botsSectionName,
          maxLength: 64,
        );
        if (text == null || !_current(host)) return;
        saved = await controller.rename(section, text);
      case _SectionAction.restoreName:
        saved = await controller.rename(section, null);
      case _SectionAction.moveUp:
        saved = await controller.move(section, -1);
      case _SectionAction.moveDown:
        saved = await controller.move(section, 1);
      case _SectionAction.toggle:
        saved = await controller.toggle(section);
    }
    if (!saved && _current(host)) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.botsSectionSavedFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    final layout = ref.watch(botLayoutProvider(widget.host));
    final section = widget.section;
    final id = section.name;
    final collapsed = layout.collapsed.contains(section);
    final index = layout.order.indexOf(section);
    final title = layout.titles[section] ?? botSectionDefaultTitle(context, section);
    final toggleLabel = collapsed ? l10n.botsSectionExpand : l10n.botsSectionCollapse;
    return Column(
      key: ValueKey('bot-section-$id'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  expanded: !collapsed,
                  label: [title, if (collapsed) '${widget.count}'].join(l10n.botsListSeparator),
                  hint: toggleLabel,
                  onTap: layout.loaded ? () => _perform(_SectionAction.toggle) : null,
                  onLongPress: layout.loaded ? () => _menu.currentState?.showButtonMenu() : null,
                  excludeSemantics: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('bot-section-toggle-$id'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: layout.loaded ? () => _perform(_SectionAction.toggle) : null,
                      onLongPress: layout.loaded ? () => _menu.currentState?.showButtonMenu() : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          children: [
                            Icon(collapsed ? AppIcons.disclosure : AppIcons.expand, size: 17, color: palette.muted),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                title,
                                key: ValueKey('bot-section-title-$id'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: palette.muted),
                              ),
                            ),
                            if (collapsed) ...[
                              const SizedBox(width: 10),
                              Text(
                                '${widget.count}',
                                key: ValueKey('bot-section-count-$id'),
                                style: AppType.tabular(
                                  Theme.of(context).textTheme.labelMedium!.copyWith(color: palette.muted),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<_SectionAction>(
                key: _menu,
                tooltip: l10n.botsSectionOptions,
                enabled: layout.loaded,
                icon: Icon(AppIcons.more, key: ValueKey('bot-section-menu-$id'), size: 21, color: palette.muted),
                constraints: const BoxConstraints(minWidth: 180),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: ValueKey('bot-section-rename-$id'),
                    value: _SectionAction.rename,
                    child: Text(l10n.botsSectionRename),
                  ),
                  PopupMenuItem(
                    key: ValueKey('bot-section-restore-$id'),
                    value: _SectionAction.restoreName,
                    enabled: layout.titles.containsKey(section),
                    child: Text(l10n.botsSectionRestoreName),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    key: ValueKey('bot-section-move-up-$id'),
                    value: _SectionAction.moveUp,
                    enabled: index > 0,
                    child: Text(l10n.botsSectionMoveUp),
                  ),
                  PopupMenuItem(
                    key: ValueKey('bot-section-move-down-$id'),
                    value: _SectionAction.moveDown,
                    enabled: index < layout.order.length - 1,
                    child: Text(l10n.botsSectionMoveDown),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: _SectionAction.toggle, child: Text(toggleLabel)),
                ],
                onSelected: _perform,
              ),
            ],
          ),
        ),
        if (widget.child != null) ExpandReveal(open: !collapsed, child: widget.child!),
      ],
    );
  }
}

Future<void> showBotSectionsSettings(BuildContext context) async {
  final host = ProviderScope.containerOf(context, listen: false).read(dsBotProvider).host;
  await showAppSheet<void>(
    context,
    heightFactor: 0.72,
    glass: false,
    dismissal: SheetDismissal.button,
    builder: (_) => BotWorkspace(child: _BotSectionsSettings(host: host)),
  );
}

class _BotSectionsSettings extends ConsumerWidget {
  const _BotSectionsSettings({required this.host});

  final HostRef host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dsBotProvider);
    final layout = ref.watch(botLayoutProvider(host));
    final palette = BotWorkspacePalette.of(context);
    final team = status.host == host ? status.team : null;
    return Material(
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          SheetHeader(context.l10n.botsSectionsSettings),
          Expanded(
            child: status.host != host
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.l10n.botsRelayLimitConnectionChanged),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final section in layout.order)
                        BotSection(
                          key: ValueKey((host, section)),
                          host: host,
                          section: section,
                          count: switch (section) {
                            BotTeamSection.main =>
                              team == null ? 0 : team.bots.where((bot) => team.isMain(bot.id)).length,
                            BotTeamSection.members =>
                              team == null ? 0 : team.bots.where((bot) => !team.isMain(bot.id)).length,
                            BotTeamSection.rooms => team?.rooms.length ?? 0,
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
