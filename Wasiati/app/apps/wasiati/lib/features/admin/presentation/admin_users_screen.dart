import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/admin_users_providers.dart';
import '../data/admin_users_api.dart';

/// Admin users (design "Admin users"): a 26px title, an Export-to-Excel outline
/// button, three headline stat tiles (total users · sealed wills · ID verified),
/// and a four-column table (User · Region · Plan · Identity). ADMIN-only, wired to
/// the real `/admin/users` provider.
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final data = ref.watch(adminUsersProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
          data: (d) => LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              return ListView(
                // The bar's height rides on the content, so user rows slide under the glass
                // mid-scroll and the last one still comes to rest clear of it.
                padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 24) +
                    EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                children: [
                  // Title + Export to Excel.
                  Row(children: [
                    Expanded(child: Text(l.auTitle, style: t.headlineMedium)),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _export(context, d),
                      icon: const WasiatiIcon(svg: WasiatiIcons.download, size: 16),
                      label: Text(l.auExportExcel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.tokens.muted,
                        side: BorderSide(color: context.tokens.hairline, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _StatTiles(data: d),
                  const SizedBox(height: 20),
                  _UsersTable(users: d.users),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The prototype's "Export to Excel": build a CSV from the loaded table and save
  /// it (opens straight into Excel). A UTF-8 BOM keeps Arabic names intact there.
  Future<void> _export(BuildContext context, AdminUsersData d) async {
    final rows = <List<String>>[
      ['Email', 'Phone', 'Region', 'Role', 'Plan', 'Identity', 'Email verified', 'Comp', 'Last IP', 'Joined'],
      for (final u in d.users)
        [
          u.email,
          u.phone ?? '',
          u.region,
          u.role,
          u.plan ?? 'FREE',
          u.idVerificationStatus,
          u.emailVerified ? 'yes' : 'no',
          u.compTier ?? '',
          u.lastIp ?? '',
          u.createdAt,
        ],
    ];
    final csv = rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');
    final bytes = Uint8List.fromList(utf8.encode('﻿$csv'));
    try {
      await FileSaver.instance.saveFile(
        name: 'wasiati-users',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  static String _csvCell(String s) =>
      (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// The three headline stat tiles. Numbers come straight from the provider; the
/// deltas are honest (users/wills added in the last 7 days, and the share of
/// identities still in review) rather than the prototype's placeholder figures.
class _StatTiles extends StatelessWidget {
  final AdminUsersData data;
  const _StatTiles({required this.data});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    var newUsers = 0;
    for (final u in data.users) {
      final at = DateTime.tryParse(u.createdAt);
      if (at != null && at.isAfter(weekAgo)) newUsers++;
    }
    final total = data.total;
    final verified = data.statusCount('VERIFIED');
    final pending = data.statusCount('PENDING');
    final verifiedPct = total > 0 ? (verified * 100 / total).round() : 0;
    final reviewPct = total > 0 ? (pending * 100 / total).round() : 0;

    final tiles = [
      _StatTile(
          label: l.auStatTotalUsers,
          value: context.digits('$total'),
          foot: context.digits(l.auStatDeltaWeek(newUsers)),
          footColor: context.tokens.successInk),
      _StatTile(
          label: l.auStatSealedWills,
          value: context.digits('${data.sealedWills}'),
          foot: context.digits(l.auStatDeltaWeek(data.sealedWillsWeek)),
          footColor: context.tokens.successInk),
      _StatTile(
          label: l.auStatIdVerified,
          value: context.digits('$verifiedPct%'),
          foot: context.digits(l.auStatInReview(reviewPct)),
          footColor: context.tokens.muted),
    ];

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 560) {
        // IntrinsicHeight bounds the Row's cross-axis so `stretch` gives equal-height
        // tiles WITHOUT demanding infinite height — the row lives inside a ListView,
        // whose vertical extent is otherwise unbounded.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      }
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            tiles[i],
          ],
        ],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String foot;
  final Color footColor;
  const _StatTile({required this.label, required this.value, required this.foot, required this.footColor});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tokens.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.faint)),
        const SizedBox(height: 4),
        Text(value, style: t.headlineMedium),
        const SizedBox(height: 4),
        Text(foot, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: footColor)),
      ]),
    );
  }
}

/// User · Region · Plan · Identity. A four-column flex layout that adapts down to
/// mobile without a horizontal scroll (matching the prototype's grid).
class _UsersTable extends StatelessWidget {
  final List<AdminUser> users;
  const _UsersTable({required this.users});

  static const _userFlex = 13;
  static const _regionFlex = 7;
  static const _planFlex = 8;
  static const _idFlex = 8;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: context.tokens.raised, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(flex: _userFlex, child: _HeaderCell(l.auColUser)),
          Expanded(flex: _regionFlex, child: _HeaderCell(l.auColRegion)),
          Expanded(flex: _planFlex, child: _HeaderCell(l.auColPlan)),
          Expanded(flex: _idFlex, child: _HeaderCell(l.auColIdentity, alignEnd: true)),
        ]),
      ),
      for (var i = 0; i < users.length; i++) _UserRow(user: users[i], zebra: i.isOdd),
    ]);
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final bool alignEnd;
  const _HeaderCell(this.text, {this.alignEnd = false});
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.muted),
    );
  }
}

