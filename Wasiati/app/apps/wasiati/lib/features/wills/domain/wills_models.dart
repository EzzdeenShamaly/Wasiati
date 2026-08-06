// Will, heir, and Sharia-share models + a Dart port of the backend calculator so
// shares recompute live as the user edits heirs (server remains the source of truth).

enum HeirRelation {
  husband,
  wife,
  son,
  daughter,
  sonSon,
  sonDaughter,
  father,
  mother,
  grandfather,
  paternalGrandmother,
  maternalGrandmother,
  fullBrother,
  fullSister,
  consanguineBrother,
  consanguineSister,
  maternalSibling,
  fullNephew,
  consanguineNephew,
  fullUncle,
  consanguineUncle,
  fullCousin,
  consanguineCousin,
}

extension HeirRelationX on HeirRelation {
  String get api => switch (this) {
        HeirRelation.husband => 'HUSBAND',
        HeirRelation.wife => 'WIFE',
        HeirRelation.son => 'SON',
        HeirRelation.daughter => 'DAUGHTER',
        HeirRelation.sonSon => 'SON_SON',
        HeirRelation.sonDaughter => 'SON_DAUGHTER',
        HeirRelation.father => 'FATHER',
        HeirRelation.mother => 'MOTHER',
        HeirRelation.grandfather => 'GRANDFATHER',
        HeirRelation.paternalGrandmother => 'PATERNAL_GRANDMOTHER',
        HeirRelation.maternalGrandmother => 'MATERNAL_GRANDMOTHER',
        HeirRelation.fullBrother => 'FULL_BROTHER',
        HeirRelation.fullSister => 'FULL_SISTER',
        HeirRelation.consanguineBrother => 'CONSANGUINE_BROTHER',
        HeirRelation.consanguineSister => 'CONSANGUINE_SISTER',
        HeirRelation.maternalSibling => 'MATERNAL_SIBLING',
        HeirRelation.fullNephew => 'FULL_NEPHEW',
        HeirRelation.consanguineNephew => 'CONSANGUINE_NEPHEW',
        HeirRelation.fullUncle => 'FULL_UNCLE',
        HeirRelation.consanguineUncle => 'CONSANGUINE_UNCLE',
        HeirRelation.fullCousin => 'FULL_COUSIN',
        HeirRelation.consanguineCousin => 'CONSANGUINE_COUSIN',
      };

  /// English fallback label (the live UI uses the localised heirRelLabel(l, api)).
  String get label => switch (this) {
        HeirRelation.husband => 'Husband',
        HeirRelation.wife => 'Wife',
        HeirRelation.son => 'Son',
        HeirRelation.daughter => 'Daughter',
        HeirRelation.sonSon => "Son's son (grandson)",
        HeirRelation.sonDaughter => "Son's daughter (granddaughter)",
        HeirRelation.father => 'Father',
        HeirRelation.mother => 'Mother',
        HeirRelation.grandfather => 'Grandfather (paternal)',
        HeirRelation.paternalGrandmother => 'Grandmother (paternal)',
        HeirRelation.maternalGrandmother => 'Grandmother (maternal)',
        HeirRelation.fullBrother => 'Brother (full)',
        HeirRelation.fullSister => 'Sister (full)',
        HeirRelation.consanguineBrother => 'Brother (paternal half)',
        HeirRelation.consanguineSister => 'Sister (paternal half)',
        HeirRelation.maternalSibling => 'Sibling (maternal half)',
        HeirRelation.fullNephew => "Brother's son (full)",
        HeirRelation.consanguineNephew => "Brother's son (paternal half)",
        HeirRelation.fullUncle => 'Paternal uncle (full)',
        HeirRelation.consanguineUncle => 'Paternal uncle (paternal half)',
        HeirRelation.fullCousin => "Paternal uncle's son (full)",
        HeirRelation.consanguineCousin => "Paternal uncle's son (paternal half)",
      };
}

class Heir {
  final HeirRelation relation;
  final String name;
  const Heir(this.relation, this.name);
}

class ShariaShare {
  final String heirRelation;
  final String heirName;
  final double sharePercent;
  final String? basisEn; // scriptural basis (Qur'an/Sunnah citation), from the backend
  final String? basisAr;
  const ShariaShare({
    required this.heirRelation,
    required this.heirName,
    required this.sharePercent,
    this.basisEn,
    this.basisAr,
  });

