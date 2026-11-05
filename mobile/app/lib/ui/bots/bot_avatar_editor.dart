import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dsh_client/dsh_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../common/app_sheet.dart';
import '../features/feature_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_action_scope.dart';
import 'bot_avatar.dart';
import 'bot_character.dart';
import 'bot_workspace.dart';

// DS Bot src/host/constants.js + avatar.js at 0dde6a76254d. The bound is
// the entire data URL, not the raw image size. Keep the existing host limit.
const botAvatarMaxDataUrlLength = 160000;
const botAvatarMaxBytes = 119982;
const botAvatarSourceMaxBytes = 16 * 1024 * 1024;

enum BotAvatarImageIssue { invalid, tooLarge, gifTooLarge }

class BotAvatarImageException implements Exception {
  const BotAvatarImageException(this.issue);
  final BotAvatarImageIssue issue;
}

class BotAvatarImage {
  const BotAvatarImage({required this.bytes, required this.mime});
  final Uint8List bytes;
  final String mime;
  bool get isGif => mime == 'image/gif';
  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

String? _imageMime(Uint8List bytes) {
  bool prefix(List<int> values, [int offset = 0]) =>
      bytes.length >= offset + values.length && values.indexed.every((entry) => bytes[offset + entry.$1] == entry.$2);
  if (prefix(const [0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10])) return 'image/png';
  if (prefix(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (prefix(const [71, 73, 70, 56, 55, 97]) || prefix(const [71, 73, 70, 56, 57, 97])) return 'image/gif';
  if (prefix(const [82, 73, 70, 70]) && prefix(const [87, 69, 66, 80], 8)) return 'image/webp';
  return null;
}

/// Validate locally. GIF bytes remain untouched so their animation survives.
/// Static images are decoded at a bounded size, center-cropped and encoded as
/// a small PNG; no source path or image is sent before explicit Save.
Future<BotAvatarImage> prepareBotAvatarImage(Uint8List bytes) async {
  final mime = _imageMime(bytes);
  if (mime == null) throw const BotAvatarImageException(BotAvatarImageIssue.invalid);
  if (mime == 'image/gif' && bytes.length > botAvatarMaxBytes) {
    throw const BotAvatarImageException(BotAvatarImageIssue.gifTooLarge);
  }
  if (bytes.length > botAvatarSourceMaxBytes) {
    throw const BotAvatarImageException(BotAvatarImageIssue.tooLarge);
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width, height = descriptor.height;
    if (width <= 0 || height <= 0) throw const BotAvatarImageException(BotAvatarImageIssue.invalid);
    if (width > 32768 || height > 32768 || width * height > 64 * 1024 * 1024) {
      throw const BotAvatarImageException(BotAvatarImageIssue.tooLarge);
    }
    final scale = math.min(1.0, 512 / math.max(width, height));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    if (mime == 'image/gif') {
      final result = BotAvatarImage(bytes: bytes, mime: mime);
      if (result.dataUrl.length > botAvatarMaxDataUrlLength) {
        throw const BotAvatarImageException(BotAvatarImageIssue.gifTooLarge);
      }
      return result;
    }
    final side = math.min(image.width, image.height).toDouble();
    final source = Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side, side);
    for (final pixels in const [160, 128, 96]) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, pixels.toDouble(), pixels.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final resized = await picture.toImage(pixels, pixels);
      picture.dispose();
      ByteData? encoded;
      try {
        encoded = await resized.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        resized.dispose();
      }
      if (encoded == null) continue;
      final png = encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
      final result = BotAvatarImage(bytes: png, mime: 'image/png');
      if (png.length <= botAvatarMaxBytes && result.dataUrl.length <= botAvatarMaxDataUrlLength) return result;
    }
    throw const BotAvatarImageException(BotAvatarImageIssue.tooLarge);
  } on BotAvatarImageException {
    rethrow;
  } catch (_) {
    throw const BotAvatarImageException(BotAvatarImageIssue.invalid);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Injectable local picker. FilePicker leaves GIF bytes intact; its extension
/// filter is only a convenience, and actual signatures are checked afterward.
final botAvatarImagePickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      compressionQuality: 0,
    );
    if (file == null) return null;
    final length = file.lengthSync();
    if (length != null && length > botAvatarSourceMaxBytes) {
      throw const BotAvatarImageException(BotAvatarImageIssue.tooLarge);
    }
    final output = BytesBuilder(copy: false);
    final prefix = Uint8List(12);
    var prefixLength = 0;
    await for (final chunk in file.readAsByteStream()) {
      final take = math.min(prefix.length - prefixLength, chunk.length);
      prefix.setRange(prefixLength, prefixLength + take, chunk);
      prefixLength += take;
      if (_imageMime(Uint8List.sublistView(prefix, 0, prefixLength)) == 'image/gif' &&
          ((length != null && length > botAvatarMaxBytes) || chunk.length > botAvatarMaxBytes - output.length)) {
        throw const BotAvatarImageException(BotAvatarImageIssue.gifTooLarge);
      }
      if (chunk.length > botAvatarSourceMaxBytes - output.length) {
        throw const BotAvatarImageException(BotAvatarImageIssue.tooLarge);
      }
      output.add(chunk);
    }
    return output.takeBytes();
  },
);

