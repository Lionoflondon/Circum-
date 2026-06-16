# CIRCUM Design System V2 Plan

Status: Planning artifact  
Scope: UI inventory, design-system foundation, component plan, product personality rules, performance rules, and phased migration plan.  
Non-goal: This document does not authorize changing booking logic, pricing, Delivery IRIS, Gifts IRIS, Stripe, Firebase Functions, Firestore schema, rider workflows, admin workflows, audit logs, chat, notifications, or authentication.

## Preservation Rule

Future UI work must preserve every existing screen, field, CTA, validation rule, workflow, admin action, rider action, sender action, payment path, IRIS output, and audit event.

No current capability may be removed, reduced, hidden, redacted, simplified, bypassed, or weakened during a visual migration. Visual upgrades must wrap or restyle existing behaviour rather than replacing it.

## UI Inventory

The current web surface is primarily composed through `lib/web_sender_app.dart`, with supporting domain modules under `lib/app/*`, pricing under `lib/pricing/*`, and backend workflows under `server/functions/*`.

### Public Surfaces

| Surface | Current location / entry point | Migration need |
| --- | --- | --- |
| Homepage | `_LandingPage`, `_LandingFooter` | Apply V2 navigation, hero, CTA, footer, and public-card system. |
| Navigation | `_LandingPage`, `_WebAppMode` routing | Standardize tabs, top actions, mobile menu, and product entry points. |
| Login / signup | role-based mode selection and Firebase Auth flows | Standardize auth cards, validation messages, account-state banners. |
| Delivery booking | sender flow in `_PhoneStage` / sender booking sections | Apply booking cards, section headers, inputs, address fields, delivery options. |
| Tracking | sender delivery status/tracking sections | Apply timeline, rider card, IRIS/Vanguard cards, empty/error states. |
| Gifts | `_GiftsRequestPage` | Highest visual intensity; preserve Early Access Beta, Stripe Checkout, consent, anonymity, campaign safeguards. |
| Health+ | sender Health+ step plus `lib/app/health_plus/*` | Calm clinical premium styling with clear prescription safety copy. |
| Vanguard | Vanguard cards/PIN flows and `lib/app/vanguard/*` | Secure trust-focused visual language; preserve PIN and evidence flows. |

### Sender Surfaces

| Surface | Migration need |
| --- | --- |
| Sender dashboard | Replace placeholder-prone panels with V2 EmptyState, DeliveryStatusCard, and SectionHeader. |
| Booking history | Use TimelineCard and compact list cards with real data only. |
| Delivery details | Use DeliveryDetailLayout, PriceBreakdownCard, IRIS panel, Vanguard panel, proof-of-delivery panel. |
| Chat | Use ChatBubble, unread badges, loading and error states. |
| Notifications | Use NotificationCard, unread badge, mark-read controls. |
| Profile/settings | Use ProfileHeader, settings rows, security cards, saved-address components. |

### Rider Surfaces

| Surface | Migration need |
| --- | --- |
| Onboarding | Mobile-first glass cards, document upload cards, status panels. |
| Available jobs | JobCard with vehicle suitability, rank/trust indicators, payout, pickup/drop-off summary. |
| Job details | Preserve acceptance, PIN, discrepancy, weight verification, chat, navigation actions. |
| My jobs / schedule | Separate active, scheduled, completed states with strong empty/loading states. |
| Earnings / wallet | WalletCard set: available, pending, withdrawn, lifetime, withdrawal form. |
| Withdrawals | Consistent validation and masked bank details. |
| Rank progress | ProfileHeader plus rank progression card for Agent through Veteran. |
| Chat / notifications | Same shared chat and notification components, optimized for speed. |
| Profile/settings | Rider profile, security, vehicle, documents, onboarding status. |

### Admin Surfaces

| Surface | Migration need |
| --- | --- |
| Admin dashboard | Mission Control overview using grouped metric bands. |
| Rider management | Dense tables, profile drawer, rank controls, document review, audit visibility. |
| Delivery management | AdminTableWrapper, status badges, route/weight/vehicle/payment summaries. |
| Gifts admin | Separate standard/campaign/admin-only procurement sections; use operational density. |
| Approvals | Review queues for rider onboarding, Health+, disputes, Gifts. |
| Adjudication | Evidence panels, IRIS detail panels, decision controls. |
| Finance | Liability cards, wallet ledgers, withdrawal queue, payout summaries. |
| Audit logs | Dense readable tables with filters and export-friendly layout. |
| Support chat | Compact live chat drawer, support ticket actions, unread indicators. |
| Notifications | Admin alert panel with severity/status badges. |
| Settings | Admin roles, permissions, feature flags, operational config. |

