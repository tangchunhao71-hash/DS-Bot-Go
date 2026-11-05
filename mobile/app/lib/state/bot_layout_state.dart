// Presentation preferences for the mobile Bot workspace. These are private
// to this app and host; they never change the desktop roster or its groups.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hosts_state.dart';

enum BotTeamSection { main, members, rooms }

/// Use the same identity as HostRef equality, never the editable display name.
String botLayoutPrefsKey(HostRef host) => 'ds_bot_mobile_layout_v1:${host.kind.name}:${Uri.encodeComponent(host.id)}';

@immutable
class BotLayout {
  const BotLayout({
    this.order = BotTeamSection.values,
    this.titles = const {},
    this.collapsed = const {},
    this.loaded = false,
  });

  final List<BotTeamSection> order;
  final Map<BotTeamSection, String> titles;
  final Set<BotTeamSection> collapsed;
  final bool loaded;

  /// Stored names are overrides; defaults follow the app's current language.
  static bool validTitle(String value) =>
      value.trim().isNotEmpty && value.length <= 256 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

  static BotLayout decode(String? raw) {
    const fallback = BotLayout(loaded: true);
    if (raw == null || raw.length > 16384) return fallback;
    try {
      final map = jsonDecode(raw);
      if (map is! Map || map['version'] != 1) return fallback;
      final rawOrder = map['order'];
      final rawTitles = map['titles'];
      final rawCollapsed = map['collapsed'];
      if (rawOrder is! List || rawTitles is! Map || rawCollapsed is! List) return fallback;
      BotTeamSection? section(Object? value) => BotTeamSection.values.where((item) => item.name == value).firstOrNull;
      final order = <BotTeamSection>[];
      for (final value in rawOrder) {
        final item = section(value);
        if (item == null || order.contains(item)) return fallback;
        order.add(item);
      }
      if (order.length != BotTeamSection.values.length) return fallback;
      final titles = <BotTeamSection, String>{};
      for (final entry in rawTitles.entries) {
        final item = section(entry.key);
        final value = entry.value;
        if (item == null || value is! String || !validTitle(value)) return fallback;
        titles[item] = value.trim();
      }
      final collapsed = <BotTeamSection>{};
      for (final value in rawCollapsed) {
        final item = section(value);
        if (item == null || !collapsed.add(item)) return fallback;
      }
      return BotLayout(
        order: List.unmodifiable(order),
        titles: Map.unmodifiable(titles),
        collapsed: Set.unmodifiable(collapsed),
        loaded: true,
      );
    } catch (_) {
      return fallback;
    }
  }

  String encode() => jsonEncode({
    'version': 1,
    'order': [for (final section in order) section.name],
    'titles': {for (final entry in titles.entries) entry.key.name: entry.value},
    'collapsed': [for (final section in collapsed) section.name],
  });
}

/// An injectable boundary for delayed reads and failed writes in tests.
abstract class BotLayoutStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesBotLayoutStore implements BotLayoutStore {
  final _prefs = SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await (await _prefs).setString(key, value)) throw StateError('Bot layout preference write failed');
  }
}

final botLayoutStoreProvider = Provider<BotLayoutStore>((ref) => SharedPreferencesBotLayoutStore());

class BotLayoutController extends Notifier<BotLayout> {
  BotLayoutController(this.host);

  final HostRef host;
  late BotLayoutStore _store;
  late Future<void> _loaded;
  Future<void> _writes = Future.value();
  int _generation = 0;

  @override
  BotLayout build() {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    _store = ref.read(botLayoutStoreProvider);
    _loaded = _load(generation);
    return const BotLayout();
  }

  Future<void> get ready => _loaded;

  bool _current(int generation) => ref.mounted && generation == _generation;

  Future<void> _load(int generation) async {
    String? raw;
    try {
      raw = await _store.read(botLayoutPrefsKey(host));
    } catch (_) {
      // A missing or unreadable local preference uses the same safe defaults.
    }
    if (_current(generation)) state = BotLayout.decode(raw);
  }

  Future<bool> _update(BotLayout? Function(BotLayout) change) async {
    final generation = _generation;
    await _loaded;
    if (!_current(generation)) return false;
    final next = change(state);
    if (next == null) return false;
    state = next;
    // Capture both payload and host before the async write. Queued edits keep
    // their order, even when the user switches hosts before storage completes.
    final key = botLayoutPrefsKey(host);
    final raw = next.encode();
    final store = _store;
    final write = _writes.then((_) => store.write(key, raw));
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await write;
      return true;
    } catch (_) {
      // Keep the person's current layout, but let the UI report that it was
      // not saved. A later edit writes a complete new snapshot.
      return false;
    }
  }

  Future<bool> toggle(BotTeamSection section) => _update((layout) {
    final collapsed = {...layout.collapsed};
    if (!collapsed.add(section)) collapsed.remove(section);
    return BotLayout(order: layout.order, titles: layout.titles, collapsed: Set.unmodifiable(collapsed), loaded: true);
  });

  Future<bool> rename(BotTeamSection section, String? title) {
    if (title != null && !BotLayout.validTitle(title)) return Future.value(false);
    return _update((layout) {
      final titles = {...layout.titles};
      if (title == null) {
        titles.remove(section);
      } else {
        titles[section] = title.trim();
      }
      return BotLayout(
        order: layout.order,
        titles: Map.unmodifiable(titles),
        collapsed: layout.collapsed,
        loaded: true,
      );
    });
  }

  Future<bool> move(BotTeamSection section, int delta) {
    if (delta != -1 && delta != 1) return Future.value(false);
    return _update((layout) {
      final order = [...layout.order];
      final current = order.indexOf(section);
      final next = current + delta;
      if (current < 0 || next < 0 || next >= order.length) return null;
      order[current] = order[next];
      order[next] = section;
      return BotLayout(
        order: List.unmodifiable(order),
        titles: layout.titles,
        collapsed: layout.collapsed,
        loaded: true,
      );
    });
  }

  Future<bool> reset() => _update((_) => const BotLayout(loaded: true));
}

// Keep one tiny preference controller per visited host for the app session.
// Returning to a host reuses its pending-write queue instead of racing an old
// queue against a newly created controller for the same preference key.
final botLayoutProvider = NotifierProvider.family<BotLayoutController, BotLayout, HostRef>(BotLayoutController.new);
