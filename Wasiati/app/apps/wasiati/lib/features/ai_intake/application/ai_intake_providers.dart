import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/ai_intake_api.dart';

final aiIntakeApiProvider = Provider<AiIntakeApi>((ref) => AiIntakeApi(ref.read(apiClientProvider).dio));
