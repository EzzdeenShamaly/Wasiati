// Parses a Chrome / Apple Passwords CSV export into vault entries, entirely on the
// device. The raw CSV is never sent anywhere — each entry is encrypted client-side
// before it touches the network (see VaultCrypto), and the user is told to delete
// the export file afterward.
//
// Chrome header:  name,url,username,password,note
// Apple header:   Title,URL,Username,Password,Notes[,OTPAuth]
// Column order/casing varies, so we map by header name, not position.

class ImportedPassword {
  final String label; // site/title — becomes the vault item label
  final String username;
  final String password;
  final String url;

  const ImportedPassword({
    required this.label,
    required this.username,
    required this.password,
    required this.url,
  });

  /// The plaintext stored (encrypted) in the vault for this entry.
  String get secretValue {
    final lines = <String>[
      if (url.isNotEmpty) 'URL: $url',
      if (username.isNotEmpty) 'Username: $username',
      if (password.isNotEmpty) 'Password: $password',
    ];
    return lines.join('\n');
  }
}

class PasswordImportResult {
  final List<ImportedPassword> entries;
  final int skipped; // rows that couldn't be understood / had no password
  const PasswordImportResult(this.entries, this.skipped);
}

/// Parses CSV text. Tolerant of quoted fields, embedded commas/newlines, CRLF, and
/// a trailing blank line. Rows with no password are skipped (counted).
PasswordImportResult parsePasswordCsv(String csv) {
  final rows = _parseCsvRows(csv);
  if (rows.isEmpty) return const PasswordImportResult([], 0);

  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iLabel = col(['name', 'title']);
  final iUrl = col(['url', 'website']);
  final iUser = col(['username', 'user']);
  final iPass = col(['password']);

  // Not a recognisable password export.
  if (iPass < 0) return const PasswordImportResult([], 0);

  final entries = <ImportedPassword>[];
  var skipped = 0;
  for (final r in rows.skip(1)) {
    if (r.every((c) => c.trim().isEmpty)) continue; // blank line
    String at(int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';
    final password = at(iPass);
    if (password.isEmpty) {
      skipped++;
      continue;
    }
    final url = at(iUrl);
    final label = at(iLabel).isNotEmpty ? at(iLabel) : (url.isNotEmpty ? _hostOf(url) : 'Password');
    entries.add(ImportedPassword(label: label, username: at(iUser), password: password, url: url));
  }
  return PasswordImportResult(entries, skipped);
}

String _hostOf(String url) {
  final u = Uri.tryParse(url);
  final host = u?.host ?? '';
  return host.isNotEmpty ? host : url;
}

/// Minimal RFC-4180-ish CSV reader: handles double-quoted fields, escaped quotes
/// (""), commas and newlines inside quotes, and CRLF line endings.
List<List<String>> _parseCsvRows(String input) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  final s = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  void endField() {
    row.add(field.toString());
    field = StringBuffer();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else {
        field.write(ch);
      }
    }
  }
  // Flush the final field/row if there's trailing content.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