## Design System V2 Foundation

### Principles

- Premium, trustworthy, intelligent, fast, and consistent.
- Dark premium base with controlled iridescent accents.
- Mobile-first layouts for sender/rider flows; dense but readable layouts for admin.
- Clear typography hierarchy and consistent spacing.
- Accessible contrast, visible focus states, predictable interactions.
- Glassmorphism should add depth, not obscure readability.

### Palette

| Token | Value | Use |
| --- | --- | --- |
| `deepBlack` | `#0D0D0D` | App base, page backgrounds. |
| `pearlWhite` | `#FFFFFF` | Primary text and high-contrast labels. |
| `softAqua` | `#A5F3FC` | Trust, IRIS, active accents. |
| `softLavender` | `#D8B4FE` | Premium accents, Gifts, selected states. |
| `softPink` | `#FBCFE8` | Iridescent highlights, Gifts moments. |
| `silver` | `#E5E7EB` | Secondary text, borders, rank accents. |

### Visual Treatment

- Core delivery: functional premium with moderate iridescence.
- Gifts: cinematic premium, strongest iridescence, strongest glass treatment.
- IRIS: intelligent glow, clear explanation hierarchy, no technical clutter for customers.
- Health+: calm, clinical, low shimmer, high clarity.
- Vanguard: secure, elite, strong trust signals.
- Rider: high contrast, minimal animation, speed-first.
- Admin: professional, readable, dense where required, minimal animation.

## Component Plan

| Component | Purpose | Primary use | Intensity |
| --- | --- | --- | --- |
| `AppShell` | Shared page chrome, mode-aware layout, safe areas. | Public, sender, rider, admin. | Normal dark UI. |
| `ResponsiveScaffold` | Mobile/tablet/desktop content constraints. | All main screens. | Normal dark UI. |
| `GlassCard` | Reusable individual content card. | Gift cards, delivery summaries, rider cards. | Light glass by default. |
| `GlassPanel` | Larger grouped section. | Forms, dashboards, admin panels. | Light glass; heavier only in Gifts/IRIS. |
| `PrimaryButton` | Main action CTA. | Booking, payment, submit, approve. | Moderate iridescent accent. |
| `SecondaryButton` | Secondary action. | Back, view details, alternate flows. | Normal dark UI. |
| `GhostButton` | Low-emphasis action. | Filters, optional controls, utility actions. | Normal dark UI. |
| `GlassInput` | Text, select, date, address inputs. | Booking, Gifts, Health+, profile. | Light glass. |
| `GlassModal` | Desktop modal container. | Review, payment summary, confirmations. | Normal glass. |
| `GlassBottomSheet` | Mobile modal/sheet. | Chat, action menus, confirmations. | Normal glass. |
| `SectionHeader` | Title, subtitle, optional action. | Every page section. | Normal dark UI. |
| `StatusBadge` | Status/risk/payment/rank label. | Jobs, admin tables, Gifts, Health+. | Colour by status. |
| `InfoBanner` | Important contextual message. | Private beta, warnings, verification. | Normal dark UI. |
| `IrisPanel` | Customer-safe IRIS explanation. | Booking, pricing, admin details. | Iridescent intelligent. |
| `TrustBadge` | Vanguard, verified rider, secure handoff. | Tracking, rider cards, delivery review. | Moderate trust accent. |
| `TimelineCard` | Delivery lifecycle, Gifts status, Health+ pickup. | Tracking/history/admin details. | Normal dark UI. |
| `JobCard` | Rider/admin delivery job summary. | Available jobs, accepted jobs, admin delivery list. | Rider: high contrast; admin: dense. |
| `DeliveryOptionCard` | Vehicle/speed/price option selection. | Sender booking. | Moderate iridescence on selected. |
| `WalletCard` | Earnings and liability metrics. | Rider earnings, admin finance. | Normal dark UI with green success accents. |
| `AdminTableWrapper` | Scroll-safe table shell with action wrapping. | Admin lists. | Low-glass professional. |
| `EmptyState` | Honest no-data state. | Dashboard, jobs, history, support. | Normal dark UI. |
| `LoadingState` | Loading spinner/skeleton. | Data fetches, payment starts. | Minimal. |
| `ErrorState` | Recoverable error state. | Firebase/API failures. | Clear warning. |
| `NotificationCard` | Notification row/card. | Notification center. | Normal dark UI. |
| `ChatBubble` | Role-aware message bubble. | Support/delivery/admin chat. | Functional, readable. |
| `ProfileHeader` | Identity, avatar, rank/status summary. | Sender, rider, admin user detail. | Normal dark UI. |

