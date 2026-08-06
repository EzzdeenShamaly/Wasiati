# Backup, restore, and what "erased" actually means

**Status: NOT YET IMPLEMENTED.** There are no Postgres backups today — single region, S3
versioning as the only file safety net. This document is the design and the runbook, to be
executed in Phase 2 (blocked on the AWS account). It is written first because, for this
product, **losing a will is a worse failure than failing to erase one**, and the 29 Jul
best-practice benchmark found that priority inverted: effort was going into making
hypothetical future backups erasable while the backups that should exist did not.

---

## 1. The retention number is a product decision, not an ops default

Backup retention sets two things at once, and they pull in opposite directions:

- **How much data loss a disaster costs** (longer window = more recovery options).
- **When erased data is actually gone.** A purge deletes from live systems immediately, but
  the deceased's rows sit in every base backup and WAL segment taken before it. So the
  honest erasure date is **purge + backup retention**, not the purge itself.

That second point is the one nobody writes down, and it is exactly what a regulator asks.
The ICO's "put beyond use" position accepts a backup lag provided it is bounded, the data
is not used, and **you tell people the number**. So pick it deliberately:

| | Value | Why |
|---|---|---|
| **RDS PITR retention** | **7 days** | §25's figure. Long enough to notice and recover from a bad migration or a deletion incident; short enough that "erasure completes within 7 days of the purge" is a sentence you can put in the privacy notice without embarrassment. |
| **S3 noncurrent version expiry** | **14–30 days** | Required by §26 to clear the orphan reaper's delete markers. Same disclosure logic. |
| **Manual snapshot before every migration** | kept 30 days | The circuit breaker rolls code back in 3 minutes but cannot un-drop a column. |

**Action when this is implemented:** update the privacy notice and the death-claim UX to
state the real numbers, replacing any unqualified "permanently deleted". The tombstone
wording in `DataPurgeLog` should likewise read *"live copies erased and verified; residual
backup copies expire by <date>"* once backups exist. Today, with no backups, the
unqualified claim happens to be true — which is precisely why it must be revisited on the
day backups are switched on.

---

## 2. What is backed up, and what can never be

| Asset | Mechanism | Recovery |
|---|---|---|
| Postgres (wills, heirs, assets, audit) | RDS automated backups + PITR | Any second within the retention window |
| Uploaded documents & videos (S3) | Versioning + Intelligent-Tiering | Previous version, until noncurrent expiry |
| Infrastructure definition | Terraform state in a **versioned** S3 bucket | Re-apply |
| Application image | ECR, last 10 images, **SHA-tagged** | Roll back to a revision (never rebuild — the Dockerfile installs unpinned ranges) |
| **A user's vault passphrase** | **NOTHING — by design** | **Impossible.** The vault is client-side end-to-end encrypted; the server holds ciphertext and a wrapped key it cannot open. No backup can help. Say so in the UI *before* they store anything. |

> There is **no server-side vault key** to escrow. A `VAULT_ENCRYPTION_KEY` variable was
> once documented as a "server-side wrapping key"; it was verified to have no reader
> anywhere in the codebase and was removed (29 Jul 2026). Do not reintroduce it — it
> implied a control that does not exist.

---

## 3. Restore runbook

Fill in `<db-id>`, `<bucket>` at implementation time. Every command is deliberately
explicit rather than wrapped in a script: a restore is done rarely, under stress, and a
script nobody has read is not reassurance.

### 3a. Point-in-time restore (bad migration, mass deletion, corruption)

RDS PITR restores to a **new instance** — it never overwrites the running one, which is
what makes it safe to attempt.

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier <db-id> \
  --target-db-instance-identifier <db-id>-restore \
  --restore-time 2026-07-29T13:45:00Z \
  --db-subnet-group-name <subnet-group> \
  --no-publicly-accessible
```

Then: verify the restored data **before** any cutover (§4), and only then repoint
`DATABASE_URL` via SSM and restart the service. Never flip the restored instance to
publicly accessible — reach it with SSM Session Manager port forwarding.

### 3b. Recover a deleted or overwritten S3 object

A delete on a versioned bucket only writes a delete marker, so the object is still there:

```bash
# List every version, including delete markers
aws s3api list-object-versions --bucket <bucket> --prefix "legacy-videos/<userId>/"
# Recover by removing the delete marker
aws s3api delete-object --bucket <bucket> --key "<key>" --version-id "<deleteMarkerVersionId>"
```

**This will not work for a purged estate, and that is intentional** — the posthumous purge
deletes every version *and* every delete marker by version id (§26). Purged data is
unrecoverable by design.

### 3c. Roll the application back

```bash
aws ecs update-service --cluster <cluster> --service <service> \
  --task-definition <family>:<previous-revision>
```

~2–3 minutes. Roll back to a **revision**, never by rebuilding an image.

---

## 4. The drill — quarterly, calendared, non-negotiable

An untested backup is a hope, not a plan. Once a quarter:

1. PITR-restore the latest into a scratch instance (§3a).
2. Point a local backend at it (`DATABASE_URL`, SSM port-forward) and boot.
3. **Open a sealed will and render its PDF.** Not "does the database exist" — does the
   product's core artefact still come out correctly?
4. Confirm `SELECT count(*)` on `Will`, `User`, `FileObject` is within expectation.
5. Delete the scratch instance. Record the date, the restore duration, and anything that
   surprised you.

Costs roughly $1 of instance-hours. Step 3 is the one that catches real problems.

**Also drill this once:** restore a snapshot taken *before* a purge and confirm the purged
user is absent from the live system afterwards — i.e. that a restore cannot silently
resurrect erased records. The EDPB's 2026 erasure report found this to be one of the two
most common failures across surveyed controllers. When backups exist, the `DataPurgeLog`
tombstone becomes the natural suppression key: any restore runbook must re-apply pending
purges as a mandatory step.

---

## 5. Targets to state publicly

| | Launch tier (single-AZ) | HA tier (from first paying customers) |
|---|---|---|
| **RPO** | ≤ 15 min (PITR ~5 min in practice) | ~1 min |
| **RTO** | ≤ 4 hours | ~1 hour (automatic failover ~60 s) |

Region loss is a **pilot-light** story: enable RDS cross-region automated backup
replication and S3 Cross-Region Replication (~$5–15/mo early on); data is safe
immediately, compute is stood up from Terraform in hours.

> **Before enabling CRR, read §26.** S3 version deletions are **never replicated**, and
> delete markers are not replicated by default — so on the day replication is switched on,
> the posthumous purge silently stops reaching the replica and the tombstone becomes false.
> The purge must sweep every replica bucket (a config list and a loop over the erasure
> already built) in the same change that enables replication. Write the DR region into the
> privacy policy too, so the promise matches the topology.
