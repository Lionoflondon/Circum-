# Circum Sender / Public Application

This repository owns the Circum Sender/Public application, the public marketing
website, and the Circum Admin Portal build. Rider entry URLs redirect to the
dedicated canonical Rider application.

Read [the Canonical Application Registry](docs/APPLICATION_REGISTRY.md) before
running, routing, testing, or deploying any Circum application. It identifies
the canonical `Circum-Rider` repository, every Hosting target, and the Rider
entry points used in production.

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
- **Circum Rider App:** `github-sync/Circum-Rider`, deployed to
  `circum-rider-2797c.web.app`.
- **Rider public entry:** `/rider` and Rider aliases on this host redirect to
  the canonical Rider application; they do not render a Rider portal here.
