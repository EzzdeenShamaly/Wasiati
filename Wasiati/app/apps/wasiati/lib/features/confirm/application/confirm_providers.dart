import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/portal_client.dart';
import '../data/confirm_api.dart';

/// The confirm surface rides the same bare client the portal uses: no auth
/// interceptor (a signed-in owner opening a relative's witness link must not
/// send their own Bearer token, and a 401 here must never sign them out).
final confirmApiProvider = Provider<ConfirmApi>((ref) => ConfirmApi(PortalClient.create().dio));
