import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'widgets/will_step_bar.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../assets/application/assets_providers.dart';
import '../../assets/domain/asset_models.dart';
import '../../auth/domain/auth_state.dart';
import '../../commerce/application/entitlement_providers.dart';
import '../application/wills_providers.dart';
import '../domain/fx_rates.dart';
import '../../ai_intake/application/ai_intake_providers.dart';
import '../../ai_intake/domain/ai_intake_models.dart';
import '../domain/heir_registry_seed.dart';
import '../domain/wills_models.dart';
import 'wasiyya_template_formatter.dart';

/// The guided create-will flow — the prototype's SIX steps (data-screen-label
/// "Create will"):
///   1 Family & heirs                  — structured counters + live fara'id preview
///   2 Heir registry                   — contact details per heir (WillHeirContact)
///   3 Witnesses, trustee & guardian   — witnesses/trustee + guardianship of minors
///   4 Your estate & bequest           — estate hero card + the free-third slider
///   5 Wishes & words                  — funeral wishes + "Words for my family"
///   6 Review & confirm                — shares table, disclaimer gate, seal
///
/// A persistent header (title + "Step {a} of 6 — {name}" + Draft-saved chip) and a
/// six-segment progress bar sit above every step. The live fara'id preview shows on
/// steps 1·2·3·6 (hidden on the estate and wishes steps, per the prototype).
///
/// AUTOSAVE (unchanged contract): the DRAFT will row is created on the first
/// meaningful change, then every change PATCHes the whole form snapshot onto it
/// (draftState). Heir contacts, guardianship and witnesses/trustees persist through
/// their own owner-scoped endpoints, not draftState; the flow restores them on load.
class CreateWillScreen extends ConsumerStatefulWidget {
  const CreateWillScreen({super.key, this.willId, this.seed});

  /// What Ameen understood, when the owner arrives from a finished conversation.
  ///
  /// The wizard already keeps exactly these counters as its own state and turns them into
  /// individual heirs in [_buildHeirs], so a seed is simply that state's starting value —
  /// Ameen creates no will and saves nothing. The owner still walks every step and can
  /// correct anything before a draft exists, which is the point: a conversation must never
  /// silently produce a legal document.
  final IntakeSeed? seed;

  /// Which draft to open, when the owner picked one (`/wills/:id/edit`).
  ///
  /// Null on `/wills/new/form`, where the wizard restores whichever flow draft it finds —
  /// fine when starting fresh, wrong the moment an account holds more than one. Without
  /// this the wizard had no notion of WHICH draft, which is why Continue on a draft used
  /// to route to the will detail instead, and why the guided steps were unreachable from
  /// an existing will at all.
  final String? willId;

  @override
  ConsumerState<CreateWillScreen> createState() => _CreateWillScreenState();
}

// Step indices (0-based); the label/progress bar show them 1-based.
//
// The flow is six steps. Only the first five live in this wizard — the sixth,
// Review & seal, is its own page (/wills/:id/review), which is why there is no
// _stReview here. See _next() and DECISIONS §0.
const int _stFamily = 0;
const int _stRegistry = 1;
const int _stPeople = 2;
const int _stEstate = 3;
const int _stWishes = 4;
const int _stLastGuided = _stWishes;


class _CreateWillScreenState extends ConsumerState<CreateWillScreen> {
  // --- Step 1: structured heir counters (the heir LIST is generated from these,
  // so the live fara'id preview recomputes as the user edits). ---
  String _sex = 'male'; // 'male' | 'female'
  int _wives = 0; // male: 0–4
  bool _husband = false; // female
  int _sons = 0;
  int _daughters = 0;
  bool _mother = false;
  bool _father = false;
  bool _showExtended = false;
  bool _grandfather = false; // paternal — steps into an absent father
  // Split deliberately: the two grandmothers are excluded by different people, so one
  // combined answer cannot produce a correct division. See _buildHeirs.
  bool _gmMaternal = false;
  bool _gmPaternal = false;
  int _brothers = 0; // full
  int _sisters = 0; // full
  int _uncles = 0; // paternal uncles (full) — residuary (ʿaṣaba)
  int _cousins = 0; // paternal uncle's sons (full) — residuary (ʿaṣaba)
  String _school = 'JUMHUR';

  int _step = _stFamily;
  bool _busy = false;

  // --- Step 2: heir registry (contact details per heir) ---
  List<HeirContact> _heirContacts = [];
  bool _heirLoaded = false;

  /// Which heir cards are open. Empty = all collapsed, which is the default.
  ///
  /// A will with four wives and a dozen children puts twenty-odd cards on this step, each
  /// carrying a name, a phone, an email and — for a minor — a whole guardian block.
  /// Expanded, that is several screens of identical fields with no way to see the shape of
  /// the family or which entries are still missing something. Collapsed, each row says who
  /// it is and whether it still needs details, which is the question this step actually
  /// asks; opening one is a click.
  final Set<String> _openHeirs = <String>{};
  /// Seed keys ('son#0', 'wife#1', …) the registry has ALREADY auto-loaded. Rides in
  /// draftState so a row the owner deleted is never resurrected on re-entry.
  Set<String> _heirSeeded = {};
  bool _seeding = false;
  final Map<String, TextEditingController> _hcCtrls = {};
  final Map<String, Timer> _hcTimers = {};

  // --- Step 3: guardianship of minor children ---
  String _guardianMode = 'parent'; // 'parent' | 'islamic' | 'named'
  final TextEditingController _gName = TextEditingController();
  final TextEditingController _gPhone = TextEditingController();
  final TextEditingController _gEmail = TextEditingController();
  Timer? _guardianTimer;

  // --- Step 4: the bequest (share of the free third, 0..100; ⅓ cap by construction) ---
  double _third = 0;
  final TextEditingController _bequestName = TextEditingController();
  bool _estateListOpen = false;

  // --- Step 5: funeral wishes (default all four) + "Words for my family" ---
  bool _wishSunnah = true;
  bool _wishSimple = true;
  bool _wishLocal = true;
  bool _wishAzaa = true;
  final TextEditingController _words = TextEditingController();

  // The disclaimer tick moved to the Review page along with the seal button it gates.
  bool _wvDeferred = false;

  // --- autosave (draftState) ---
  String? _willId; // the DRAFT will row, created on the first meaningful change
  DateTime? _savedAt; // last successful autosave — drives the "Draft saved" chip
  Timer? _saveTimer;
  bool _flushing = false;
  bool _dirty = false;
  bool _restoring = true;
  bool _autosaveBlocked = false; // set when the will cap refuses the draft row

  String get _region {
    final a = ref.read(authControllerProvider);
    return a is AuthSignedIn ? a.user.region : 'US';
  }

  @override
  void initState() {
    super.initState();
    _applySeed();
    _restore();
  }

  /// Starts the family step from what Ameen understood.
  ///
  /// Applied BEFORE [_restore], so a real saved draft always wins: someone who already has
  /// a draft in progress must not have it overwritten by a conversation. Nothing is saved
  /// here either — these are just the field values the owner now reviews, and the wizard's
  /// normal autosave only fires once they actually touch something.
  void _applySeed() {
    final s = widget.seed;
    if (s == null) return;
    _sex = s.sex;
    _wives = s.wives;
    _husband = s.husband;
    _sons = s.sons;
    _daughters = s.daughters;
    _mother = s.mother;
    _father = s.father;
    _grandfather = s.grandfather;
    _gmMaternal = s.gmMaternal;
    _gmPaternal = s.gmPaternal;
    _brothers = s.brothers;
    _sisters = s.sisters;
    _uncles = s.uncles;
    _cousins = s.cousins;
    // Only a school the picker actually offers (DECISIONS §20 — two schools ship).
    if (s.madhhab == 'HANAFI' || s.madhhab == 'JUMHUR') _school = s.madhhab!;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _guardianTimer?.cancel();
    for (final t in _hcTimers.values) {
      t.cancel();
    }
    for (final c in _hcCtrls.values) {
      c.dispose();
    }
    _gName.dispose();
    _gPhone.dispose();
    _gEmail.dispose();
    _bequestName.dispose();
    _words.dispose();
    super.dispose();
  }

