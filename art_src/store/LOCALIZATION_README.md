# Localised store listings: paste checklist

Texts: `listing_de.md`, `listing_fr.md`, `listing_es.md`, `listing_pt-BR.md`,
`listing_ja.md`, `listing_ko.md` (English source: `listing_en.md`). Every
length is checked with `python3`, and the count sits after each limit.
**The game itself stays English only.** Each description ends with a line that
says so, in that language. Keep it: it heads off 1★ "not in my language"
reviews.

Featuring and events texts: `featuring_nomination.md`, `in_app_events.md`.

## App Store Connect

Description, keywords and subtitle can only change with a **new app version**,
so add the localisations to the **1.0.1** version before you submit it.
Promotional text can change at any time.

1. **Add the languages:** My Apps → Narrow Haul → **App Information**. In the
   language menu at the top right (it shows "English (U.S.)"), choose **Add
   Language** and add each locale:

   | File | App Store localisation(s) |
   |---|---|
   | `listing_de.md` | German |
   | `listing_fr.md` | French (optionally French (Canada) too, same text) |
   | `listing_es.md` | Spanish (Spain) **and** Spanish (Mexico), same text |
   | `listing_pt-BR.md` | Portuguese (Brazil) |
   | `listing_ja.md` | Japanese |
   | `listing_ko.md` | Korean |

2. **App Information page, per language:**
   - **Name:** `Narrow Haul` in every locale.
   - **Subtitle:** from the file.
   - Privacy policy URL: the same English URL.
3. **The 1.0.1 version page, per language** (switch language at the top right):
   - Promotional Text
   - Description
   - Keywords (paste the line exactly, no spaces after commas)
   - Support URL and Marketing URL (same URLs as English)
   - Screenshots and previews: leave them empty. Each locale falls back to the
     English (primary) media, which is right for an English-only game.
4. **What's New:** the release notes need a text in each locale too. Use the
   English text if you have no translation; Apple accepts that.
5. Submit 1.0.1 as usual. All the localisations go into review with it.

### Keyword fields that stack in one storefront

Apple's *App Store localizations* reference lists the languages each storefront
can show. Several third-party ASO sources (MobileAction, AppTweak, AppFollow)
report that a storefront also **indexes the keywords** of those extra
languages. Apple's page doesn't say this, so treat it as likely, not certain.
What it means here:

| Storefront | Default + extra languages (Apple's table) | So these keyword fields may count there |
|---|---|---|
| United States | English (U.S.) + Spanish (Mexico), French, Korean, Portuguese (Brazil), Arabic, Chinese, Russian, Vietnamese | en-US **plus** the `es`, `fr`, `ko` and `pt-BR` keywords |
| Germany, France, Spain, Brazil, South Korea, Mexico and most of Latin America | the local language + **English (U.K.)** | local keywords **plus** English (U.K.) |
| Japan | Japanese + English (U.S.) | ja **plus** en-US |
| Canada | English (Canada) + French (Canada) | en-CA + fr-CA |

Two cheap wins:
- **Add an English (U.K.) localisation** with the English texts but a
  *different* keyword line. It's indexed in the UK and offered in every
  storefront above. Use words en-US doesn't have. Suggested line
  (99 chars, not used anywhere yet):
  `gravitar,lunar,landing,rocket,space,shuttle,tug,pod,expedition,asteroid,thruster,hover,mission,game`
- **Don't repeat words across stacked fields.** The `es`/`fr`/`ko`/`pt-BR`
  lines start with `thrust,lander` because Spanish, French, Korean and
  Brazilian players search those English genre words. In the US store those two
  are already in en-US. If you want more US reach, swap them in **Spanish
  (Mexico)** for two English words such as `gravitar,lunar` (a trade-off: less
  for Mexico, more for the US; your decision).

## Google Play Console

1. Narrow Haul → **Grow users → Store presence → Store listings** → the main
   listing → **Manage translations → Add your own translation text**.
2. Add the languages:

   | File | Play language(s) |
   |---|---|
   | `listing_de.md` | German – de-DE |
   | `listing_fr.md` | French – fr-FR (optionally fr-CA) |
   | `listing_es.md` | Spanish (Spain) – es-ES **and** Spanish (Latin America) – es-419; optionally es-US |
   | `listing_pt-BR.md` | Portuguese (Brazil) – pt-BR |
   | `listing_ja.md` | Japanese – ja-JP |
   | `listing_ko.md` | Korean – ko-KR |

3. Per language:
   - **App name** [30]: `Narrow Haul`
   - **Short description** [80]: from the file
   - **Full description** [4000]: the file's App Store description, unchanged
4. Graphics: leave them empty. Play falls back to the default-language feature
   graphic and screenshots.
5. Save. **Send changes for review** (Publishing overview). Listing changes
   don't need a new release.

Play has no keyword field. It indexes the title, short description and full
description, so those carry the search terms.

## Before pasting

- [ ] Decide the tilt wording (see the note in the handoff): every
  translation says "steer with the on-screen stick **or** tilt your phone like
  a wheel (pick in Settings)". That's true whichever is the default. The
  English listing still says tilt first.
- [ ] Optional native read-through (a friend, or the Fiverr/Gengo equivalent),
  especially of `ja` and `ko`. The texts were written to sound natural, but no
  native speaker has checked them.
- [ ] App Store: the localisations ride along with the **1.0.1** submission.

## Sources
- Apple, App Store localizations: https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations
- Keyword stacking (third-party): https://www.mobileaction.co/blog/app-store-cross-localization/ · https://www.apptweak.com/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store
