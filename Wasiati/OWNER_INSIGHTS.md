# Owner Insights — "How is my business doing?"

The secure building block is live: **`GET /admin/metrics/summary`** — ADMIN (owner) only,
returns KPIs + a `headline` sentence meant to be read aloud. Every channel below just
reads that one endpoint.

## 🎙️ Siri ("how is my business doing") — owner only, top encryption
**How it works:** an **iOS App Intent / Siri Shortcut** calls `/admin/metrics/summary`
and speaks the `headline` ("You have 42 active subscriptions and about $1,250 MRR. 5 new
sign-ups this week…").

**"Only me, no one else" is enforced at four layers:**
1. **Role** — endpoint requires the ADMIN (owner) account; a 403 for anyone else (verified).
2. **Device credential** — the owner's token lives in the **iOS Keychain**, and the
   Shortcut/App Intent is gated behind **Face ID / Touch ID** every invocation.
3. **Transport** — **TLS 1.3 + HSTS** (Cloudflare Full-Strict), optionally **certificate
   pinning** in the app so a stolen network can't MITM it.
4. **No PII** — the summary is aggregate only; even if intercepted it exposes no customer.

**To build (future, needs the iOS app + Apple config):** add an App Intent
`BusinessStatusIntent` in the Flutter iOS runner (or a small native extension) that reads
the Keychain token, calls the endpoint, and returns `headline` as the spoken response;
donate it to Siri so "Hey Siri, how is my business doing?" triggers it.

## 📊 Other ways to get sales updates (recommended, ranked)
All reuse the same endpoint + our existing infra (BullMQ, Twilio, FCM, mail):
1. **Daily/weekly email digest** — a scheduled BullMQ job emails the headline + KPIs each
   morning. *Lowest effort — we already have BullMQ + mail.*
2. **WhatsApp or SMS digest** — same job via **Twilio** (already integrated) texts you the
   headline daily. Great for a quick glance.
3. **Push notification (FCM)** — daily summary, plus **threshold alerts** (new Ultimate
   subscription, a payment went past-due, a churn) pushed the moment they happen.
4. **Private Slack/Discord webhook** — post KPIs to an owner-only channel; nice history.
5. **Admin dashboard card** — surface the same summary at the top of the admin console
   (no new backend needed — the endpoint already returns it).
6. **Threshold/event alerts** — beyond digests, alert on the events that matter
   (first Ultimate sale of the day, MRR crosses a milestone, KYC rejection spike).

**My recommendation:** start with **#1 (daily email)** + **#3 threshold push** — cheapest,
and covers both the "morning glance" and "tell me the instant something important happens."
Siri is a lovely on-top layer once the iOS app ships.
