import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens an external URL, but ONLY if it uses an allow-listed scheme.
///
/// KYC, checkout, and the admin-set zakat charity link are all URLs the *server*
/// (or a human admin via the Content console) supplies. A compromised backend,
/// a phished admin, or a MITM on a misconfigured build could otherwise hand the
/// device an `intent:`, `file:`, `content:`, or `javascript:` URL — on Android an
/// external `intent:` launch can start arbitrary exported activities. Restricting
/// to `https` (and `mailto` for support links) removes that class of abuse.
///
/// Returns true if the URL was accepted and launched, false otherwise.
Future<bool> safeLaunchExternal(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return false;
  const allowed = {'https', 'mailto'};
  if (!allowed.contains(uri.scheme.toLowerCase())) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Convenience wrapper that surfaces a failure via [onError] (e.g. a snackbar)
/// when the URL is rejected or the launch fails. [context] is only used to let
/// callers guard their own `mounted` checks around [onError].
Future<void> safeLaunchOrNotify(
  BuildContext context,
  String rawUrl, {
  required void Function() onError,
}) async {
  final ok = await safeLaunchExternal(rawUrl);
  if (!ok) onError();
}
