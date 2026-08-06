import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/wills_api.dart';
import '../domain/wills_models.dart';

final willsApiProvider = Provider<WillsApi>((ref) => WillsApi(ref.read(apiClientProvider).dio));

final willsListProvider = FutureProvider.autoDispose<List<Will>>((ref) => ref.read(willsApiProvider).list());

final willProvider =
    FutureProvider.autoDispose.family<Will, String>((ref, id) => ref.read(willsApiProvider).getOne(id));

final disclaimerProvider =
    FutureProvider.autoDispose<({String version, String text})>((ref) => ref.read(willsApiProvider).disclaimer());

final witnessesProvider =
    FutureProvider.autoDispose.family<List<Witness>, String>((ref, willId) => ref.read(willsApiProvider).witnesses(willId));

final trusteesProvider =
    FutureProvider.autoDispose.family<List<Trustee>, String>((ref, willId) => ref.read(willsApiProvider).trustees(willId));

final heirContactsProvider = FutureProvider.autoDispose
    .family<List<HeirContact>, String>((ref, willId) => ref.read(willsApiProvider).heirContacts(willId));

/// Directives beyond the will (POA / HCD) — user-scoped, at most one of each.
final directivesProvider =
    FutureProvider.autoDispose<List<DirectiveDoc>>((ref) => ref.read(willsApiProvider).directives());

/// Roster rows (witness/trustee ids) whose invite reached NOBODY — the add call
/// came back `notified: false`, meaning no SMS was dispatched and no email was
/// on file. The owner is the only person who can fix that, so the rows are
/// flagged in the UI instead of the failure being swallowed.
///
/// Client-side state: the backend computes `notified` at invite time and does
/// not persist it, so this survives navigation (deliberately NOT autoDispose)
/// but not a reload — the trade the backend contract imposes.
final rosterUnreachedProvider = StateProvider<Set<String>>((ref) => <String>{});

/// The will-preview page's two controls: ESTATE FORMAT (table | essay) and SHARES AS
/// (percent | fraction).
///
/// Lifted out of the preview widget so the Download button hands back exactly the document
/// that was on screen. A preview whose toggles do not carry into the download is worse than
/// no preview — you would be reading one document and keeping a different one.
///
/// Not autoDispose: flipping to Table, scrolling away to fix a witness and coming back
/// should not silently reset to Narrative.
///
/// NARRATIVE is the default (owner, 5 Aug 2026 — DECISIONS §29): the first document a
/// person reads should sound like a will — "I declare that, as of the sealing of this
/// will, I own…" — not like an inventory printout. The table stays one tap away for
/// anyone who prefers rows.
final willPreviewChoiceProvider =
    StateProvider<({String format, String display})>((ref) => (format: 'essay', display: 'percent'));
