# Circum Repository Governance

## Repository Purpose

`Circum-` is the canonical platform repository for the Circum customer-facing app, public web surfaces, Admin web surface, Firebase rules, and Cloud Functions source.

## Ownership

The default code owner is `@Lionoflondon`.

Architecture-sensitive files retain explicit ownership in `.github/CODEOWNERS`.

## Pull Request Workflow

All changes to `main` must be reviewed through a pull request.

Pull requests must pass repository CI before merge. Architecture-sensitive changes must also pass the protected architecture review workflow.

## CI Workflow

The repository Flutter quality workflow is `Circum Flutter CI`.

It runs:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

Existing product-specific governance workflows may add additional checks for deployment isolation, backend functions, and protected architecture.

## Merge Requirements

Merges to `main` should require:

- one approving review
- code owner review
- all conversations resolved
- stale approvals dismissed after new commits
- required status checks passing
- force pushes blocked
- branch deletion blocked
- backend authority review for any feature that changes operational state

Operational changes must be backend-owned. A pull request that adds direct
client writes to deliveries, dispatch, identity, verification, payments, Roth,
Wallet, IRIS, Health+, Gifts, Vanguard, Business, chat, notifications, tracking,
or Admin recovery must be rejected unless the write is explicitly non-operational
client state such as a local preference, cache entry, or draft.

## Release Process

Release changes must be made from reviewed pull requests. Release tags should be immutable and should reference the reviewed merge commit.

Recommended tag format:

- `sender-vYYYY.MM.DD-N`
- `admin-vYYYY.MM.DD-N`
- `backend-vYYYY.MM.DD-N`
- `platform-vYYYY.MM.DD-N`

## Deployment Responsibilities

Deployments are separate from merges.

Sender, Website, Admin, Cloud Functions, Firestore Rules, and Storage Rules must be deployed through their dedicated release lanes only.

No workflow in this repository should deploy as part of the repository quality CI.

## Branch Strategy

`main` is the canonical protected branch.

Feature and recovery work should use short-lived branches and merge only through pull requests.

Direct pushes to `main` should remain restricted.
