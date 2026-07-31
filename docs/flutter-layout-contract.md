# Flutter Layout Contract

The Sender app is mobile-first. iPhone and Android phone layouts are the source of truth; tablet and desktop web adapt from the same page architecture.

## Primary Rule

Each primary Sender screen must have one vertical scroll owner unless an inner scrollable is explicitly constrained.

Do not wrap an existing vertical scrollable in another vertical scrollable. Avoid patterns such as:

- `ListView` inside `ListView`
- `ListView` inside `SingleChildScrollView`
- `CustomScrollView` inside `ListView`
- `RefreshIndicator` with an unconstrained inner `ListView` inside another vertical scroll parent

Horizontal nested scrolling is allowed when it is intentionally horizontal, such as chips or carousel rows.

## Canonical Shell

Primary Sender pages must use `SenderPrimaryPageShell` or `SenderScrollablePageShell` from:

`lib/app/sender_mobile/sender_page_shell.dart`

The shell owns:

- viewport padding
- top alignment
- responsive content width
- scroll ownership
- mobile-first adaptation

Do not add a new root page shell for Home, Activity, Wallet or Profile.

## Constraint Tools

When layout needs structure, use Flutter constraints deliberately:

- `Expanded` or `Flexible` inside columns and rows
- `ConstrainedBox` when a child needs bounded dimensions
- sliver patterns when a screen needs coordinated scrolling
- one page-level `ListView` for ordinary vertical page content

## Test Contract

Every primary Sender tab must render the first frame with no Flutter layout exceptions:

- Home
- Send
- Activity
- Wallet
- Profile

The guard lives in:

`test/sender_mobile/sender_first_frame_layout_test.dart`

Any exception in the render tree is a release blocker, including:

- unbounded viewport constraints
- `RenderBox was not laid out`
- `RenderFlex` overflow
- infinite constraints
- incorrect parent data

## Debug Diagnostics

Debug builds log layout failures with:

- widget tree
- render tree
- stack trace

Search logs for `CIRCUM_LAYOUT_EXCEPTION`.
