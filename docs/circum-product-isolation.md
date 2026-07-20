# Circum Product Isolation

Circum is partitioned into five products:

1. Circum Website
2. Sender App
3. Rider App
4. Admin
5. Backend

## Circum Website

Owns Sender Web and Rider Web as one website product.

Allowed:

- `lib/main_public_web.dart`
- `lib/website/**`
- `lib/web_platform_routing.dart`
- Website shell, website navigation, website authentication, SEO and legal pages

Forbidden:

- Sender mobile app shell
- Rider mobile app shell
- Admin console
- Cloud Functions
- Firestore or Storage Rules

## Sender App

Owns the independent Sender mobile application.

Allowed:

- `lib/main.dart`
- `lib/app/sender_mobile/**`
- Sender booking, wallet, activity, profile and tracking presentation

Forbidden:

- `lib/website/**`
- Website shell
- Rider application code
- Admin console
- Backend infrastructure

## Rider App

The Rider app remains intentionally isolated in the Rider repository. Fixes do not propagate automatically from Circum. Shared code must only be extracted deliberately into a small package after explicit approval.

## Admin

Admin is an independent product and must not be compiled into the Circum Website.

## Backend

Backend is independent. Frontend changes must not deploy Functions, Firestore Rules or Storage Rules unless the task explicitly includes backend work.

## Deployment Guard

`scripts/deploy_guard.js` reads `deploy-manifest.json` and blocks deployments when a selected product includes files outside its ownership boundary.
