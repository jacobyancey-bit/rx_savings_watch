# Google Play Store Listing — Rx Savings Watch

Ready-to-paste copy and exact form answers for Google Play Console (`com.danglingdicestudios.rx`, `version 1.0.1+2` — keep in sync with `app/pubspec.yaml`).

> **Accuracy rule:** every claim here must match what the shipped Android build actually does. Do not
> advertise features that are not in the build (there is currently **no** pill-bottle / OCR scanner), and
> keep the Data Safety and Ads answers in sync with the code paths listed in section 2.

---

## 1. Main Store Listing

### App Name (≤ 30 chars)
`Rx Savings Watch` *(16 chars)*

### Short Description (≤ 80 chars)
`Track Rx & OTC meds, FDA generic launch alerts & reminders. No account needed.` *(78 chars)*

### Full Description (≤ 4,000 chars)
```text
Stop manually checking every few months to see whether a generic is finally available for your brand-name prescription. Rx Savings Watch is a free medication tracker and generic launch monitor that references publicly available U.S. healthcare datasets to help you stay informed.

KEY FEATURES
• 2-Signal Generic Launch Alerts
Many tools flag a generic the day it is approved on paper—months or years before pharmacies actually stock it. Rx Savings Watch checks for BOTH (1) an FDA approval with a therapeutic equivalence listing AND (2) commercial pharmacy distribution records before alerting you.

• Clear Pharmacist Substitution Guidance
See the generic name to ask about, whether a listing is marked A-rated (typically substitutable by a pharmacist) or may require a new prescription from your doctor, and known brand-name equivalents when viewing a generic.

• Dosage Forms & Strengths
Organized by dosage form (Oral Tablet, Extended-Release Capsule, Oral Solution, Injectable, Topical, Inhaler, etc.) so you can pick the prescription on your bottle.

• Medication Reminders & OTC / Supplements
Set daily, specific-day, or monthly reminders with optional discreet lock-screen mode (hides medication names on notifications), track Taken Today, and organize vitamins or over-the-counter items alongside prescriptions.

• Caregiver Multi-Cabinet Support
Managing medications for aging parents, children, or other family members? Create separate medication cabinets on your device with isolated lists and labeled reminders—no account required.

• Drug Shortage Monitoring
Get notified when your medication's dosage form appears in publicly listed U.S. drug shortage records.

• Local Pharmacies by ZIP (Optional)
Enter a 5-digit ZIP to see licensed retail pharmacies from the public CMS NPI Registry. Some listings may be clearly labeled sponsored local partners.

PRIVACY BY DESIGN
• No account, no login, no email required. No ad SDKs or analytics trackers.
• Your medication list, cabinets, and reminders are saved on your device.
• To check for generic and shortage updates, the app sends public drug codes to our server—never your name, account, or device ID—and adds a few decoy common medications to each check.
• Move your cabinet to a new device anytime with a QR code or private transfer link.

PRICE INFORMATION
Where shown, price comparisons use CMS NADAC pharmacy acquisition benchmarks for the same strength and dosage form. They are not the price you will pay; your cost depends on your pharmacy and coverage.

GOVERNMENT DISCLAIMER & PUBLIC DATA SOURCES
Rx Savings Watch is an independent application developed by Dangling Dice Studios. It is NOT affiliated with, endorsed by, sponsored by, or representing the FDA, NLM, CMS, or any U.S. government agency.

Public reference data displayed in this app is sourced from:
• FDA Orange Book: https://www.accessdata.fda.gov/scripts/cder/ob/
• Drugs@FDA: https://www.accessdata.fda.gov/scripts/cder/daf/
• openFDA (NDC & Shortages): https://open.fda.gov/
• FDA Drug Shortages: https://www.accessdata.fda.gov/scripts/drugshortages/
• NLM RxNorm: https://www.nlm.nih.gov/research/umls/rxnorm/
• NLM DailyMed: https://dailymed.nlm.nih.gov/
• CMS NADAC (Medicaid): https://data.medicaid.gov/
• CMS NPI Registry: https://npiregistry.cms.hhs.gov/

Informational only — not medical, clinical, or pharmacy advice. Always verify prescriptions, dosages, and generic substitutions with your prescribing doctor or licensed pharmacist.
```

### Graphics checklist
- **Feature graphic:** `feature_graphic_1024x500.png` — 1024×500, 24-bit RGB PNG, **no alpha** (Play rejects transparency).
  ⚠️ The current artwork contains the text "Zero Data Collected", which contradicts the Data Safety answers below. Re-export the artwork with different wording (e.g. "No Account Needed") before uploading.
- **App icon:** `app_icon_512x512.png` — 512×512, 32-bit PNG.

