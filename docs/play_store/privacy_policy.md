# Rx Savings Watch — Privacy Policy

**Effective date:** November 27, 2026
**Developer:** Dangling Dice Studios™ ("we", "us")
**Contact:** support@danglingdicestudios.com

This policy explains what information the Rx Savings Watch app (Android) and website (rx.dangling-dice-studios.com) handle, why, and the choices you have. Rx Savings Watch is an independent app and is not affiliated with, endorsed by, or representing the FDA, NIH/NLM, CMS, HHS, or any government agency.

## 1. The short version

- **No accounts.** You never create an account, log in, or give us your name, email, or phone number to use the app.
- **Your medication list stays on your device.** Your medication cabinets, reminders, refill dates, supplements, notes, and settings are stored only on your phone (or in your browser on the website).
- **Some lookups need our server.** To check for generic launches, shortages, and prices, the app sends public drug codes to our server. These requests carry no name, account, or device ID.
- **No ad networks, no analytics SDKs, no cookies, no selling of data.**

## 2. Information stored only on your device

The following stays on your device and is never sent to us: medication cabinets and caregiver cabinet names, medication reminders and "Taken Today" status, refill dates and supply information, OTC and supplement lists, the copay amount you type into the savings calculator, your saved ZIP code, and your app settings.

You can erase all of it at any time in **Settings → Erase My Medication List**, by clearing the app's storage, or by uninstalling the app (or clearing site data in your browser).

## 3. Information sent to our server

| What is sent | When | Why | Stored? |
|---|---|---|---|
| **Drug codes (RxNorm RxCUIs)** for the medications in your active cabinet, plus a few decoy codes for common medications | When the app checks for updates | To return current FDA generic availability, shortage, and price information | No. Used only to answer the request. |
| **Medication search terms** | When you search for a medication | To find the medication in our catalog or in public FDA/NLM databases | No. Your search text is never saved. If a medication is new to our catalog, we add the official public drug record, not your search text. |
| **A drug code** | When you open savings options for a medication | To return pharmacy and savings links for that medication | No |
| **Data-quality reports** (a drug code plus a fixed issue category, such as "price looks off") | Only if you choose to report a data problem | To find and fix catalog errors | Yes, without any information about who sent it |
| **Your 5-digit ZIP code** (never your medication) | Only if you enter a ZIP to see local pharmacies | To list licensed pharmacies near you from the public CMS NPI Registry | No. Pharmacy results are cached by ZIP for up to 24 hours, not linked to you. |
| **Sponsored pharmacy taps** (which sponsored pharmacy and whether you tapped Call, Transfer, or Website) | When you tap a button on a sponsored pharmacy listing | To give sponsoring pharmacies a total count of taps | Only as a running total per pharmacy. No record of individual taps is kept. |
| **Reviews and feedback** (star rating, category, your message, and platform such as "android" or "web") | Only if you send a review in the app | To read and respond to feedback | Yes. Stored privately on our server and emailed to our support inbox. Reviews are never displayed publicly. |

**Please do not include your name, contact details, or personal health details in a review message.** If you do, we will treat it as part of your review.

We also keep **daily aggregate counts** (for example, total searches per day). These are plain numbers with no information about individual users.

## 4. IP addresses and network information

Like any internet service, our server and hosting provider receive your device's IP address when the app connects. We use IP addresses only temporarily, in memory, for rate limiting, abuse prevention, and preventing duplicate counts of sponsored-pharmacy taps (kept for up to 24 hours). We do not store IP addresses in our database or link them to drug codes, searches, ZIP codes, or reviews. Our hosting provider may keep standard network and request logs for a short period for security and reliability.

## 5. Camera and the QR transfer scanner (Android)

The Android app can use your camera to scan a QR code when you move your medication cabinet from another device. Camera images are processed on your device and are never saved or uploaded by us. The scanner uses **Google ML Kit**, which Google says may send diagnostic and usage information to Google. This includes device and app information (such as device model, OS version, and app version), performance metrics, error codes, and a per-installation identifier that is not intended to identify you or your device. This happens only when you use the scanner. See Google's ML Kit data disclosure: https://developers.google.com/ml-kit/android-data-disclosure

