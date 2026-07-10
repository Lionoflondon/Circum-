# Circum Sender / Public Application

This repository owns the Circum Sender/Public application, the public marketing
website, and the Circum Admin Portal build. It also contains an embedded Rider
web portal and explicit Rider preview routes, but it is **not** the canonical
native Rider application.

Read [the Canonical Application Registry](docs/APPLICATION_REGISTRY.md) before
running, routing, testing, or deploying any Circum application. It identifies
the dedicated `Circum-Rider` repository, every Hosting target, and the preview
routes that must not be used as production Rider entry points.

## Run Locally

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
```

## Application Identity

- **Circum Sender / Public App:** this repository's public Hosting targets.
- **Circum Admin Portal:** this repository's dedicated admin Hosting target.
- **Circum Rider App:** `github-sync/Circum-Rider`; use it for native Rider
  development and Rider-specific releases.
- **Rider Architecture Preview:** `/rider` and Rider query aliases in this
  repository are presentation previews, not canonical Rider application URLs.