class _UserRow extends ConsumerWidget {
  final AdminUser user;
  final bool zebra;
  const _UserRow({required this.user, required this.zebra});

  /// Grant or revoke a comped tier (POST|DELETE /admin/users/:id/comp) — the
  /// mechanism demo, QA and support accounts depend on. Until this was wired
  /// the endpoints existed with no way to reach them from the console.
  Future<void> _openComp(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    var tier = user.compTier ?? 'PREMIUM';
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.auCompTitle),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                l.auCompBody(user.email),
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: ctx.tokens.muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              // Raw tier enums, like the rest of the console: the identifier IS
              // the useful label here.
              DropdownButtonFormField<String>(
                value: tier,
                decoration: InputDecoration(labelText: l.auCompTierLabel),
                items: [
                  for (final t in const ['BASIC', 'STANDARD', 'PREMIUM', 'ULTIMATE'])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setLocal(() => tier = v ?? tier),
              ),
            ]),
          ),
          actions: [
            if (user.compTier != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: ctx.tokens.dangerInk),
                onPressed: () => Navigator.pop(ctx, 'revoke'),
                child: Text(l.auCompRevoke),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'grant'), child: Text(l.auCompGrant)),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final api = ref.read(adminUsersApiProvider);
    try {
      if (action == 'grant') {
        await api.grantComp(user.id, tier);
      } else {
        await api.revokeComp(user.id);
      }
      ref.invalidate(adminUsersProvider);
      if (context.mounted) {
        WasiatiSnack.success(context, action == 'grant' ? l.auCompGranted : l.auCompRevoked);
      }
    } on ApiException catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => _openComp(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: zebra ? context.tokens.raised.withValues(alpha: 0.4) : Colors.transparent,
          border: Border(bottom: BorderSide(color: context.tokens.hairline)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            flex: _UsersTable._userFlex,
            child: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: _UsersTable._regionFlex,
            child: Text(user.region, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          ),
          Expanded(
            flex: _UsersTable._planFlex,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(spacing: 4, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _PlanPill(plan: user.plan),
                // A comped account is flagged distinctly from its PAID plan —
                // conflating them would hide who is actually paying.
                if (user.compTier != null) _CompChip(tier: user.compTier!),
              ]),
            ),
          ),
          Expanded(
            flex: _UsersTable._idFlex,
            child: Align(alignment: AlignmentDirectional.centerEnd, child: _IdentityCell(status: user.idVerificationStatus)),
          ),
        ]),
      ),
    );
  }
}

/// Gold-outlined "Comp · TIER" pill: this account's access is granted, not paid.
class _CompChip extends StatelessWidget {
  final String tier;
  const _CompChip({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: WasiatiColors.brassGold),
      ),
      child: Text(
        context.l10n.auCompChip(tier),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.tokens.goldInk),
      ),
    );
  }
}

class _PlanPill extends StatelessWidget {
  final String? plan;
  const _PlanPill({required this.plan});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (plan) {
      case 'STANDARD':
        // greenInk, not bottleGreen: as type on a night card the raw brand green
        // is 1.59:1. The wash follows the ink so the pill keeps its shape.
        bg = context.tokens.greenInk.withValues(alpha: 0.12);
        fg = context.tokens.greenInk;
        label = l.auPlanStandard;
        break;
      case 'PREMIUM':
        bg = WasiatiColors.brassGold.withValues(alpha: 0.18);
        fg = context.tokens.goldInk;
        label = l.auPlanPremium;
        break;
      case 'ULTIMATE':
        bg = WasiatiColors.bottleGreen;
        fg = WasiatiColors.onDark;
        label = l.auPlanUltimate;
        break;
      case 'BASIC':
        bg = context.tokens.muted.withValues(alpha: 0.14);
        fg = context.tokens.muted;
        label = l.auPlanBasic;
        break;
      default:
        bg = context.tokens.raised;
        fg = context.tokens.faint;
        label = l.auPlanFree;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _IdentityCell extends StatelessWidget {
  final String status;
  const _IdentityCell({required this.status});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    late final Color color;
    late final String label;
    switch (status) {
      case 'VERIFIED':
        color = context.tokens.successInk;
        label = l.kycStateVerified;
        break;
      case 'PENDING':
        color = context.tokens.warningInk;
        label = l.kycStatePending;
        break;
      case 'REJECTED':
        color = context.tokens.dangerInk;
        label = l.kycStateRejected;
        break;
      default:
        color = context.tokens.faint;
        label = l.kycStateUnverified;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))),
    ]);
  }
}
