import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../files/domain/file_models.dart';
import '../../portal/application/portal_providers.dart' show portalClientProvider;
import '../data/claim_api.dart';

/// The claim flow SHARES the portal's bare Dio — see portal_client.dart. A claimant
/// has no account, and a signed-in visitor filing on a relative's estate must not
/// carry their Bearer token onto these routes.
///
/// Reused rather than re-created: both surfaces speak the same base URL and the
/// same X-Claim-Token contract, so a second instance would only be a second
/// connection pool and a second place to edit when that policy moves.
final claimApiProvider = Provider<ClaimApi>((ref) => ClaimApi(ref.read(portalClientProvider).dio));

final claimCertificateUploaderProvider =
    Provider<ClaimCertificateUploader>((ref) => ClaimCertificateUploader(ref.read(claimApiProvider)));

/// Where the claimant is in the invite-landing flow at /claim/:token.
/// [checking] and [linkDead] exist because the link's validity was previously discovered
/// only by the presign — i.e. after the claimant had filled in the form, chosen a file and
/// waited for it to be read into memory. The recovery copy for that moment
/// (pcLinkInvalidTitle / pcLinkInvalidSub / pcStartOver) was written and translated into
/// both locales and rendered nowhere.
enum ClaimSubmitStep { checking, form, done, linkDead }

class ClaimSubmitState {
  final ClaimSubmitStep step;
  final String name;

  /// The confirmed death certificate. Submit stays disabled until this exists —
  /// the certificate is REQUIRED, and the backend refuses a file that is not kind
  /// 'death_certificate' with scanStatus CLEAN anyway.
  final StoredFile? certificate;

  /// The chosen file's name, for the "attached" row. Not sent anywhere.
  final String? certificateName;

  final bool uploading;
  final bool busy;
  /// The failure itself, not a pre-rendered sentence.
  ///
  /// Held as the object so the SCREEN decides the wording — see localizedApiMessage. It
  /// used to be a String built in this controller, which had no locale and therefore no
  /// choice but to hardcode English.
  final Object? error;

  const ClaimSubmitState({
    this.step = ClaimSubmitStep.form,
    this.name = '',
    this.certificate,
    this.certificateName,
    this.uploading = false,
    this.busy = false,
    this.error,
  });

  /// Both gates, and both are real: the backend requires a 2..200 character name
  /// and a certificate file id.
  bool get canSubmit => name.trim().length >= 2 && certificate != null && !busy && !uploading;

