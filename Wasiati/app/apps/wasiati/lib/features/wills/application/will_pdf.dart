import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import 'wills_providers.dart';

/// Lets the user choose a shape and language, fetches the server-rendered PDF
/// (Arabic shaped correctly), and hands it to the platform share/print sheet.
///
/// The two formats and two languages are the spec's requirement (handoff §5): a
/// structured table listing or a narrative essay, in English or Arabic. The
/// endpoint is owner-scoped and needs the auth header, so bytes come via Dio.
/// When [format] and [lang] are supplied the sheet is SKIPPED: the caller already has the
/// owner's choice on screen (the will-preview toggles), and asking again could only produce
/// a download that disagrees with the document they just read.
Future<void> shareWillPdf(
  BuildContext context,
  WidgetRef ref,
  String willId, {
  String? format,
  String? lang,
  String display = 'percent',
}) async {
  final choice = (format != null && lang != null)
      ? (format: format, lang: lang)
      : await showModalBottomSheet<({String format, String lang})>(
          context: context,
          showDragHandle: true,
          builder: (_) => const _ExportSheet(),
        );
  if (choice == null || !context.mounted) return;

  try {
    final bytes = await ref.read(willsApiProvider).downloadPdf(
          willId,
          format: choice.format,
          lang: choice.lang,
          display: display,
        );
    await Printing.sharePdf(bytes: bytes, filename: 'wasiati-will-${choice.format}-${choice.lang}.pdf');
  } on ApiException catch (e) {
    if (context.mounted) WasiatiSnack.danger(context, e.message);
  } catch (e) {
    if (context.mounted) WasiatiSnack.danger(context, '$e');
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();
  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  // Narrative first and preselected (DECISIONS §29): the export should sound like a
  // will unless the owner deliberately chooses rows.
  String _format = 'essay';
  String _lang = 'en';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.exportTitle, style: t.titleLarge),
          const SizedBox(height: 16),

          Text(l.exportFormat, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          const SizedBox(height: 8),
          _Option(
            label: l.exportFormatEssay,
            sub: l.exportFormatEssaySub,
            selected: _format == 'essay',
            onTap: () => setState(() => _format = 'essay'),
          ),
          const SizedBox(height: 8),
          _Option(
            label: l.exportFormatTable,
            sub: l.exportFormatTableSub,
            selected: _format == 'table',
            onTap: () => setState(() => _format = 'table'),
          ),

          const SizedBox(height: 18),
          Text(l.exportLanguage, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _Pill(label: l.exportLangEnglish, selected: _lang == 'en', onTap: () => setState(() => _lang = 'en')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Pill(label: l.exportLangArabic, selected: _lang == 'ar', onTap: () => setState(() => _lang = 'ar')),
            ),
          ]),

          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, (format: _format, lang: _lang)),
            icon: const WasiatiIcon(svg: WasiatiIcons.download, size: 18),
            label: Text(l.exportDownload),
          ),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.sub, required this.selected, required this.onTap});
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? context.tokens.gold : context.tokens.hairline, width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20, color: selected ? context.tokens.gold : context.tokens.faint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(sub, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? WasiatiColors.bottleGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? WasiatiColors.bottleGreen : context.tokens.hairline),
        ),
        child: Text(
          label,
          style: t.bodyMedium?.copyWith(
            color: selected ? WasiatiColors.onDark : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
