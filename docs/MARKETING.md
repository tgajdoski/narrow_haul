# Marketing & business model

Status: brainstorm, 2026-10-14. Store builds in review (Play closed test, TestFlight; production review held). Numbers are benchmark estimates until launch data replaces them. Play pre-registration was considered and skipped: it only pays off with weeks of promotion before launch, and it holds the production release.

## 1. Revenue model
What we sell: free with light ads (interstitials only after ≥4 deliveries and 300 s flown, every 3 clears, ≤4 a session; rewarded continue / 2× coins / ammo / trial), Full Game $4.99, Supporter $6.99, Fleet Pass $2.99, ammo packs $0.99 / $2.99. Both stores take 15% under $1M/yr (small business programs). No backend, so fixed costs are Apple $99/yr + Google $25 once.

Per install, net after the store cut:

| | Low | Mid | High |
|---|---|---|---|
| Payers | 1% | 2% | 3.5% |
| Net per payer | $5 | $6 | $7 |
| IAP per install | $0.05 | $0.12 | $0.25 |
| Ads per install | $0.03 | $0.08 | $0.20 |
| **LTV per install** | **~$0.08** | **~$0.20** | **~$0.45** |

| Installs | Low | Mid | High |
|---|---|---|---|
| 1k | $80 | $200 | $450 |
| 10k | $800 | $2k | $4.5k |
| 100k | $8k | $20k | $45k |

Daily players: at $0.03–0.10 a day each, 1k DAU ≈ $11k–36k/yr, but holding 1k DAU needs ~100–150 new installs every day. 10k+ DAU needs featuring, a viral clip or a publisher.

**Paid ads don't pay yet:** a casual-game install costs ~$0.85 (Android, worldwide) to ~$1.90 (Android, US), more on US iOS, against an LTV of ~$0.20. Paid ads are for measuring the game, not for making money, until LTV goes up 3–5×.

Benchmarks used: under 5% of mobile gamers ever pay; ad + IAP games earn $0.15–0.50 a day per daily player; US rewarded eCPM is ~$21–30 (much lower worldwide); the market's median D30 retention is under 1%.

## 2. Free credits and free store tools
- **Apple Ads:** $100 one-time credit for a new account linked to App Store Connect, once the app is live. Search Results campaigns on "cave flyer", "thrust", "lander", "gravity game".
- **Google Ads:** new-advertiser offer, usually spend $500 in 60 days → $500 credit (varies by country; shown in the account). Covers App campaigns for Android and iOS. It's credit, not cash, and some advertisers report credits being revoked, so read the terms.
- **Google Play:** no marketing credit, but free tools:
  - store listing experiments (icon, first screenshot, video)
  - promotional content (event cards)
  - the indie featuring form
  - Indie Games Festival / Accelerator (check eligible countries and dates)
- **App Store:**
  - **Featuring Nomination** in App Store Connect: launch, 1.1 (Game Center), every big update, 2–4 weeks ahead
  - In-App Events (weekly "Daily dispatch", a "Salvage Chaos weekend")
  - Product Page Optimization and Custom Product Pages
  - offer codes
- **Localized store listings** (DE, FR, ES, PT-BR, JA, KO + our own language): cheapest visibility boost there is.
- Featuring usually needs traction (~50k installs, 4.5★ is the quoted bar). Play Games achievements and leaderboards help, which is one more reason to ship 1.1.