Cabinet transfer links (`…/#import=…`) put drug codes after the `#` in the link. Web browsers do not send that part of a link to any server, and the app removes it from the address bar after import.

## 6. Website-only features

- **Browser notifications (optional).** If you turn on notifications on the website, your browser gives us a push subscription (an endpoint address and encryption keys from your browser's push service). We store it only to send public generic-launch alerts, which are the same for everyone and contain nothing about your medications. You can turn notifications off in your browser settings at any time.
- **Tip jar.** The optional "Leave a Tip" link opens Buy Me a Coffee, which handles any payment under its own privacy policy. We never see your payment details.
- **Pharmacy and clinic partner program (businesses only).** Businesses that apply on our Partners page give us business contact information: business name, contact name, work email, phone, address, website, service ZIP codes, and optionally an NPI number. We use this to review applications, publish approved sponsored listings, verify NPI numbers with the public CMS NPI Registry, and manage billing. Payments are processed by Stripe, and we never receive full card details. Partner records are kept while the partnership is active and as needed for billing and legal records.

## 7. Advertising

The app shows **"Sponsored Local Partner (Ad)"** listings for local pharmacies that pay a flat monthly fee to appear for specific ZIP codes. These listings are chosen only by the ZIP code you enter, never by your medications or any profile of you. We do not use ad networks, advertising IDs, or tracking for advertising.

## 8. Links to other websites

The app links to third-party pharmacy and savings sites (such as GoodRx, SingleCare, Cost Plus Drugs, and Amazon Pharmacy) and to official government data sources. When you tap a link, that site's own privacy policy applies. We send no personal or device identifiers with these links, and we ask your browser not to send referrer information. As an Amazon Associate, we earn from qualifying purchases. Amazon links include our affiliate tag but no information about you.

## 9. Service providers and public data sources

- **Railway**: hosts our server
- **Resend**: delivers review messages to our support inbox
- **Google ML Kit**: QR scanner on Android (see section 5)
- **Stripe**: payment processing for business partners only
- **QR Server (api.qrserver.com)**: generates the QR code image on printable partner counter flyers (business partners only)
- **Public government data services**, queried by our server without any information about you: openFDA and Drugs@FDA, NLM RxNorm and DailyMed, CMS NADAC (data.medicaid.gov), and the CMS NPI Registry

We do not sell or rent personal information, and we do not share it for cross-context behavioral advertising.

## 10. Security

All communication between the app and our server is encrypted with HTTPS. Administrative functions require a secret key. Because we do not have accounts and do not link lookups to individuals, there is no profile of you on our server to expose.

## 11. Data retention and deletion

- **On your device:** kept until you erase it (see section 2).
- **Reviews:** kept until we no longer need them to respond to and improve the app, or until you ask us to delete them.
- **Data-quality reports and aggregate counts:** kept to maintain catalog accuracy and service statistics. They contain no information about who sent them.
- **Browser push subscriptions:** kept until you unsubscribe or your browser's push service reports the subscription as expired.

To ask us to delete a review or ask about your data, email **support@danglingdicestudios.com**. Because we do not have accounts and most server data is not linked to any person, we may not be able to identify data that belongs to you. If you tell us roughly when you sent a review and what it said, we will find and delete it.

## 12. Your privacy rights

Depending on where you live (for example, California or the EU/UK), you may have rights to access, correct, delete, or object to the processing of your personal information. Contact us at support@danglingdicestudios.com and we will respond within the time required by law. We will not discriminate against you for exercising these rights.

## 13. Health information

Rx Savings Watch is a consumer information tool. It is not a healthcare provider or health plan, and it is not a HIPAA-covered entity. It does not provide medical advice. Always confirm medications, dosages, and generic substitutions with your doctor or pharmacist.

## 14. Children

Rx Savings Watch is intended for adults and is not directed to children under 13. We do not knowingly collect personal information from children. If you believe a child has sent us information, contact us and we will delete it.

## 15. Changes to this policy

If we change this policy, we will update the effective date above and, for significant changes, give notice in the app or on our website.

## 16. Contact

Dangling Dice Studios™
Email: support@danglingdicestudios.com
