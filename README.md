# ShopPadi

Shop companion for Nigerian small businesses — sales, stock, customer debts,
receipts, WhatsApp sharing. Offline-first Flutter app with Supabase as the
source of truth.

Design doc: the "ShopPadi — Product & Technical Design" artifact (v1.2).

## Status: Phase 1 in progress

Working end to end, offline, against local SQLite:

- **Sell** — searchable product grid, cart, checkout with cash / transfer
  (OPay, PalmPay, Moniepoint, bank) / POS / credit, part-payment that becomes
  tracked debt, and a WhatsApp-ready text receipt.
- **Inventory** — product add/edit, stock in, counted corrections, low-stock
  and out-of-stock flags. Quantity is always a rollup of the movement ledger.
- **Customers** — debtors ranked by balance with debt ageing, repayment
  (oldest debt first), and one-tap WhatsApp reminders.
- **Insights** — revenue, exact gross profit from per-line cost snapshots,
  margin, cash collected vs sold on credit, and all-time money owed.
- **Shop details** — name, phone, receipt footer, and the wallet accounts that
  print on receipts when a balance is outstanding.

Backend groundwork: PostgreSQL schema + RLS policies in `supabase/migrations/`
(both applied to the live Supabase project), local drift database with a sync
outbox table.

Not yet: auth screens, the sync engine that drains the outbox, day close,
returns, invoices, thermal printing, Crashlytics (needs a Firebase project).

## One-time setup

1. **Flutter SDK** — installed at `C:\Users\PC\flutter` (official 3.44.8 zip;
   a git clone will NOT work on this network, see Troubleshooting). Add
   `C:\Users\PC\flutter\bin` to PATH. Android SDK already exists at
   `C:\Users\PC\android-sdk`; point Flutter at it:
   ```
   flutter config --android-sdk C:\Users\PC\android-sdk
   flutter doctor
   ```
2. **Platform folders** — from this directory:
   ```
   flutter create . --platforms=android --org ng.shoppadi
   ```
3. **Dependencies + drift codegen**:
   ```
   flutter pub get
   dart run build_runner build
   ```
4. **Supabase** — done: both migrations are applied to the live project. The
   SQL editor has no file browser; paste each file's contents and Run, 0001
   before 0002.

## Run

```
flutter run --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Runs without the dart-defines too (Supabase init is skipped) — useful for
UI work before the backend exists.

## Conventions

- **Money is integer kobo, always.** Format only via `lib/core/money.dart`.
- **Quantities are in base units** (sachet, piece); pack sizes convert through
  `product_units.factor_to_base`.
- **Ledger tables are append-only** (stock_movements, payments, day_closes):
  fix mistakes with a new correcting row, never an update.
- Client-generated UUID ids everywhere, so offline writes merge cleanly.
- **drift result columns are matched by object identity.** Store an aggregate
  expression in a variable and reuse it; calling `.sum()` twice silently reads
  null.

## Troubleshooting this network

Some hosts return headers but transfer zero bytes on this connection. Verified
July 2026:

| Host | Works? |
|---|---|
| `storage.googleapis.com`, `dl.google.com`, `pub.dev` | yes |
| `repo1.maven.org`, `plugins.gradle.org` | yes |
| `repo.maven.apache.org` (what `mavenCentral()` uses) | **no** |
| `github.com` git pack transfers | **no** |
| `services.gradle.org` over HTTP/2 | **no** (works over HTTP/1.1) |

Consequences, already handled in this repo: the Gradle repositories in
`android/` list `repo1.maven.org` ahead of `mavenCentral()`, and the Flutter
SDK was installed from the release zip rather than cloned. For large downloads
use `curl.exe -4 --http1.1 -C -` under a supervisor that restarts it whenever
throughput collapses.
