import { ConfigService } from '@nestjs/config';
import { S3StorageProvider } from './s3-storage.provider';
import { UnconfiguredStorageProvider } from './unconfigured-storage.provider';

/**
 * The `configured` flag decides whether the module serves uploads or the honest 503,
 * so it must be true ONLY when a bucket is set. And the unconfigured adapter must
 * refuse rather than silently succeed.
 */
const cfg = (over: Record<string, string | undefined> = {}) =>
  ({ get: (k: string) => over[k] }) as unknown as ConfigService;

describe('S3StorageProvider.configured', () => {
  it('is true when STORAGE_BUCKET is set', () => {
    expect(new S3StorageProvider(cfg({ STORAGE_BUCKET: 'wasiati-us' })).configured).toBe(true);
  });

  it('is false with no bucket — so the module falls back to the 503 adapter', () => {
    expect(new S3StorageProvider(cfg()).configured).toBe(false);
  });
});

describe('UnconfiguredStorageProvider', () => {
  const svc = new UnconfiguredStorageProvider();

  it('reports itself as not configured', () => {
    expect(svc.configured).toBe(false);
  });

  // fail() throws synchronously (the methods aren't async), so assert on the throw
  // directly rather than a rejected promise.
  it('REFUSES to presign an upload rather than silently no-op', () => {
    expect(() => svc.presignUpload()).toThrow(/not available yet/i);
  });

  it('REFUSES to presign a download', () => {
    expect(() => svc.presignDownload()).toThrow(/not available yet/i);
  });
});
