import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/application/files_providers.dart';
import 'package:wasiati/features/files/data/files_api.dart';
import 'package:wasiati/features/files/domain/file_models.dart';
import 'package:wasiati/features/files/presentation/video_messages_card.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The legacy-video play control used to be a decorative icon wired to nothing —
/// it rendered, so the feature looked done, while tapping it did nothing at all.
/// These tests assert BEHAVIOUR: the tap must reach the download API (the same
/// GET /files/:id/download the backend serves), and the two scan states must
/// explain themselves instead of silently doing nothing.
class _RecordingFilesApi extends FilesApi {
  _RecordingFilesApi() : super(Dio());
  final downloads = <String>[];

  @override
  Future<String> downloadUrl(String id) async {
    downloads.add(id);
    // http (not https) is rejected by safeLaunchExternal, which conveniently
    // keeps url_launcher's missing test plugin out of the assertion path.
    return 'http://storage.local/presigned/$id';
  }
}

const _clean = StoredFile(
    id: 'file-clean', kind: 'video_legacy', key: 'k1', contentType: 'video/mp4', sizeBytes: 1024);
const _pending = StoredFile(
    id: 'file-pending',
    kind: 'video_legacy',
    key: 'k2',
    contentType: 'video/mp4',
    sizeBytes: 2048,
    scanStatus: 'PENDING');
const _infected = StoredFile(
    id: 'file-bad',
    kind: 'video_legacy',
    key: 'k3',
    contentType: 'video/mp4',
    sizeBytes: 4096,
    scanStatus: 'INFECTED');

Future<_RecordingFilesApi> _pump(WidgetTester t, List<StoredFile> files) async {
  t.view.physicalSize = const Size(900, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = _RecordingFilesApi();
  await t.pumpWidget(ProviderScope(
    overrides: [
      filesApiProvider.overrideWithValue(api),
      storageQuotaProvider.overrideWith((ref) async =>
          const StorageQuota(usedBytes: 0, quotaBytes: 1024 * 1024, remainingBytes: 1024 * 1024)),
      videoFilesProvider.overrideWith((ref) async => files),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: VideoMessagesCard())),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('tapping play on a clean video actually calls the download API', (t) async {
    final api = await _pump(t, [_clean]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.byTooltip(l.vidPlay));
    await t.pumpAndSettle();

    expect(api.downloads, ['file-clean'],
        reason: 'The play control must fetch the presigned URL, not just render an icon.');
  });

  testWidgets('a scan-pending video explains itself and does NOT hit the API', (t) async {
    final api = await _pump(t, [_pending]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    // The state is already visible on the row before any tap.
    expect(find.text(l.vidScanPending), findsOneWidget);

    await t.tap(find.byTooltip(l.vidPlay));
    await t.pumpAndSettle();

    expect(api.downloads, isEmpty,
        reason: 'The server would 403 anyway; the client must say why instead of calling.');
    // And the tap surfaces the message again as feedback (row text + snackbar).
    expect(find.text(l.vidScanPending), findsNWidgets(2));
  });

  testWidgets('a scan-failed video is a clear message, not a silent no-op', (t) async {
    final api = await _pump(t, [_infected]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l.vidScanFailed), findsOneWidget);

    await t.tap(find.byTooltip(l.vidPlay));
    await t.pumpAndSettle();

    expect(api.downloads, isEmpty);
    expect(find.text(l.vidScanFailed), findsNWidgets(2));
  });
}