## Product Personality Rules

### Circum Core Delivery

- Functional premium, fast, clear.
- Moderate iridescence only on selected delivery options, IRIS, and trust moments.
- Avoid decorative complexity that slows booking.

### Gifts

- Magical premium, cinematic, emotional.
- Strongest iridescence and glass treatment.
- Keep exact contents confidential before delivery.
- Never make Gifts feel like a product catalogue.

### IRIS

- Intelligent and calm.
- Use subtle glow and clear evidence hierarchy.
- Customer copy should explain decisions without exposing internal scoring formulas.

### Health+

- Clinical premium, calm, legible.
- Less shimmer; more confidence, safety copy, and form clarity.

### Vanguard

- Secure, strong, elite.
- Emphasize chain of custody, PIN verification, proof, and trust.

### Rider

- Speed-first, high contrast, lightweight glass.
- Minimal animation.
- Prioritize job scanning, payout, vehicle suitability, and action clarity.

### Admin

- Professional, readable, dense when needed.
- Tables must remain clear.
- Very limited animation.
- Action buttons must wrap and never overlap.

## Performance Rules

- Reuse shared components rather than adding one-off page styles.
- Avoid nested blur layers.
- Maximum blur radius: `16px`.
- No background videos.
- No particle systems.
- No permanent animations on every screen.
- Disable off-screen animations.
- Respect reduced-motion preferences.
- Rider workflows prioritize speed over visual richness.
- Admin workflows prioritize readability over visual richness.
- Gifts receives the richest treatment, but only inside Gifts surfaces.

## Migration Plan

### Phase 1: Foundation Only

- Create shared Design System V2 tokens and components.
- Do not rewrite pages.
- Build components alongside current UI.
- Add snapshot/demo examples if the repo structure supports it.
- Acceptance: no functional UI or workflow behaviour changes.

### Phase 2: Public Homepage, Navigation, Shared Layout

- Apply `AppShell`, `ResponsiveScaffold`, `PrimaryButton`, `SecondaryButton`, and public footer styling.
- Keep all existing public routes and CTAs.
- Acceptance: homepage, Gifts entry, Health+, rider entry, and sender entry remain reachable.

### Phase 3: Booking Flow and IRIS Panels

- Apply `GlassInput`, `DeliveryOptionCard`, `IrisPanel`, `InfoBanner`, and `StatusBadge`.
- Preserve booking validation, pricing, address verification, Stripe, IRIS, Vanguard, scheduling, and vehicle selection.
- Acceptance: pricing outputs remain identical for regression cases.

### Phase 4: Sender Dashboard, Tracking, Chat, Notifications, Profile

- Apply `TimelineCard`, `ChatBubble`, `NotificationCard`, `EmptyState`, `ProfileHeader`.
- Remove visual placeholder feel without hiding any real states.
- Acceptance: no fake delivery data; all existing sender actions remain available.

### Phase 5: Rider Flow Light Upgrade

- Apply fast variants of `JobCard`, `WalletCard`, `ProfileHeader`, document upload rows, and empty/loading states.
- Preserve rider onboarding locks, vehicle eligibility, rank dispatch, acceptance, discrepancy reporting, wallet, and withdrawals.
- Acceptance: rider can scan and act faster; no workflow is removed.

### Phase 6: Admin Practical Upgrade

- Apply `AdminTableWrapper`, compact `StatusBadge`, dense `GlassPanel`, and action wrapping.
- Keep admin data density and all actions.
- Acceptance: no admin action disappears; tables remain readable on laptop widths.

## Required Regression Checks For Any Future UI Migration

- Sender can create delivery, pay, and reach tracking.
- IRIS delivery pricing and vehicle output remain unchanged.
- Rider can view eligible jobs and accept compatible jobs.
- Admin can view delivery, rider, Gifts, finance, support, and audit sections.
- Gifts Early Access flow opens Stripe Checkout and paid requests enter admin review.
- Health+ page and subscription entry remain accessible.
- Vanguard PIN/proof flow remains accessible for protected jobs.
- Chat and notifications remain functional.

## Immediate Recommendation

Start with Phase 1 only: add a small shared component/tokens layer, then migrate one low-risk public surface as a proof of style. Do not restyle rider/admin first; they have the highest operational sensitivity.