  // --- restore ---------------------------------------------------------------
  Future<void> _restore() async {
    try {
      final api = ref.read(willsApiProvider);
      // A named draft wins over "whichever one comes back first" — with two drafts on an
      // account, firstOrNull is a coin toss, and editing the wrong will is not a mistake
      // this app gets to make.
      final Will? draft = widget.willId != null
          ? await api.getOne(widget.willId!)
          : (await api.list()).where((w) => w.isFlowDraft).firstOrNull;
      if (!mounted) return;
      // draftState is force-unwrapped below. The list() path filtered on isFlowDraft, which
      // guarantees it; getOne() guarantees nothing — a sealed will, or one created outside
      // the guided flow, has no draftState and would have thrown here. Fall through to a
      // blank wizard instead, which is the same thing /wills/new/form does.
      if (draft == null || draft.draftState == null) {
        setState(() => _restoring = false);
        return;
      }
      final d = draft.draftState!;
      int asInt(Object? v, int min, int max) => v is num ? v.toInt().clamp(min, max) : min;
      bool asBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;
      final wishes = (d['wishes'] as Map?)?.cast<String, dynamic>() ??
          draft.funeralWishes ??
          const <String, dynamic>{};
      final bequest = (d['bequest'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      setState(() {
        _willId = draft.id;
        _savedAt = draft.updatedAt;
        _sex = d['sex'] == 'female' ? 'female' : 'male';
        _wives = asInt(d['wives'], 0, 4);
        _husband = asBool(d['husband']);
        _sons = asInt(d['sons'], 0, 20);
        _daughters = asInt(d['daughters'], 0, 20);
        _mother = asBool(d['mother']);
        _father = asBool(d['father']);
        _grandfather = asBool(d['grandfather']);
        // Older drafts carry a single 'grandmother' flag, which always meant MATERNAL —
        // that is what the one toggle built. Restore it as such so nobody's saved answer
        // silently changes meaning.
        _gmMaternal = asBool(d['gmMaternal'], asBool(d['grandmother']));
        _gmPaternal = asBool(d['gmPaternal']);
        _brothers = asInt(d['brothers'], 0, 20);
        _sisters = asInt(d['sisters'], 0, 20);
        _uncles = asInt(d['uncles'], 0, 20);
        _cousins = asInt(d['cousins'], 0, 20);
        // The disclosure is derived, never restored. It used to be persisted into the
        // draft ('extended' in _snapshot), so a single click reopened the panel on every
        // later visit to that will — most owners have no extended heirs and met the whole
        // grandparents/siblings/uncles/cousins block expanded for good. The prototype does
        // not persist it either.
        //
        // Derived rather than forced closed, because collapsing a section that HOLDS values
        // hides heirs the owner entered — and they still count toward the fara'id shares.
        // So: open exactly when there is something in it to see.
        _showExtended = _grandfather || _gmMaternal || _gmPaternal || _brothers > 0 || _sisters > 0 || _uncles > 0 || _cousins > 0;
        if (d['madhhab'] is String) _school = d['madhhab'] as String;
        _heirSeeded = {for (final k in (d['heirSeed'] as List?) ?? const []) '$k'};
        _third = (bequest['third'] is num) ? (bequest['third'] as num).toDouble().clamp(0, 100) : 0;
        _bequestName.text = (bequest['name'] as String?) ?? '';
        _wishSunnah = asBool(wishes['sunnah'], true);
        _wishSimple = asBool(wishes['simple'], true);
        _wishLocal = asBool(wishes['local'], true);
        _wishAzaa = asBool(wishes['azaa'], true);
        _words.text = (d['words'] as String?) ?? draft.personalMessage ?? '';
        // Guardianship rides on the will row (list() includes the scalar fields).
        _guardianMode = draft.guardianMode ?? 'parent';
        _gName.text = draft.guardianName ?? '';
        _gPhone.text = draft.guardianPhone ?? '';
        _gEmail.text = draft.guardianEmail ?? '';
        _step = (draft.draftStep - 1).clamp(0, _stLastGuided);
        _restoring = false;
      });

      // A draft saved on step 6 opens on step 5 — the last step this wizard owns — and
      // NOT on the Review page.
      //
      // It used to redirect to Review, on the reasoning that a draft should reopen where
      // it was left. That trapped people. Handing off to Review writes step 6, so every
      // returning draft matched, and the redirect used go(), which replaces the stack —
      // leaving Review with nothing to pop, so its back fell through to the will detail,
      // whose only forward action is Review again. Steps 1 to 5 became unreachable and the
      // will could not be edited at all.
      //
      // Resuming exactly where you left off is worth less than being able to change your
      // will, and Review is one Continue away from here.

      _ensureHeirLoaded();
      // Resuming lands on the saved step without passing through _next(), so seed here
      // too. Only when the draft comes back ON the wishes step: further along means the
      // owner already walked past it and chose to leave it blank.
      if (_step == _stWishes) _seedWasiyya();
    } catch (_) {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// The full form snapshot the server persists (and lifts heirs/wishes/words/
  /// bequest out of). `step` is 1-based (1..6).
  Map<String, dynamic> _snapshot(AppLocalizations l, {int? stepOverride}) => {
        'v': 1,
        'step': stepOverride ?? (_step + 1),
        'sex': _sex,
        'wives': _wives,
        'husband': _husband,
        'sons': _sons,
        'daughters': _daughters,
        'mother': _mother,
        'father': _father,
        // 'extended' is deliberately NOT persisted — see _restore. It is a disclosure
        // state, not will content, and saving it made one click permanent.
        'grandfather': _grandfather,
        // Still written so a draft saved here stays readable by an older build; it carries
        // the maternal answer, which is what that single toggle meant.
        'grandmother': _gmMaternal,
        'gmMaternal': _gmMaternal,
        'gmPaternal': _gmPaternal,
        'brothers': _brothers,
        'sisters': _sisters,
        'uncles': _uncles,
        'cousins': _cousins,
        'madhhab': _school,
        'heirs': [
          for (final h in _buildHeirs(l)) {'relation': h.relation.api, 'name': h.name}
        ],
        'heirSeed': _heirSeeded.toList(),
        'bequest': {'name': _bequestName.text.trim(), 'third': _third},
        'wishes': {'sunnah': _wishSunnah, 'simple': _wishSimple, 'local': _wishLocal, 'azaa': _wishAzaa},
        'words': _words.text,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      };

  void _set(VoidCallback fn) {
    setState(fn);
    _touch();
  }

  void _touch() {
    if (_autosaveBlocked || _restoring) return;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  Future<void> _flush({int? stepOverride}) async {
    if (!mounted || _autosaveBlocked) return;
    if (_flushing) {
      _touch();
      return;
    }
    _flushing = true;
    _dirty = false;
    final l = context.l10n;
    final firstSave = _willId == null;
    try {
      final api = ref.read(willsApiProvider);
      _willId ??= (await api.create(tier: 'STANDARD', heirs: _buildHeirs(l), madhhab: _engineMadhhab)).id;
      await api.updateDraft(_willId!, _snapshot(l, stepOverride: stepOverride));
      ref.invalidate(willsListProvider);
      ref.invalidate(willProvider(_willId!));
      if (mounted) setState(() => _savedAt = DateTime.now());
      if (firstSave) {
        _ensureHeirLoaded();
        _reportSeeded();
      }
    } on ApiException catch (e) {
      if (_willId == null) {
        _autosaveBlocked = true;
        if (mounted) WasiatiSnack.danger(context, e.message);
      }
    } finally {
      _flushing = false;
      if (_dirty && mounted) _touch();
    }
  }

  String get _engineMadhhab => _school;

  /// Tells Ameen which will its conversation became, once a draft actually exists.
  ///
  /// Deliberately fire-and-forget: this is bookkeeping that stops one conversation
  /// seeding two wills, and the owner's draft has already saved successfully. Failing
  /// their save over it — or showing an error about an intake session they have stopped
  /// thinking about — would be the wrong trade.
  void _reportSeeded() {
    final sessionId = widget.seed?.sessionId;
    final willId = _willId;
    if (sessionId == null || willId == null) return;
    unawaited(
      ref.read(aiIntakeApiProvider).markSeeded(sessionId, willId).catchError((_) {}),
    );
  }

  /// Generates the individual heir entries the engine/API expect from the counters.
  List<Heir> _buildHeirs(AppLocalizations l) {
    Heir mk(HeirRelation r, {int? index, int? total}) {
      final base = heirRelLabel(l, r.api);
      return Heir(r, (total != null && total > 1) ? '$base ${index! + 1}' : base);
    }

    final h = <Heir>[];
    if (_sex == 'male') {
      for (var i = 0; i < _wives; i++) {
        h.add(mk(HeirRelation.wife, index: i, total: _wives));
      }
    } else if (_husband) {
      h.add(mk(HeirRelation.husband));
    }
    for (var i = 0; i < _sons; i++) {
      h.add(mk(HeirRelation.son, index: i, total: _sons));
    }
    for (var i = 0; i < _daughters; i++) {
      h.add(mk(HeirRelation.daughter, index: i, total: _daughters));
    }
    if (_mother) h.add(mk(HeirRelation.mother));
    if (_father) h.add(mk(HeirRelation.father));
    if (_grandfather && !_father) h.add(mk(HeirRelation.grandfather));
    // WHICH grandmother has to be asked, because they are excluded by different people.
    // The mother excludes BOTH. The father excludes only his OWN mother — the paternal one —
    // while the maternal grandmother inherits her sixth alongside him.
    //
    // There used to be one toggle, "Grandmother living", and it always built a MATERNAL
    // grandmother. So an owner whose surviving grandmother was paternal, with their father
    // also alive, was handed a sixth she is not owed and the father was short by the same
    // amount — a wrong division, printed and sealed, from a question that never distinguished
    // the two people.
    if (_gmMaternal && !_mother) h.add(mk(HeirRelation.maternalGrandmother));
    if (_gmPaternal && !_mother && !_father) h.add(mk(HeirRelation.paternalGrandmother));
    for (var i = 0; i < _brothers; i++) {
      h.add(mk(HeirRelation.fullBrother, index: i, total: _brothers));
    }
    for (var i = 0; i < _sisters; i++) {
      h.add(mk(HeirRelation.fullSister, index: i, total: _sisters));
    }
    for (var i = 0; i < _uncles; i++) {
      h.add(mk(HeirRelation.fullUncle, index: i, total: _uncles));
    }
    for (var i = 0; i < _cousins; i++) {
      h.add(mk(HeirRelation.fullCousin, index: i, total: _cousins));
    }
    return h;
  }

  /// The bequest as a % OF THE ESTATE (0..33.33) — the free-third slider is a % of
  /// the free third, so estate% = third ÷ 3.
  double get _bequestEstatePct => _third / 3;

  bool get _hasMinors => _heirContacts.any((h) => h.isMinor);

  /// The live fara'id result for the current step-1 counters — the same call the
  /// preview renders with. The registry seeds off THIS, so what the preview shows a
  /// share to is exactly what the registry pre-loads.
  List<ShariaShare> _liveShares(AppLocalizations l) =>
      calculateShariaShares(_buildHeirs(l), madhhab: _engineMadhhab);

  /// Pre-populates the registry from the live fara'id preview (owner punch-list #1).
  /// Additive by seed key — a key is seeded at most once ever, so a row the owner
  /// removed stays removed and contact details already typed are never clobbered.
  /// The one subtraction: a row we seeded whose heir no longer qualifies (the owner
  /// went back and added a son, blocking the brothers) is dropped only while it is
  /// still empty, so it cannot strand the "every heir needs contact details" seal gate
  /// on someone who inherits nothing. A row with anything typed into it always stays.
  Future<void> _syncSeededHeirs() async {
    if (_willId == null || !_heirLoaded || _seeding || !mounted) return;
    final want = qualifyingHeirSeeds(_liveShares(context.l10n));
    final wantKeys = {for (final w in want) w.key};
    final rowKey = heirRowKeys(_heirContacts);
    final haveKeys = rowKey.values.toSet();

    final toAdd = want.where((w) => !haveKeys.contains(w.key) && !_heirSeeded.contains(w.key)).toList();
    final toRemove = _heirContacts.where((c) {
      final k = rowKey[c.id];
      return k != null &&
          _heirSeeded.contains(k) &&
          !wantKeys.contains(k) &&
          c.name.trim().isEmpty &&
          c.phone.trim().isEmpty &&
          c.email.trim().isEmpty;
    }).toList();
    if (toAdd.isEmpty && toRemove.isEmpty) return;

    _seeding = true; // no await above this line — the guard above is the whole lock
    try {
      for (final row in toRemove) {
        final k = rowKey[row.id]!;
        await _removeHeir(row.id);
        if (!mounted) return;
        // Forget the key as well: WE dropped this row, so if the heir qualifies again
        // (the owner removes the son that was blocking the brothers) it must re-seed.
        // A row the OWNER deleted keeps its key, which is what stops the resurrection.
        setState(() => _heirSeeded = {..._heirSeeded}..remove(k));
      }
      final api = ref.read(willsApiProvider);
      for (final w in toAdd) {
        final row = await api.addHeirContact(_willId!, relation: w.relation);
        if (!mounted) return;
        setState(() {
          _heirContacts = [..._heirContacts, row];
          _heirSeeded = {..._heirSeeded, w.key};
        });
      }
      _touch(); // persist _heirSeeded into draftState
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      _seeding = false;
    }
  }

  // --- heir registry wiring --------------------------------------------------
  Future<void> _ensureHeirLoaded() async {
    if (_willId == null) return;
    if (!_heirLoaded) {
      try {
        final list = await ref.read(willsApiProvider).heirContacts(_willId!);
        if (!mounted) return;
        setState(() {
          _heirContacts = list;
          _heirLoaded = true;
        });
      } catch (_) {
        // Don't wedge the step on a transient error — but don't seed on top of an
        // unknown roster either, or re-entry would duplicate every row.
        if (mounted) setState(() => _heirLoaded = true);
        return;
      }
    }
    await _syncSeededHeirs();
  }

  TextEditingController _hcCtrl(String key, String initial) =>
      _hcCtrls.putIfAbsent(key, () => TextEditingController(text: initial));

  Future<void> _addHeir() async {
    if (_willId == null) return;
    try {
      final row = await ref.read(willsApiProvider).addHeirContact(_willId!, relation: 'son');
      if (!mounted) return;
      setState(() {
        _heirContacts = [..._heirContacts, row];
        // A row you just asked for opens: you added it to fill it in, and an empty
        // collapsed card would look like the button had done nothing.
        _openHeirs.add(row.id);
      });
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    }
  }

  Future<void> _removeHeir(String id) async {
    setState(() => _heirContacts = _heirContacts.where((h) => h.id != id).toList());
    for (final f in const ['name', 'phone', 'email']) {
      _hcCtrls.remove('$id|$f')?.dispose();
    }
    _hcTimers.remove(id)?.cancel();
    try {
      await ref.read(willsApiProvider).deleteHeirContact(_willId!, id);
    } catch (_) {}
  }

  /// Immediate patch (relation / minor toggle) — updates local + server now.
  void _patchHeir(String id, {String? relation, bool? isMinor}) {
    final i = _heirContacts.indexWhere((h) => h.id == id);
    if (i < 0) return;
    setState(() {
      _heirContacts = [..._heirContacts]..[i] = _heirContacts[i].copyWith(relation: relation, isMinor: isMinor);
    });
    () async {
      try {
        await ref.read(willsApiProvider).updateHeirContact(_willId!, id, relation: relation, isMinor: isMinor);
      } catch (_) {}
    }();
  }

  /// Debounced patch for the free-text fields (name / phone / email).
  void _debounceHeir(String id, {String? name, String? phone, String? email}) {
    final i = _heirContacts.indexWhere((h) => h.id == id);
    if (i < 0) return;
    _heirContacts[i] = _heirContacts[i].copyWith(name: name, phone: phone, email: email);
    setState(() {}); // reflect completeness chip / counts
    _hcTimers[id]?.cancel();
    _hcTimers[id] = Timer(const Duration(milliseconds: 600), () async {
      try {
        await ref.read(willsApiProvider).updateHeirContact(_willId!, id, name: name, phone: phone, email: email);
      } catch (_) {}
    });
  }

  // --- guardian wiring -------------------------------------------------------
  void _saveGuardian({bool immediate = false}) {
    if (_willId == null) return;
    _guardianTimer?.cancel();
    Future<void> run() async {
      try {
        await ref.read(willsApiProvider).updateGuardian(
              _willId!,
              mode: _guardianMode,
              name: _gName.text.trim(),
              phone: _gPhone.text.trim(),
              email: _gEmail.text.trim(),
            );
        if (mounted) ref.invalidate(willProvider(_willId!));
      } catch (_) {}
    }

    if (immediate) {
      run();
    } else {
      _guardianTimer = Timer(const Duration(milliseconds: 500), run);
    }
  }

  // --- navigation ------------------------------------------------------------
  Future<void> _next() async {
    // Leaving the family step (or otherwise before the will exists) creates the
    // DRAFT row so the sub-resource steps (registry / people) have a will id.
    if (_willId == null) {
      setState(() => _busy = true);
      _saveTimer?.cancel();
      await _flush();
      if (mounted) setState(() => _busy = false);
      if (_willId == null) return; // cap refused the draft — stay put
    }
    if (!mounted) return;
    // Step 4 validation: a bequest with a share must name who receives it.
    if (_step == _stEstate && _third >= 0.5 && _bequestName.text.trim().isEmpty) {
      WasiatiSnack.danger(context, context.l10n.cwBequestNameNeeded);
      return;
    }

    // Past the last guided step the flow LEAVES the wizard. DECISIONS §0: "guided
    // steps → a required Review page → seal". Review used to be a sixth step inside
    // this screen that also sealed, which put the same shares table on screen twice
    // (once as the review card, once as the live-fara'id panel beside it) and meant
    // the dedicated Review & Seal page was never reached from the create flow at all.
    if (_step == _stLastGuided) {
      _saveTimer?.cancel();
      setState(() => _busy = true);
      // Flush before navigating: the review page reads the will from the server, so
      // anything still sitting in the 0.6s autosave debounce would not be in it.
      await _flush(stepOverride: _stLastGuided + 2);
      if (!mounted) return;
      setState(() => _busy = false);
      final id = _willId;
      if (id == null) return;

      // PUSH, not go(). go() replaces the stack, which left the review page with nothing
      // to go back TO — its back control had to guess a destination, and it guessed the
      // will dashboard, throwing the owner out of the flow at the last step. Pushing keeps
      // this wizard alive underneath, so back returns to step 5 with the form untouched.
      await context.push('/wills/$id/review');

      // Popped back. The draft on the server still says step 6 (flushed above), which is
      // no longer where the owner is — resuming later would drop them on review again.
      if (mounted) _touch();
      return;
    }

    final nextStep = (_step + 1).clamp(0, _stLastGuided);
    setState(() => _step = nextStep);
    if (nextStep == _stRegistry) _ensureHeirLoaded();
    if (nextStep == _stPeople) _ensureHeirLoaded();
    if (nextStep == _stWishes) _seedWasiyya();
    _touch();
  }

  /// Puts the classic wasiyya in the field as REAL, editable text on arrival.
  ///
  /// It used to be seeded only by pressing Enter on an empty field (the prototype's
  /// msgKey handler), with the words shown meanwhile as a faded placeholder. Nobody
  /// presses Enter in an empty textarea to see what happens, so in practice the template
  /// was gone: people met a blank box on the hardest question in the flow — what to say
  /// to your family — and a greyed-out hint they could not edit.
  ///
  /// Only ever seeds an EMPTY field, so a restored draft and anything already typed are
  /// untouched. Deleting it still clears the field (WasiyyaTemplateFormatter), and once a
  /// word is changed it is the owner's text and nothing rewrites it.
  void _seedWasiyya() {
    if (_words.text.trim().isNotEmpty) return;
    final template = context.l10n.cwWordsDefault;
    _words.value = TextEditingValue(
      text: template,
      selection: TextSelection.collapsed(offset: template.length),
    );
  }

  void _back() {
    if (_step == _stFamily) {
      context.go('/wills');
      return;
    }
    setState(() => _step = _step - 1);
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final heirs = _buildHeirs(context.l10n);
    final shares = calculateShariaShares(heirs, madhhab: _engineMadhhab);
    // Prototype rule (previewVisible): shown while the family is being edited, hidden on
    // the estate and wishes steps. It is an editing aid — the Review page states the same
    // shares definitively, so repeating it there was the duplication this flow change removes.
    final showPreview = _step == _stFamily || _step == _stRegistry || _step == _stPeople;

    return Scaffold(
      // Back / Continue ride in bottomNavigationBar, NOT as the last child of the scroll.
      //
      // Scaffold's own slot rather than a Column child on purpose: Scaffold lays fixed
      // SnackBars out ABOVE the bottom bar. In a Column the bar is just body content, so
      // the first snackbar to appear covers the wizard's only navigation — measured, not
      // guessed: a tap on Continue hit the snackbar instead.
      bottomNavigationBar: LayoutBuilder(builder: (context, box) {
        final pad = box.maxWidth >= 860 ? 34.0 : 18.0;
        return Container(
          key: const ValueKey('createWillNav'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: context.tokens.hairline)),
          ),
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 12) +
              EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          // heightFactor: 1 — the bottomNavigationBar slot passes LOOSE constraints, and a
          // bare Center would grow to the full screen height. Scaffold then refuses to place
          // a floating SnackBar ("presented off screen") and layout asserts.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: _pinnedNav(context, heirs),
            ),
          ),
        );
      }),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 860;
          final pad = wide ? 34.0 : 18.0;
          return Column(children: [
            Expanded(
              child: Scrollbar(
                // The absent scrollbar is half the defect: with the controls off-screen and
                // no thumb, nothing said the page continued.
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, pad, pad, 8),
                  child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _header(context),
                  const SizedBox(height: 18),
                  WillStepBar(step: _step + 1),
                  const SizedBox(height: 20),
                  if (wide && showPreview)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 5, child: _stepBody(context, heirs, shares)),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: _Preview(heirs: heirs, shares: shares, school: _school),
                      ),
                    ])
                  else if (!wide && showPreview)
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _PreviewStrip(shares: shares),
                      const SizedBox(height: 14),
                      _stepBody(context, heirs, shares),
                    ])
                  else
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _stepBody(context, heirs, shares),
                      ),
                    ),
                ]),
              ),
            ),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  // --- persistent header + progress -----------------------------------------
  Widget _header(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cwPageTitle, style: text.headlineLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_stepLabel(context), style: text.bodyMedium?.copyWith(color: context.tokens.muted)),
            if (_savedAt != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check, size: 13, color: context.tokens.successInk),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(l.cwSavedAuto,
                      style: text.bodySmall?.copyWith(color: context.tokens.successInk, fontWeight: FontWeight.w600)),
                ),
              ]),
          ]),
        ]),
      ),
      const SizedBox(width: 12),
      _AiPill(onTap: () => context.go('/intake')),
    ]);
  }


  String _stepLabel(BuildContext context) {
    final l = context.l10n;
    final n = _step + 1;
    final name = switch (n) {
      2 => l.cwStepName2,
      3 => l.cwStepName3,
      4 => l.cwStepName4,
      5 => l.cwStepName5,
      // No arm for 6 — cwStepName6 ("Review & confirm") belongs to the Review page,
      // which the wizard hands off to rather than rendering itself.
      _ => l.cwStepName1,
    };
    return context.digits(l.cwStepOf(MaterialLocalizations.of(context).formatDecimal(n), name));
  }

  Widget _navRow(BuildContext context, {required VoidCallback? onNext, String? nextLabel}) {
    final l = context.l10n;
    return Row(children: [
      OutlinedButton(onPressed: _back, child: Text(l.cwNavBack)),
      const Spacer(),
      FilledButton(
        onPressed: onNext,
        child: _busy
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(nextLabel ?? l.cwNavContinue),
      ),
    ]);
  }

  /// Back / Continue, pinned BELOW the scroll instead of riding at the end of it.
  ///
  /// The row used to be the last child of a page-length SingleChildScrollView, which put
  /// its bottom edge a fixed ~984px down the page on every step (measured; the step bodies
  /// are all about the same height and the page is width-capped at 1120, so it does not
  /// move). A browser maximised on a 1080p monitor has roughly 950-985px of viewport once
  /// its chrome is taken — so Back and Continue sat just below the fold, on every step,
  /// with no persistent scrollbar to say anything was under them. It reads as the button
  /// disappearing, and it is why the owner saw it on "most" pages rather than all: the
  /// margin is a couple of dozen pixels either way.
  ///
  /// Each step's enabled-state is recomputed here from the same providers the step bodies
  /// watch, so the pinned row cannot drift out of step with the form above it.
  Widget _pinnedNav(BuildContext context, List<Heir> heirs) {
    final l = context.l10n;
    final witList =
        _willId == null ? const <Witness>[] : (ref.watch(witnessesProvider(_willId!)).asData?.value ?? const []);
    final will = _willId == null ? null : ref.watch(willProvider(_willId!)).asData?.value;
    final needWit = will?.requiredWitnesses ?? 2;
    final witEnough = witList.length >= needWit;

    switch (_step) {
      case _stRegistry:
        return _navRow(context, onNext: _busy ? null : _next);
      case _stPeople:
        return _navRow(context, onNext: (_busy || !witEnough) ? null : _next);
      case _stEstate:
        final nameMissing = _third >= 0.5 && _bequestName.text.trim().isEmpty;
        return _navRow(context, onNext: (heirs.isEmpty || nameMissing || _busy) ? null : _next);
      case _stWishes:
        // Last guided step: forward leaves the wizard for the Review page, so it says so
        // rather than "Continue". Nothing is sealed from this screen any more.
        return _navRow(context, onNext: _busy ? null : _next, nextLabel: l.cwToReview);
      default:
        return _navRow(context, onNext: (heirs.isEmpty || _busy) ? null : _next);
    }
  }

  Widget _stepBody(BuildContext context, List<Heir> heirs, List<ShariaShare> shares) => switch (_step) {
        _stRegistry => _registryForm(context),
        _stPeople => _peopleForm(context),
        _stEstate => _estateForm(context, heirs),
        _stWishes => _wishesForm(context),
        _ => _familyForm(context, heirs),
      };

  // --- Step 1: Family & heirs ------------------------------------------------
  Widget _familyForm(BuildContext context, List<Heir> heirs) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WasiatiCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cwFamilyHeirs, style: text.titleMedium),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _school,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.cwMadhhabQuestion),
            items: [
              DropdownMenuItem(value: 'JUMHUR', child: Text(l.cwMadhhabJumhur)),
              DropdownMenuItem(value: 'HANAFI', child: Text(l.cwMadhhabHanafi)),
            ],
            onChanged: (v) => _set(() => _school = v ?? 'JUMHUR'),
          ),
          const SizedBox(height: 6),
          Text(l.cwMadhhabNote, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4)),
          const SizedBox(height: 20),
          _CounterLabel(l.cwSexLabel),
          _SexToggle(sex: _sex, onChanged: (s) => _set(() => _sex = s)),
          const SizedBox(height: 16),
          if (_sex == 'male')
            _StepperRow(
                label: l.cwWivesLabel,
                helper: l.cwSpousesHelp,
                value: _wives,
                min: 0,
                max: 4,
                onChanged: (v) => _set(() => _wives = v))
          else
            _ToggleRow(label: l.cwHusbandLabel, value: _husband, onChanged: (v) => _set(() => _husband = v)),
          const SizedBox(height: 16),
          _CounterLabel(l.cwChildrenLabel),
          _pair(
            _StepperRow(label: heirRelLabel(l, 'SON'), value: _sons, min: 0, max: 20, onChanged: (v) => _set(() => _sons = v)),
            _StepperRow(
                label: heirRelLabel(l, 'DAUGHTER'),
                value: _daughters,
                min: 0,
                max: 20,
                onChanged: (v) => _set(() => _daughters = v)),
          ),
          const SizedBox(height: 16),
          _CounterLabel(l.cwParentsLabel),
          _pair(
            _ToggleRow(label: l.cwMotherLbl, value: _mother, onChanged: (v) => _set(() => _mother = v)),
            _ToggleRow(label: l.cwFatherLbl, value: _father, onChanged: (v) => _set(() => _father = v)),
          ),
          const SizedBox(height: 14),
          _ExtendedToggle(open: _showExtended, onTap: () => _set(() => _showExtended = !_showExtended)),
          if (_showExtended) ...[
            const SizedBox(height: 12),
            _pair(
              _ToggleRow(label: l.cwGmotherMaternalLbl, value: _gmMaternal, onChanged: (v) => _set(() => _gmMaternal = v)),
              _ToggleRow(label: l.cwGmotherPaternalLbl, value: _gmPaternal, onChanged: (v) => _set(() => _gmPaternal = v)),
            ),
            const SizedBox(height: 12),
            _pair(
              _ToggleRow(label: l.cwGfatherLbl, value: _grandfather, onChanged: (v) => _set(() => _grandfather = v)),
              const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            // Olive sub-panel — the extended family counted only when they qualify.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                // The prototype's olive sub-panel (#EBEFE7); the design system has
                // no olive token, so use the literal in light and a green tone in dark.
                color: dark ? WasiatiColors.greenDeep : const Color(0xFFEBEFE7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.tokens.hairline),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.cwExtendedHead,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.faint)),
                const SizedBox(height: 10),
                _pair(
                  _StepperRow(label: l.cwBrothersLbl, value: _brothers, min: 0, max: 20, onChanged: (v) => _set(() => _brothers = v)),
                  _StepperRow(label: l.cwSistersLbl, value: _sisters, min: 0, max: 20, onChanged: (v) => _set(() => _sisters = v)),
                ),
                const SizedBox(height: 8),
                _pair(
                  _StepperRow(label: l.cwUnclesLbl, value: _uncles, min: 0, max: 20, onChanged: (v) => _set(() => _uncles = v)),
                  _StepperRow(label: l.cwCousinsLbl, value: _cousins, min: 0, max: 20, onChanged: (v) => _set(() => _cousins = v)),
                ),
                const SizedBox(height: 10),
                Text(l.cwDhawuNote, style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5, fontSize: 11.5)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Text(l.cwFamilyFootnote, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
        ]),
      ),
    ]);
  }

  // --- Step 2: Heir registry -------------------------------------------------
  Widget _registryForm(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final complete = _heirContacts.isNotEmpty && _heirContacts.every((h) => h.isComplete);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WasiatiCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(l.cwHeirRegTitle, style: text.titleMedium)),
            // Only worth offering once there is more than one card to act on.
            if (_heirLoaded && _heirContacts.length > 1)
              TextButton.icon(
                onPressed: () => setState(() {
                  final anyOpen = _heirContacts.any((h) => _openHeirs.contains(h.id));
                  _openHeirs.clear();
                  if (!anyOpen) _openHeirs.addAll(_heirContacts.map((h) => h.id));
                }),
                icon: Icon(
                  _heirContacts.any((h) => _openHeirs.contains(h.id))
                      ? Icons.unfold_less
                      : Icons.unfold_more,
                  size: 17,
                ),
                label: Text(
                  _heirContacts.any((h) => _openHeirs.contains(h.id)) ? l.cwCollapseAll : l.cwExpandAll,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: context.tokens.muted,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Text(l.cwHeirRegSub, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
          if (_heirLoaded && _heirContacts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _noteBox(context, l.cwHeirRegSeeded, gold: false),
          ],
          const SizedBox(height: 14),
          if (!_heirLoaded)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else ...[
            for (final row in _heirContacts) ...[
              _heirRow(context, row),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: _willId == null ? null : _addHeir,
              icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
              label: Text(l.cwAddHeirBtn),
            ),
            const SizedBox(height: 10),
            if (_heirContacts.isNotEmpty && !complete)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, size: 15, color: context.tokens.warningInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l.cwHeirRegMissing,
                      style: text.bodySmall?.copyWith(color: context.tokens.warningInk, height: 1.5)),
                ),
              ])
            else if (complete)
              Row(children: [
                Icon(Icons.check_circle, size: 15, color: context.tokens.successInk),
                const SizedBox(width: 6),
                Text(l.cwHeirRegDone,
                    style: text.bodySmall?.copyWith(color: context.tokens.successInk, fontWeight: FontWeight.w600)),
              ]),
          ],
        ]),
      ),
    ]);
  }

  Widget _heirRow(BuildContext context, HeirContact row) {
    final l = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final open = _openHeirs.contains(row.id);
    return Container(
      padding: EdgeInsets.fromLTRB(14, open ? 14 : 4, 14, open ? 14 : 4),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!open) _heirSummary(context, row),
        if (open) Row(children: [
          // Closes the card again. Paired with the chevron on the collapsed summary, so the
          // control is in the same place whichever state the row is in.
          IconButton(
            icon: const Icon(Icons.expand_less, size: 20),
            tooltip: l.cwCollapseAll,
            visualDensity: VisualDensity.compact,
            color: context.tokens.muted,
            onPressed: () => setState(() => _openHeirs.remove(row.id)),
          ),
          DropdownButton<String>(
            value: row.relation,
            underline: const SizedBox.shrink(),
            items: [
              for (final k in const ['wife', 'husband', 'son', 'daughter', 'mother', 'father', 'brother', 'sister', 'other'])
                DropdownMenuItem(value: k, child: Text(_regRelLabel(l, k))),
            ],
            onChanged: (v) => _patchHeir(row.id, relation: v),
          ),
          const Spacer(),
          Text(l.cwMinorLbl, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted)),
          Switch(
            value: row.isMinor,
            onChanged: (v) => _patchHeir(row.id, isMinor: v),
            activeColor: WasiatiColors.bottleGreen),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: context.tokens.dangerInk),
            tooltip: l.cwCancel,
            onPressed: () => _removeHeir(row.id),
          ),
        ]),
        if (open) ...[
          const SizedBox(height: 8),
          _RegField(label: l.cwFullNameLbl, controller: _hcCtrl('${row.id}|name', row.name), hint: l.cwFullNamePh,
              onChanged: (v) => _debounceHeir(row.id, name: v)),
          const SizedBox(height: 8),
          _pair(
            _RegField(label: l.cwPhoneLbl, controller: _hcCtrl('${row.id}|phone', row.phone), hint: l.cwPhonePh,
                ltr: true, onChanged: (v) => _debounceHeir(row.id, phone: v)),
            _RegField(label: l.cwEmailLbl, controller: _hcCtrl('${row.id}|email', row.email), hint: l.cwEmailPh,
                ltr: true, onChanged: (v) => _debounceHeir(row.id, email: v)),
          ),
          if (row.isMinor) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: WasiatiColors.brassGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WasiatiColors.goldBorderSoft),
              ),
              child: Text(l.cwGuardianNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.goldInk, height: 1.5)),
            ),
          ],
        ],
      ]),
    );
  }

  /// The collapsed heir card: who it is, and whether it still needs details.
  ///
  /// Those two facts are the whole reason collapsing is safe. Sealing refuses while any
  /// heir is missing a name, phone or email, so a card that hid its state would turn a
  /// twenty-heir will into a hunt for the one that is incomplete. The chip says it outright
  /// and the incomplete ones are the only coloured thing on the step.
  Widget _heirSummary(BuildContext context, HeirContact row) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final named = row.name.trim().isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _openHeirs.add(row.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(Icons.chevron_right, size: 18, color: context.tokens.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              named ? row.name.trim() : _regRelLabel(l, row.relation),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          // The relation stays visible next to a name, because "Yusuf" alone does not say
          // whether this is the son or the brother — and the share depends on which.
          if (named) ...[
            const SizedBox(width: 8),
            Text(_regRelLabel(l, row.relation),
                style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          ],
          if (row.isMinor) ...[
            const SizedBox(width: 8),
            Text(l.cwMinorLbl, style: t.bodySmall?.copyWith(color: context.tokens.goldInk)),
          ],
          const SizedBox(width: 10),
          if (row.isComplete)
            Icon(Icons.check_circle_outline, size: 17, color: context.tokens.successInk)
          else
            Text(l.cwHeirNeedsDetails,
                style: t.bodySmall?.copyWith(color: context.tokens.warningInk, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  String _regRelLabel(AppLocalizations l, String key) => switch (key) {
        'wife' => l.relWife,
        'husband' => l.relHusband,
        'son' => l.relSon,
        'daughter' => l.relDaughter,
        'mother' => l.relMother,
        'father' => l.relFather,
        'brother' => l.relBrother,
        'sister' => l.relSister,
        _ => l.cwRelOther,
      };

  // --- Step 3: Witnesses, trustee & guardian ---------------------------------
  Widget _peopleForm(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final witnesses = _willId == null ? const AsyncValue<List<Witness>>.data([]) : ref.watch(witnessesProvider(_willId!));
    final trustees = _willId == null ? const AsyncValue<List<Trustee>>.data([]) : ref.watch(trusteesProvider(_willId!));
    final witList = witnesses.asData?.value ?? const <Witness>[];
    final trList = trustees.asData?.value ?? const <Trustee>[];
    // Witness minimum (owner punch-list #2). requiredWitnesses is the will's own
    // threshold (schema default 2) and the same number the server enforces on sign/seal.
    final needWit = _willId == null ? 2 : (ref.watch(willProvider(_willId!)).asData?.value.requiredWitnesses ?? 2);
    final witEnough = witList.length >= needWit;
    final witOk = witEnough && trList.isNotEmpty;
    final fmt = MaterialLocalizations.of(context).formatDecimal;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WasiatiCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cwWitTrustTitle, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(l.cwWitTrustSub, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
          const SizedBox(height: 14),
          for (final w in witList) ...[
            _personRow(context,
                role: l.cwRoleWitness,
                name: w.fullName,
                phone: w.phone,
                confirmed: w.status == 'SIGNED',
                unreached: ref.watch(rosterUnreachedProvider).contains(w.id)),
            const SizedBox(height: 8),
          ],
          Row(children: [
            OutlinedButton.icon(
              onPressed: _willId == null ? null : () => _addPerson(isWitness: true),
              icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
              label: Text(l.cwAddWitness),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(witEnough ? Icons.check_circle : Icons.info_outline,
                    size: 14, color: witEnough ? context.tokens.successInk : context.tokens.warningInk),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    context.digits(l.cwWitnessCountReq(fmt(witList.length), fmt(needWit))),
                    style: text.bodySmall?.copyWith(
                        color: witEnough ? context.tokens.successInk : context.tokens.warningInk,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ]),
          if (!witEnough) ...[
            const SizedBox(height: 8),
            Text(context.digits(l.cwWitnessMinNote(fmt(needWit))),
                style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
          ],
          const SizedBox(height: 14),
          for (final t in trList) ...[
            _personRow(context,
                role: l.cwRoleTrustee,
                name: t.fullName,
                phone: t.phone,
                confirmed: t.status == 'CONFIRMED',
                unreached: ref.watch(rosterUnreachedProvider).contains(t.id)),
            const SizedBox(height: 8),
          ],
          if (trList.isEmpty)
            OutlinedButton.icon(
              onPressed: _willId == null ? null : () => _addPerson(isWitness: false),
              icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
              label: Text(l.cwAddTrustee),
            ),
          if (!witOk) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // muted, not warningInk: this is informational ("sealing unlocks once…"),
              // not a warning, and it sat right under the muted witness-min note in a
              // different colour — the inconsistency the owner flagged. Neutral note style.
              Icon(Icons.info_outline, size: 15, color: context.tokens.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(l.cwWitGateNote, style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5))),
            ]),
          ],
        ]),
      ),
      if (_hasMinors) ...[
        const SizedBox(height: 14),
        _guardianCard(context),
      ],
      // The witness minimum gates Continue — the server refuses to sign below it, so
      // letting the flow walk past here would only fail at the seal.
    ]);
  }

  Widget _personRow(BuildContext context,
      {required String role,
      required String name,
      required String phone,
      required bool confirmed,
      bool unreached = false}) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          // greenTint is a light-theme fill: left unconditional it burned a bright
          // chip into the dark card. Dark gets the same idea built from the green
          // scale's other end — a green wash under light green type.
          decoration: BoxDecoration(
            color: dark ? WasiatiColors.greenSoft.withValues(alpha: 0.25) : WasiatiColors.greenTint,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(role.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: dark ? WasiatiColors.greenTint : WasiatiColors.bottleGreen)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (phone.isNotEmpty)
              Text(phone, style: text.bodySmall?.copyWith(color: context.tokens.faint), textDirection: TextDirection.ltr),
            // The invite reached nobody (notified: false) — say so calmly, on the
            // row, so the owner knows to pass it on themselves.
            if (unreached)
              Text(l.wdInviteUnreached,
                  style: text.bodySmall?.copyWith(
                      color: context.tokens.warningInk, fontWeight: FontWeight.w600, height: 1.35)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: confirmed ? WasiatiColors.success : WasiatiColors.warning),
          ),
          child: Text(confirmed ? l.cwConfirmedLbl : l.cwPendingLbl,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: confirmed ? context.tokens.successInk : context.tokens.warningInk)),
        ),
      ]),
    );
  }

  Widget _guardianCard(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    Widget modeBtn(String mode, String label) {
      final active = _guardianMode == mode;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() {
            _guardianMode = mode;
            _saveGuardian(immediate: true);
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? WasiatiColors.bottleGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: active ? WasiatiColors.bottleGreen : context.tokens.hairline),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: active ? WasiatiColors.onDark : context.tokens.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ),
      );
    }

    return WasiatiCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.cwGuardTitle, style: text.titleMedium),
        const SizedBox(height: 4),
        Text(l.cwGuardSub, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(width: 160, child: Row(children: [modeBtn('parent', l.cwGParentLbl)])),
          SizedBox(width: 200, child: Row(children: [modeBtn('islamic', l.cwGIslamicLbl)])),
          SizedBox(width: 160, child: Row(children: [modeBtn('named', l.cwGNamedLbl)])),
        ]),
        const SizedBox(height: 12),
        if (_guardianMode == 'parent')
          _noteBox(context, l.cwGParentNote, gold: false)
        else if (_guardianMode == 'islamic')
          _noteBox(context, l.cwGIslamicNote, gold: true)
        else
          Column(children: [
            _RegField(label: l.cwFullNameLbl, controller: _gName, hint: l.cwFullNamePh, onChanged: (_) => _saveGuardian()),
            const SizedBox(height: 8),
            _pair(
              _RegField(label: l.cwPhoneLbl, controller: _gPhone, hint: l.cwPhonePh, ltr: true, onChanged: (_) => _saveGuardian()),
              _RegField(label: l.cwEmailLbl, controller: _gEmail, hint: l.cwEmailPh, ltr: true, onChanged: (_) => _saveGuardian()),
            ),
          ]),
      ]),
    );
  }

  Widget _noteBox(BuildContext context, String textStr, {required bool gold}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: gold
            ? WasiatiColors.brassGold.withValues(alpha: 0.10)
            : (dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gold ? WasiatiColors.goldBorderSoft : context.tokens.hairline),
      ),
      child: Text(textStr,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: gold ? context.tokens.goldInk : context.tokens.muted, height: 1.55)),
    );
  }

  Future<void> _addPerson({required bool isWitness}) async {
    final l = context.l10n;
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isWitness ? ctx.l10n.wdAddWitnessTitle : ctx.l10n.wdAddTrusteeTitle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: ctx.l10n.wdFullName)),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ctx.l10n.wdPhone)),
            const SizedBox(height: 10),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: ctx.l10n.cwEmailLbl)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cwCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.cwAdd)),
          ],
        ),
      );
      if (ok != true || name.text.trim().length < 2 || _willId == null) return;
      final api = ref.read(willsApiProvider);
      final e = email.text.trim().isEmpty ? null : email.text.trim();
      final ({String id, bool notified}) added;
      if (isWitness) {
        added = await api.addWitness(_willId!, fullName: name.text.trim(), phone: phone.text.trim(), email: e);
        ref.invalidate(witnessesProvider(_willId!));
      } else {
        added = await api.addTrustee(_willId!, fullName: name.text.trim(), phone: phone.text.trim(), email: e);
        ref.invalidate(trusteesProvider(_willId!));
      }
      // notified: false = the invite reached NOBODY (no SMS dispatched, no email
      // on file). Flag the row so the owner contacts them another way — see
      // rosterUnreachedProvider.
      if (!added.notified) {
        ref.read(rosterUnreachedProvider.notifier).update((s) => {...s, added.id});
      }
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      name.dispose();
      phone.dispose();
      email.dispose();
    }
  }

  // --- Step 4: Your estate & bequest -----------------------------------------
  Widget _estateForm(BuildContext context, List<Heir> heirs) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final nameMissing = _third >= 0.5 && _bequestName.text.trim().isEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _EstateCard(
        willId: _willId,
        region: _region,
        listOpen: _estateListOpen,
        onShowAll: () => setState(() => _estateListOpen = true),
        onEdit: _willId == null ? null : () => context.push('/wills/$_willId/assets'),
      ),
      const SizedBox(height: 14),
      WasiatiCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cwBequestCardTitle, style: text.titleMedium),
          const SizedBox(height: 2),
          Text(l.cwBequestCardSub, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
          // Prototype order (data-screen-label "Create will", step 4 bequest card):
          // title → sub → the "% of the free third" row → slider → equivalence line.
          // The beneficiary field follows; the prototype's static mock has no such
          // field, but the flow validates it and the bequest row needs the name.
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Text(l.cwBequestPctLabel, style: text.bodyMedium?.copyWith(color: tokens.muted))),
            Text(context.digits('${_third.toStringAsFixed(0)}%'),
                style: text.headlineSmall?.copyWith(color: context.tokens.goldInk, fontWeight: FontWeight.w700, height: 1)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: WasiatiColors.brassGold,
              thumbColor: WasiatiColors.brassGold,
              inactiveTrackColor: WasiatiColors.goldBorderSoft,
              overlayColor: WasiatiColors.brassGold.withValues(alpha: 0.14),
              trackHeight: 6,
            ),
            child: Slider(
              value: _third.clamp(0, 100).toDouble(),
              min: 0,
              max: 100,
              onChanged: (v) => _set(() => _third = v),
            ),
          ),
          // Equivalence line: "Up to ⅓ … Your current bequest equals X% of the estate."
          Text.rich(TextSpan(
            style: text.bodySmall?.copyWith(color: tokens.muted, height: 1.55),
            children: [
              TextSpan(text: '${l.cwBequestHelpLead} '),
              TextSpan(
                  text: context.digits('${_bequestEstatePct.toStringAsFixed(_bequestEstatePct % 1 == 0 ? 0 : 1)}% '),
                  style: TextStyle(color: context.tokens.goldInk, fontWeight: FontWeight.w700)),
              TextSpan(text: l.cwOfEstateDot),
            ],
          )),
          const SizedBox(height: 16),
          _CounterLabel(l.cwBequestWhoLabel),
          const SizedBox(height: 8),
          TextField(
            controller: _bequestName,
            onChanged: (_) => _set(() {}),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: l.cwBequestWhoHint),
          ),
          if (nameMissing) ...[
            const SizedBox(height: 8),
            Text(l.cwBequestNameNeeded,
                style: text.bodySmall?.copyWith(color: context.tokens.dangerInk, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    ]);
  }

  // --- Step 5: Wishes & words ------------------------------------------------
  Widget _wishesForm(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final tokens = context.tokens;
    Widget wish(String label, bool value, ValueChanged<bool> onChanged) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: value ? WasiatiColors.bottleGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: value ? WasiatiColors.bottleGreen : tokens.hairline, width: 1.5),
                ),
                child: value ? const Icon(Icons.check, size: 13, color: WasiatiColors.onDark) : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: text.bodyMedium?.copyWith(height: 1.5))),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WasiatiCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cwWishesCardTitle, style: text.titleMedium),
          const SizedBox(height: 10),
          wish(l.cwWish1, _wishSunnah, (v) => _set(() => _wishSunnah = v)),
          wish(l.cwWish2, _wishSimple, (v) => _set(() => _wishSimple = v)),
          wish(l.cwWish3, _wishLocal, (v) => _set(() => _wishLocal = v)),
          wish(_wishAzaa ? l.cwWish4 : l.cwWish4No, _wishAzaa, (v) => _set(() => _wishAzaa = v)),
          const SizedBox(height: 8),
          Text(l.cwWishesNote, style: text.bodySmall?.copyWith(color: tokens.faint, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 14),
      WasiatiCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cwWordsTitle, style: text.titleMedium),
          const SizedBox(height: 2),
          Text(l.cwWordsSubtitle, style: text.bodySmall?.copyWith(color: tokens.faint, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _words,
            maxLines: 10,
            minLines: 7,
            maxLength: 5000,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            textAlignVertical: TextAlignVertical.top,
            // The template rides in as a faded multi-line placeholder (prototype: the
            // textarea's wordsPh) — a one-line hint clipped it to nothing.
            decoration: InputDecoration(
              hintText: l.cwWordsHint,
              hintMaxLines: 5,
              hintStyle: text.bodyMedium?.copyWith(color: tokens.faint, height: 1.6),
            ),
            inputFormatters: [WasiyyaTemplateFormatter(l.cwWordsDefault)],
            onChanged: (_) => _set(() {}), // keeps the character counter live
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(context.digits(l.cwWordsCount(_words.text.length)),
                style: text.bodySmall?.copyWith(color: tokens.faint)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      // The Premium+ video for the family. DECISIONS §0 puts the video step BEFORE
      // Review, and now that Review is its own page this is the last guided step —
      // so it belongs here, beside the written words it stands in for.
      _videoBlock(context),
    ]);
  }

  Widget _videoBlock(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ent = ref.watch(entitlementProvider).asData?.value;
    final premium = entitlementHas(ent, 'videoMessages');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tokens.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.rsVideoTitle,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.goldInk)),
        const SizedBox(height: 10),
        if (!premium)
          Row(children: [
            Expanded(child: Text(l.rsVideoGateNote, style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5))),
            const SizedBox(width: 10),
            FilledButton(onPressed: () => context.go('/pricing'), style: WasiatiButtons.goldSolid(context), child: Text(l.cwUpgrade)),
          ])
        else if (_wvDeferred)
          Row(children: [
            Expanded(child: Text(l.rsVideoDeferredNote, style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5))),
            TextButton(onPressed: () => context.go('/legacy/record'), child: Text(l.rsVideoRecordNow)),
          ])
        else
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => context.go('/legacy/record'),
                icon: const Icon(Icons.fiber_manual_record, size: 14, color: WasiatiColors.record),
                label: Text(l.rsVideoRecord),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/legacy'),
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: Text(l.rsVideoUpload),
              ),
              TextButton(onPressed: () => setState(() => _wvDeferred = true), child: Text(l.rsVideoSkip)),
            ]),
            const SizedBox(height: 8),
            Text(l.rsVideoNote, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
          ]),
      ]),
    );
  }
}

