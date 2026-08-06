import { sanitizeWillText } from './text-sanitize';

describe('sanitizeWillText (no code in the will body)', () => {
  it('strips script tags and their brackets', () => {
    const out = sanitizeWillText('Hello <script>alert(1)</script> world');
    expect(out).not.toContain('<');
    expect(out).not.toContain('>');
    expect(out).not.toContain('script');
    expect(out).toContain('Hello');
    expect(out).toContain('world');
  });

  it('removes HTML tags but keeps their inner text', () => {
    expect(sanitizeWillText('<b>bismillah</b>')).toBe('bismillah');
    expect(sanitizeWillText('a <img src=x onerror=alert(1)> b')).toBe('a  b');
  });

  it('strips stray angle brackets (no closing tag to match)', () => {
    expect(sanitizeWillText('2 < 3 always')).toBe('2  3 always'); // lone '<' removed
    expect(sanitizeWillText('a > b')).toBe('a  b'); // lone '>' removed
  });

  it('aggressively drops any complete angle-bracket span (defence over fidelity)', () => {
    // A '<' followed later by a '>' is treated as a tag and removed wholesale.
    expect(sanitizeWillText('1 < 2 and 3 > 2')).toBe('1  2');
  });

  it('preserves newlines and Arabic text', () => {
    const out = sanitizeWillText('بسم الله\nالحمد لله');
    expect(out).toBe('بسم الله\nالحمد لله');
  });

  it('collapses excessive blank lines', () => {
    expect(sanitizeWillText('a\n\n\n\nb')).toBe('a\n\nb');
  });

  it('caps length', () => {
    expect(sanitizeWillText('x'.repeat(6000)).length).toBe(5000);
  });

  it('handles null / empty', () => {
    expect(sanitizeWillText(null)).toBe('');
    expect(sanitizeWillText(undefined)).toBe('');
    expect(sanitizeWillText('   ')).toBe('');
  });
});
