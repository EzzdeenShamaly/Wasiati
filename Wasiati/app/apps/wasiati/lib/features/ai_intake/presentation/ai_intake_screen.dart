import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/ai_intake_providers.dart';
import '../data/ameen_voice.dart';
import '../domain/ai_intake_models.dart';

/// Conversational will intake (design 9b, Premium+). The user talks or types
/// naturally; the agent asks one question at a time and quietly builds a running
/// list of heirs and assets on the right. When they confirm they're done, one
/// tap turns the extraction into a real, editable will.
class AiIntakeScreen extends ConsumerStatefulWidget {
  const AiIntakeScreen({super.key});
  @override
  ConsumerState<AiIntakeScreen> createState() => _AiIntakeScreenState();
}

class _AiIntakeScreenState extends ConsumerState<AiIntakeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  final _voice = AmeenVoice();

  String? _sessionId;
  ExtractedData _extracted = const ExtractedData();
  bool _completed = false;
  bool _starting = true;
  bool _sending = false;
  bool _finalizing = false;
  bool _gated = false;
  bool _voiceReady = false;
  bool _listening = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    _boot();
    _voice.init().then((ok) {
      if (mounted && ok) setState(() => _voiceReady = true);
    });
  }

  @override
  void dispose() {
    _voice.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Mic: dictate into the input; tap again to stop and send. Web uses the
  /// browser speech engine; unsupported browsers never reach here (button hidden).
  Future<void> _toggleMic() async {
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _voice.listen(
      languageCode: Localizations.localeOf(context).languageCode,
      onResult: (text) {
        if (!mounted) return;
        setState(() => _input.text = text);
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      },
    );
  }

  /// The one unfinished conversation this browser may resume. Only an id is
  /// kept client-side; the transcript stays server-authoritative and the server
  /// re-checks ownership on every GET (a different signed-in account gets a 404
  /// and simply starts fresh).
  static const _kSessionKey = 'aiIntakeSessionId';

  /// Local storage is best-effort: blocked storage (private browsing, tests)
  /// must degrade to "no resume", never block Ameen from starting at all.
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> _boot() async {
    final api = ref.read(aiIntakeApiProvider);
    final prefs = await _prefs();

    // Resume first (GET /ai-intake/:id): an interrupted session used to be
    // unreachable — every visit started Ameen from scratch and the half-told
    // conversation was stranded on the server.
    final savedId = prefs?.getString(_kSessionKey);
    if (savedId != null) {
      try {
        final s = await api.getSession(savedId);
        // Already turned into a will -> nothing left to resume; start clean.
        // (A completed-but-uncommitted session IS resumed, so the finalize
        // card comes back and the extraction is not silently lost.)
        if (s.extracted.committedWillId == null) {
          if (!mounted) return;
          setState(() {
            _sessionId = s.id;
            _extracted = s.extracted;
            _completed = s.completed;
            _messages.addAll(s.messages);
            _starting = false;
          });
          _scrollDown();
          if (s.messages.isNotEmpty) WasiatiSnack.success(context, context.l10n.aiResumed);
          return;
        }
        await prefs?.remove(_kSessionKey);
      } on ApiException catch (e) {
        if (e.statusCode == 403) {
          // The feature gate (ownership failures are 404s) — same as start().
          if (mounted) {
            setState(() {
              _starting = false;
              _gated = true;
            });
          }
          return;
        }
        // 404 (another account's session, or deleted) or transient failure:
        // forget the id and fall through to a fresh start.
        await prefs?.remove(_kSessionKey);
      }
      if (!mounted) return;
    }

    try {
      final turn = await api.start();
      await prefs?.setString(_kSessionKey, turn.sessionId);
      if (!mounted) return;
      setState(() {
        _sessionId = turn.sessionId;
        _extracted = turn.extracted;
        _completed = turn.completed;
        if (turn.reply.trim().isNotEmpty) _messages.add(ChatMessage(fromUser: false, text: turn.reply));
        _starting = false;
      });
      _scrollDown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        if (e.statusCode == 403) {
          _gated = true;
        } else if (e.statusCode == 503) {
          _fatal = context.l10n.aiFatal503;
        } else {
          _fatal = e.message;
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _sessionId == null) return;
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
    }
    setState(() {
      _messages.add(ChatMessage(fromUser: true, text: text));
      _input.clear();
      _sending = true;
    });
    _scrollDown();
    try {
      final turn = await ref.read(aiIntakeApiProvider).message(_sessionId!, text);
      if (!mounted) return;
      setState(() {
        _extracted = turn.extracted;
        _completed = turn.completed;
        if (turn.reply.trim().isNotEmpty) _messages.add(ChatMessage(fromUser: false, text: turn.reply));
      });
      // Ameen speaks its reply aloud (best-effort; silent where unsupported).
      if (_voiceReady && turn.reply.trim().isNotEmpty) {
        _voice.speak(turn.reply, languageCode: Localizations.localeOf(context).languageCode);
      }
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  Future<void> _finalize() async {
    if (_sessionId == null || _finalizing) return;
    setState(() => _finalizing = true);
    try {
      // Hands back a SEED, not a will — finalize creates nothing. This used to read a
      // `willId` off the response and route to `/wills/<null>`, which is why the finish
      // button could only fail: the backend stopped creating wills here precisely so a
      // conversation could never produce a legal document the owner had not reviewed.
      final seed = await ref.read(aiIntakeApiProvider).finalize(_sessionId!);
      // The session is spent — a later visit must start fresh, not resume it.
      await (await _prefs())?.remove(_kSessionKey);
      // Into the guided form, pre-filled. The owner reviews every step, and the wizard
      // reports back which will it created (markSeeded) once a draft actually exists.
      if (mounted) context.go('/wills/new/form', extra: seed);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_gated) return _GatedView();
    if (_fatal != null) return _FatalView(message: _fatal!);
    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the pinned composer's padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final chat = _chatColumn(context);
          final panel = _capturePanel(context);
          if (!wide) return chat;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 3, child: chat),
            Container(width: 1, color: context.tokens.hairline),
            SizedBox(width: 320, child: panel),
          ]);
        }),
      ),
    );
  }

  Widget _chatColumn(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      // Ameen is entered from "How would you like to build your will?" (/wills/new) and had
      // no way back to it. Spec §2 asks for "Back and Review & seal nav on the Ameen
      // screen"; neither was here, so anyone who opened the conversation to see what it was
      // had to finish it or fall back on the rail.
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 20, 0),
        child: WasiatiBackLink(
          label: context.l10n.wdBackToWills,
          onTap: () => context.go('/wills'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Seal(size: 34, status: SealStatus.idle),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(l.aiGuidedIntake,
                    style: TextStyle(color: context.tokens.goldInk, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(width: 8),
                WasiatiChip(l.aiPremium, kind: WasiatiChipKind.lockedFeature),
              ]),
              const SizedBox(height: 2),
              Text(l.aiTalkThrough, style: t.titleLarge),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: _starting
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                children: [
                  for (final m in _messages) _Bubble(message: m),
                  if (_sending) const _TypingBubble(),
                ],
              ),
      ),
      _composer(context),
    ]);
  }

  Widget _composer(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      // The composer is pinned, not scrolled, so it carries the bar's height rather than
      // the chat list: its surface runs on down behind the glass, its controls stay clear.
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16) +
          EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentLight,
        border: Border(top: BorderSide(color: context.tokens.hairline)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Mic — only shown when a speech engine is available (Web Speech / native).
        if (_voiceReady) ...[
          SizedBox(
            height: 48,
            width: 48,
            child: IconButton(
              onPressed: _starting ? null : _toggleMic,
              tooltip: _listening ? context.l10n.aiMicStop : context.l10n.aiMicListen,
              isSelected: _listening,
              style: IconButton.styleFrom(
                backgroundColor: _listening ? WasiatiColors.brassGold.withValues(alpha: 0.18) : null,
                foregroundColor: _listening ? context.tokens.goldInk : context.tokens.muted,
              ),
              icon: _listening
                  ? const Icon(Icons.stop_rounded, size: 22)
                  : const WasiatiIcon(svg: WasiatiIcons.mic, size: 22),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            enabled: !_starting,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(hintText: _listening ? context.l10n.aiMicListening : context.l10n.aiComposerHint),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          width: 48,
          child: IconButton.filled(
            onPressed: _sending || _starting ? null : _send,
            icon: const Icon(Icons.arrow_upward, size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _capturePanel(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentLight,
      child: ListView(
        // Only built on the wide branch, where the shell shows the rail and this is 0 —
        // but the SafeArea above is shared, so a real home-indicator inset lands here too.
        padding: const EdgeInsets.all(18) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          Text(l.aiCaptured,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted)),
          const SizedBox(height: 14),
          Text(l.aiHeirs, style: t.titleSmall),
          const SizedBox(height: 8),
          if (_extracted.heirs.isEmpty)
            Text(l.aiHeirsNone, style: t.bodySmall?.copyWith(color: context.tokens.faint))
          else
            ..._extracted.heirs.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CaptureRow(icon: Icons.person_outline, title: h.name.isEmpty ? heirRelLabel(l, h.relation) : h.name, sub: heirRelLabel(l, h.relation)),
                )),
          const SizedBox(height: 18),
          Text(l.aiAssets, style: t.titleSmall),
          const SizedBox(height: 8),
          if (_extracted.assets.isEmpty)
            Text(l.aiAssetsNone, style: t.bodySmall?.copyWith(color: context.tokens.faint))
          else
            ..._extracted.assets.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CaptureRow(
                      icon: Icons.inventory_2_outlined,
                      title: a.label.isEmpty ? a.type : a.label,
                      sub: a.institution ?? a.type),
                )),
          const SizedBox(height: 20),
          if (_completed || _extracted.readyToFinalize) _finalizeCard(context) else _hintCard(context),
        ],
      ),
    );
  }

  Widget _finalizeCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Light-theme fill + light-theme inks, hard-coded: the same defect as the
        // dashboard checklist. tokens.highlight/.greenInk hold the light values
        // exactly and invert for dark.
        color: context.tokens.highlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WasiatiColors.greenBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.aiReadyTitle,
            style: t.titleSmall?.copyWith(color: context.tokens.greenInk, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(context.l10n.aiReadyBody, style: t.bodySmall?.copyWith(color: context.tokens.greenInk)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: WasiatiButtons.goldSolid(context),
            onPressed: _finalizing ? null : _finalize,
            child: _finalizing
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.l10n.aiTurnIntoWill),
          ),
        ),
      ]),
    );
  }

  Widget _hintCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.nightRaised : WasiatiColors.parchment,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        context.l10n.aiHintCard,
        style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5),
      ),
    );
  }
}

