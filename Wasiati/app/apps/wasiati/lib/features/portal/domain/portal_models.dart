/// Which side of the will this session speaks for. Mirrors the backend's
/// ClaimRole, minus WITNESS — a witness has no portal.
enum PortalRole { heir, trustee }

extension PortalRoleX on PortalRole {
  /// The wire value the backend's PortalStartDto expects.
  String get api => switch (this) {
        PortalRole.heir => 'HEIR',
        PortalRole.trustee => 'TRUSTEE',
      };

  static PortalRole? fromApi(String? v) => switch (v?.toUpperCase()) {
        'HEIR' => PortalRole.heir,
        'TRUSTEE' => PortalRole.trustee,
        _ => null,
      };
}

/// DeathClaim.status as the portal sees it.
enum ClaimStatus { submitted, underReview, approved, rejected, released }

ClaimStatus? claimStatusFromApi(String? v) => switch (v) {
      'SUBMITTED' => ClaimStatus.submitted,
      'UNDER_REVIEW' => ClaimStatus.underReview,
      'APPROVED' => ClaimStatus.approved,
      'REJECTED' => ClaimStatus.rejected,
      'RELEASED' => ClaimStatus.released,
      _ => null,
    };

/// The result of exchanging an emailed code for a session. [token] is returned
/// ONCE and is unrecoverable afterwards — it is held in memory only (never in
/// storage, never in the URL).
class PortalSession {
  final String token;
  final DateTime? expiresAt;
  final PortalRole role;
  final String estateName;
  final ClaimStatus? claimStatus;

  const PortalSession({
    required this.token,
    required this.expiresAt,
    required this.role,
    required this.estateName,
    required this.claimStatus,
  });

  factory PortalSession.fromJson(Map<String, dynamic> j) => PortalSession(
        token: j['token'] as String,
        expiresAt: DateTime.tryParse((j['expiresAt'] as String?) ?? ''),
        role: PortalRoleX.fromApi(j['role'] as String?) ?? PortalRole.heir,
        estateName: (j['estateName'] as String?) ?? '',
        claimStatus: claimStatusFromApi(j['claimStatus'] as String?),
      );
}

/// GET /portal/me — who this session is. Not gated on release.
class PortalMe {
  final PortalRole role;
  final String estateName;
  final ClaimStatus? claimStatus;

  /// This trustee was named on the will but never accepted the role, so the estate stays
  /// closed to them until they do. Reported here rather than discovered as a 403 on the
  /// will screen: they came to do a job, and the fix is one tap on this same page.
  final bool trusteeAcceptancePending;

  const PortalMe({
    required this.role,
    required this.estateName,
    required this.claimStatus,
    this.trusteeAcceptancePending = false,
  });

  factory PortalMe.fromJson(Map<String, dynamic> j) => PortalMe(
        role: PortalRoleX.fromApi(j['role'] as String?) ?? PortalRole.heir,
        estateName: (j['estateName'] as String?) ?? '',
        claimStatus: claimStatusFromApi(j['claimStatus'] as String?),
        trusteeAcceptancePending: (j['trusteeAcceptancePending'] as bool?) ?? false,
      );
}

/// One row of the heir release roll-call.
class HeirConfirmation {
  final String heirContactId;
  final String name;
  final String relation;

  /// Mirrors the backend release gate exactly: `!isMinor && (phone || email)`.
  /// An unreachable heir is NOT waited on, and the UI must not imply otherwise.
  final bool reachable;
  final bool confirmed;
  final DateTime? confirmedAt;

  const HeirConfirmation({
    required this.heirContactId,
    required this.name,
    required this.relation,
    required this.reachable,
    required this.confirmed,
    required this.confirmedAt,
  });

