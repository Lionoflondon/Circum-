# Circum Sender / Public Application

This repository owns the Circum Sender/Public application, the public marketing
website, the Circum Admin Portal build, and the canonical Rider web
application.

Read [the Canonical Application Registry](docs/APPLICATION_REGISTRY.md) before
running, routing, testing, or deploying any Circum application. It identifies
the legacy `Circum-Rider` repository, every Hosting target, and the Rider entry
points used in production.

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
- **Circum Rider Web App:** this repository's authenticated Rider portal at
  `/rider`, deployed with the public Hosting targets.
- **Legacy Rider Client:** `github-sync/Circum-Rider`; do not use it for the
  current Rider product without an explicit migration decision.