class _CaptureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _CaptureRow({required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Icon(icon, size: 18, color: context.tokens.greenInk),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(sub, style: t.bodySmall?.copyWith(color: context.tokens.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final t = Theme.of(context).textTheme;
    final user = message.fromUser;
    final bg = user
        ? WasiatiColors.bottleGreen
        : (dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight);
    final fg = user ? WasiatiColors.onDark : (dark ? WasiatiColors.darkText : WasiatiColors.inkNavy);
    return Align(
      alignment: user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bg,
          // Directional so the tail mirrors correctly in Arabic (RTL): the tail
          // sits on the sender's start edge (user = end side, assistant = start).
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(user ? 16 : 4),
            bottomEnd: Radius.circular(user ? 4 : 16),
          ),
          border: user ? null : Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
        ),
        child: Text(message.text, style: t.bodyMedium?.copyWith(color: fg, height: 1.45)),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
          borderRadius: const BorderRadiusDirectional.only(
            topStart: Radius.circular(16),
            topEnd: Radius.circular(16),
            bottomEnd: Radius.circular(16),
            bottomStart: Radius.circular(4),
          ),
          border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
        ),
        child: const SizedBox(
          width: 34,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(0), SizedBox(width: 4), _Dot(1), SizedBox(width: 4), _Dot(2),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final int i;
  const _Dot(this.i);
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: WasiatiColors.goldSoft.withValues(alpha: i == 1 ? 0.9 : 0.5),
          shape: BoxShape.circle,
        ),
      );
}

class _GatedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Seal(size: 44, status: SealStatus.locked, filled: true),
              const SizedBox(height: 16),
              WasiatiChip(context.l10n.aiGatedBadge, kind: WasiatiChipKind.lockedFeature),
              const SizedBox(height: 12),
              Text(context.l10n.aiGatedTitle, style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(
                context.l10n.aiGatedBody,
                style: t.bodyMedium?.copyWith(color: context.tokens.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: WasiatiButtons.goldSolid(context),
                onPressed: () => context.go('/pricing'),
                child: Text(context.l10n.commonSeePlans),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FatalView extends StatelessWidget {
  final String message;
  const _FatalView({required this.message});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chat_bubble_outline, size: 40, color: context.tokens.muted),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: context.tokens.muted, height: 1.5)),
              const SizedBox(height: 18),
              FilledButton(onPressed: () => context.go('/wills/new/form'), child: Text(context.l10n.aiBuildByHand)),
            ]),
          ),
        ),
      ),
    );
  }
}

