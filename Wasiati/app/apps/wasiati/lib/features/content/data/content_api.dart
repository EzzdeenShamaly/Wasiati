import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

/// One admin-editable UI string, EN + AR, with its publish state and last editor.
class ContentString {
  final String key;
  final String valueEn;
  final String valueAr;
  final String? note;
  final bool published;
  final String? updatedBy;
  final DateTime? updatedAt;

  const ContentString({
    required this.key,
    required this.valueEn,
    required this.valueAr,
    required this.note,
    required this.published,
    required this.updatedBy,
    required this.updatedAt,
  });

  factory ContentString.fromJson(Map<String, dynamic> j) => ContentString(
        key: j['key'] as String,
        valueEn: (j['valueEn'] as String?) ?? '',
        valueAr: (j['valueAr'] as String?) ?? '',
        note: j['note'] as String?,
        published: (j['published'] as bool?) ?? true,
        updatedBy: j['updatedBy'] as String?,
        updatedAt: j['updatedAt'] == null ? null : DateTime.tryParse(j['updatedAt'] as String),
      );
}

class ContentRevision {
  final String valueEn;
  final String valueAr;
  final String? editedBy;
  final DateTime? createdAt;
  const ContentRevision({required this.valueEn, required this.valueAr, required this.editedBy, required this.createdAt});

  factory ContentRevision.fromJson(Map<String, dynamic> j) => ContentRevision(
        valueEn: (j['valueEn'] as String?) ?? '',
        valueAr: (j['valueAr'] as String?) ?? '',
        editedBy: j['editedBy'] as String?,
        createdAt: j['createdAt'] == null ? null : DateTime.tryParse(j['createdAt'] as String),
      );
}

class ContentApi {
  final Dio _dio;
  ContentApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PUBLIC: published overrides as { key: {en, ar} }, merged over the ARB bundle.
  Future<Map<String, ({String en, String ar})>> overrides() => _guard(() async {
        final res = await _dio.get('/content');
        final m = (res.data as Map).cast<String, dynamic>();
        return m.map((k, v) {
          final o = (v as Map).cast<String, dynamic>();
          return MapEntry(k, (en: (o['en'] as String?) ?? '', ar: (o['ar'] as String?) ?? ''));
        });
      });

  Future<List<ContentString>> listAll() => _guard(() async {
        final res = await _dio.get('/content/admin');
        return (res.data as List).cast<Map>().map((m) => ContentString.fromJson(m.cast<String, dynamic>())).toList();
      });

  Future<List<ContentRevision>> revisions(String key) => _guard(() async {
        final res = await _dio.get('/content/admin/$key/revisions');
        return (res.data as List).cast<Map>().map((m) => ContentRevision.fromJson(m.cast<String, dynamic>())).toList();
      });

  Future<void> upsert(String key, {required String en, required String ar, String? note, bool published = true}) =>
      _guard(() => _dio.put('/content/admin/$key', data: {
            'en': en,
            'ar': ar,
            if (note != null && note.isNotEmpty) 'note': note,
            'published': published,
          }));

  Future<void> remove(String key) => _guard(() => _dio.delete('/content/admin/$key'));
}
