import 'dart:math' as math;

import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_app/ui/bots/bot_character.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show loadTestFonts;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

void main() {
  setUpAll(loadTestFonts);
  for (final size in [32.0, 40.0, 56.0, 64.0]) {
    testWidgets('stacked avatars leave the rear native eyes clear at $size', (tester) async {
      final team = DsBotTeam.fromJson(sampleTeam(working: false));
      await tester.pumpWidget(
        goldenApp(
          brightness: Brightness.light,
          home: Scaffold(
            body: Center(
              child: RoomAvatar(room: team.room('r1')!, team: team, size: size),
            ),
          ),
        ),
      );
      await tester.pump();
      final tile = tester.getRect(find.byType(RoomAvatar));
      final faces = find.byType(BotAvatar);
      final back = tester.getRect(faces.first);
      final front = tester.getRect(faces.last);
      final gap = (size * .05).clamp(1.5, 3.0);
      final eyes = botCharacters[botShapeOf(team.bot('m1')!)]!.eyes;
      expect(eyes, hasLength(2));
      for (final eye in eyes) {
        final rotation = eye[4] * math.pi / 180;
        for (var sample = 0; sample < 16; sample++) {
          final angle = sample * math.pi / 8;
          final x = math.cos(angle) * eye[2] / 2;
          final y = math.sin(angle) * eye[3] / 2;
          final point =
              back.topLeft +
              Offset(
                (eye[0] + x * math.cos(rotation) - y * math.sin(rotation)) * back.width / 100,
                (eye[1] + x * math.sin(rotation) + y * math.cos(rotation)) * back.height / 100,
              );
          expect((point - front.center).distance, greaterThan(front.width / 2 + gap + .5));
        }
      }
      expect(back.width, closeTo(size * .6, .01));
      expect(back.height, closeTo(size * .6, .01));
      expect(front.size, back.size);
      expect(back.left, tile.left);
      expect(back.top, tile.top);
      expect(front.right, tile.right);
      expect(front.bottom, tile.bottom);
      expect(back.center.dx + front.center.dx, closeTo(tile.center.dx * 2, .5));
      expect(back.center.dy + front.center.dy, closeTo(tile.center.dy * 2, .5));
    });
  }
}
