import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/content_api.dart';

final contentApiProvider = Provider<ContentApi>((ref) => ContentApi(ref.read(apiClientProvider).dio));

/// Admin list of every editable string.
final contentListProvider =
    FutureProvider.autoDispose<List<ContentString>>((ref) => ref.read(contentApiProvider).listAll());

/// Published overrides the app merges over its bundled ARB strings. Loaded once at
/// launch; any surface that opts into runtime overrides reads from here.
final contentOverridesProvider =
    FutureProvider<Map<String, ({String en, String ar})>>((ref) => ref.read(contentApiProvider).overrides());

/// Resolves a runtime-overridable string — this is how the "ARB default + admin
/// override" decision is realised (docs/DECISIONS.md §4). A surface opts in per
/// string by calling this with its bundled value as [fallback]:
///
/// ```dart
/// Text(overrideText(ref, key: 'sealWry', fallback: l.sealWry, isRtl: context.isRtl))
/// ```
///
/// If the admin has published an override for [key] it wins (in the current
/// locale); otherwise the compiled ARB [fallback] is used, so the app always
/// renders — offline, on first paint, and if the fetch fails.
/// The keys the app ACTUALLY honours — every string wired through [overrideText].
///
/// The admin Content editor took a free-form key, saved anything, and answered 200. The
/// app renders only what a surface has opted in, so editing any other key was a silent
/// no-op: the owner corrected a string, saw it saved, and the old text kept rendering
/// forever with nothing anywhere reporting the mismatch. On the legal disclaimer that is
/// not a cosmetic failure.
///
/// The editor now offers this list instead of a free-text field, so what an admin can
/// save is exactly what the app can show. ADD A KEY HERE when you wire a new
/// [overrideText] call — the two must not drift apart.
const overridableKeys = <String>[
  // The disclaimer the user ticks to seal. ContentService names this one explicitly as
  // the reason the override system exists.
  'rsReviewedConfirm',
  // The wry line on the sealed screen.
  'sealWry',
];

String overrideText(
  WidgetRef ref, {
  required String key,
  required String fallback,
  required bool isRtl,
}) {
  final overrides = ref.watch(contentOverridesProvider).valueOrNull;
  final v = overrides?[key];
  if (v == null) return fallback;
  final value = isRtl ? v.ar : v.en;
  return value.trim().isEmpty ? fallback : value;
}