// --- a compact labelled text field for the registry / guardian forms ----------
class _RegField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool ltr;
  final ValueChanged<String> onChanged;
  const _RegField({required this.label, required this.controller, required this.hint, required this.onChanged, this.ltr = false});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.faint)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        onChanged: onChanged,
        textDirection: ltr ? TextDirection.ltr : null,
        decoration: InputDecoration(hintText: hint, isDense: true),
      ),
    ]);
  }
}

// --- estate hero card (step 4) ------------------------------------------------
// The compact totals variant went with step 6: the Review page states the estate
// through the document preview itself, which is the artefact being sealed.
class _EstateCard extends ConsumerWidget {
  final String? willId;
  final String region;
  final bool listOpen;
  final VoidCallback? onShowAll;
  final VoidCallback? onEdit;
  const _EstateCard({
    required this.willId,
    required this.region,
    this.listOpen = true,
    this.onShowAll,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final local = localCurrencyForRegion(region);
    final assetsAsync = willId == null ? const AsyncValue<List<EstateAsset>>.data([]) : ref.watch(assetsProvider(willId!));
    final assets = assetsAsync.asData?.value ?? const <EstateAsset>[];

    double sum(bool liab) => assets
        .where((a) => a.isLiability == liab && a.estimatedValue != null)
        .fold(0.0, (acc, a) => acc + toLocal(a.estimatedValue!, a.currency ?? local, local));
    final assetsTotal = sum(false);
    final loansTotal = sum(true);
    final net = assetsTotal - loansTotal;
    final hasFx = assets.any((a) => a.currency != null && a.currency != local && a.estimatedValue != null);
    // The amount is a quantity, so it localises; the currency CODE stays Latin, which
    // digits() already guarantees by touching ASCII digits only.
    String money(double v) => context.digits('$local ${groupedAmount(v)}');

    return WasiatiCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.cwEstateTitle, style: text.titleMedium)),
          if (onEdit != null)
            OutlinedButton(onPressed: onEdit, child: Text('${l.cwEstateEdit} ›')),
        ]),
        ...[
          const SizedBox(height: 14),
          if (assets.isEmpty)
            Text(l.cwEstateEmpty, style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5))
          else if (listOpen)
            Column(children: [
              for (final a in assets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            // Ink, so the bullet matches the amount it marks.
                            color: a.isLiability ? context.tokens.dangerInk : WasiatiColors.bottleGreen,
                            borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    Text(_rowAmount(a, local),
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, color: a.isLiability ? context.tokens.dangerInk : null)),
                  ]),
                ),
            ])
          else
            OutlinedButton(onPressed: onShowAll, child: Text(context.digits(l.cwShowAllRows(assets.length.toString())))),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.tokens.hairline),
          ),
          child: Wrap(spacing: 24, runSpacing: 12, children: [
            _estateStat(context, l.cwEstateAssets, money(assetsTotal), null),
            _estateStat(context, l.cwEstateLoans, '− ${money(loansTotal)}', context.tokens.dangerInk),
            // bottleGreen is a light-theme ink: on nightSurface the headline net
            // figure came out at 1.58:1 — the single worst contrast in the flow.
            // The prototype theme-swaps --green to #4A6B5A here, but that is still
            // only 2.59:1, so dark takes the palette's green-tinted ink instead.
            _estateStat(context, l.cwEstateNet, money(net),
                dark ? WasiatiColors.darkTextMuted : WasiatiColors.bottleGreen, big: true),
          ]),
        ),
        ...[
          if (hasFx) ...[
            const SizedBox(height: 10),
            Text(l.cwFxNote(local), style: text.bodySmall?.copyWith(color: context.tokens.goldInk, height: 1.5)),
          ],
          const SizedBox(height: 8),
          Text(l.cwEstateNote, style: text.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
        ],
      ]),
    );
  }

  String _rowAmount(EstateAsset a, String local) {
    final cur = a.currency ?? local;
    final base = '${a.isLiability ? '− ' : ''}$cur ${groupedAmount(a.estimatedValue!)}';
    if (cur != local) return '$base ≈ $local ${groupedAmount(toLocal(a.estimatedValue!, cur, local))}';
    return base;
  }

  Widget _estateStat(BuildContext context, String label, String value, Color? color, {bool big = false}) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.faint)),
      const SizedBox(height: 2),
      Text(value,
          style: (big ? text.headlineSmall : text.titleMedium)?.copyWith(fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// --- structured heir counters (shared with step 1) ---------------------------
class _CounterLabel extends StatelessWidget {
  final String text;
  const _CounterLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.muted)),
      );
}

