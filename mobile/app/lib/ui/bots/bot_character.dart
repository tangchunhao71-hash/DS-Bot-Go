// Portions derived from DS Bot (https://github.com/Fei2411/DS-Bot), Apache-2.0.
// Source: ds-bot/src/client/characters.js, mark.js, styles.js at 0dde6a76254d.
// Modified: native Flutter paths, transparent eye cutouts and state motion;
// idle animation uses short, scheduled bursts rather than a continuous ticker.
// See THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'bot_character_data.dart';

export 'bot_character_data.dart' show botCharacters;

const botDefaultShapes = ['star', 'moon', 'gumdrop', 'peanut', 'bunny', 'kitty', 'acorn'];

int _multiply32(int a, int b) {
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return (al * bl + (((ah * bl + al * bh) << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

/// Exactly DS Bot's FNV-1a + fmix32 choice, including UTF-16 ids.
String botDefaultShape(String id) {
  var value = dsBotFnv1a(id);
  value = _multiply32(value ^ (value >> 16), 73244475);
  value = _multiply32(value ^ (value >> 13), 3266489909);
  return botDefaultShapes[((value ^ (value >> 16)) & 0xFFFFFFFF) % botDefaultShapes.length];
}

String botShapeOf(DsBot bot) => botCharacters.containsKey(bot.shape) ? bot.shape! : botDefaultShape(bot.id);

/// DS Bot's actual silhouette and layered colors, with eyes cut out to reveal
/// the underlying surface. Small transcript marks may set [live] to false.
class BotCharacter extends StatefulWidget {
  const BotCharacter({
    super.key,
    required this.shape,
    required this.color,
    this.seed = '',
    this.size = 40,
    this.working = false,
    this.activity,
    this.live = true,
  });

  final String shape;
  final String color;
  final String seed;
  final double size;
  final bool working;
  final String? activity;
  final bool live;

  @override
  State<BotCharacter> createState() => _BotCharacterState();
}

class _BotCharacterState extends State<BotCharacter> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  Timer? _idle;
  bool _enabled = false;
  bool _working = false;
  bool _fidget = false;
  int _idleTurns = 0;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BotCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _sync();
    if (mounted) setState(() {});
  }

  void _sync() {
    final enabled = widget.live && _foreground && TickerMode.valuesOf(context).enabled && !AppMotion.reduced(context);
    if (enabled == _enabled && widget.working == _working) return;
    _enabled = enabled;
    _working = widget.working;
    _idle?.cancel();
    _idle = null;
    _clock.stop();
    _clock.value = 0;
    if (!_enabled) return;
    if (_working) {
      _clock.duration = const Duration(milliseconds: 4800);
      unawaited(_clock.repeat());
    } else {
      _scheduleIdle(first: true);
    }
  }

  void _scheduleIdle({bool first = false}) {
    if (!_enabled || _working || _idle != null) return;
    final jitter = dsBotFnv1a('${widget.seed}:$_idleTurns') % 1800;
    _idle = Timer(Duration(milliseconds: (first ? 1200 : 2800) + jitter), () {
      _idle = null;
      if (!mounted || !_enabled || _working) return;
      _idleTurns++;
      setState(() => _fidget = _idleTurns % 3 == 0);
      _clock.duration = Duration(milliseconds: _fidget ? 800 : 320);
      unawaited(_clock.forward(from: 0));
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_working) _scheduleIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _clock.removeStatusListener(_onStatus);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        key: ValueKey('bot-character-${botCharacters.containsKey(widget.shape) ? widget.shape : 'gumdrop'}'),
        painter: _CharacterPainter(
          clock: _clock,
          shape: widget.shape,
          color: widget.color,
          dark: Theme.of(context).brightness == Brightness.dark,
          working: _enabled && _working,
          fidget: _fidget,
          activity: widget.activity,
        ),
      ),
    ),
  );
}

class _CharacterPaths {
  _CharacterPaths(BotCharacterDefinition definition)
    : body = _makePath(definition.body),
      shade = _makePath(definition.shade),
      paints = [for (final paint in definition.paints) _makePath(paint.contours)];

  final Path body;
  final Path shade;
  final List<Path> paints;
}

Path _makePath(List<List<double>> contours) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final contour in contours) {
    path.moveTo(contour[0], contour[1]);
    for (var i = 2; i < contour.length; i += 2) {
      path.lineTo(contour[i], contour[i + 1]);
    }
    path.close();
  }
  return path;
}

