-- The death certificate a claim was filed on could not be opened by the admin reviewing it.
--
-- `certificateFileUrl` stores ${APP_BASE_URL}/files/<fileId>/download. The only route of
-- that shape is FilesController.download, which is JWT-guarded and owner-scoped: it
-- resolves the row and refuses unless `file.userId === callerId`. Claim uploads are
-- attributed to the DECEASED owner, so no admin can ever be that caller. The reviewer was
-- approving on evidence the system would not show them.
--
-- Keeping the file id (not just the URL) lets the server resolve the object on the
-- reviewer's behalf through an explicitly admin-scoped route, rather than relaxing the
-- owner check on the general download path.
--
-- Nullable, and backfilled below rather than defaulted: the URL is always server-derived
-- by DeathClaimsService.certificateUrl(), so the id is recoverable from existing rows.
ALTER TABLE "DeathClaim" ADD COLUMN "certificateFileId" TEXT;

-- Backfill from the derived URL: .../files/<id>/download. Only rows matching that exact
-- shape are touched; anything else stays NULL and the reviewer is told the certificate
-- cannot be resolved, which is the honest answer.
UPDATE "DeathClaim"
SET "certificateFileId" = substring("certificateFileUrl" from '/files/([^/]+)/download')
WHERE "certificateFileUrl" ~ '/files/[^/]+/download$';
