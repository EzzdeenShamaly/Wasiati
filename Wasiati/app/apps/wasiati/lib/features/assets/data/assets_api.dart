import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/asset_models.dart';

/// Estate assets are recorded against a will. Endpoints follow the nested REST
/// shape used elsewhere (witnesses/trustees/bequests): /wills/:willId/assets.
class AssetsApi {
  final Dio _dio;
  AssetsApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<EstateAsset>> list(String willId) => _guard(() async {
        final res = await _dio.get('/wills/$willId/assets');
        return (res.data as List).map((e) => EstateAsset.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<EstateAsset> add(
    String willId, {
    required String label,
    required String kind,
    String? notes,
    double? estimatedValue,
    String? currency,
    String? institution,
    String? contactPhone,
    String? contactEmail,
    String? accountRef,
  }) =>
      _guard(() async {
        final res = await _dio.post('/wills/$willId/assets', data: {
          // The backend expects `type` as an AssetType enum, plus optional value/currency.
          'type': assetTypeFromKind(kind),
          'label': label,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (estimatedValue != null) 'estimatedValue': estimatedValue,
          if (currency != null && currency.isNotEmpty) 'currency': currency,
          if (institution != null && institution.isNotEmpty) 'institution': institution,
          if (contactPhone != null && contactPhone.isNotEmpty) 'contactPhone': contactPhone,
          if (contactEmail != null && contactEmail.isNotEmpty) 'contactEmail': contactEmail,
          if (accountRef != null && accountRef.isNotEmpty) 'accountRef': accountRef,
        });
        return EstateAsset.fromJson((res.data as Map).cast<String, dynamic>());
      });

  // Delete is a top-level route on the backend: DELETE /assets/:assetId.
  Future<void> delete(String willId, String assetId) =>
      _guard(() => _dio.delete('/assets/$assetId'));

  /// Partial edit — only the provided fields change. Empty strings clear a field.
  Future<EstateAsset> update(
    String assetId, {
    String? label,
    String? kind,
    double? estimatedValue,
    String? currency,
    String? institution,
    String? contactPhone,
    String? contactEmail,
    String? accountRef,
    String? notes,
  }) =>
      _guard(() async {
        final res = await _dio.patch('/assets/$assetId', data: {
          if (kind != null) 'type': assetTypeFromKind(kind),
          if (label != null) 'label': label,
          if (estimatedValue != null) 'estimatedValue': estimatedValue,
          if (currency != null) 'currency': currency,
          if (institution != null) 'institution': institution,
          if (contactPhone != null) 'contactPhone': contactPhone,
          if (contactEmail != null) 'contactEmail': contactEmail,
          if (accountRef != null) 'accountRef': accountRef,
          if (notes != null) 'notes': notes,
        });
        return EstateAsset.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// The inventory as CSV bytes (the "Export to Excel" file), owner-scoped.
  Future<List<int>> exportCsv(String willId) => _guard(() async {
        final res = await _dio.get<List<int>>(
          '/wills/$willId/assets/export.csv',
          options: Options(responseType: ResponseType.bytes),
        );
        return res.data ?? const <int>[];
      });
}