  /// The basis in the given locale ('ar' -> Arabic), or null if the backend didn't send one.
  String? basisFor(String languageCode) => languageCode == 'ar' ? basisAr : basisEn;

  factory ShariaShare.fromJson(Map<String, dynamic> j) => ShariaShare(
        heirRelation: j['heirRelation'] as String,
        heirName: j['heirName'] as String,
        sharePercent: double.tryParse('${j['sharePercent']}') ?? 0,
        basisEn: j['basisEn'] as String?,
        basisAr: j['basisAr'] as String?,
      );
}

class Bequest {
  final String id;
  final String beneficiaryName;
  final double sharePercent;
  final String? notes;
  const Bequest({required this.id, required this.beneficiaryName, required this.sharePercent, this.notes});

  factory Bequest.fromJson(Map<String, dynamic> j) => Bequest(
        id: j['id'] as String,
        beneficiaryName: j['beneficiaryName'] as String,
        sharePercent: double.tryParse('${j['sharePercent']}') ?? 0,
        notes: j['notes'] as String?,
      );
}

class Witness {
  final String id;
  final String fullName;
  final String phone;
  final String status;

  /// When THIS witness signed. The server has always sent it (findOne/listForWill return
  /// full rows) and this model dropped it — which forced the will document to date every
  /// signature with the will's SEAL date, a date on which nobody but the system did
  /// anything. On an attestation page the whole point of a date is who acted when.
  final DateTime? signedAt;

  const Witness({required this.id, required this.fullName, required this.phone, required this.status, this.signedAt});
  factory Witness.fromJson(Map<String, dynamic> j) => Witness(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        phone: j['phone'] as String,
        status: j['status'] as String,
        signedAt: DateTime.tryParse('${j['signedAt'] ?? ''}'),
      );
}

class Trustee {
  final String id;
  final String fullName;
  final String phone;
  final String status;

  /// When THIS trustee confirmed — same reasoning as Witness.signedAt.
  final DateTime? confirmedAt;

  const Trustee({required this.id, required this.fullName, required this.phone, required this.status, this.confirmedAt});
  factory Trustee.fromJson(Map<String, dynamic> j) => Trustee(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        phone: j['phone'] as String,
        status: j['status'] as String,
        confirmedAt: DateTime.tryParse('${j['confirmedAt'] ?? ''}'),
      );
}

/// A directive beyond the will (prototype "Wills" screen): 'POA' (financial power
/// of attorney) or 'HCD' (healthcare directive). User-scoped, not will-scoped —
/// effective in life, never part of the exported will PDF. One per type; saving
/// signs it, so `status` is 'SIGNED' once executed.
class DirectiveDoc {
  final String id;
  final String type; // 'POA' | 'HCD'
  final String agentName;
  final String agentPhone;
  final String agentEmail;
  final String wishes; // HCD treatment wishes; empty on a POA
  final String status; // 'DRAFT' | 'SIGNED'
  const DirectiveDoc({
    required this.id,
    required this.type,
    this.agentName = '',
    this.agentPhone = '',
    this.agentEmail = '',
    this.wishes = '',
    this.status = 'DRAFT',
  });

  bool get signed => status == 'SIGNED';

