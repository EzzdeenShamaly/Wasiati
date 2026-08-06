// Chromium is launched at BOOT, not on the first document.
//
// It used to launch lazily on first render. That handed the entire browser launch to
// whoever opened the will document first — seconds in the container, minutes on a cold
// dev machine — while the Flutter client gave up at its 20s receiveTimeout and drew
// "The preview could not be rendered. Please try again." So the document viewer appeared
// broken after every restart and worked on the retry, which is the most misleading shape
// a bug can take: the owner reported the viewer as broken, and every check of the
// endpoint afterwards (by then warm) returned a perfectly good PDF in ~2s.
//
// These tests pin the two properties that fix it: the warm-up FIRES at boot, and a
// failure to launch does NOT take the API down with it.

import { PdfRendererService } from './pdf-renderer.service';

describe('PdfRendererService — boot warm-up', () => {
  /** Waits for the fire-and-forget warm-up promise chain to settle. */
  const settle = () => new Promise((r) => setImmediate(r));

  it('launches the browser at boot, so the first reader does not pay for it', async () => {
    const svc = new PdfRendererService();
    const launch = jest
      .spyOn(svc as any, 'getBrowser')
      .mockResolvedValue({ connected: true } as any);

    svc.onModuleInit();
    await settle();

    expect(launch).toHaveBeenCalledTimes(1);
  });

  it('does not await the launch — boot must not block on Chromium', () => {
    const svc = new PdfRendererService();
    // A launch that never resolves stands in for a slow cold start.
    jest.spyOn(svc as any, 'getBrowser').mockReturnValue(new Promise(() => {}));

    // The hook returns void and must return promptly; if it ever became `async` and
    // awaited getBrowser(), Nest would hold the whole application boot behind Chromium.
    expect(svc.onModuleInit()).toBeUndefined();
  });

  it('survives a Chromium that cannot launch — documents fail, the API still boots', async () => {
    const svc = new PdfRendererService();
    jest.spyOn(svc as any, 'getBrowser').mockRejectedValue(new Error('no chromium here'));
    const logged = jest.spyOn((svc as any).logger, 'error').mockImplementation(() => undefined);

    // An unhandled rejection here would take the process down on a machine that simply
    // has no browser installed — the API has plenty to do that is not printing PDFs.
    expect(() => svc.onModuleInit()).not.toThrow();
    await settle();

    expect(logged).toHaveBeenCalledWith(expect.stringContaining('no chromium here'));
  });
});