### Category & Contact Details
- **App category**: `Medical` (or `Health & Fitness`)
- **Tags**: `Medication reminder`, `Pharmacy`, `Health`, `Prescriptions`
- **Support Email**: `support@danglingdicestudios.com`
- **Privacy Policy URL**: `https://dangling-dice-studios.com/rx-savings-watch/privacy.html`
  ⚠️ The hosted privacy policy must describe the same data flows as the Data Safety form below (drug codes for update checks, optional ZIP lookup, optional reviews forwarded by email, ML Kit diagnostics).

---

## 2. Play Console Policy & Declaration Answers

### Data Safety Form
**Does your app collect or share any of the required user data types?** → **Yes**

**Is all of the user data collected by your app encrypted in transit?** → **Yes** (HTTPS only)

**Do you provide a way for users to request that their data is deleted?** → Medication data is stored on-device and can be erased in Settings → *Erase My Medication List*. Reviews can be deleted on request via support@danglingdicestudios.com.

| Data type (Play category) | What & where in code | Collected | Shared | Processed ephemerally | Required / Optional | Purpose |
|---|---|---|---|---|---|---|
| **Location → Approximate location** | Optional 5-digit ZIP sent to `POST /api/b2b/local` for the CMS NPI pharmacy lookup | Yes | No | **Yes** | Optional | App functionality |
| **Health and fitness → Health info** | Drug codes (RxCUIs) sent by cabinet update checks (`POST /api/check-updates`), savings lookups (`POST /api/drugs/partners`), and data-quality flags (`POST /api/drugs/flag` — RxCUI + issue type are **stored** in `data_flags`, unlinked to any user) | Yes | No | **No** (flags are stored) | Required (core generic/shortage checks) | App functionality |
| **App activity → In-app search history** | Medication search terms (`POST /api/drugs/search`); used to answer the search, never stored | Yes | No | **Yes** | Required | App functionality |
| **App activity → App interactions** | Taps on a sponsored partner's Call / Transfer / Website buttons (`POST /api/b2b/event`: partner_id + event type only); only aggregate per-partner counters are kept | Yes | No | **Yes** (only an aggregate counter is incremented) | Optional | Analytics |
| **App activity → Other user-generated content** | Optional in-app review / feedback text + star rating (`POST /api/reviews`), stored on the server and emailed to support via a service provider (Resend) | Yes | No | No (stored) | Optional | App functionality |
| **App info and performance → Diagnostics** | Bundled Google ML Kit barcode scanning (`mobile_scanner` 7.5.0 → `com.google.mlkit:barcode-scanning`, QR transfer scanner): device/app info, latency, error codes | Yes | No | No | Optional (only when the QR scanner is used) | Analytics |
| **Device or other IDs → Device or other IDs** | Same ML Kit SDK: per-installation identifier "not intended to uniquely identify a user or physical device" | Yes | No | No | Optional (only when the QR scanner is used) | Analytics |

Notes for the reviewer field (optional):
- No account, name, email (except a review the user chooses to write), contact list, photos, device ID, or advertising ID is collected.
- Drug search terms that are not yet in the catalog are looked up server-side against public FDA/NLM APIs without any user identifier (anonymous data), so this is not counted as sharing.
- The bare ZIP is sent server-side to the public CMS NPI Registry without any identifier.

### Ads
- **Does your app contain ads?** → **Yes**
  - The app shows directly-sold, clearly labeled **"Sponsored Local Partner (Ad)"** listings for local pharmacies in the user's ZIP (`app/lib/screens/drug_detail_screen.dart`). No ad networks or ad SDKs are used.

### Health Apps Declaration
- **Select applicable health features**:
  - ✅ **Medication and pain management** *(medication tracking, reminders, and public FDA/CMS generic drug information)*
- **Is your app a medical device?** → **No** *(informational and personal organization tool only; does not diagnose, treat, cure, or prevent any disease).*

### App Access
- **All functionality is available without special access** → **Yes** *(no login or test credentials required).*

### Target Audience & Content Rating (IARC)
- **Target age group**: `18 and over`
- **Violence / Sexual / Gambling / Profanity**: None
- **User-to-user interaction**: None

### Payments
- No in-app purchases, subscriptions, or external payment links in the Android build. The optional tip jar and the B2B `/partners` sign-up (Stripe) are shown on the website only (`kIsWeb`-gated).

---

## 3. Release Notes (v1.0.1)
```text
Welcome to Rx Savings Watch!
• Track prescriptions & OTC supplements—no account needed
• 2-signal FDA + pharmacy generic launch alerts & substitution guidance
• Dosage form & strength selectors (Oral, ER Capsule, Solution, Injectable, etc.)
• QR code cabinet transfer between devices
• Caregiver multi-cabinet support and discreet medication reminders
• Reminders now stay on time across daylight saving changes
```