double _keyframes(double t, List<(double, double)> frames) {
  for (var i = 1; i < frames.length; i++) {
    final a = frames[i - 1], b = frames[i];
    if (t <= b.$1) return ui.lerpDouble(a.$2, b.$2, ((t - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0))!;
  }
  return frames.last.$2;
}

class _CharacterPainter extends CustomPainter {
  _CharacterPainter({
    required this.clock,
    required this.shape,
    required this.color,
    required this.dark,
    required this.working,
    required this.fidget,
    required this.activity,
  }) : super(repaint: clock);

  final AnimationController clock;
  final String shape;
  final String color;
  final bool dark;
  final bool working;
  final bool fidget;
  final String? activity;
  static final _cache = <String, _CharacterPaths>{};

  @override
  void paint(Canvas canvas, Size size) {
    final id = botCharacters.containsKey(shape) ? shape : 'gumdrop';
    final definition = botCharacters[id]!;
    final paths = _cache.putIfAbsent(id, () => _CharacterPaths(definition));
    var dx = 0.0, dy = 0.0, rotation = 0.0, sx = 1.0, sy = 1.0, blink = 1.0;
    final seconds = (clock.lastElapsedDuration?.inMicroseconds ?? 0) / 1000000;
    if (working) {
      final t = (seconds / 1.6) % 1;
      if (activity == 'searching') {
        dx = math.sin(seconds / 1.6 * 2 * math.pi) * 2;
        rotation = -2 + math.sin(t * 2 * math.pi) * 2;
        dy = -2 * (1 - math.cos(t * 2 * math.pi));
      } else if (activity == 'thinking') {
        rotation = 4 + 3 * math.sin(seconds / 2.2 * 2 * math.pi);
        dy = -1.5 * (1 - math.cos(seconds / 2.2 * 2 * math.pi));
      } else if (activity == 'sending') {
        dx = _keyframes((seconds / 1.1) % 1, const [(0, 0), (.35, 9), (.55, -2), (1, 0)]);
        rotation = dx * .75;
      } else if (const ['star', 'hex', 'plus', 'gem', 'magnet', 'ring'].contains(id)) {
        rotation = math.sin(seconds / 1.4 * 2 * math.pi) * 12;
        sx = sy = 1 + .04 * math.sin(seconds / 1.4 * math.pi).abs();
      } else if (const ['gumdrop', 'peanut', 'cushion', 'squircle', 'moon', 'wave'].contains(id)) {
        final phase = (seconds / 1.2) % 1;
        sx = _keyframes(phase, const [(0, 1), (.3, 1.08), (.55, .94), (.8, 1.02), (1, 1)]);
        sy = _keyframes(phase, const [(0, 1), (.3, .90), (.55, 1.08), (.8, .98), (1, 1)]);
        dy = _keyframes(phase, const [(0, 0), (.3, 0), (.55, -4), (.8, 0), (1, 0)]);
      } else {
        dy = _keyframes(t, const [(0, 0), (.3, -4), (.65, 0), (1, 0)]);
        rotation = _keyframes(t, const [(0, 0), (.3, -5), (.65, 4), (1, 0)]);
      }
      blink = _keyframes((seconds / 2.4) % 1, const [(0, 1), (.42, 1), (.46, .03), (.48, 1.06), (.50, 1), (1, 1)]);
    } else if (clock.isAnimating) {
      blink = _keyframes(clock.value, const [(0, 1), (.35, 1), (.52, .03), (.75, 1.06), (1, 1)]);
      if (fidget) {
        dy = -5 * math.sin(clock.value * math.pi);
        rotation = 3 * math.sin(clock.value * 2 * math.pi);
      }
    }
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.translate(50 + dx, 92 + dy);
    canvas.rotate(rotation * math.pi / 180);
    canvas.scale(sx, sy);
    canvas.translate(-50, -92);
    // An even-odd clip cuts transparent eyes out of every layer, matching the
    // SVG mask without an offscreen saveLayer for each small avatar.
    final mask = Path()..fillType = PathFillType.evenOdd;
    mask.addRect(const Rect.fromLTWH(-100, -100, 300, 300));
    for (final eye in definition.eyes) {
      final radians = eye[4] * math.pi / 180;
      final c = math.cos(radians), s = math.sin(radians);
      final height = eye[3] * blink;
      final local = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: eye[2], height: height),
            Radius.circular(eye[2] / 2),
          ),
        );
      mask.addPath(
        local.transform(Float64List.fromList([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, eye[0], eye[1], 0, 1])),
        Offset.zero,
      );
    }
    canvas.clipPath(mask);
    final body = Paint()..color = Color(dsBotInkArgb(color, dark: dark));
    if (color == 'aurora') {
      body.shader = ui.Gradient.linear(
        const Offset(18, 10),
        const Offset(78, 92),
        const [Color(0xFFA4FFB0), Color(0xFF00F0E4), Color(0xFF2E9EF7)],
        const [0, .42, 1],
      );
    }
    canvas.drawPath(paths.body, body);
    for (var i = 0; i < definition.paints.length; i++) {
      final layer = definition.paints[i];
      canvas.drawPath(paths.paints[i], Paint()..color = Color(layer.argb).withValues(alpha: layer.opacity));
    }
    canvas.drawPath(paths.shade, Paint()..color = const Color(0x12000000));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CharacterPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.dark != dark ||
      oldDelegate.working != working ||
      oldDelegate.fidget != fidget ||
      oldDelegate.activity != activity;
}
