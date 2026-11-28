---
trigger: always_on
description: Clinical Fintech Design System rules for all Rx Savings Watch UI (Flutter Web, Android, and server-rendered HTML pages).
---

# DESIGN SYSTEM: CLINICAL FINTECH (RX SAVINGS & PRICE WATCH)

All UI work in `rx_savings_watch` (Flutter `app/lib/`, `app/web/index.html`, and Express server-rendered HTML in `server/src/`) MUST strictly follow these rules:

## 1. Core Aesthetic & Anti-Slop Rules
- **Aesthetic Direction:** Clinical Fintech. High-trust editorial light mode paired with high-density financial price tickers and tabular pharmacy comparisons.
- **Strictly Forbidden:**
  - NO purple, indigo, or neon cyan gradients.
  - NO glassmorphism (`backdrop-blur`), floating blobs, or heavy drop shadows (`shadow-lg`, `shadow-xl`).
  - NO generic 3-column symmetrical feature cards with centered icons.
  - NO emojis in UI copy, headings, or badges. Use crisp `1.5px` stroke icons only.
  - NO pill-shaped (`rounded-full`) primary action buttons. Use sharp, architectural `6px` corners for buttons and inputs, and `8px` for containers.

## 2. Color Tokens (4-Token Discipline + Semantic Savings)
- **Canvas Background:** `#FAF9F6` (Warm Alabaster — never sterile `#FFFFFF` page backgrounds).
- **Elevated Surface / Cards:** `#FFFFFF` with a crisp `1px solid #E5E4E0` hairline border (`#F3F2EE` for subtle hover states and table headers).
- **Primary Ink:** `#11181C` (Deep Charcoal Slate) for headings and primary data; `#59636E` (Muted Slate) for secondary labels and disclaimers.
- **Primary Brand Action:** `#0F5132` (Deep Clinical Forest Green) with `#FFFFFF` text for primary CTAs. Hover: `#0A3622`.
- **Semantic Savings / Alert Accents:**
  - **Price Drop / Best Deal:** `#ECFDF5` background, `#065F46` text, `1px solid #A7F3D0` border.
  - **Target Watch Active:** `#FEFCE8` background, `#854D0E` text, `1px solid #FDE047` border.
  - **Retail / Uninsured Baseline (Strikethrough):** `#9CA3AF`.

## 3. Typography & Data Hierarchy
- **Font Pairing:**
  - **Display & UI Sans:** `Plus Jakarta Sans` or `Inter`.
  - **Prices, NDC Codes, & Timestamps:** `JetBrains Mono` or `Geist Mono` (`monospace`).
- **Scale & Tracking Rules:**
  - `h1` Hero Display: `40px–56px`, weight `600`, tight tracking `-0.035em`, line-height `1.08`.
  - `h2` Section Headers: `28px–32px`, weight `600`, tight tracking `-0.025em`, line-height `1.15`.
  - Body Copy: `15px–16px`, line-height `1.6`, constrained to `max-w-[60ch]`.
  - **Tabular Numbers (`tabular-nums` / `FontFeature.tabularFigures()`):** MANDATORY on every dollar amount, percentage drop, distance (`mi`), and dosage (`mg`) so price columns align vertically.
  - Micro-labels (e.g., `GENERIC EQUIVALENT`, `LAST CHECKED 4M AGO`): `11px`, uppercase, tracking `0.08em`, monospace.

## 4. Layout & Component Architecture
- **Hero Architecture (Split Utility, Not Marketing Fluff):**
  - Left column (`55%`): Tight value proposition + immediate, functional multi-parameter search (`Drug Name`, `Dosage/Form`, `ZIP Code`) above the fold.
  - Right column (`45%`): Live, interactive Price Watch Ticker preview card with real medication example, sparkline, and alert toggle.
- **Pharmacy Comparison Layout:**
  - Render pharmacy prices as a scannable, dense **Data Table / Row List** separated by `1px solid #E5E4E0` horizontal rules (never bulky stacked cards).
  - Highlight the lowest price row with a subtle `#ECFDF5` left accent bar (`4px solid #0F5132`), not a flashy badge.
- **Watchlist & Alert Controls:**
  - Clean inline range sliders or stepped target-price inputs paired with crisp toggle switches.
- **Motion & Micro-interactions:**
  - Transitions: `150ms cubic-bezier(0.16, 1, 0.3, 1)` on border colors and row backgrounds only. Never scale cards on hover.
