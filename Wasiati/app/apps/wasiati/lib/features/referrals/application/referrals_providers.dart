import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/referrals_api.dart';
import '../domain/referral_models.dart';

final referralsApiProvider = Provider<ReferralsApi>((ref) => ReferralsApi(ref.read(apiClientProvider).dio));

final referralSummaryProvider =
    FutureProvider.autoDispose<ReferralSummary>((ref) => ref.read(referralsApiProvider).summary());

/// A `?ref=CODE` captured from the registration link, held until the account exists.
///
/// The claim endpoint needs an authenticated user, so the code cannot be sent while
/// the visitor is still a visitor. It is parked here by the register screen and
/// redeemed immediately after sign-up succeeds.
final pendingReferralCodeProvider = StateProvider<String?>((_) => null);
