/// Structured data the intake agent extracts behind the conversation. Mirrors
/// the backend ExtractedData shape (ai-intake.service.ts): cumulative heirs +
/// assets, a readyToFinalize flag, and a committedWillId once turned into a will.
class ExtractedHeir {
  final String relation;
  final String name;
  const ExtractedHeir({required this.relation, required this.name});
  factory ExtractedHeir.fromJson(Map<String, dynamic> j) =>
      ExtractedHeir(relation: (j['relation'] ?? '') as String, name: (j['name'] ?? '') as String);
}

class ExtractedAsset {
  final String type;
  final String label;
  final String? institution;
  const ExtractedAsset({required this.type, required this.label, this.institution});
  factory ExtractedAsset.fromJson(Map<String, dynamic> j) => ExtractedAsset(
        type: (j['type'] ?? 'OTHER') as String,
        label: (j['label'] ?? '') as String,
        institution: j['institution'] as String?,
      );
}

class ExtractedData {
  final List<ExtractedHeir> heirs;
  final List<ExtractedAsset> assets;
  final bool readyToFinalize;
  final String? committedWillId;
  const ExtractedData({this.heirs = const [], this.assets = const [], this.readyToFinalize = false, this.committedWillId});

  factory ExtractedData.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ExtractedData();
    return ExtractedData(
      heirs: ((j['heirs'] as List?) ?? [])
          .map((e) => ExtractedHeir.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      assets: ((j['assets'] as List?) ?? [])
          .map((e) => ExtractedAsset.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      readyToFinalize: j['readyToFinalize'] == true,
      committedWillId: j['committedWillId'] as String?,
    );
  }

  bool get hasAnything => heirs.isNotEmpty || assets.isNotEmpty;
}

/// One turn returned by start/message: the assistant's reply plus the latest
/// cumulative extraction and whether the user has confirmed they're done.
class IntakeTurn {
  final String sessionId;
  final String reply;
  final ExtractedData extracted;
  final bool completed;
  const IntakeTurn({required this.sessionId, required this.reply, required this.extracted, required this.completed});

  factory IntakeTurn.fromJson(Map<String, dynamic> j) => IntakeTurn(
        sessionId: j['sessionId'] as String,
        reply: (j['reply'] ?? '') as String,
        extracted: ExtractedData.fromJson((j['extractedData'] as Map?)?.cast<String, dynamic>()),
        completed: j['completed'] == true,
      );
}

/// A stored intake session as returned by `GET /ai-intake/:sessionId` — the
/// server-authoritative transcript + extraction, used to RESUME an interrupted
/// conversation. [messages] flattens the transcript into displayable bubbles:
/// user entries are plain strings; assistant entries are Claude content-block
/// lists whose text blocks are joined (tool_use blocks are the extraction's
/// plumbing, not conversation, and are skipped).
class IntakeSession {
  final String id;
  final bool completed;
  final ExtractedData extracted;
  final List<ChatMessage> messages;
  const IntakeSession({required this.id, required this.completed, required this.extracted, required this.messages});

  factory IntakeSession.fromJson(Map<String, dynamic> j) {
    final messages = <ChatMessage>[];
    for (final entry in (j['transcript'] as List?) ?? const []) {
      if (entry is! Map) continue;
      final content = entry['content'];
      final text = content is String
          ? content
          : content is List
              ? content
                  .whereType<Map>()
                  .where((b) => b['type'] == 'text')
                  .map((b) => (b['text'] ?? '').toString())
                  .join('\n')
              : '';
      if (text.trim().isEmpty) continue;
      messages.add(ChatMessage(fromUser: entry['role'] == 'user', text: text));
    }
    return IntakeSession(
      id: j['id'] as String,
      completed: j['completed'] == true,
      extracted: ExtractedData.fromJson((j['extractedData'] as Map?)?.cast<String, dynamic>()),
      messages: messages,
    );
  }
}

/// Humanises a HEIR_RELATIONS code (e.g. WIFE, SON, FATHER) for display.
String heirRelationLabel(String code) {
  final s = code.replaceAll('_', ' ').toLowerCase();
  return s.isEmpty ? code : s[0].toUpperCase() + s.substring(1);
}

/// A locally-rendered chat bubble (user or assistant). The transcript itself is
/// authoritative on the server; we keep a light client mirror for display.
class ChatMessage {
  final bool fromUser;
  final String text;
  const ChatMessage({required this.fromUser, required this.text});
}

/// What Ameen hands the guided form when the conversation is finished.
///
/// Deliberately COUNTERS, not named people, because that is exactly the state the will
/// wizard already keeps (`_sex`, `_wives`, `_sons`, … in CreateWillScreen) and converts
/// into individual heirs itself. Ameen therefore seeds the form rather than creating
/// anything: the backend's finalize() builds no will at all, so the owner still walks the
/// same wizard, sees what was understood, and can correct it before anything is saved.
/// That is the whole point of the redesign — a conversation must never silently produce
/// a legal document.
class IntakeSeed {
  /// The conversation this came from, so the wizard can report back which will it
  /// became (markSeeded) and one intake cannot seed two.
  final String? sessionId;
  final String sex; // 'male' | 'female'
  final int wives;
  final bool husband;
  final int sons;
  final int daughters;
  final bool mother;
  final bool father;
  final bool grandfather;
  final bool gmMaternal;
  final bool gmPaternal;
  final int brothers;
  final int sisters;
  final int uncles;
  final int cousins;
  final String? madhhab;

  const IntakeSeed({
    this.sessionId,
    this.sex = 'male',
    this.wives = 0,
    this.husband = false,
    this.sons = 0,
    this.daughters = 0,
    this.mother = false,
    this.father = false,
    this.grandfather = false,
    this.gmMaternal = false,
    this.gmPaternal = false,
    this.brothers = 0,
    this.sisters = 0,
    this.uncles = 0,
    this.cousins = 0,
    this.madhhab,
  });

  static int _int(dynamic v) => v is num ? v.toInt() : 0;
  static bool _bool(dynamic v) => v == true;

  /// [sessionId] rides alongside rather than inside the seed object on the wire: the
  /// backend answers finalize with { sessionId, seed }.
  factory IntakeSeed.fromJson(Map<String, dynamic> j, {String? sessionId}) => IntakeSeed(
        sessionId: sessionId,
        sex: j['sex'] == 'female' ? 'female' : 'male',
        wives: _int(j['wives']),
        husband: _bool(j['husband']),
        sons: _int(j['sons']),
        daughters: _int(j['daughters']),
        mother: _bool(j['mother']),
        father: _bool(j['father']),
        grandfather: _bool(j['grandfather']),
        gmMaternal: _bool(j['gmMaternal']),
        gmPaternal: _bool(j['gmPaternal']),
        brothers: _int(j['brothers']),
        sisters: _int(j['sisters']),
        uncles: _int(j['uncles']),
        cousins: _int(j['cousins']),
        madhhab: j['madhhab'] as String?,
      );

  /// True when the conversation captured at least one heir. A seed with nobody in it
  /// would drop the owner into an empty form having claimed Ameen understood them.
  bool get hasAnyone =>
      wives > 0 ||
      husband ||
      sons > 0 ||
      daughters > 0 ||
      mother ||
      father ||
      grandfather ||
      gmMaternal ||
      gmPaternal ||
      brothers > 0 ||
      sisters > 0 ||
      uncles > 0 ||
      cousins > 0;
}
