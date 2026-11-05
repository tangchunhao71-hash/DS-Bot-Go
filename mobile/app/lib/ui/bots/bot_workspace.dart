import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The Bot workspace uses a quiet reading surface. This is a route-local theme:
/// the app's settings, accent preference and other workspaces are untouched.
/// Identity and activity retain their semantic colors; decoration stays neutral.
class BotWorkspace extends StatelessWidget {
  const BotWorkspace({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final p = BotWorkspacePalette.of(context);
    GlassStyle surface(Color fill) => GlassStyle(
      fill: fill,
      fallbackFill: fill,
      hairline: p.line,
      rim: Colors.transparent,
      hairlineWidth: 1,
    );
    final surfaces = DshSurfaces.of(context).copyWith(
      backdropTop: p.background,
      backdropBottom: p.background,
      glowPrimary: Colors.transparent,
      glowSecondary: Colors.transparent,
      userBubble: p.subtle,
      onUserBubble: p.ink,
      chrome: surface(p.surface),
      sheet: surface(p.surface),
      card: surface(p.surface),
      pill: surface(p.subtle),
      blurEnabled: false,
    );
    final colors = DshColors.of(context).copyWith(textTertiary: p.muted);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: p.background,
        colorScheme: base.colorScheme.copyWith(
          surface: p.surface,
          onSurface: p.ink,
          onSurfaceVariant: p.muted,
          outlineVariant: p.line,
        ),
        dividerColor: p.line,
        extensions: [
          ...base.extensions.values.where((e) => e is! DshSurfaces && e is! DshColors),
          surfaces,
          colors,
        ],
      ),
      child: child,
    );
  }
}

/// Shared surface and spacing choices for the team, chat and context panels.
/// Work/status colors continue to come from [DshColors].
@immutable
class BotWorkspacePalette {
  const BotWorkspacePalette._({
    required this.background,
    required this.surface,
    required this.subtle,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
  });

  static const contentInset = 20.0;
  static const radius = 16.0;

  final Color background;
  final Color surface;
  final Color subtle;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;

  static BotWorkspacePalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const BotWorkspacePalette._(
          background: Color(0xFF141414),
          surface: Color(0xFF1F1F1F),
          subtle: Color(0xFF262626),
          ink: Color(0xFFF2F2F2),
          muted: Color(0xFFB2B2B2),
          line: Color(0xFF353535),
          accent: Color(0xFF8B9FFF),
        )
      : const BotWorkspacePalette._(
          background: Color(0xFFFCFCFC),
          surface: Color(0xFFFFFFFF),
          subtle: Color(0xFFF1F1F1),
          ink: Color(0xFF141414),
          muted: Color(0xFF686868),
          line: Color(0xFFE5E5E5),
          accent: Color(0xFF3D55D9),
        );
}
