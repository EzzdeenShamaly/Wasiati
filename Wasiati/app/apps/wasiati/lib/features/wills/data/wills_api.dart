import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/wills_models.dart';

class WillsApi {
  final Dio _dio;
  WillsApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// The rendered will as PDF bytes. Fetched through Dio so the auth header is
  /// attached — the endpoint is owner-scoped, not a public URL.
  ///
  /// [format] is 'table' (structured listing) or 'essay' (narrative prose);
  /// [lang] is 'en' or 'ar' (Arabic renders full RTL, shaped, Arabic-Indic digits).
  /// [display] renders the fara'id shares as percentages or as the canonical fractions
  /// (1/2, 1/4, 1/8 …). The server has always accepted it; the app never sent it, so the
  /// spec's %-or-fractions choice was unreachable from the UI.
  Future<Uint8List> downloadPdf(
    String willId, {
    String format = 'table',
    String lang = 'en',
    String display = 'percent',
  }) =>
      _guard(() async {
        final res = await _dio.get<List<int>>(
          '/wills/$willId/pdf',
          queryParameters: {'format': format, 'lang': lang, 'display': display},
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// The same document, for reading on screen before committing to a download.
  ///
  /// A separate route because the download is export-gated (witnesses + trustee) while
  /// reading your own will is not — but it renders through the SAME builder on the server,
  /// so what the preview shows is exactly what the download gives.
  Future<Uint8List> previewPdf(
    String willId, {
    String format = 'table',
    String lang = 'en',
    String display = 'percent',
  }) =>
      _guard(() async {
        final res = await _dio.get<List<int>>(
          '/wills/$willId/pdf/preview',
          queryParameters: {'format': format, 'lang': lang, 'display': display},
          options: Options(
            responseType: ResponseType.bytes,
            // The client-wide receiveTimeout is 20s, which is right for JSON and wrong
            // here. This endpoint prints a document through headless Chromium: warm, it
            // answers in ~2s, but the FIRST render after the server starts also pays the
            // browser launch, and that runs to minutes on a cold machine. At 20s the
            // viewer showed "The preview could not be rendered" every single time — the
            // will document looked permanently broken when the server was merely still
            // starting up, which is exactly how it was reported.
            //
            // The other half of the fix is server-side (PdfRendererService warms Chromium
            // at boot), so in practice nobody waits this long. This is the backstop.
            receiveTimeout: const Duration(minutes: 3),
          ),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  Future<({String version, String text})> disclaimer() => _guard(() async {
        final res = await _dio.get('/wills/disclaimer');
        final m = (res.data as Map).cast<String, dynamic>();
        return (version: m['version'] as String, text: m['text'] as String);
      });

  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) =>
      _guard(() async {
        final res = await _dio.post('/wills', data: {
          'tier': tier,
          'disclaimerAccepted': true,
          'madhhab': madhhab,
          'heirs': heirs.map((h) => {'relation': h.relation.api, 'name': h.name}).toList(),
        });
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<List<Will>> list() => _guard(() async {
        final res = await _dio.get('/wills');
        return (res.data as List).map((e) => Will.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<Will> getOne(String id) =>
      _guard(() async => Will.fromJson(((await _dio.get('/wills/$id')).data as Map).cast<String, dynamic>()));

  /// Autosaves the create-flow snapshot onto the DRAFT will (spec §3 autosave).
  /// The server stores the JSON and lifts heirs → shares, wishes → funeralWishes,
  /// words → personalMessage and the bequest → its own row, so the draft will
  /// always mirrors the flow.
  Future<Will> updateDraft(String willId, Map<String, dynamic> draftState) => _guard(() async {
        final res = await _dio.patch('/wills/$willId/draft', data: {'draftState': draftState});
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Saves the owner's personal "Words for my family" message onto the will.
  Future<Will> saveMessage(String willId, String message) => _guard(() async {
        final res = await _dio.patch('/wills/$willId', data: {'personalMessage': message});
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Records guardianship of minor children (create-flow step 3). [mode] is
  /// 'parent' | 'islamic' | 'named'; name/phone/email apply to a named guardian.
  Future<Will> updateGuardian(String willId,
          {required String mode, String? name, String? phone, String? email}) =>
      _guard(() async {
        final res = await _dio.patch('/wills/$willId/guardian', data: {
          'mode': mode,
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
        });
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  // --- heir registry (create-flow step 2) ---
  Future<List<HeirContact>> heirContacts(String willId) => _guard(() async {
        final res = await _dio.get('/wills/$willId/heir-contacts');
        return (res.data as List).map((e) => HeirContact.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<HeirContact> addHeirContact(String willId, {required String relation}) => _guard(() async {
        final res = await _dio.post('/wills/$willId/heir-contacts', data: {'relation': relation});
        return HeirContact.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<HeirContact> updateHeirContact(String willId, String id,
          {String? relation, String? name, String? phone, String? email, bool? isMinor}) =>
      _guard(() async {
        final res = await _dio.patch('/wills/$willId/heir-contacts/$id', data: {
          if (relation != null) 'relation': relation,
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
          if (isMinor != null) 'isMinor': isMinor,
        });
        return HeirContact.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<void> deleteHeirContact(String willId, String id) =>
      _guard(() => _dio.delete('/wills/$willId/heir-contacts/$id'));

  /// The user's directives beyond the will (POA / HCD) — at most one of each.
  Future<List<DirectiveDoc>> directives() => _guard(() async {
        final res = await _dio.get('/directives');
        return (res.data as List).map((e) => DirectiveDoc.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// Save & sign a directive in one step (the only action the card offers).
  /// [type] is 'POA' or 'HCD'; [wishes] applies to the HCD only. Premium+ —
  /// the server 403s below that, but the UI soft-sells instead of calling.
  Future<DirectiveDoc> saveDirective(
    String type, {
    required String agentName,
    required String agentPhone,
    required String agentEmail,
    String? wishes,
  }) =>
      _guard(() async {
        final res = await _dio.put('/directives/$type', data: {
          'agentName': agentName,
          'agentPhone': agentPhone,
          'agentEmail': agentEmail,
          if (wishes != null) 'wishes': wishes,
        });
        return DirectiveDoc.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Issues the step-up re-authentication code required before a will can be
  /// unpublished or deleted (spec §3: "Delete/unpublish require
  /// re-authentication"). The server sends it by SMS when the owner has a phone,
  /// otherwise to their verified email — `via` says which, so the code prompt can
  /// name the right channel. `devCode` is echoed only in dev-echo mode.
  Future<({String via, String? devCode})> requestStepUpOtp(String willId) => _guard(() async {
        final res = await _dio.post('/wills/$willId/step-up-otp');
        final m = (res.data as Map).cast<String, dynamic>();
        return (via: (m['via'] as String?) ?? 'sms', devCode: m['devCode'] as String?);
      });

  /// Legacy name kept for the delete flow — same endpoint as [requestStepUpOtp].
  Future<String?> sendWillDeleteCode(String willId) async => (await requestStepUpOtp(willId)).devCode;

  /// SEALED -> DRAFT. Requires the step-up [otp] from [requestStepUpOtp]; the
  /// will reopens for editing, every signature is cleared (re-sealing is a fresh
  /// ceremony) and witnesses who had signed are notified server-side.
  Future<void> unpublish(String willId, String otp) =>
      _guard(() => _dio.post('/wills/$willId/unpublish', data: {'otp': otp}));

  /// Permanently deletes a will. Requires the step-up [otp] from
  /// [requestStepUpOtp]; the deletion is audited server-side.
  Future<void> deleteWill(String willId, String otp) =>
      _guard(() => _dio.delete('/wills/$willId', data: {'otp': otp}));

  Future<void> addBequest(String willId, {required String beneficiaryName, required double sharePercent, String? notes}) =>
      _guard(() => _dio.post('/wills/$willId/bequests', data: {
            'beneficiaryName': beneficiaryName,
            'sharePercent': sharePercent,
            if (notes != null && notes.isNotEmpty) 'notes': notes,
          }));

  // --- signing lifecycle: DRAFT -> SIGNED -> WITNESSED -> SEALED ---
  /// Owner applies their digital signature (base64 image / vector path). Locks the will.
  Future<Will> sign(String willId, {required String signatureData}) => _guard(() async {
        final res = await _dio.post('/wills/$willId/sign', data: {'signatureData': signatureData});
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Owner seals the executed will once the required witnesses have signed.
  Future<Will> seal(String willId) => _guard(() async {
        final res = await _dio.post('/wills/$willId/seal');
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Opens a revision of a SEALED will: a fresh DRAFT carrying the original's
  /// shares, bequests, wishes and guardianship, occupying the single draft
  /// slot. The sealed will stays in force untouched until the revision is
  /// itself sealed. The server refuses BASIC (immutable), a non-sealed will,
  /// and a second draft — each with its own message, surfaced verbatim.
  Future<Will> revise(String willId) => _guard(() async {
        final res = await _dio.post('/wills/$willId/revise');
        return Will.fromJson((res.data as Map).cast<String, dynamic>());
      });

  // --- witnesses ---
  /// Adds a witness to the roster. The response's `notified` says whether ANY
  /// channel actually reached them: `false` means no SMS was dispatched and no
  /// email was on file, so this person will never confirm unless the owner
  /// contacts them another way. Surfaced, never swallowed — see
  /// [rosterUnreachedProvider] and witnesses.service.ts (backend).
  Future<({String id, bool notified})> addWitness(String willId,
          {required String fullName, required String phone, String? email}) =>
      _guard(() async {
        final res = await _dio.post('/wills/$willId/witnesses',
            data: {'fullName': fullName, 'phone': phone, if (email != null && email.isNotEmpty) 'email': email});
        final m = (res.data as Map).cast<String, dynamic>();
        // Missing field (older server) defaults to true: never false-alarm.
        return (id: m['id'] as String, notified: m['notified'] as bool? ?? true);
      });

  Future<List<Witness>> witnesses(String willId) => _guard(() async {
        final res = await _dio.get('/wills/$willId/witnesses');
        return (res.data as List).map((e) => Witness.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// Texts the witness their signing code.
  ///
  /// Returns nothing by design: this endpoint is unauthenticated, so it never echoes
  /// the code back — that would hand a consumable credential to any anonymous caller.
  /// The code reaches the witness over SMS and nowhere else.
  Future<void> sendWitnessCode(String witnessId) =>
      _guard(() => _dio.post('/witnesses/$witnessId/send-code'));

  // --- trustees ---
  /// Adds a trustee. Same `notified` contract as [addWitness]: `false` means
  /// nobody was reached, so release could never be gated on this trustee unless
  /// the owner contacts them another way.
  Future<({String id, bool notified})> addTrustee(String willId,
          {required String fullName, required String phone, String? email}) =>
      _guard(() async {
        final res = await _dio.post('/wills/$willId/trustees',
            data: {'fullName': fullName, 'phone': phone, if (email != null && email.isNotEmpty) 'email': email});
        final m = (res.data as Map).cast<String, dynamic>();
        return (id: m['id'] as String, notified: m['notified'] as bool? ?? true);
      });

  Future<List<Trustee>> trustees(String willId) => _guard(() async {
        final res = await _dio.get('/wills/$willId/trustees');
        return (res.data as List).map((e) => Trustee.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// Texts the trustee their confirmation code. Returns nothing, for the same reason
  /// as [sendWitnessCode].
  Future<void> sendTrusteeCode(String trusteeId) =>
      _guard(() => _dio.post('/trustees/$trusteeId/send-code'));
}