  ClaimSubmitState copyWith({
    ClaimSubmitStep? step,
    String? name,
    StoredFile? certificate,
    String? certificateName,
    bool? uploading,
    bool? busy,
    Object? error,
    bool clearError = false,
  }) =>
      ClaimSubmitState(
        step: step ?? this.step,
        name: name ?? this.name,
        certificate: certificate ?? this.certificate,
        certificateName: certificateName ?? this.certificateName,
        uploading: uploading ?? this.uploading,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class ClaimSubmitController extends Notifier<ClaimSubmitState> {
  /// Starts in [ClaimSubmitStep.checking], not [ClaimSubmitStep.form]: the link is verified
  /// before the form is offered. Set here rather than as the field's default, because a
  /// hand-constructed state — in a test, or anywhere else — means "show me the form", and
  /// making every construction start in a loading state is a trap.
  @override
  ClaimSubmitState build() => const ClaimSubmitState(step: ClaimSubmitStep.checking);

  /// Checks the link BEFORE the form is offered.
  ///
  /// A dead link is a dead end, not an error on a form: there is nothing to correct and
  /// nothing to retry, so the screen has to say so and point at starting again. Only an
  /// explicit rejection counts — a network failure must NOT be read as "your link is
  /// invalid", which would send someone off to burn one of three daily lookups over a
  /// dropped connection. Anything that is not a refusal falls through to the form, where
  /// the real attempt will produce a real error.
  Future<void> checkLink(String claimToken) async {
    // Only ever runs on the way in. A remount — hot reload, or the screen being rebuilt
    // after the claim is already filed — must not drag a finished flow back to the form.
    if (state.step != ClaimSubmitStep.checking) return;
    try {
      await ref.read(claimApiProvider).session(claimToken);
      state = state.copyWith(step: ClaimSubmitStep.form, clearError: true);
    } on ApiException catch (e) {
      state = e.statusCode == 401 || e.statusCode == 403
          ? state.copyWith(step: ClaimSubmitStep.linkDead)
          : state.copyWith(step: ClaimSubmitStep.form);
    } catch (_) {
      state = state.copyWith(step: ClaimSubmitStep.form);
    }
  }

  void setName(String v) => state = state.copyWith(name: v, clearError: true);

  /// presign → PUT → confirm, against the claim-scoped routes.
  ///
  /// The token buys exactly TWO storage operations, so this runs once per attached
  /// file and a failed presign is refunded by the backend rather than burning the
  /// claimant's only chance to file.
  Future<void> attachCertificate({
    required String token,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (state.uploading) return;
    state = state.copyWith(uploading: true, clearError: true);
    try {
      final stored = await ref.read(claimCertificateUploaderProvider).upload(
            token: token,
            contentType: contentType,
            bytes: bytes,
          );
      state = state.copyWith(uploading: false, certificate: stored, certificateName: fileName);
    } catch (e) {
      state = state.copyWith(uploading: false, error: e);
    }
  }

  Future<bool> submit(String token) async {
    if (!state.canSubmit) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await ref.read(claimApiProvider).submit(
            token: token,
            submittedByName: state.name.trim(),
            certificateFileId: state.certificate!.id,
          );
      state = state.copyWith(busy: false, step: ClaimSubmitStep.done);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e);
      return false;
    }
  }

}

final claimSubmitControllerProvider =
    NotifierProvider<ClaimSubmitController, ClaimSubmitState>(ClaimSubmitController.new);

/// The public lookup at /claim. It has exactly two outcomes in the UI — "not sent
/// yet" and "acknowledged" — because the backend has exactly one: 202 for
/// everything. Nothing here may confirm or deny that a will exists.
class ClaimLookupState {
  final String deceasedContact;
  final String claimantContact;
  final bool acknowledged;
  final bool busy;
  /// The failure itself, not a pre-rendered sentence.
  ///
  /// Held as the object so the SCREEN decides the wording — see localizedApiMessage. It
  /// used to be a String built in this controller, which had no locale and therefore no
  /// choice but to hardcode English.
  final Object? error;

  const ClaimLookupState({
    this.deceasedContact = '',
    this.claimantContact = '',
    this.acknowledged = false,
    this.busy = false,
    this.error,
  });

  /// Both fields are free text — an email OR a phone; the server discriminates on
  /// '@'. The DTO's floor is 3 characters, mirrored here so the button is honest.
  bool get canSubmit =>
      deceasedContact.trim().length >= 3 && claimantContact.trim().length >= 3 && !busy;

  ClaimLookupState copyWith({
    String? deceasedContact,
    String? claimantContact,
    bool? acknowledged,
    bool? busy,
    Object? error,
    bool clearError = false,
  }) =>
      ClaimLookupState(
        deceasedContact: deceasedContact ?? this.deceasedContact,
        claimantContact: claimantContact ?? this.claimantContact,
        acknowledged: acknowledged ?? this.acknowledged,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class ClaimLookupController extends Notifier<ClaimLookupState> {
  @override
  ClaimLookupState build() => const ClaimLookupState();

  void setDeceased(String v) => state = state.copyWith(deceasedContact: v, clearError: true);
  void setClaimant(String v) => state = state.copyWith(claimantContact: v, clearError: true);

  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await ref.read(claimApiProvider).lookup(
            deceasedContact: state.deceasedContact.trim(),
            claimantContact: state.claimantContact.trim(),
          );
      state = state.copyWith(busy: false, acknowledged: true);
    } catch (e) {
      state = state.copyWith(busy: false, error: e is ApiException ? e.message : null);
    }
  }
}

final claimLookupControllerProvider =
    NotifierProvider<ClaimLookupController, ClaimLookupState>(ClaimLookupController.new);
