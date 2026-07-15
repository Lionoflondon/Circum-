# Circum Product Registry

| Product | Entry point | Root widget | Build | Hosting |
|---|---|---|---|---|
| Public Website | `lib/public_web/main_public.dart` | `CircumPublicWebsiteApp` | `flutter build web --target lib/public_web/main_public.dart --base-href /` | `hosting:public`, `/` |
| Sender Web | `lib/sender_web/main_sender_web.dart` | `WebSenderApp` | `flutter build web --target lib/sender_web/main_sender_web.dart --base-href /send/` | `hosting:public`, `/send` |
| Rider Web | `lib/rider_web/main_rider_web.dart` | `CircumRiderWebApp` | `flutter build web --target lib/rider_web/main_rider_web.dart --base-href /rider/` | `hosting:public`, `/rider` |
| Rider App | Circum-Rider repository canonical entry | `CircumRiderApp` | Owned by Circum-Rider | `hosting:rider`, `circum-rider-2797c.web.app` |
| Admin | `lib/main_admin.dart` | `CircumAdminHostingApp` | `flutter build web --target lib/main_admin.dart` | `hosting:admin` |

## Boundaries

- Public, Sender Web, and Rider Web have independent Flutter entry points, root widgets, routers, and bundles.
- The Public site links to `/send` and `/rider`; it never mounts either application root.
- Rider App is owned and deployed only by the Circum-Rider repository.
- Admin remains independently built and hosted.
- `scripts/guard_public_web_architecture.js` and `scripts/verify_web_platform.js` enforce source and compiled-bundle boundaries.
