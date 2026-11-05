import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/bot_layout_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/ui/bots/bot_schedules_page.dart';
import 'package:dsh_app/ui/bots/bot_workspace_settings_page.dart';
import 'package:dsh_app/ui/bots/bots_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts;
import 'refinement_harness.dart';
import 'support.dart';

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('workspace settings is a separate page with phone-only wording and existing task navigation', (
    tester,
  ) async {
    final fake = FakeDsBotTransport(team: sampleTeam(working: false))
      ..handlers['schedules'] = (_) => {'available': true, 'tasks': []};
    await openRefinement(tester, const BotsPage(), fake, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('bots-workspace-settings')));
    await refinementFrames(tester);
    expect(find.byType(BotWorkspaceSettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('bots-team-header')), findsNothing);
    final l10n = tester.element(find.byType(BotWorkspaceSettingsPage)).l10n;
    expect(find.text(l10n.botsWorkspaceLocalOnly), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-settings-sections')), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-settings-app')), findsOneWidget);
    await captureRefinement(tester, 'workspace-settings-390-dark');
    await tester.tap(find.byKey(const ValueKey('bot-settings-schedules')));
    await refinementFrames(tester);
    expect(find.byType(BotSchedulesPage), findsOneWidget);
    expect(find.text(l10n.botsSchedulesNone), findsOneWidget);
    expect(fake.endpoints.where((e) => e == 'schedules'), hasLength(1));
    expect(fake.endpoints.where((e) => ['schedule-create', 'schedule-delete', 'update-bot'].contains(e)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section menu renames, folds with a count and moves the phone section without changing the host', (
    tester,
  ) async {
    final fake = FakeDsBotTransport(team: sampleTeam(working: false));
    await openRefinement(tester, const BotsPage(), fake, width: 320, scale: 2);
    final container = ProviderScope.containerOf(tester.element(find.byType(BotsPage)));
    Future<void> menu(String action) async {
      final icon = find.byKey(const ValueKey('bot-section-menu-members'));
      await tester.ensureVisible(icon);
      await refinementFrames(tester, 2);
      await tester.tap(icon);
      await refinementFrames(tester, 2);
      final item = find.byKey(ValueKey('bot-section-$action-members'));
      await tester.ensureVisible(item);
      await refinementFrames(tester, 3);
      if (action == 'move-up') await captureRefinement(tester, 'section-menu-320-large-text');
      await tester.tap(item);
      await refinementFrames(tester);
    }

    await menu('rename');
    const name = '本机负责写作与程序开发的伙伴们';
    await tester.enterText(find.byType(TextField), name);
    FocusManager.instance.primaryFocus?.unfocus();
    await refinementFrames(tester, 2);
    final save = find.byType(FilledButton);
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await refinementFrames(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('bot-section-title-members'))).data, name);
    await tester.tap(find.byKey(const ValueKey('bot-section-toggle-members')));
    await refinementFrames(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('bot-section-count-members'))).data, '2');
    final layout = container.read(botLayoutProvider(HostRef.local));
    expect(layout.titles[BotTeamSection.members], name);
    expect(layout.collapsed, contains(BotTeamSection.members));
    await menu('move-up');
    expect(container.read(botLayoutProvider(HostRef.local)).order.first, BotTeamSection.members);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bot-section-toggle-members'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('bot-section-toggle-main'))).dy),
    );
    await captureRefinement(tester, 'roster-sections-320-large-text');
    expect(fake.endpoints.where((e) => !['hello', 'state', 'notices', 'avatar'].contains(e)), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