Future<bool?> showBotAvatarEditor(BuildContext context, WidgetRef ref, DsBot bot, {BotActionScope? scope}) async {
  final target = scope ?? BotActionScope(ref, botId: bot.id);
  final origin = ref.read(dsBotProvider);
  if (!target.current(context, ref) || !origin.ready || origin.team?.bot(bot.id)?.sessionId != bot.sessionId) {
    return null;
  }
  return showAppSheet<bool>(
    context,
    heightFactor: .9,
    glass: false,
    dismissal: SheetDismissal.button,
    builder: (_) => BotWorkspace(
      child: _AvatarEditor(bot: bot, origin: origin, scope: target),
    ),
  );
}

class _AvatarEditor extends ConsumerStatefulWidget {
  const _AvatarEditor({required this.bot, required this.origin, required this.scope});
  final DsBot bot;
  final DsBotStatus origin;
  final BotActionScope scope;

  @override
  ConsumerState<_AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends ConsumerState<_AvatarEditor> {
  late String? _shape = widget.bot.shape;
  BotAvatarImage? _image;
  bool _removeImage = false, _reset = false, _dirty = false, _picking = false, _saving = false, _retired = false;
  int _pickGeneration = 0;
  String? _error;
  ProviderSubscription<DsBotStatus>? _status;
  StreamSubscription<DsBotFeedEvent>? _feed;

  bool _sameOwner() =>
      mounted &&
      !_retired &&
      widget.scope.current(context, ref) &&
      ref.read(dsBotProvider).ready &&
      ref.read(dsBotProvider).team?.bot(widget.bot.id)?.sessionId == widget.bot.sessionId;

  bool _avatarUnchanged() {
    final bot = ref.read(dsBotProvider).team?.bot(widget.bot.id);
    return bot?.shape == widget.bot.shape && bot?.imageRef == widget.bot.imageRef;
  }

  bool _current() => _sameOwner() && (_saving || _avatarUnchanged());

  void _retire() {
    if (mounted && !_retired) {
      _pickGeneration++;
      setState(() => _retired = true);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_current()) _retired = true;
    _status = ref.listenManual(dsBotProvider, (_, _) {
      if (!_current()) _retire();
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

  String _imageError(Object error) => switch (error) {
    BotAvatarImageException(issue: BotAvatarImageIssue.gifTooLarge) => context.l10n.botsAvatarGifLimit,
    BotAvatarImageException(issue: BotAvatarImageIssue.tooLarge) => context.l10n.botsAvatarImageTooLarge,
    BotAvatarImageException() => context.l10n.botsAvatarInvalidImage,
    _ => context.l10n.botsAvatarPickFailed,
  };

  Future<void> _pick() async {
    if (_picking || _saving || !_current()) return;
    final generation = ++_pickGeneration;
    final picker = ref.read(botAvatarImagePickerProvider);
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = await picker();
      if (!_current() || generation != _pickGeneration || bytes == null) return;
      final image = await prepareBotAvatarImage(bytes);
      if (!_current() || generation != _pickGeneration) return;
      setState(() {
        _image = image;
        _removeImage = false;
        _reset = false;
        _dirty = true;
      });
    } catch (error) {
      if (_current() && generation == _pickGeneration) setState(() => _error = _imageError(error));
    } finally {
      if (mounted && generation == _pickGeneration) setState(() => _picking = false);
    }
  }

  void _chooseShape(String shape) {
    if (_picking || _saving || !_current()) return;
    setState(() {
      _shape = shape;
      _image = null;
      _removeImage = true;
      _reset = false;
      _error = null;
      _dirty = widget.bot.shape != shape || widget.bot.imageRef != null;
    });
  }

  void _removePhoto() {
    if (_picking || _saving || !_current()) return;
    setState(() {
      _shape ??= botShapeOf(widget.bot);
      _image = null;
      _removeImage = true;
      _reset = false;
      _error = null;
      _dirty = widget.bot.imageRef != null || widget.bot.shape != _shape;
    });
  }

  void _resetAvatar() {
    if (_picking || _saving || !_current()) return;
    setState(() {
      _shape = null;
      _image = null;
      _removeImage = true;
      _reset = true;
      _error = null;
      _dirty = widget.bot.shape != null || widget.bot.imageRef != null;
    });
  }

  Future<void> _save() async {
    if (_picking || _saving || !_dirty || !_current()) return;
    final api = widget.scope.api!;
    final hub = ref.read(dsBotProvider.notifier);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final savedLabel = context.l10n.botsAvatarSaved;
    // Snapshot the local draft once. Later host changes never redirect a write.
    final shape = _shape;
    final image = _image?.dataUrl;
    final clear = _reset;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_sameOwner()) return;
      await api.setAvatar(widget.bot.id, shape: shape, image: image, clear: clear);
      if (!_sameOwner()) return;
      await hub.refresh();
      if (!_sameOwner()) return;
      navigator.pop(true);
      messenger?.showSnackBar(SnackBar(content: Text(savedLabel)));
    } catch (error) {
      if (_sameOwner()) setState(() => _error = describeDsBotError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dsBotProvider);
    final current = _current();
    final l10n = context.l10n;
    final palette = BotWorkspacePalette.of(context);
    final busy = current && (_saving || _picking);
    final hasImage = _image != null || (!_removeImage && widget.bot.imageRef != null);
    final selected = _reset || !botCharacters.containsKey(_shape) ? botDefaultShape(widget.bot.id) : _shape!;
    Widget preview() {
      if (_image case final image?) {
        return TickerMode(
          enabled: !AppMotion.reduced(context),
          child: ClipOval(
            child: Image(
              image: ResizeImage(
                MemoryImage(image.bytes),
                width: (96 * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 1024),
                height: (96 * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 1024),
                policy: ResizeImagePolicy.fit,
              ),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
        );
      }
      if (!_removeImage && !_reset) return BotAvatar(bot: widget.bot, size: 96);
      return BotCharacter(shape: selected, color: widget.bot.ink, seed: widget.bot.id, size: 96);
    }

    return PopScope(
      canPop: !busy,
      child: ColoredBox(
        key: const ValueKey('bot-avatar-editor'),
        color: palette.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.botsEditAvatar, style: Theme.of(context).textTheme.titleLarge)),
                  SheetIconButton(
                    key: const ValueKey('bot-avatar-close'),
                    icon: AppIcons.close,
                    tooltip: l10n.commonClose,
                    onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !current
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: FeatureMessage(icon: AppIcons.disconnected, title: l10n.botsAvatarChanged),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        Center(child: preview()),
                        const SizedBox(height: 16),
                        Text(
                          l10n.botsAvatarPreviewHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: const ValueKey('bot-avatar-pick-image'),
                          onPressed: busy ? null : _pick,
                          icon: _picking
                              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(AppIcons.image, size: 20),
                          label: Text(l10n.botsAvatarChooseImage),
                        ),
                        if (hasImage)
                          TextButton(
                            key: const ValueKey('bot-avatar-remove-image'),
                            onPressed: busy ? null : _removePhoto,
                            child: Text(l10n.botsAvatarRemoveImage),
                          ),
                        const SizedBox(height: 20),
                        Text(l10n.botsAvatarChooseCharacter, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = (constraints.maxWidth - 32) / 5;
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final shape in botCharacters.keys)
                                  SizedBox(
                                    width: width,
                                    child: Semantics(
                                      button: true,
                                      selected: !hasImage && selected == shape,
                                      label: botCharacterLabel(context, shape),
                                      child: Material(
                                        color: !hasImage && selected == shape ? palette.subtle : palette.surface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: !hasImage && selected == shape ? palette.accent : palette.line,
                                          ),
                                        ),
                                        child: InkWell(
                                          key: ValueKey('bot-avatar-shape-$shape'),
                                          onTap: busy ? null : () => _chooseShape(shape),
                                          borderRadius: BorderRadius.circular(12),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                                            child: Column(
                                              children: [
                                                BotCharacter(
                                                  shape: shape,
                                                  color: widget.bot.ink,
                                                  size: math.min(40, width - 6),
                                                  live: false,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  botCharacterLabel(context, shape),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(context).textTheme.labelSmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          key: const ValueKey('bot-avatar-reset'),
                          onPressed: busy ? null : _resetAvatar,
                          child: Text(l10n.botsAvatarReset),
                        ),
                        Text(
                          l10n.botsAvatarResetHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              _error!,
                              key: const ValueKey('bot-avatar-error'),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: DshColors.of(context).danger),
                            ),
                          ),
                      ],
                    ),
            ),
            if (current)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FilledButton.icon(
                  key: const ValueKey('bot-avatar-save'),
                  onPressed: busy || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(AppIcons.done, size: 18),
                  label: Text(l10n.commonSave),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String botCharacterLabel(BuildContext context, String shape) {
  final l10n = context.l10n;
  return switch (shape) {
    'whale' => l10n.botsAvatarShapeWhale,
    'star' => l10n.botsAvatarShapeStar,
    'moon' => l10n.botsAvatarShapeMoon,
    'wave' => l10n.botsAvatarShapeWave,
    'squircle' => l10n.botsAvatarShapeSquircle,
    'zed' => l10n.botsAvatarShapeBull,
    'hex' => l10n.botsAvatarShapeBlossom,
    'gumdrop' => l10n.botsAvatarShapeGumdrop,
    'peanut' => l10n.botsAvatarShapePeanut,
    'saucer' => l10n.botsAvatarShapeSaucer,
    'bunny' => l10n.botsAvatarShapeBunny,
    'kitty' => l10n.botsAvatarShapeKitty,
    'beacon' => l10n.botsAvatarShapeBeacon,
    'plus' => l10n.botsAvatarShapePlus,
    'magnet' => l10n.botsAvatarShapeMagnet,
    'acorn' => l10n.botsAvatarShapeAcorn,
    'pebbles' => l10n.botsAvatarShapePebbles,
    'cushion' => l10n.botsAvatarShapeCushion,
    'ring' => l10n.botsAvatarShapeRing,
    _ => l10n.botsAvatarShapeGem,
  };
}