class _SexToggle extends StatelessWidget {
  final String sex;
  final ValueChanged<String> onChanged;
  const _SexToggle({required this.sex, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget seg(String value, String label) {
      final active = sex == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: active ? WasiatiColors.bottleGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    color: active ? WasiatiColors.onDark : context.tokens.muted, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.nightRaised : WasiatiColors.parchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.tokens.hairline),
      ),
      child: Row(children: [seg('male', l.cwMale), seg('female', l.cwFemale)]),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final String? helper;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _StepperRow(
      {required this.label,
      this.helper,
      required this.value,
      required this.min,
      required this.max,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: enabled ? WasiatiColors.greenBorder : context.tokens.hairline),
              ),
              child: Icon(icon, size: 17, color: enabled ? WasiatiColors.bottleGreen : context.tokens.faint),
            ),
          ),
        );
    return _rowCard(
      context,
      Row(children: [
        Expanded(
          child: helper == null
              ? Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(helper!, style: t.bodySmall?.copyWith(color: context.tokens.faint, fontSize: 12, height: 1.35)),
                ]),
        ),
        btn(Icons.remove, value > min, () => onChanged(value - 1)),
        SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.center, style: t.titleMedium)),
        btn(Icons.add, value < max, () => onChanged(value + 1)),
      ]),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _rowCard(
      context,
      Row(children: [
        Expanded(child: Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        Switch(value: value, onChanged: onChanged, activeColor: WasiatiColors.bottleGreen),
      ]),
      onTap: () => onChanged(!value),
    );
  }
}

