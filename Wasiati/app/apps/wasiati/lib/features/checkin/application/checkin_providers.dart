import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/checkin_api.dart';

final checkinApiProvider = Provider<CheckinApi>((ref) => CheckinApi(ref.read(apiClientProvider).dio));

final checkinStatusProvider =
    FutureProvider.autoDispose<CheckinStatus>((ref) => ref.read(checkinApiProvider).status());
