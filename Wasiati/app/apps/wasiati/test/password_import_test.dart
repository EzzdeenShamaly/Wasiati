import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/vault/domain/password_import.dart';

/// The import runs entirely on-device before encryption, so the parser is the whole
/// correctness surface: both export formats, quoted fields, and skipping junk rows.
void main() {
  test('parses a Chrome export (name,url,username,password,note)', () {
    const csv = 'name,url,username,password,note\n'
        'GitHub,https://github.com,alice,hunter2,\n'
        'Bank,https://bank.example,alice@x.com,s3cr3t,main account\n';
    final r = parsePasswordCsv(csv);
    expect(r.entries, hasLength(2));
    expect(r.entries[0].label, 'GitHub');
    expect(r.entries[0].username, 'alice');
    expect(r.entries[0].password, 'hunter2');
    expect(r.entries[0].url, 'https://github.com');
  });

  test('parses an Apple export (Title,URL,Username,Password,Notes,OTPAuth)', () {
    const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
        'iCloud,https://icloud.com,bob,p@ss,,otpauth://x\n';
    final r = parsePasswordCsv(csv);
    expect(r.entries, hasLength(1));
    expect(r.entries[0].label, 'iCloud');
    expect(r.entries[0].username, 'bob');
    expect(r.entries[0].password, 'p@ss');
  });

  test('handles quoted fields with commas, newlines and escaped quotes', () {
    const csv = 'name,url,username,password\n'
        '"Acme, Inc.",https://acme.example,"al,ice","p""a""ss"\n'
        '"Multi\nline",https://m.example,u,pw\n';
    final r = parsePasswordCsv(csv);
    expect(r.entries[0].label, 'Acme, Inc.');
    expect(r.entries[0].username, 'al,ice');
    expect(r.entries[0].password, 'p"a"ss'); // "" -> "
    expect(r.entries[1].label, 'Multi\nline');
  });

  test('SKIPS rows with no password, and counts them', () {
    const csv = 'name,url,username,password\n'
        'Good,https://g.example,u,pw\n'
        'NoPass,https://np.example,u,\n'
        '\n'; // trailing blank line ignored, not counted as skipped
    final r = parsePasswordCsv(csv);
    expect(r.entries, hasLength(1));
    expect(r.skipped, 1);
  });

  test('falls back to the URL host when there is no name/title', () {
    const csv = 'url,username,password\nhttps://sub.example.com/login,u,pw\n';
    final r = parsePasswordCsv(csv);
    expect(r.entries[0].label, 'sub.example.com');
  });

  test('returns nothing for a CSV with no password column (not a password export)', () {
    const csv = 'foo,bar\n1,2\n';
    expect(parsePasswordCsv(csv).entries, isEmpty);
  });

  test('is tolerant of CRLF line endings and header casing', () {
    const csv = 'Name,Url,Username,Password\r\nSite,https://s.example,u,pw\r\n';
    final r = parsePasswordCsv(csv);
    expect(r.entries, hasLength(1));
    expect(r.entries[0].label, 'Site');
  });

  test('secretValue lays out URL / Username / Password, omitting blanks', () {
    final e = const ImportedPassword(label: 'X', username: 'u', password: 'pw', url: '');
    expect(e.secretValue, 'Username: u\nPassword: pw');
    expect(e.secretValue.contains('URL'), isFalse);
  });

  test('empty input yields no entries', () {
    expect(parsePasswordCsv('').entries, isEmpty);
    expect(parsePasswordCsv('   ').entries, isEmpty);
  });
}
