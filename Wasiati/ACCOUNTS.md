# Wasiati — Accounts & Subscriptions Checklist

Everything the platform touches, grouped by **when you need it**. "Wire" status = the
backend integration is built and degrades gracefully until credentials arrive.

## ✅ Already have
- **Domain + Cloudflare** — wasiati.com (DNS/TLS; also powers IP-based pricing geo)
- **Stripe** — test/sandbox keys loaded. **This is the payment processor** (DECISIONS §12,
  14 Jul 2026): the company incorporates in the **UAE** and charges cards with Stripe.
  Checkout.com is removed completely — they onboard enterprises only. Stripe is the **card
  processor only**; our own subscription engine stays behind `PaymentProviderPort`.
- **Google OAuth** — web client configured (⚠️ rotate the secret before production)

## 🔓 Unblocks features already built (get first)
| Account | For | Cost | Wired? |
|---|---|---|---|
| **Google Gemini API key** | AI conversational will-intake (Ameen) | usage (~pennies/session) | ✅ 503 until key |
| **Apple Developer** | Sign in with Apple **+ App Store** | $99/yr | ✅ 503 until creds |
| **Microsoft Azure (Entra ID)** | Sign in with Microsoft | free | ✅ 503 until creds |
| **Google Cloud** | Sign in with Google (+ mobile client IDs) | free | ✅ live in dev |

## 🆔 Identity / KYC
| Account | For | Cost | Wired? |
|---|---|---|---|
| **Sumsub** (the **built** vendor — `docs/DECISIONS.md` §7) | KYC for **US / CA** users | per-verification, no minimum | ✅ 503 until keys (`SUMSUB_*`) |

> ⚠️ **Vendor decision vs. what's built.** DECISIONS **§13** (15 Jul) replaces Sumsub with
> **Stripe Identity**, but no Stripe Identity adapter exists yet — `SumsubIdentityProvider` is
> still the only document-KYC implementation. Don't buy Sumsub credentials without first
> confirming which way you're going. Nafath (KSA) is unaffected either way.
| **Nafath** (NIC government onboarding) | KYC for **KSA** users — national identity | onboarding-based | ✅ 503 until onboarded |

> **Nafath is not self-serve.** Credentials + the exact API contract are issued by the
> **National Information Center** during government onboarding (apply as a registered KSA
> business via your commercial registration / Absher Business). The backend flow
> (initiate → user matches a number in the Nafath app → poll/callback → verified) is
> built and isolated so the endpoint/field names are a one-file reconcile at onboarding.

## 💳 Payments
| Account | For | Cost |
|---|---|---|
| **Stripe** (activate live, **UAE entity**) | Hosted Checkout Sessions, saved cards, `off_session` renewal PaymentIntents, refunds, signed webhooks (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`; plus the `PAYMENT_RETURN_HOSTS` allowlist) | per-txn fees |

> **Stripe is the card processor only** (DECISIONS §12). We deliberately do **not** adopt
> Stripe Billing — the subscription engine, billing cycle, promos and credit ledger are our
> own code behind `PaymentProviderPort`. Requires **UAE incorporation**; Checkout.com was
> dropped because they onboard enterprises only.

## 📣 Communications
| Account | For | Cost | Simpler alt |
|---|---|---|---|
| **Twilio** | SMS MFA (+ WhatsApp later) | ~$0.008/SMS + number | — |
| **AWS SES** *or* **Resend** | Transactional email | SES $0.10/1k · Resend free→$20/mo | Resend |
| **Firebase (FCM)** | Push notifications | free | — |

## ☁️ Production hosting & data (deferred until cutover)
| Account | For | Cost (small launch) |
|---|---|---|
| **AWS** (or equivalent) | Hosting + S3 regional buckets + Secrets Manager | ~$50–150/mo |
| **Managed Postgres** — RDS *or* Neon | Database | RDS ~$15–60/mo · Neon free→$19 |
| **Managed Redis** — ElastiCache *or* Upstash | Sessions/queues/cache | ~$15/mo · Upstash free→usage |

> ⚠️ **KSA data residency** is a real decision (AWS Bahrain/UAE, Google Cloud Dammam,
> Oracle Jeddah, or a local KSA cloud) — decide at cutover based on Saudi law.

## 📱 App stores (at launch)
| Account | Cost |
|---|---|
| **Apple Developer Program** | $99/yr (same as Apple sign-in) |
| **Google Play Console** | $25 one-time |

## 🩺 Monitoring (optional)
| Account | For | Cost |
|---|---|---|
| **Sentry** | Crash/error tracking | free dev → ~$26/mo |
| **Cloudflare** (have) | TLS/WAF | free → Pro $20/mo |

---
### Fastest path to a working demo
1. **Google Gemini** key → AI intake on.
2. **Apple** (Service ID/key) + **Azure** (client ID) → those sign-in buttons on.
3. **Rotate the Google secret**, add `localhost` origin (web) / mobile client IDs.
4. **Nafath** + **Stripe live** (needs the UAE entity) + **Sumsub keys** + everything under *Production* → the launch push.
