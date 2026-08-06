# Terraform (placeholder — not implemented)

Regional cloud infrastructure lives here. **Nothing is deployed yet**; this directory is a
committed placeholder so the module layout is fixed before Phase 2.

> **Rewritten 29 Jul 2026 because it had gone stale and actively contradicted current
> decisions.** It previously described four regional stacks including Qatar, Secrets
> Manager, and Sumsub — all superseded. Anyone following it would have built the wrong
> thing. If the topology changes, change this file in the same commit.

## Topology — ONE region at launch (`docs/DECISIONS.md` §25, superseding §0)

A single stack in **`ca-central-1`** serving **US + CA + KSA** via `SERVED_REGIONS`. No
market legally requires in-country storage (researched, §25), so the per-region shard model
stays *available* — `REGION` still pins one deployment to one database — but is not
exercised at launch. The `Region` enum is **KSA | CA | US**; Qatar was removed from the
schema.

Region #2 is then a new `envs/` directory and nothing else, which is why every module must
take `region_code` and `aws_region` as variables from day one.

## Planned modules

- `network/` — VPC, public subnets (no NAT Gateway — §25), security groups
- `data/` — RDS Postgres (region-pinned, private, `deletion_protection`) + **backups**
- `cache/` — ElastiCache Valkey (passkey challenges + BullMQ)
- `storage/` — S3 bucket per region, Intelligent-Tiering, versioning, **lifecycle rules**
- `secrets/` — **SSM Parameter Store** SecureString (NOT Secrets Manager: ~$12/mo for the
  ~30 variables this app reads, versus free — §25)
- `email/` — SES domain identity, DKIM, verified sender
- `compute/` — ECS Fargate service, ALB, ECR

## Constraints these modules MUST satisfy

Not style preferences — each is load-bearing for something already built:

1. **S3 versioning ON**, with `NoncurrentVersionExpiration` (14–30 d) and
   `ExpiredObjectDeleteMarker`. Versioning is currently the only recovery net for the
   orphan reaper, which decides what to delete by diffing storage against the database
   (§26). The lifecycle rules are what stop its delete markers accumulating forever.
2. **No S3 Object Lock in compliance mode and no legal hold with retention outliving the
   purge window; MFA Delete OFF.** Either would make the posthumous purge fail per-object
   forever while the tombstone claimed success (§26). A correctness constraint, not a
   preference.
3. **S3 CORS** must allow the presigned-PUT headers the client sends (`content-type`,
   `content-length`) — missing CORS is the most likely first-day failure.
4. **RDS PITR enabled** with a deliberate retention number — it is also the honest answer
   to "when is erased data actually gone?" (see `docs/BACKUP_RESTORE.md`).
5. **`region_code` / `aws_region` as variables** everywhere, so region #2 is a new `envs/`
   directory rather than a fork.

## Sequencing

Blocked on the AWS account existing (Phase 1 of the plan). Terraform is deliberately **not**
written ahead of that: it cannot be `validate`d or `plan`ned without an account, and
unvalidated infrastructure code is a liability rather than a head start.
