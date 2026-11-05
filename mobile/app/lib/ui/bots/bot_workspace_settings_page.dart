import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../common/list_page_row.dart';
import '../features/feature_widgets.dart';
import '../settings/settings_screen.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import 'bot_action_scope.dart';
import 'bot_schedules_page.dart';
import 'bot_sections.dart';
import 'bot_workspace.dart';

/// Workspace navigation, with local phone preferences kept distinct from
/// host tasks and the app's existing settings hub.
class BotWorkspaceSettingsPage extends ConsumerWidget {
  const BotWorkspaceSettingsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const BotWorkspaceSettingsPage());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    final scope = BotActionScope(ref);
    return BotWorkspace(
      child: Builder(
        builder: (context) {
          final l10n = context.l10n;
          return AppPage.list(
            key: const ValueKey('bot-workspace-settings'),
            title: l10n.botsWorkspaceSettings,
            children: [
              ListPageCard(
                title: l10n.botsWorkspaceTeam,
                children: [
                  ListPageRow(
                    icon: AppIcons.remoteHost,
                    title: status.hostLabel,
                    subtitle: status.ready ? l10n.botsTeamConnected : l10n.commonNotConnected,
                    chevron: false,
                  ),
                  if (team != null)
                    ListPageRow(
                      icon: AppIcons.groupChat,
                      title: l10n.botsBotCount(team.bots.length),
                      subtitle: l10n.botsRoomCount(team.rooms.length),
                      chevron: false,
                    ),
                  ListPageRow(
                    key: const ValueKey('bot-settings-schedules'),
                    icon: AppIcons.scheduled,
                    title: l10n.botsSchedules,
                    onTap: status.ready
                        ? () {
                            if (scope.connected(context, ref)) Navigator.of(context).push(BotSchedulesPage.route());
                          }
                        : null,
                  ),
                ],
              ),
              if (status.readOnly != null) FeatureNote('${status.readOnly}'),
              const SizedBox(height: 24),
              ListPageCard(
                title: l10n.botsWorkspaceMobile,
                children: [
                  ListPageRow(
                    key: const ValueKey('bot-settings-sections'),
                    icon: AppIcons.menu,
                    title: l10n.botsWorkspaceDisplay,
                    subtitle: l10n.botsWorkspaceDisplayHint,
                    subtitleMaxLines: 2,
                    onTap: () => showBotSectionsSettings(context),
                  ),
                ],
              ),
              FeatureNote(l10n.botsWorkspaceLocalOnly),
              const SizedBox(height: 24),
              ListPageCard(
                children: [
                  ListPageRow(
                    key: const ValueKey('bot-settings-app'),
                    icon: AppIcons.settings,
                    title: l10n.botsWorkspaceAppSettings,
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