  factory DirectiveDoc.fromJson(Map<String, dynamic> j) => DirectiveDoc(
        id: j['id'] as String,
        type: j['type'] as String,
        agentName: (j['agentName'] as String?) ?? '',
        agentPhone: (j['agentPhone'] as String?) ?? '',
        agentEmail: (j['agentEmail'] as String?) ?? '',
        wishes: (j['wishes'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'DRAFT',
      );
}

/// A heir-registry row (create-flow step 2) — contact details per heir so the
/// will can be released to each of them at claim time. The `relation` here is the
/// free registry key (son/daughter/wife/husband/…/other), NOT the fara'id enum.
class HeirContact {
  final String id;
  final String relation;
  final String name;
  final String phone;
  final String email;
  final bool isMinor;
  const HeirContact({
    required this.id,
    required this.relation,
    this.name = '',
    this.phone = '',
    this.email = '',
    this.isMinor = false,
  });

  /// True once name, phone and email are all present — the seal gate.
  bool get isComplete => name.trim().isNotEmpty && phone.trim().isNotEmpty && email.trim().isNotEmpty;

  HeirContact copyWith({String? relation, String? name, String? phone, String? email, bool? isMinor}) => HeirContact(
        id: id,
        relation: relation ?? this.relation,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        isMinor: isMinor ?? this.isMinor,
      );

  factory HeirContact.fromJson(Map<String, dynamic> j) => HeirContact(
        id: j['id'] as String,
        relation: (j['relation'] as String?) ?? 'other',
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        isMinor: j['isMinor'] as bool? ?? false,
      );
}

class Will {
  final String id;
  final String tier;
  final bool locked;
  final String? disclaimerVersion;
  final String? personalMessage; // "Words for my family" — released with the will
  final String status; // DRAFT | SIGNED | WITNESSED | SEALED
  final DateTime? sealedAt; // when the will reached SEALED
  final DateTime? signedAt; // when the OWNER signed — distinct from sealing, often days apart
  final DateTime? updatedAt; // last server-side change
  final int? requiredWitnesses; // witnesses needed to reach WITNESSED
  // Guardianship of minor children (create-flow step 3): 'parent' | 'islamic' | 'named'.
  final String? guardianMode;
  final String? guardianName;
  final String? guardianPhone;
  final String? guardianEmail;

  /// Create-flow autosave snapshot (spec §3 autosave). Non-null only on the DRAFT
  /// will the guided flow is mid-way through; sealing clears it server-side.
  final Map<String, dynamic>? draftState;

  /// Funeral & burial wishes (spec §8: wishes{sunnah,simple,local,azaa}).
  final Map<String, dynamic>? funeralWishes;
  final List<ShariaShare> shariaShares;
  final List<Bequest> bequests;

  /// Witness rows as sent by the LIST endpoint — may be trimmed to {id, status}
  /// (no PII), so fullName/phone can be empty strings here.
  final List<Witness> witnesses;

  const Will({
    required this.id,
    required this.tier,
    required this.locked,
    this.disclaimerVersion,
    this.personalMessage,
    this.status = 'DRAFT',
    this.sealedAt,
    this.signedAt,
    this.updatedAt,
    this.requiredWitnesses,
    this.guardianMode,
    this.guardianName,
    this.guardianPhone,
    this.guardianEmail,
    this.draftState,
    this.funeralWishes,
    this.shariaShares = const [],
    this.bequests = const [],
    this.witnesses = const [],
  });

  /// True when this row is the guided create flow's live draft — the one the
  /// DRAFT card (dashboard + wills list) resumes.
  bool get isFlowDraft => status == 'DRAFT' && draftState != null;

  /// The 1-based step (1..6) the create flow was on, from the autosave snapshot.
  int get draftStep {
    final s = draftState?['step'];
    if (s is num) return s.toInt().clamp(1, 6);
    return 1;
  }

  factory Will.fromJson(Map<String, dynamic> j) => Will(
        id: j['id'] as String,
        tier: j['tier'] as String,
        locked: j['locked'] as bool? ?? false,
        disclaimerVersion: j['disclaimerVersion'] as String?,
        personalMessage: j['personalMessage'] as String?,
        status: (j['status'] as String?) ?? ((j['locked'] as bool? ?? false) ? 'SEALED' : 'DRAFT'),
        sealedAt: DateTime.tryParse('${j['sealedAt'] ?? ''}'),
        signedAt: DateTime.tryParse('${j['signedAt'] ?? ''}'),
        updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}'),
        requiredWitnesses: (j['requiredWitnesses'] as num?)?.toInt(),
        guardianMode: j['guardianMode'] as String?,
        guardianName: j['guardianName'] as String?,
        guardianPhone: j['guardianPhone'] as String?,
        guardianEmail: j['guardianEmail'] as String?,
        draftState: (j['draftState'] as Map?)?.cast<String, dynamic>(),
        funeralWishes: (j['funeralWishes'] as Map?)?.cast<String, dynamic>(),
        shariaShares: ((j['shariaShares'] as List?) ?? const [])
            .map((e) => ShariaShare.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        bequests: ((j['bequests'] as List?) ?? const [])
            .map((e) => Bequest.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        // Parsed defensively (not via Witness.fromJson): the list endpoint sends
        // only {id, status} and omits the PII fields.
        witnesses: ((j['witnesses'] as List?) ?? const []).map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return Witness(
            id: '${m['id'] ?? ''}',
            fullName: (m['fullName'] as String?) ?? '',
            phone: (m['phone'] as String?) ?? '',
            status: (m['status'] as String?) ?? '',
          );
        }).toList(),
      );
}

class _S {
  final String rel;
  final String name;
  double f;
  _S(this.rel, this.name, this.f);
}

/// Rounds exact fractions (which sum to 1) to 2-dp percentages summing to EXACTLY
/// 100.00 — largest-remainder (Hamilton). Mirrors the backend's apportionPercents:
/// rounding each share independently drifts the total to 100.01/99.99. Fractions are
/// untouched; only the leftover basis points are handed to the largest remainders.
List<double> _apportionPercents(List<double> fractions) {
  const totalBp = 10000; // 100.00% in basis points
  final exact = fractions.map((f) => f * totalBp).toList();
  final floors = exact.map((e) => e.floor()).toList();
  final deficit = totalBp - floors.fold<int>(0, (s, n) => s + n);
  final order = List.generate(exact.length, (i) => i)
    ..sort((a, b) {
      final d = (exact[b] - floors[b]).compareTo(exact[a] - floors[a]);
      return d != 0 ? d : a.compareTo(b);
    });
  final bp = [...floors];
  for (var k = 0; k < deficit && k < order.length; k++) {
    bp[order[k]] += 1;
  }
  return bp.map((n) => n / 100).toList();
}

/// The public treasury — takes a surplus no heir is entitled to. Not a person.
const String kBaytAlMal = 'BAYT_AL_MAL';

/// Schools that return a surplus to the non-spouse sharers (radd) rather than
/// sending it to bayt al-mal. Maliki and Shafi'i (classical) do not.
// Contemporary practice (DECISIONS §0): ALL schools return a surplus to the heirs.
// So Maliki/Shafi'i match Jumhur for the heirs we model; only the grandfather case
// still separates Hanafi from the rest.
const Set<String> kRaddSchools = {'JUMHUR', 'HANAFI', 'HANBALI', 'MALIKI', 'SHAFII'};

/// Dart mirror of the backend fara'id calculator, kept line-for-line consistent with
/// `backend/src/wills/sharia-calculator.ts`. Used only for the LIVE PREVIEW while the
/// user edits heirs; the server recomputes on save and remains authoritative.
///
/// Models the full primary Sunni heir set, the 'asaba priority chain, hijab, 'awl,
/// school-aware radd, and the special cases al-Gharrawayn (spouse + both parents →
/// mother takes 1/3 of the residue after the spouse), 'asaba ma'a al-ghayr (sisters
/// residuary alongside daughters), and grandfather muqasama.
///
/// `madhhab` is one of JUMHUR | HANAFI | MALIKI | SHAFII | HANBALI. It governs radd
/// and the grandfather-with-siblings dispute. Dhawu al-arham are not modelled.
List<ShariaShare> calculateShariaShares(List<Heir> heirs, {String madhhab = 'JUMHUR'}) {
  List<Heir> grp(HeirRelation r) => heirs.where((h) => h.relation == r).toList();
  final sons = grp(HeirRelation.son);
  final daughters = grp(HeirRelation.daughter);
  final sonSons = grp(HeirRelation.sonSon);
  final sonDaughters = grp(HeirRelation.sonDaughter);
  final wives = grp(HeirRelation.wife);
  final husband = grp(HeirRelation.husband).firstOrNull;
  final father = grp(HeirRelation.father).firstOrNull;
  final mother = grp(HeirRelation.mother).firstOrNull;
  final gf0 = grp(HeirRelation.grandfather).firstOrNull;
  final patGms = grp(HeirRelation.paternalGrandmother);
  final matGms = grp(HeirRelation.maternalGrandmother);
  final fullBros = grp(HeirRelation.fullBrother);
  final fullSis = grp(HeirRelation.fullSister);
  final conBros = grp(HeirRelation.consanguineBrother);
  final conSis = grp(HeirRelation.consanguineSister);
  final matSibs = grp(HeirRelation.maternalSibling);
  final fullNephews = grp(HeirRelation.fullNephew);
  final conNephews = grp(HeirRelation.consanguineNephew);
  final fullUncles = grp(HeirRelation.fullUncle);
  final conUncles = grp(HeirRelation.consanguineUncle);
  final fullCousins = grp(HeirRelation.fullCousin);
  final conCousins = grp(HeirRelation.consanguineCousin);

  final hasSon = sons.isNotEmpty;
  final hasSonSon = sonSons.isNotEmpty;
  final maleDesc = hasSon || hasSonSon;
  final anyDesc = maleDesc || daughters.isNotEmpty || sonDaughters.isNotEmpty;
  final femaleDesc = daughters.isNotEmpty || sonDaughters.isNotEmpty;
  final hasFather = father != null;
  final gf = !hasFather ? gf0 : null;
  final fatherLine = hasFather || gf != null;

  final shares = <_S>[];
  void push(String rel, String name, double f) {
    if (f > 1e-12) shares.add(_S(rel, name, f));
  }

  double sum() => shares.fold(0.0, (a, x) => a + x.f);

  final siblingHeadcount = fullBros.length + fullSis.length + conBros.length + conSis.length + matSibs.length;
  final double spouseFraction = husband != null ? 1 / 2 : (wives.isNotEmpty ? 1 / 4 : 0.0);
  final gharrawayn = spouseFraction > 0 && mother != null && fatherLine && !anyDesc && siblingHeadcount == 0;

  // --- Spouse ---
  if (husband != null) push('HUSBAND', husband.name, anyDesc ? 1 / 4 : 1 / 2);
  if (wives.isNotEmpty) {
    final t = anyDesc ? 1 / 8 : 1 / 4;
    for (final w in wives) {
      push('WIFE', w.name, t / wives.length);
    }
  }

  // --- Mother / grandmothers ---
  if (mother != null) {
    final mf =
        gharrawayn ? (1 - spouseFraction) / 3 : ((anyDesc || siblingHeadcount >= 2) ? 1 / 6 : 1 / 3);
    push('MOTHER', mother.name, mf);
  } else {
    final gms = <({String rel, String name})>[
      for (final g in matGms) (rel: 'MATERNAL_GRANDMOTHER', name: g.name),
      if (!hasFather)
        for (final g in patGms) (rel: 'PATERNAL_GRANDMOTHER', name: g.name),
    ];
    for (final g in gms) {
      push(g.rel, g.name, 1 / 6 / gms.length);
    }
  }

  // --- Uterine siblings ---
  final matSibsActive = (!anyDesc && !fatherLine) ? matSibs : <Heir>[];
  if (matSibsActive.isNotEmpty) {
    final t = matSibsActive.length == 1 ? 1 / 6 : 1 / 3;
    for (final s in matSibsActive) {
      push('MATERNAL_SIBLING', s.name, t / matSibsActive.length);
    }
  }

  // --- Father / grandfather fixed portion ---
  var fatherResiduary = false;
  var gfResiduary = false;
  if (hasFather) {
    if (maleDesc) {
      push('FATHER', father.name, 1 / 6);
    } else if (femaleDesc) {
      push('FATHER', father.name, 1 / 6);
      fatherResiduary = true;
    } else {
      fatherResiduary = true;
    }
  } else if (gf != null) {
    // When the grandfather shares the residue with siblings by muqasama (every school
    // but Hanafi), his ENTIRE share is decided by the best-of-three in the residue block
    // below (muqasama vs 1/3-of-residue vs the 1/6-of-estate floor). Pushing a fixed 1/6
    // here as well would double-count it and wrongly shrink the siblings.
    final gfMuqasamaWithSiblings =
        madhhab != 'HANAFI' && fullBros.length + fullSis.length + conBros.length + conSis.length > 0;
    if (maleDesc) {
      push('GRANDFATHER', gf.name, 1 / 6);
    } else if (femaleDesc) {
      // Like a father, the grandfather takes 1/6 + residue — EXCEPT when muqasama with
      // siblings applies, where the 1/6 is folded into the best-of-three below.
      if (!gfMuqasamaWithSiblings) push('GRANDFATHER', gf.name, 1 / 6);
      gfResiduary = true;
    } else {
      gfResiduary = true;
    }
  }

  // --- Daughters fixed (no son) ---
  if (!hasSon && daughters.isNotEmpty) {
    final t = daughters.length == 1 ? 1 / 2 : 2 / 3;
    for (final d in daughters) {
      push('DAUGHTER', d.name, t / daughters.length);
    }
  }

  // --- Son's daughters fixed (no son, no son's son) ---
  if (!hasSon && !hasSonSon && sonDaughters.isNotEmpty) {
    if (daughters.isEmpty) {
      final t = sonDaughters.length == 1 ? 1 / 2 : 2 / 3;
      for (final d in sonDaughters) {
        push('SON_DAUGHTER', d.name, t / sonDaughters.length);
      }
    } else if (daughters.length == 1) {
      for (final d in sonDaughters) {
        push('SON_DAUGHTER', d.name, 1 / 6 / sonDaughters.length);
      }
    }
  }

  // --- Sister status flags ---
  final fullSisBlocked = maleDesc || hasFather;
  final fullSisMaaAlGhayr = fullSis.isNotEmpty && !fullSisBlocked && gf == null && fullBros.isEmpty && femaleDesc;
  final fullSisIsResiduary =
      fullSis.isNotEmpty && (fullSisMaaAlGhayr || (!fullSisBlocked && gf == null && fullBros.isNotEmpty));
  if (!fullSisBlocked && gf == null && fullBros.isEmpty && !femaleDesc && fullSis.isNotEmpty) {
    final t = fullSis.length == 1 ? 1 / 2 : 2 / 3;
    for (final s in fullSis) {
      push('FULL_SISTER', s.name, t / fullSis.length);
    }
  }

  final fullSisTookTwoThirds =
      !fullSisBlocked && gf == null && fullBros.isEmpty && !femaleDesc && fullSis.length >= 2;
  final conBlocked = maleDesc || hasFather || fullBros.isNotEmpty || fullSisIsResiduary || fullSisTookTwoThirds;
  final conSisMaaAlGhayr = conSis.isNotEmpty && !conBlocked && gf == null && conBros.isEmpty && femaleDesc;
  final conSisIsResiduary =
      conSis.isNotEmpty && (conSisMaaAlGhayr || (!conBlocked && gf == null && conBros.isNotEmpty));
  if (!conBlocked && gf == null && conBros.isEmpty && !femaleDesc && conSis.isNotEmpty) {
    final oneFullSisterTookHalf = fullSis.length == 1 && !fullSisBlocked && fullBros.isEmpty;
    if (oneFullSisterTookHalf) {
      for (final s in conSis) {
        push('CONSANGUINE_SISTER', s.name, 1 / 6 / conSis.length);
      }
    } else if (fullSis.isEmpty) {
      final t = conSis.length == 1 ? 1 / 2 : 2 / 3;
      for (final s in conSis) {
        push('CONSANGUINE_SISTER', s.name, t / conSis.length);
      }
    }
  }

  // --- Residue (ʿaṣaba) ---
  final residue = 1 - sum();
  final r = residue > 0 ? residue : 0.0;
  void distribute(List<({String rel, String name, int units})> rs, double amount) {
    final totalUnits = rs.fold(0, (a, x) => a + x.units);
    if (totalUnits <= 0 || amount <= 1e-12) return;
    for (final x in rs) {
      push(x.rel, x.name, amount * (x.units / totalUnits));
    }
  }

  List<({String rel, String name, int units})> u(List<Heir> l, String rel, int units) =>
      [for (final x in l) (rel: rel, name: x.name, units: units)];

  if (hasSon) {
    distribute([...u(sons, 'SON', 2), ...u(daughters, 'DAUGHTER', 1)], r);
  } else if (hasSonSon) {
    distribute([...u(sonSons, 'SON_SON', 2), ...u(sonDaughters, 'SON_DAUGHTER', 1)], r);
  } else if (fatherResiduary && hasFather) {
    push('FATHER', father.name, r);
  } else if (gfResiduary && gf != null) {
    final gfSibs = [...fullBros, ...fullSis, ...conBros, ...conSis];
    // Hanafi: the grandfather blocks siblings outright. Every other school shares
    // with them by muqasama — including when a daughter/son's-daughter is present
    // (the earlier `!femaleDesc` guard wrongly gave the grandfather the whole residue
    // and disinherited the siblings in the Jumhur default).
    if (madhhab != 'HANAFI' && gfSibs.isNotEmpty) {
      final sibUnits = <({String rel, String name, int units})>[
        ...u(fullBros, 'FULL_BROTHER', 2),
        ...u(fullSis, 'FULL_SISTER', 1),
        if (fullBros.isEmpty && fullSis.isEmpty) ...[
          ...u(conBros, 'CONSANGUINE_BROTHER', 2),
          ...u(conSis, 'CONSANGUINE_SISTER', 1),
        ],
      ];
      final units = 2 + sibUnits.fold(0, (a, x) => a + x.units);
      final muqasama = r * (2 / units);
      final hasFixedSharers = sum() > 1e-9;
      var gfShare = muqasama > r / 3 ? muqasama : r / 3;
      if (hasFixedSharers && gfShare < 1 / 6) gfShare = 1 / 6;
      if (gfShare > r) gfShare = r;
      push('GRANDFATHER', gf.name, gfShare);
      distribute(sibUnits, (r - gfShare) > 0 ? (r - gfShare) : 0);
    } else {
      push('GRANDFATHER', gf.name, r);
    }
  } else if (fullBros.isNotEmpty) {
    distribute([...u(fullBros, 'FULL_BROTHER', 2), ...u(fullSis, 'FULL_SISTER', 1)], r);
  } else if (fullSisIsResiduary && fullSis.isNotEmpty) {
    distribute(u(fullSis, 'FULL_SISTER', 1), r);
  } else if (conBros.isNotEmpty && !conBlocked) {
    distribute([...u(conBros, 'CONSANGUINE_BROTHER', 2), ...u(conSis, 'CONSANGUINE_SISTER', 1)], r);
  } else if (conSisIsResiduary && conSis.isNotEmpty) {
    distribute(u(conSis, 'CONSANGUINE_SISTER', 1), r);
  } else if (fullNephews.isNotEmpty) {
    distribute(u(fullNephews, 'FULL_NEPHEW', 1), r);
  } else if (conNephews.isNotEmpty) {
    distribute(u(conNephews, 'CONSANGUINE_NEPHEW', 1), r);
  } else if (fullUncles.isNotEmpty) {
    distribute(u(fullUncles, 'FULL_UNCLE', 1), r);
  } else if (conUncles.isNotEmpty) {
    distribute(u(conUncles, 'CONSANGUINE_UNCLE', 1), r);
  } else if (fullCousins.isNotEmpty) {
    distribute(u(fullCousins, 'FULL_COUSIN', 1), r);
  } else if (conCousins.isNotEmpty) {
    distribute(u(conCousins, 'CONSANGUINE_COUSIN', 1), r);
  }

  // Merge duplicate (rel+name) entries, then apply 'awl / radd.
  final merged = <String, _S>{};
  for (final s in shares) {
    final k = '${s.rel}|${s.name}';
    final ex = merged[k];
    if (ex != null) {
      ex.f += s.f;
    } else {
      merged[k] = _S(s.rel, s.name, s.f);
    }
  }
  final list = merged.values.toList();
  final total = list.fold(0.0, (a, x) => a + x.f);
  if (total > 1.0000001) {
    for (final x in list) {
      x.f /= total;
    }
  } else if (total < 0.9999999) {
    final surplus = 1 - total;
    // A spouse never takes by radd.
    final raddable = list.where((x) => x.rel != 'HUSBAND' && x.rel != 'WIFE').toList();
    final base = raddable.fold(0.0, (a, x) => a + x.f);

    if (base > 0 && kRaddSchools.contains(madhhab)) {
      for (final x in raddable) {
        x.f += surplus * (x.f / base);
      }
    } else {
      // Maliki / Shafi'i: no radd, the surplus escheats. Or (any school) nobody but
      // a spouse survives. Either way it belongs to bayt al-mal and is shown as
      // such — never silently dropped, so the result always sums to 100%.
      list.add(_S(kBaytAlMal, 'Bayt al-mal (public treasury)', surplus));
    }
  }

  // Apportion the rounding so displayed shares sum to exactly 100.00; the fractions
  // are the authority and stay untouched.
  final percents = _apportionPercents(list.map((x) => x.f).toList());
  return [
    for (var i = 0; i < list.length; i++)
      () {
        final x = list[i];
        final b = shareBasis(x.rel);
        return ShariaShare(
          heirRelation: x.rel,
          heirName: x.name,
          sharePercent: percents[i],
          basisEn: b.en,
          basisAr: b.ar,
        );
      }(),
  ];
}

/// Scriptural basis for each heir's share, by RELATION — mirrors the backend
/// `share-basis.ts` so the live create preview can show the fiqh "why" (the
/// Qur'anic citations 4:11/4:12/4:176, the Sunnah grandmother rule, and the
/// ʿaṣaba residue) before the will is even created. Keyed on the relation, not
/// the computed %, so it stays correct under ʿawl/radd. The share amounts
/// themselves remain the authority of `calculateShariaShares`.
({String en, String ar}) shareBasis(String relation) {
  switch (relation) {
    case 'HUSBAND':
      return (en: 'Qur’an 4:12 — one half (no children), one quarter (with children)', ar: 'النساء ١٢ — النِّصف بلا ولد، والرُّبع مع الولد');
    case 'WIFE':
      return (en: 'Qur’an 4:12 — one quarter (no children) or one eighth (with children), shared among the wives', ar: 'النساء ١٢ — الرُّبع بلا ولد أو الثُّمن مع الولد، مقسومًا بين الزوجات');
    case 'MOTHER':
      return (en: 'Qur’an 4:11 — one third, reduced to one sixth with children or two or more siblings', ar: 'النساء ١١ — الثلث، ويُخفَّض إلى السُّدس مع الولد أو مع اثنين فأكثر من الإخوة');
    case 'FATHER':
      return (en: 'Qur’an 4:11 — one sixth with a son; one sixth plus the residue with only daughters; the whole residue (ʿaṣaba) with no children', ar: 'النساء ١١ — السُّدس مع الابن، والسُّدس مع الباقي تعصيبًا مع البنات، والباقي كله تعصيبًا بلا ولد');
    case 'GRANDFATHER':
      return (en: 'In the father’s place (Qur’an 4:11 basis) — one sixth and/or the residue (ʿaṣaba)', ar: 'مقام الأب (النساء ١١) — السُّدس و/أو الباقي تعصيبًا');
    case 'GRANDMOTHER':
    case 'PATERNAL_GRANDMOTHER':
    case 'MATERNAL_GRANDMOTHER':
      return (en: 'Sunnah — one sixth (when the mother is absent)', ar: 'السنة — السُّدس (عند فقد الأم)');
    case 'SON':
      return (en: 'Residue (ʿaṣaba) — the son takes the remainder, 2:1 male to female (Qur’an 4:11)', ar: 'عصبة — للذكر مثل حظ الأنثيين (النساء ١١)');
    case 'DAUGHTER':
      return (en: 'Qur’an 4:11 — one half (alone), two thirds (shared by two or more), or residue 2:1 alongside a son', ar: 'النساء ١١ — النِّصف للواحدة، والثلثان للاثنتين فأكثر، أو عصبة مع الابن');
    case 'SON_SON':
      return (en: 'Residue (ʿaṣaba) — agnatic grandson, 2:1 male to female (Qur’an 4:11)', ar: 'عصبة — ابن الابن، للذكر مثل حظ الأنثيين (النساء ١١)');
    case 'SON_DAUGHTER':
      return (en: 'Qur’an 4:11 — son’s daughter: as a daughter alone, or one sixth completing two thirds with a daughter', ar: 'النساء ١١ — بنت الابن: كالبنت منفردةً، أو السُّدس تكملةً للثلثين مع البنت');
    case 'FULL_SISTER':
      return (en: 'Qur’an 4:176 (kalāla) — one half / two thirds, or residue alongside a daughter (maʿa al-ghayr)', ar: 'النساء ١٧٦ (الكلالة) — النِّصف أو الثلثان، أو عصبة مع البنت (مع الغير)');
    case 'FULL_BROTHER':
      return (en: 'Residue (ʿaṣaba) — full brother, 2:1 male to female (Qur’an 4:176)', ar: 'عصبة — الأخ الشقيق، للذكر مثل حظ الأنثيين (النساء ١٧٦)');
    case 'CONSANGUINE_SISTER':
      return (en: 'Qur’an 4:176 — consanguine (paternal) sister', ar: 'النساء ١٧٦ — الأخت لأب');
    case 'CONSANGUINE_BROTHER':
      return (en: 'Residue (ʿaṣaba) — consanguine (paternal) brother', ar: 'عصبة — الأخ لأب');
    case 'MATERNAL_SIBLING':
      return (en: 'Qur’an 4:12 — uterine sibling: one sixth alone, one third shared equally', ar: 'النساء ١٢ — الأخ لأم: السُّدس للواحد، والثلث للأكثر بالتساوي');
    case 'FULL_NEPHEW':
    case 'CONSANGUINE_NEPHEW':
    case 'FULL_UNCLE':
    case 'CONSANGUINE_UNCLE':
    case 'FULL_COUSIN':
    case 'CONSANGUINE_COUSIN':
      return (en: 'Residue — the nearest male agnate (ʿaṣaba)', ar: 'عصبة — أقرب عاصب');
    case 'BAYT_AL_MAL':
      return (en: 'Public treasury — no eligible heir for the surplus', ar: 'بيت المال — لا وارث للفائض');
    default:
      return (en: 'Fixed share (farḍ) or residue (ʿaṣaba)', ar: 'فرض أو عصبة');
  }
}
