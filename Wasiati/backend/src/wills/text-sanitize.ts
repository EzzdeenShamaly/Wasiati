/**
 * Keeps free-text will fields (the personal message / opening) strictly plain
 * text — "no code in the box". Strips HTML/XML tags and stray angle brackets,
 * removes control characters (keeping newlines and tabs), collapses excessive
 * blank lines, and hard-caps the length. Mirrors the Flutter client sanitiser
 * (sanitizePlainText) so client and server agree; the server is authoritative.
 */
export function sanitizeWillText(input: string | null | undefined, maxLen = 5000): string {
  if (!input) return '';
  let s = String(input);
  s = s.replace(/<[^>]*>/g, ''); // drop tag-like sequences: <script>…</script>, <img …>, </p>
  s = s.replace(/[<>]/g, ''); // remove any remaining stray angle brackets
  // eslint-disable-next-line no-control-regex
  s = s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ''); // control chars except \t and \n
  s = s.replace(/\n{3,}/g, '\n\n'); // collapse 3+ newlines to a paragraph break
  s = s.trim();
  return s.length > maxLen ? s.slice(0, maxLen).trim() : s;
}