  factory HeirConfirmation.fromJson(Map<String, dynamic> j) => HeirConfirmation(
        heirContactId: (j['heirContactId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        relation: (j['relation'] as String?) ?? '',
        reachable: (j['reachable'] as bool?) ?? false,
        confirmed: (j['confirmed'] as bool?) ?? false,
        confirmedAt: DateTime.tryParse((j['confirmedAt'] as String?) ?? ''),
      );
}

/// GET /portal/claim. Below APPROVED the backend sends `{ status }` and NOTHING
/// else — the roll-call fields stay empty rather than being invented client-side.
class PortalClaim {
  final ClaimStatus? status;
  final bool overrideActive;
  final bool myConfirmationPending;
  final List<HeirConfirmation> heirConfirmations;

  const PortalClaim({
    required this.status,
    this.overrideActive = false,
    this.myConfirmationPending = false,
    this.heirConfirmations = const [],
  });

  factory PortalClaim.fromJson(Map<String, dynamic> j) => PortalClaim(
        status: claimStatusFromApi(j['status'] as String?),
        overrideActive: (j['overrideActive'] as bool?) ?? false,
        myConfirmationPending: (j['myConfirmationPending'] as bool?) ?? false,
        heirConfirmations: ((j['heirConfirmations'] as List?) ?? const [])
            .map((e) => HeirConfirmation.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// Heirs the release actually waits on. Unreachable heirs are excluded by the
  /// same rule the backend gate uses.
  Iterable<HeirConfirmation> get awaited => heirConfirmations.where((h) => h.reachable);
}

/// One heir's fara'id share of the estate.
class ShariaShare {
  final String heirName;
  final String heirRelation;

  /// A JSON number at the edge — the backend converts Prisma's Decimal so the
  /// client is never handed a string to guess at.
  final double sharePercent;

  const ShariaShare({required this.heirName, required this.heirRelation, required this.sharePercent});

  factory ShariaShare.fromJson(Map<String, dynamic> j) => ShariaShare(
        heirName: (j['heirName'] as String?) ?? '',
        heirRelation: (j['heirRelation'] as String?) ?? '',
        sharePercent: (j['sharePercent'] as num?)?.toDouble() ?? 0,
      );
}

/// A bequest (wasiyya) — up to a third, outside the fara'id shares.
class PortalBequest {
  final String beneficiaryName;
  final double sharePercent;
  final String? notes;

  const PortalBequest({required this.beneficiaryName, required this.sharePercent, this.notes});

  factory PortalBequest.fromJson(Map<String, dynamic> j) => PortalBequest(
        beneficiaryName: (j['beneficiaryName'] as String?) ?? '',
        sharePercent: (j['sharePercent'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
      );
}

/// GET /portal/will — the released contents.
///
/// There is no vault field here and there will not be one. Vault items are
/// end-to-end encrypted under a passphrase the server never holds; they do not
/// reach heirs through this portal, and no copy on these screens may suggest they do.
/// One line of the inventory, as the heirs receive it.
///
/// [accountRef] arrives UNMASKED and that is deliberate on the server's side: the owner's
/// own screens mask it to last-4 because they already know their IBAN, but this payload
/// exists — in the endpoint's own words — "so the heirs can walk into the institution and
/// locate the asset". Masking it here would defeat the reason the field was ever recorded.
class PortalAsset {
  final String type;
  final String label;
  final String? institution;
  final double? estimatedValue;
  final String? currency;
  final String? notes;
  final String? contactPhone;
  final String? contactEmail;
  final String? accountRef;

  const PortalAsset({
    required this.type,
    required this.label,
    this.institution,
    this.estimatedValue,
    this.currency,
    this.notes,
    this.contactPhone,
    this.contactEmail,
    this.accountRef,
  });

  factory PortalAsset.fromJson(Map<String, dynamic> j) => PortalAsset(
        type: (j['type'] as String?) ?? 'OTHER',
        label: (j['label'] as String?) ?? '',
        institution: j['institution'] as String?,
        estimatedValue: (j['estimatedValue'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        notes: j['notes'] as String?,
        contactPhone: j['contactPhone'] as String?,
        contactEmail: j['contactEmail'] as String?,
        accountRef: j['accountRef'] as String?,
      );
}

/// Who the testator named to care for their minor children.
class PortalGuardianship {
  final String mode;
  final String? name;
  final String? phone;
  final String? email;

  const PortalGuardianship({required this.mode, this.name, this.phone, this.email});

  factory PortalGuardianship.fromJson(Map<String, dynamic> j) => PortalGuardianship(
        mode: (j['mode'] as String?) ?? '',
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
      );
}

class PortalWill {
  final String estateName;
  final String? personalMessage;
  final List<ShariaShare> shariaShares;
  final List<PortalBequest> bequests;

  /// The inventory, the funeral wishes and the guardianship.
  ///
  /// These were fetched over the wire and thrown away by this parser: the server has
  /// always sent all three, and fromJson read only the four fields above. A father who
  /// recorded six accounts with their IBANs and branch numbers — precisely so his family
  /// could find them — handed his daughter a personal message and a list of percentages.
  /// The PDF was no fallback either: its renderer receives only type/label/institution/
  /// value/currency, so the references reached NO artifact the family could obtain, and
  /// the 90-day purge then erased them for good.
  final List<PortalAsset> assets;
  final Map<String, dynamic>? funeralWishes;
  final PortalGuardianship? guardianship;

  const PortalWill({
    required this.estateName,
    required this.personalMessage,
    required this.shariaShares,
    required this.bequests,
    this.assets = const [],
    this.funeralWishes,
    this.guardianship,
  });

  factory PortalWill.fromJson(Map<String, dynamic> j) => PortalWill(
        estateName: (j['estateName'] as String?) ?? '',
        personalMessage: j['personalMessage'] as String?,
        shariaShares: ((j['shariaShares'] as List?) ?? const [])
            .map((e) => ShariaShare.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        bequests: ((j['bequests'] as List?) ?? const [])
            .map((e) => PortalBequest.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        assets: ((j['assets'] as List?) ?? const [])
            .map((e) => PortalAsset.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        funeralWishes: (j['funeralWishes'] as Map?)?.cast<String, dynamic>(),
        guardianship: j['guardianship'] == null
            ? null
            : PortalGuardianship.fromJson((j['guardianship'] as Map).cast<String, dynamic>()),
      );
}

/// One entry of GET /portal/will/videos. [url] is short-lived (~5 min) and
/// presigned for inline playback; the list arrives OLDEST first, which is the
/// order the owner recorded them in and the order they should be watched.
class PortalVideo {
  final String fileId;
  final String url;
  final String contentType;
  final int sizeBytes;
  final DateTime? recordedAt;

  const PortalVideo({
    required this.fileId,
    required this.url,
    required this.contentType,
    required this.sizeBytes,
    required this.recordedAt,
  });

  factory PortalVideo.fromJson(Map<String, dynamic> j) => PortalVideo(
        fileId: (j['fileId'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        contentType: (j['contentType'] as String?) ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        recordedAt: DateTime.tryParse((j['recordedAt'] as String?) ?? ''),
      );
}