class _ExtendedToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  const _ExtendedToggle({required this.open, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final gold = context.tokens.goldInk;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(open ? Icons.remove : Icons.add, size: 17, color: gold),
          const SizedBox(width: 8),
          Expanded(child: Text(context.l10n.cwAddExtended, style: TextStyle(color: gold, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

Widget _rowCard(BuildContext context, Widget child, {VoidCallback? onTap}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final box = Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
    ),
    child: child,
  );
  if (onTap == null) return box;
  return InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: box);
}

class _AiPill extends StatelessWidget {
  final VoidCallback onTap;
  const _AiPill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gold = dark ? WasiatiColors.goldSoft : WasiatiColors.brassGold;
    return CustomPaint(
      foregroundPainter: _DashedPillPainter(gold),
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 13, color: gold),
              const SizedBox(width: 6),
              Text(context.l10n.cwFillAi,
                  style: TextStyle(color: context.tokens.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const WasiatiChip('PREMIUM', kind: WasiatiChipKind.comped),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  final Color color;
  const _DashedPillPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 4, metric.length)), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPillPainter old) => old.color != color;
}

Widget _pair(Widget a, Widget b) => LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 480) {
        return Column(children: [a, const SizedBox(height: 8), b]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ]);
    });

// --- live preview (wide) ------------------------------------------------------
class _Preview extends StatelessWidget {
  final List<Heir> heirs;
  final List<ShariaShare> shares;
  final String school;
  const _Preview({required this.heirs, required this.shares, required this.school});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.tokens.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: context.tokens.successInk, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.cwLivePreview,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(l.cwComputedPer(schoolLabel(l, school)),
            style: t.bodySmall?.copyWith(color: context.tokens.goldInk, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Center(
          child: SizedBox(
            width: 250,
            height: 216,
            child: CustomPaint(
              // Each heir's share is labelled AROUND the ring now, so the donut reads on its
              // own. The centre used to carry the bequest %, which sat at 0 until an owner
              // set one and read as a broken "0%" in the middle of a heirs chart. The
              // bequest lives on its own step; it does not belong in the centre of this one.
              painter: _DonutPainter(
                shares: shares,
                labels: [
                  for (final s in shares)
                    context.digits('${s.sharePercent.toStringAsFixed(s.sharePercent % 1 == 0 ? 0 : 1)}%')
                ],
                track: context.tokens.hairline,
                labelColor: context.tokens.muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettlementNote(),
        const SizedBox(height: 12),
        for (var i = 0; i < shares.length; i++) _previewRow(context, shares[i], _segColor(i)),
        const SizedBox(height: 12),
        if (shares.isNotEmpty)
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: context.tokens.hairline))),
            child: Text(l.cwPreviewNote, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
          )
        else
          Text(l.cwAddHeirPrompt, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
      ]),
    );
  }

