# Smart Safe Release Orchestrator V2

The safe release orchestrator is change-aware. It inspects the working tree,
classifies changed files into product lanes, validates only affected deployment
targets, and never blocks an unrelated product because another lane is dirty.

It does not deploy by default.

## Commands

```bash
./safe_release.sh changed
./safe_release.sh sender
./safe_release.sh website
./safe_release.sh admin
./safe_release.sh functions
./safe_release.sh storage
./safe_release.sh rules
./safe_release.sh indexes
./safe_release.sh all
./safe_release.sh --self-test
```

Add `--full` to run expensive validation such as `flutter analyze`,
`flutter test`, Functions tests, and rules tests where applicable.

Add `--deploy` only after the report is reviewed. Deployment remains scoped to
targets that are independently `SAFE`.

## Classifier

Changed files are grouped into:

- Sender Web / Sender App
- Public Website
- Admin
- Cloud Functions
- Firestore Rules
- Storage Rules
- Indexes
- Documentation
- CI
- Diagnostics
- Release tooling
- Rider external

## Rules

- No target is deployed unless its own pre-flight passes.
- A failed Functions validation does not block Website, Sender, Rider or Admin.
- A failed Storage Rules validation skips Storage Rules only.
- Missing artifacts skip only the target that needs those artifacts.
- Mobile app publishing is intentionally reported for manual release.
- Rider-owned files are reported as external and must be released from the
  Circum-Rider repository.
- Unknown files are not silently deployed.

## Outputs

The orchestrator writes:

```text
deployment_report.md
```

The report lists each target as `SAFE`, `NOT SAFE`, `NO CHANGES`, `EXTERNAL`,
or `DEPLOYED`, with exact failed validation gates.
