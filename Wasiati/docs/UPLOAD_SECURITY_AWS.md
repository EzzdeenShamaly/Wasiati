# Upload & content-injection security — audit + AWS hardening

Covers the owner's concern: *users can type HTML/code into fields; uploaded video
needs a malware/ransomware check and sandboxing; one compromised user must not
affect others (we're deploying on AWS).*

## 1. "Code in the boxes" — text-field injection  ·  AUDITED, SAFE

Two independent layers stop stored HTML/script:

- **On write** — free-text will fields (`personalMessage`, draft `words`) pass
  through `sanitizeWillText()`: strips `<…>` tag sequences and stray angle
  brackets, removes control chars, caps length. Mirrored client-side; the server
  is authoritative.
- **On render** — the only place user text becomes HTML is the PDF (Puppeteer).
  Every interpolated leaf is escaped with `esc()`: heir names, asset labels,
  institutions, witness/trustee names, bequest names. Verified line-by-line.
- **Flutter** renders all text through `Text` widgets (no `innerHTML`), so the
  app UI is not an XSS sink.
- **F1 (fixed earlier)** — `beneficiaryName`/`notes` now length-capped in the DTO.

**Residual:** short string fields (names, labels) are NOT tag-stripped on write —
they rely on render-layer escaping, which is complete today. If any of them is
ever rendered into HTML somewhere new (an admin web console, an HTML email),
that sink must `esc()` too. Recommendation: extend `sanitizeWillText` (a
plain-text variant without the newline handling) to names/labels on write as
defence-in-depth. Low priority while the PDF is the only HTML sink.

## 2. Uploaded video / files — malware, spoofing, sandboxing

### What's already right
- **Direct-to-storage** presigned PUT — the file never streams through our API.
- **Per-user key isolation** — the key is SERVER-generated:
  `{prefix}/{ownerId}/{uuid}.{ext}`. The client can't choose the path, so it
  can't write into another user's namespace or traverse (`../`). Downloads
  additionally assert `key.split('/')[1] === ownerId`.
- **Content-type allow-list + size cap** per kind, pinned into the PUT signature
  (`signableHeaders: content-type`), plus a 1 GB/user quota re-checked at confirm.

### F3 — serve-time header pinning  ·  FIXED (this change)
`presignDownload` now pins the **response** `Content-Type` and
`Content-Disposition` on the presigned GET (`ResponseContentType` /
`ResponseContentDisposition`), overriding whatever the stored object claims:
- documents/images → `application/octet-stream` + `attachment` (force download);
- legacy video → its allow-listed `video/*` type + `inline` (plays, never executes).

So even a polyglot file whose bytes are HTML can never be served as `text/html`
from the bucket origin. No caller existed yet — the video-serve endpoint is
unbuilt — so this is safe-by-construction for when it ships.

### F4 — malware / ransomware scan  ·  TODO (needs infra + a migration)
There is **no antivirus scan today**. The AWS-native answer:

1. **Enable GuardDuty Malware Protection for S3** on the upload bucket. It scans
   every new object and writes a tag `GuardDutyMalwareScanStatus =
   NO_THREATS_FOUND | THREATS_FOUND`.
2. **Quarantine gate (code):** add `scanStatus` to `FileObject`
   (`PENDING | CLEAN | INFECTED`, default `PENDING`). An EventBridge rule → a
   thin webhook (`POST /files/scan-callback`, HMAC-signed) flips it from the tag.
   `presignDownload` refuses to serve anything not `CLEAN` (the `TODO` marker is
   already in `files.service.presignDownload`). Deferred here only to avoid a
   Prisma migration while the red-team workflow is still using the live backend;
   apply right after with:
   ```prisma
   scanStatus String @default("PENDING") // PENDING | CLEAN | INFECTED
   ```
3. Alternative if not using GuardDuty: S3 upload event → Lambda + ClamAV
   (`clamav-lambda`) writing to a **quarantine bucket**; only clean objects are
   copied to the served bucket.

### F5 — sandbox / cookieless origin  ·  TODO (deployment)
Serve all user-uploaded media from a **separate origin** (e.g.
`usercontent.wasiati.com` via its own CloudFront distribution + bucket), NOT the
app/API domain. Then even a file that somehow executes has no access to app
cookies, tokens, or same-origin APIs. Pair with a restrictive `Content-Security-Policy`
on that origin. This is the "sandbox" — isolation by origin, on top of the
per-user key isolation.

## 3. One compromised user must not reach another — AWS blast-radius

App layer already enforces this (per-user key prefix + ownership checks + the
per-region separate databases for residency). Add the infra guardrails so a
leaked presign or app bug can't cross tenants:

- **Bucket policy / IAM**: the app's role gets `s3:GetObject`/`PutObject` scoped
  with a condition so a presign can only ever address `…/${aws:userid}`-style
  prefixes — belt-and-braces on the app-generated key. No `s3:ListBucket` for the
  app role.
- **No public bucket ACLs**; Block Public Access ON; access only via presigned
  URLs (short TTL, already 300 s).
- **SSE-KMS at rest**; TLS in transit (enforced by bucket policy
  `aws:SecureTransport`).
- **Least-privilege task role** per service; secrets from AWS Secrets Manager,
  not env files, in production.
- Keep the **per-region database** split (residency) — a compromise in one
  regional deployment cannot read another region's estate data.

## Status
- F1 (bequest length) — fixed & committed.
- F3 (serve-header pinning) — fixed here; `tsc` clean, files tests 24/24.
- F4 (scan quarantine), F5 (sandbox origin), IAM scoping — specified above;
  F4's code half lands right after the red-team run (one migration).