## 3. Getting seen
1. **Short vertical clips** (TikTok, YouTube Shorts, Reels), 3–5 a week for the first month: near-miss tows, crashes, salvage curses (Spore Trip, Swarm Sting), the tractor-beam swing. Store links pinned.
2. **Nostalgia hook:** "Thrust / Gravitar / Lunar Lander, rebuilt for phones". r/AndroidGaming, r/iosgaming, r/indiegames, r/retrogaming (read each sub's self-promo rules), retro / Amiga / C64 forums.
3. **Story angle:** a solo dev whose kids approve every build (the *Approved by* credits).
4. **Press and YouTubers:** Pocket Gamer, Droid Gamers, Android Police, small mobile-indie channels, with promo codes. Pocket Gamer Connects **Big Indie Pitch** (free).
5. **Community:** Discord, daily-challenge leaderboard screenshots.
6. **Long shots, once there are reviews and retention numbers:** Google Play Pass, Apple Arcade, Netflix Games. Later a Steam page (Flutter desktop + keyboard already work).
7. **Paid, only after section 4's gates:**
   - Google App campaigns (cheapest start)
   - Apple Ads (highest-intent iOS traffic)
   - Meta Advantage+
   - TikTok Ads
   - ad networks (AppLovin / Unity / Mintegral, bigger budgets)
8. **Never** install farms, bought reviews or "guaranteed top 10" services. Both stores remove apps for it.

## 4. Invest or not
Invest time, not money, until the data says otherwise.
1. Launch, spend the free credits, aim for 1–3k installs. Firebase Analytics already has the funnel (`docs/ANALYTICS.md`).
2. After 2–4 weeks:
   - **D1 ≥ 35%, D7 ≥ 12–15%, D30 ≥ 4%:** hit candidate. Pitch publishers and featuring, and test a scaled paid budget.
   - **D1 25–35%:** solid niche game. Grow organically (clips, ASO, localization). Paid ads only where LTV > CPI.
   - **D1 < 25%:** fix onboarding and difficulty (tutorial funnel first), not marketing.
3. Raise LTV before buying traffic: how many players reach the Expeditions and the Full Game offer (`tut_10`)? Test $2.99 vs $4.99.

Realistic year 1 with no budget: 10k–100k installs ≈ $2k–20k. The downside is small, so a cheap launch test is clearly worth it. Big paid user acquisition isn't, yet.

## 5. Selling or partnering
- **No revenue:** asset sale on Flippa / Acquire.com (code + IP + store listings; both stores support app transfer), typically $500–5k.
- **With revenue:** mobile apps sell at ~2.9× annual profit (median), 5×+ for the top quartile. $20k/yr profit ≈ $40–70k. Sell after 6–12 months of verified numbers. Empire Flippers needs a revenue history.
- **Publisher deal instead:** we keep the IP. They pay for user acquisition, then split revenue ~50/50 after recouping it (the developer keeps ~58% with an advance, ~68% without).
  - Premium / skill publishers: Noodlecake (physics indie games), Crescent Moon, Snapbreak.
  - Hybrid-casual publishers (Kwalee, Homa, SayGames, Tapnation): run free CPI tests, but want broad casual appeal.
  - Pitch with a 30 s video + D1/D7 numbers.

## 6. Press kit and contacts
Built 2026-10-14: https://zafrk.com/narrow-haul/press, a `press` route on `website/index.html`. It shows a fact sheet, the pitch, a gameplay loop, 8 screenshots, the logo, the trailer, a download zip and a promo-code mail link. `tool/store/make_presskit.sh` builds `website/press/` from `art_src/store/`; the mp4s and the zip are gitignored, and `website/deploy.sh` builds them when they're missing. Re-run it after new screenshots or videos.

A press kit brings no traffic by itself. It makes outreach work: writers want assets in one click.

Contacts live in `docs/press_contacts.csv` (outlet, name, title, email, submission page, status, source). Only public editorial addresses are listed, no guessed personal emails. TouchArcade shut down in September 2024. Check the `check` rows on the outlet's site before sending.

## 7. Launch-week checklist
- [ ] Featuring Nomination submitted in App Store Connect (launch, then 1.1)
- [ ] Apple Ads account linked, $100 credit on a Search Results campaign
- [ ] Decide on the Google Ads spend-$500/get-$500 offer; if yes, one App campaign, tier-1 + cheap geos split
- [ ] Store listing experiment running (icon or first screenshot)
- [ ] 10+ clips recorded before launch (release build, `tool/store/make_videos.sh`)
- [ ] Reddit / forum posts drafted, one per community, spaced out
- [ ] Press kit page deployed (`website/deploy.sh`), then 20 outreach emails with promo codes (`docs/press_contacts.csv`)
- [ ] Firebase retention / funnel dashboard checked at day 3, 7, 14, 28 → section 4 decision

## Sources
- [Apple Ads promo credit](https://searchads.apple.com/help/basic/0041-apple-search-ads-promo-credit/)
- [Google Ads promotional offers](https://support.google.com/google-ads/answer/6388096?hl=en) · [credits revoked reports](https://searchengineland.com/advertisers-report-google-ads-credits-being-revoked-after-spending-488330)
- [CPI benchmarks (RocketShip HQ)](https://www.rocketshiphq.com/?p=5758)
- [Mobile game KPIs 2026](https://gamegrowthadvisor.com/blog/2026-03-17-mobile-game-kpis-benchmarks-2026/) · [ARPDAU benchmarks](https://blog.playio.co/arpdau-benchmarks-mobile-games) · [Appodeal casual benchmarks](https://gameindustrylibrary.com/documents/mobile-casual-benchmarks-report-2025/read)
- [Get featured on Google Play (Appfigures)](https://appfigures.com/resources/marketing/how-to-get-featured-google-play)
- [Flippa mobile app valuation](https://flippa.com/blog/mobile-app-valuation-key-methods-metrics-and-multiples-for-2025/)
- [Publisher deal vs self-publishing](https://blog.playio.co/game-publishing-deal-vs-self-publishing) · [Indie funding 2026](https://gamineai.com/blog/2026-indie-game-funding-landscape-grants-publishers-crowdfunding)
