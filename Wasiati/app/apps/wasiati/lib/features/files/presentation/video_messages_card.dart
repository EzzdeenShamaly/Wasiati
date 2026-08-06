import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/safe_launch.dart';
import '../application/files_providers.dart';
import '../domain/file_models.dart';

/// Video content-type from a file extension. Only the kinds the backend allows.
String? videoContentType(String? ext) => switch ((ext ?? '').toLowerCase()) {
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      _ => null,
    };

/// Video legacy messages (Premium+). Shows the 1 GB quota, lists/deletes the user's
/// videos, uploads a picked file, and routes to the webcam recorder. All read/quota/
/// delete/upload paths run against configured storage; recording needs a camera and
/// microphone permission on the device/browser.
class VideoMessagesCard extends ConsumerWidget {
  const VideoMessagesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final quota = ref.watch(storageQuotaProvider);
    final videos = ref.watch(videoFilesProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.tokens.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.videocam_outlined, size: 22, color: context.tokens.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(l.vidTitle, style: t.titleMedium)),
        ]),
        const SizedBox(height: 6),
        Text(l.vidSubtitle, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.4)),
        const SizedBox(height: 14),

        // Quota bar. A 503 means storage isn't enabled yet — say so plainly.
        quota.when(
          loading: () => const LinearProgressIndicator(minHeight: 6),
          error: (e, _) => Text(
            e is ApiException && e.message.isNotEmpty ? e.message : l.vidUnavailable,
            style: t.bodySmall?.copyWith(color: context.tokens.faint),
          ),
          data: (q) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: q.fraction,
                minHeight: 6,
                backgroundColor: context.tokens.raised,
                valueColor: AlwaysStoppedAnimation(q.isFull ? WasiatiColors.warning : context.tokens.gold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              q.isFull ? l.vidStorageFull : context.digits(l.vidStorage(formatBytes(q.usedBytes), formatBytes(q.quotaBytes))),
              style: t.bodySmall?.copyWith(color: q.isFull ? context.tokens.warningInk : context.tokens.faint),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        videos.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Text(l.vidNone, style: t.bodySmall?.copyWith(color: context.tokens.faint))
              : Column(children: [
                  for (final v in list) _VideoRow(file: v),
                ]),
        ),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _pickAndUpload(context, ref),
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: Text(l.vidUploadFile),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.go('/legacy/record'),
              icon: const Icon(Icons.fiber_manual_record, size: 16, color: WasiatiColors.record),
              label: Text(l.vidRecord),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'webm', 'mov'],
        withData: true, // we need the bytes to PUT to storage
      );
      final file = res?.files.firstOrNull;
      final bytes = file?.bytes;
      final ct = videoContentType(file?.extension);
      if (file == null || bytes == null || ct == null) {
        if (ct == null && file != null) messenger.showSnackBar(SnackBar(content: Text(l.vidBadType)));
        return;
      }
      await ref.read(fileUploaderProvider).upload(kind: 'video_legacy', contentType: ct, bytes: Uint8List.fromList(bytes));
      ref.invalidate(storageQuotaProvider);
      ref.invalidate(videoFilesProvider);
      if (context.mounted) WasiatiSnack.success(context, l.vidUploaded);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _VideoRow extends ConsumerWidget {
  const _VideoRow({required this.file});
  final StoredFile file;

  /// Plays (or downloads) the video via a short-lived presigned URL. The scan
  /// states are told apart BEFORE the network call, so a pending or blocked
  /// file gets a plain explanation instead of a silent no-op or a bare 403 —
  /// but if the row is stale the server's own refusal message is shown as-is.
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    if (file.scanPending) {
      messenger.showSnackBar(SnackBar(content: Text(l.vidScanPending)));
      return;
    }
    if (file.scanFailed) {
      messenger.showSnackBar(SnackBar(content: Text(l.vidScanFailed)));
      return;
    }
    final errorText = l.vidPlayError;
    try {
      final url = await ref.read(filesApiProvider).downloadUrl(file.id);
      if (!context.mounted) return;
      await safeLaunchOrNotify(
        context,
        url,
        onError: () => messenger.showSnackBar(SnackBar(content: Text(errorText))),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message.isNotEmpty ? e.message : errorText)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    // Pending/blocked rows keep the muted glyph; a playable one gets the gold.
    final playable = !file.scanPending && !file.scanFailed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        IconButton(
          icon: Icon(
            file.scanFailed ? Icons.block : Icons.play_circle_outline,
            size: 22,
            color: playable ? context.tokens.gold : context.tokens.muted,
          ),
          // >= 44px target (spec §7); the label names the action for a screen
          // reader since the control is icon-only.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          tooltip: l.vidPlay,
          onPressed: () => _play(context, ref),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatBytes(file.sizeBytes), style: t.bodyMedium),
            if (file.scanPending)
              Text(l.vidScanPending, style: t.bodySmall?.copyWith(color: context.tokens.warningInk))
            else if (file.scanFailed)
              Text(l.vidScanFailed, style: t.bodySmall?.copyWith(color: context.tokens.dangerInk)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: l.vidDelete,
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                content: Text(l.vidDeleteConfirm),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.vidDelete)),
                ],
              ),
            );
            if (ok != true) return;
            await ref.read(filesApiProvider).delete(file.id);
            ref.invalidate(storageQuotaProvider);
            ref.invalidate(videoFilesProvider);
            if (context.mounted) WasiatiSnack.success(context, l.vidDeleted);
          },
        ),
      ]),
    );
  }
}