  Widget _previewRow(BuildContext context, ShariaShare s, Color color) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(width: 11, height: 11, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Builder(builder: (context) {
                final rel = heirRelLabel(context.l10n, s.heirRelation);
                final title = s.heirName == rel ? s.heirName : '${s.heirName} — $rel';
                // Unnamed heirs are numbered ("Son 1"), so the label carries a digit.
                return Text(context.digits(title), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600));
              }),
              if (s.basisFor(Localizations.localeOf(context).languageCode) != null) ...[
                const SizedBox(height: 3),
                Text(s.basisFor(Localizations.localeOf(context).languageCode)!,
                    style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.35, fontSize: 11.5)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(context.digits('${s.sharePercent.toStringAsFixed(s.sharePercent % 1 == 0 ? 0 : 1)}%'),
                style: t.titleSmall),
          ),
        ]),
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  final List<ShariaShare> shares;
  const _PreviewStrip({required this.shares});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: context.tokens.successInk, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(l.cwLivePreviewShort,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted)),
          const Spacer(),
          Text(context.digits(l.cwHeirCount(shares.length)), style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 14,
            child: shares.isEmpty
                ? Container(color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentDeep)
                : Row(children: [
                    for (var i = 0; i < shares.length; i++)
                      Expanded(
                        flex: math.max(1, (shares[i].sharePercent * 10).round()),
                        child: Container(color: _segColor(i)),
                      ),
                  ]),
          ),
        ),
        if (shares.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 6, children: [
            for (var i = 0; i < shares.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _segColor(i), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 5),
                Text(
                    context.digits(
                        '${shares[i].heirName} ${shares[i].sharePercent.toStringAsFixed(shares[i].sharePercent % 1 == 0 ? 0 : 1)}%'),
                    style: t.bodySmall),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _SettlementNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget step(int n, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${context.digits(MaterialLocalizations.of(context).formatDecimal(n))}. ',
                style: t.bodySmall?.copyWith(color: context.tokens.goldInk, fontWeight: FontWeight.w700)),
            Expanded(child: Text(label, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.4))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WasiatiColors.goldBorderSoft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 15, color: context.tokens.goldInk),
          const SizedBox(width: 7),
          Text(l.cwBeforeShares,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.goldInk)),
        ]),
        const SizedBox(height: 8),
        step(1, l.cwStep1Funeral),
        step(2, l.cwStep2Debts),
        step(3, l.cwStep3Bequest),
        const SizedBox(height: 2),
        Text(l.cwSharesApplyRest, style: t.bodySmall?.copyWith(color: context.tokens.faint, fontStyle: FontStyle.italic)),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<ShariaShare> shares;
  final List<String> labels;
  final Color track;
  final Color labelColor;
  _DonutPainter({required this.shares, required this.labels, required this.track, required this.labelColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Leave a wide margin: the % labels sit OUTSIDE the ring and must not clip the box.
    final radius = math.min(size.width, size.height) / 2 - 30;
    const stroke = 15.0;
    canvas.drawCircle(
        center, radius, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
    if (shares.isEmpty) return;
    final total = shares.fold<double>(0, (a, s) => a + s.sharePercent);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (var i = 0; i < shares.length; i++) {
      final sweep = (shares[i].sharePercent / total) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep - 0.02,
        false,
        Paint()
          ..color = _segColor(i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );

      // The share %, centred on the segment's mid-angle, just beyond the ring.
      final mid = start + sweep / 2;
      final lr = radius + stroke / 2 + 13;
      final at = Offset(center.dx + lr * math.cos(mid), center.dy + lr * math.sin(mid));
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          // A TextPainter has no ambient DefaultTextStyle, so the family must be named or
          // it falls back to the engine default (and to Ahem's filled boxes under test).
          // Same body family the rest of the panel uses, with the Arabic fallback so the
          // Arabic-Indic digits shape in the AR build.
          style: const TextStyle(
            fontFamily: WasiatiType.bodyFamily,
            fontFamilyFallback: [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ).copyWith(color: labelColor),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.shares != shares || old.labels != labels || old.track != track || old.labelColor != labelColor;
}

const _palette = [
  WasiatiColors.bottleGreen,
  WasiatiColors.brassGold,
  WasiatiColors.goldSoft,
  WasiatiColors.greenSoft,
  WasiatiColors.info,
  WasiatiColors.warning,
];
Color _segColor(int i) => _palette[i % _palette.length];

/// Localised label for a UI school-of-jurisprudence key.
String schoolLabel(AppLocalizations l, String school) => switch (school) {
      'HANAFI' => l.cwMadhhabHanafi,
      'MALIKI' || 'SHAFII' => l.cwMadhhabMalikiShafii,
      _ => l.cwMadhhabJumhur,
    };
