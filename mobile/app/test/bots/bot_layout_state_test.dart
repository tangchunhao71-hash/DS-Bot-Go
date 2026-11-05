import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/state/bot_layout_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('layout records round-trip, and invalid records fall back without a partial layout', () {
    const saved = BotLayout(
      order: [BotTeamSection.rooms, BotTeamSection.main, BotTeamSection.members],
      titles: {BotTeamSection.rooms: 'Projects'},
      collapsed: {BotTeamSection.members},
      loaded: true,
    );
    final restored = BotLayout.decode(saved.encode());
    expect(restored.order, saved.order);
    expect(restored.titles, saved.titles);
    expect(restored.collapsed, saved.collapsed);
    expect(restored.loaded, isTrue);

    final valid = jsonDecode(saved.encode()) as Map<String, dynamic>;
    final broken = <String, String?>{
      'missing': null,
      'malformed JSON': '{',
      'non-object': '[]',
      'future schema': jsonEncode({...valid, 'version': 99}),
      'unknown section': jsonEncode({
        ...valid,
        'order': ['rooms', 'main', 'other'],
      }),
      'missing section': jsonEncode({
        ...valid,
        'order': ['rooms', 'main'],
      }),
      'duplicate section': jsonEncode({
        ...valid,
        'order': ['rooms', 'main', 'main'],
      }),
      'unknown title': jsonEncode({
        ...valid,
        'titles': {'other': 'Unknown'},
      }),
      'non-text title': jsonEncode({
        ...valid,
        'titles': {'main': 12},
      }),
      'blank title': jsonEncode({
        ...valid,
        'titles': {'main': '  '},
      }),
      'control character': jsonEncode({
        ...valid,
        'titles': {'main': 'Title\nNext'},
      }),
      'unknown collapsed section': jsonEncode({
        ...valid,
        'collapsed': ['other'],
      }),
      'duplicate collapsed section': jsonEncode({
        ...valid,
        'collapsed': ['main', 'main'],
      }),
    };
    for (final entry in broken.entries) {
      final layout = BotLayout.decode(entry.value);
      expect(layout.order, BotTeamSection.values, reason: entry.key);
      expect(layout.titles, isEmpty, reason: entry.key);
      expect(layout.collapsed, isEmpty, reason: entry.key);
      expect(layout.loaded, isTrue, reason: entry.key);
    }
  });

  test('the preference key uses real host identity and ignores its display name', () {
    expect(
      botLayoutPrefsKey(const HostRef.relay('device-1', name: 'Before')),
      botLayoutPrefsKey(const HostRef.relay('device-1', name: 'After')),
    );
    expect(botLayoutPrefsKey(const HostRef.ssh('device-1')), isNot(botLayoutPrefsKey(const HostRef.relay('device-1'))));
    expect(botLayoutPrefsKey(HostRef.local), isNot(botLayoutPrefsKey(const HostRef.ssh('local'))));
    expect(botLayoutPrefsKey(const HostRef.ssh('a:b')), isNot(botLayoutPrefsKey(const HostRef.ssh('a%3Ab'))));
  });

  test('an early edit waits for its own read, and a late host A read cannot replace host B', () async {
    const a = HostRef.relay('a');
    const b = HostRef.relay('b');
    final aRead = Completer<String?>();
    final bRead = Completer<String?>();
    final store = _LayoutStore()
      ..pendingReads[botLayoutPrefsKey(a)] = aRead
      ..pendingReads[botLayoutPrefsKey(b)] = bRead;
    final container = ProviderContainer(overrides: [botLayoutStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final aController = container.read(botLayoutProvider(a).notifier);
    final edit = aController.rename(BotTeamSection.main, 'A renamed');
    final bController = container.read(botLayoutProvider(b).notifier);
    await _drain();
    expect(store.writes, isEmpty);
    expect(container.read(botLayoutProvider(a)).loaded, isFalse);
    bRead.complete(const BotLayout(titles: {BotTeamSection.rooms: 'B rooms'}).encode());
    await bController.ready;
    aRead.complete(const BotLayout(collapsed: {BotTeamSection.members}).encode());
    expect(await edit, isTrue);
    final layoutA = container.read(botLayoutProvider(a));
    final layoutB = container.read(botLayoutProvider(b));
    expect(layoutA.titles[BotTeamSection.main], 'A renamed');
    expect(layoutA.collapsed, {BotTeamSection.members});
    expect(layoutB.titles, {BotTeamSection.rooms: 'B rooms'});
    expect(layoutB.collapsed, isEmpty);
    expect(store.writes.map((entry) => entry.$1), [botLayoutPrefsKey(a)]);
  });

  test('switching A to B to A reuses the queue and never lets an older write win', () async {
    const a = HostRef.relay('a');
    const b = HostRef.relay('b');
    final store = _LayoutStore();
    final container = ProviderContainer(overrides: [botLayoutStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final firstA = container.read(botLayoutProvider(a).notifier);
    await firstA.ready;
    final gate = Completer<void>();
    store.nextWriteGate = gate;
    final rename = firstA.rename(BotTeamSection.main, 'A name');
    await _drain();
    final bController = container.read(botLayoutProvider(b).notifier);
    await bController.ready;
    expect(await bController.rename(BotTeamSection.rooms, 'B name'), isTrue);
    final returnedA = container.read(botLayoutProvider(a).notifier);
    expect(identical(firstA, returnedA), isTrue);
    final move = returnedA.move(BotTeamSection.members, -1);
    final collapse = returnedA.toggle(BotTeamSection.main);
    await _drain();
    expect(store.writes.where((entry) => entry.$1 == botLayoutPrefsKey(a)), hasLength(1));
    gate.complete();
    expect(await Future.wait([rename, move, collapse]), everyElement(isTrue));
    final storedA = BotLayout.decode(store.values[botLayoutPrefsKey(a)]);
    final storedB = BotLayout.decode(store.values[botLayoutPrefsKey(b)]);
    expect(storedA.order, [BotTeamSection.members, BotTeamSection.main, BotTeamSection.rooms]);
    expect(storedA.titles, {BotTeamSection.main: 'A name'});
    expect(storedA.collapsed, {BotTeamSection.main});
    expect(storedB.titles, {BotTeamSection.rooms: 'B name'});
    expect(storedB.collapsed, isEmpty);
    expect(store.writes.where((entry) => entry.$1 == botLayoutPrefsKey(a)), hasLength(3));
  });

  test('a failed save reports failure once and later edits can persist the full layout', () async {
    final store = _LayoutStore()..failNextWrite = true;
    final container = ProviderContainer(overrides: [botLayoutStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final controller = container.read(botLayoutProvider(HostRef.local).notifier);
    expect(await controller.rename(BotTeamSection.main, 'Unsaved name'), isFalse);
    expect(store.writes, hasLength(1));
    expect(container.read(botLayoutProvider(HostRef.local)).titles[BotTeamSection.main], 'Unsaved name');
    expect(await controller.toggle(BotTeamSection.rooms), isTrue);
    final stored = BotLayout.decode(store.values[botLayoutPrefsKey(HostRef.local)]);
    expect(stored.titles[BotTeamSection.main], 'Unsaved name');
    expect(stored.collapsed, {BotTeamSection.rooms});
    expect(store.writes, hasLength(2));
  });

  test('bounds, invalid titles, name restore and reset do not alter another host', () async {
    const other = HostRef.ssh('other');
    final store = _LayoutStore();
    final container = ProviderContainer(overrides: [botLayoutStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final controller = container.read(botLayoutProvider(HostRef.local).notifier);
    final second = container.read(botLayoutProvider(other).notifier);
    await Future.wait([controller.ready, second.ready]);
    expect(await controller.move(BotTeamSection.main, -1), isFalse);
    expect(await controller.move(BotTeamSection.rooms, 1), isFalse);
    expect(await controller.move(BotTeamSection.main, 2), isFalse);
    expect(await controller.rename(BotTeamSection.main, '  '), isFalse);
    expect(await controller.rename(BotTeamSection.main, 'Line\nBreak'), isFalse);
    expect(store.writes, isEmpty);
    expect(await second.rename(BotTeamSection.rooms, 'Other host'), isTrue);
    expect(await controller.rename(BotTeamSection.main, 'Custom'), isTrue);
    expect(await controller.rename(BotTeamSection.main, null), isTrue);
    expect(container.read(botLayoutProvider(HostRef.local)).titles, isEmpty);
    await controller.move(BotTeamSection.main, 1);
    await controller.toggle(BotTeamSection.rooms);
    expect(await controller.reset(), isTrue);
    final reset = BotLayout.decode(store.values[botLayoutPrefsKey(HostRef.local)]);
    expect(reset.order, BotTeamSection.values);
    expect(reset.titles, isEmpty);
    expect(reset.collapsed, isEmpty);
    expect(BotLayout.decode(store.values[botLayoutPrefsKey(other)]).titles, {BotTeamSection.rooms: 'Other host'});
  });

  test('SharedPreferences restores independent host choices in a fresh container', () async {
    const a = HostRef.relay('a');
    const b = HostRef.relay('b');
    final first = ProviderContainer();
    final aController = first.read(botLayoutProvider(a).notifier);
    final bController = first.read(botLayoutProvider(b).notifier);
    await Future.wait([aController.ready, bController.ready]);
    await aController.rename(BotTeamSection.members, 'A team');
    await aController.move(BotTeamSection.rooms, -1);
    await aController.toggle(BotTeamSection.rooms);
    await bController.rename(BotTeamSection.members, 'B team');
    first.dispose();
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    await Future.wait([
      fresh.read(botLayoutProvider(a).notifier).ready,
      fresh.read(botLayoutProvider(b).notifier).ready,
    ]);
    expect(fresh.read(botLayoutProvider(a)).titles, {BotTeamSection.members: 'A team'});
    expect(fresh.read(botLayoutProvider(a)).order, [BotTeamSection.main, BotTeamSection.rooms, BotTeamSection.members]);
    expect(fresh.read(botLayoutProvider(a)).collapsed, {BotTeamSection.rooms});
    expect(fresh.read(botLayoutProvider(b)).titles, {BotTeamSection.members: 'B team'});
    expect(fresh.read(botLayoutProvider(b)).collapsed, isEmpty);
  });

  test('a pending edit is abandoned if its provider is disposed before the read finishes', () async {
    final read = Completer<String?>();
    final store = _LayoutStore()..pendingReads[botLayoutPrefsKey(HostRef.local)] = read;
    final container = ProviderContainer(overrides: [botLayoutStoreProvider.overrideWithValue(store)]);
    final controller = container.read(botLayoutProvider(HostRef.local).notifier);
    final edit = controller.toggle(BotTeamSection.main);
    container.dispose();
    read.complete(null);
    expect(await edit, isFalse);
    expect(store.writes, isEmpty);
  });
}

Future<void> _drain() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _LayoutStore implements BotLayoutStore {
  final values = <String, String>{};
  final pendingReads = <String, Completer<String?>>{};
  final writes = <(String, String)>[];
  Completer<void>? nextWriteGate;
  bool failNextWrite = false;

  @override
  Future<String?> read(String key) => pendingReads[key]?.future ?? Future.value(values[key]);

  @override
  Future<void> write(String key, String value) async {
    writes.add((key, value));
    final gate = nextWriteGate;
    final fail = failNextWrite;
    nextWriteGate = null;
    failNextWrite = false;
    if (gate != null) await gate.future;
    if (fail) throw StateError('Fixture storage failure');
    values[key] = value;
  }
}
