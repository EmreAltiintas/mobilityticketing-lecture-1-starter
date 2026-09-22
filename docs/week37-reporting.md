# Week 37 — Where should reporting logic execute?

Four ways to produce daily captured revenue, compared against the same
scenario: buying the ticket price DKK 36 back-to-back through a captured
payment, a failed payment, two status corrections, a delete, and a
duplicate-reference delivery.

| # | Approach | Object | File |
| --- | --- | --- | --- |
| 1 | Direct query | ad-hoc aggregate over `payments`/`tickets`/`trips`/`routes` | `database/postgres/queries/020_base_revenue.sql` |
| 2 | SQL function | `captured_revenue_for_day(operator_id, date)` | `database/postgres/migrations/020_reporting_function.sql` |
| 3 | Materialized view | `daily_captured_revenue` | `database/postgres/migrations/022_daily_captured_revenue.sql` |
| 4 | Trigger-maintained table | `daily_revenue_by_operator` (+ `add_inserted_payment_to_daily_revenue`) | `database/postgres/migrations/021_daily_revenue_trigger.sql` |

Approaches 1 and 2 always recompute from the current, committed state of
`payments`. Approach 3 is a frozen snapshot until `REFRESH MATERIALIZED
VIEW` runs. Approach 4 is only updated by an `AFTER INSERT` trigger — it
has no `AFTER UPDATE` or `AFTER DELETE` trigger, which is the deliberate
gap this lab asks us to expose rather than quietly patch.

## Predicted outcome per test case

Run via `database/postgres/experiments/reporting_cases.sql`. Predictions
below follow directly from each object's definition; ⏳ marks what still
needs to be confirmed by actually running it (see "Evidence log").

| Case | Direct query / function | Materialized view (after refresh) | `daily_revenue_by_operator` (trigger) |
| --- | --- | --- | --- |
| 1. Captured insert | includes it immediately | includes it once refreshed | includes it immediately (`AFTER INSERT` fires, status = Captured) |
| 2. Failed insert | excludes it (status filter) | excludes it | excludes it (trigger's own guard: `if new.status is distinct from 'Captured' then return new;`) |
| 3. Failed → Captured (UPDATE) | includes it (re-reads current status) | includes it once refreshed | **still excludes it** — no `AFTER UPDATE` trigger exists, so the row is never re-evaluated |
| 4. Captured → Refunded (UPDATE) | excludes it (status filter now fails) | excludes it once refreshed | **still includes the old amount** — nothing subtracts it, since there is no `AFTER UPDATE` trigger |
| 5. Delete the (still-uncounted) row | reflects the delete, no change from case 4's state | reflects the delete once refreshed | unchanged — the row was never added in case 2/3, so removing it changes nothing in this table either |
| 6. Duplicate `external_payment_reference` on a Captured row | insert is **rejected outright** (`payments_external_reference_captured_unique`, from week 36) — none of the four ever see a new row | same | same |

Cases 3 and 4 are the "captured example where two approaches disagree"
the lab asks for: after both, `daily_revenue_by_operator` and the direct
query/function/materialized-view disagree on the same operator/day total,
and the disagreement is silent — nothing errors, the trigger-table is just
wrong until someone notices.

Case 6 is a second, different kind of finding: it shows the duplicate-
delivery problem is *already solved*, but one layer down, by the week-36
constraint — not by any of the four reporting mechanisms. None of them
needs its own duplicate handling as long as that constraint stays in place.

## Side-effect trace — one `INSERT INTO payments` (case 1)

1. **Constraints checked:** `payments_user_fk`, `payments_ticket_fk`,
   `payments_amount_non_negative`, `payments_currency_iso4217`,
   `payments_status_allowed`, and (because `status = 'Captured'`)
   `payments_external_reference_captured_unique`.
2. **Trigger execution:** `payments_daily_revenue_after_insert` fires once,
   `AFTER INSERT`, `FOR EACH ROW`. Its guard passes (`status = 'Captured'`),
   so it runs a `SELECT` through `tickets → trips → routes` to resolve
   `operator_id`.
3. **Summary-table write:** one `INSERT ... ON CONFLICT (operator_id,
   revenue_date) DO UPDATE` into `daily_revenue_by_operator` — either a new
   row or an incremented existing one.
4. **Rows/locks touched:** the new `payments` row; a row lock on the
   affected `daily_revenue_by_operator` key during the upsert; share locks
   implied by the joins into `tickets`/`trips`/`routes` (no writes there).
5. **Commit/rollback:** the `payments` insert and the trigger's upsert are
   one atomic transaction. If the upsert fails for any reason, the whole
   `INSERT` rolls back — `payments` and `daily_revenue_by_operator` cannot
   diverge *from this specific cause*. They still diverge from the missing
   `UPDATE`/`DELETE` triggers (cases 3–5).
6. **When each report becomes current:** the direct query and the function
   — on the very next read, no action needed. The trigger-table — inside
   the same transaction, so any reader after commit sees it. The
   materialized view — only after someone runs `REFRESH MATERIALIZED VIEW
   daily_captured_revenue`, which is not triggered automatically by
   anything in this migration.
7. **What the application can observe:** a client reading
   `daily_revenue_by_operator` right after commit sees the updated total. A
   client reading `daily_captured_revenue` sees the *old* total until a
   refresh runs. A client calling `captured_revenue_for_day(...)` or the
   base query always sees the current truth.

## Responsibility matrix

| | Direct query | Function | Materialized view | Trigger-table |
| --- | --- | --- | --- | --- |
| **Authority** | `payments` (recomputed) | `payments` (recomputed) | `payments`, as of last refresh | itself — drifts from `payments` after any UPDATE/DELETE |
| **Correctness** | always correct | always correct | correct as of last refresh | correct only for insert-only history; wrong after any correction, refund, or delete |
| **Freshness** | immediate | immediate | stale until refreshed | immediate for inserts, permanently stale for corrections |
| **Write cost** | none (read-only) | none (read-only) | one full recompute per `REFRESH` | one small upsert per captured insert; nothing on update/delete |
| **Read cost** | full join + aggregate every call | full join + aggregate every call | index lookup on a small pre-aggregated table | index lookup on a small pre-aggregated table |
| **Hidden side effects** | none | none | none (refresh is explicit) | yes — silently stops tracking reality the moment a payment is corrected or deleted |
| **Rebuildability** | trivial — it's a query | trivial — it's a query | trivial — `REFRESH MATERIALIZED VIEW` | requires a manual backfill script; no supplied way to resync from `payments` |
| **Operational complexity** | none | none | one scheduled/triggered `REFRESH` job to operate | one insert trigger today; a *correct* version needs update and delete triggers too, i.e. more surface to get wrong |

## Issue register

### Issue 1: `daily_revenue_by_operator` silently drifts from `payments`

- **Evidence:** cases 3, 4 and 5 above — the table has only an `AFTER
  INSERT` trigger.
- **Problem:** any status correction (a failed payment retried and
  captured, a captured payment refunded) or any delete changes the true
  daily revenue but never touches `daily_revenue_by_operator`.
- **Consequence:** the table returns a *confidently wrong* number with no
  error, no warning, and no way to tell from the table alone that it has
  drifted.
- **Specific improvement:** add `AFTER UPDATE` (recompute the delta when
  `status` changes into or out of `'Captured'`, or when `amount` changes)
  and `AFTER DELETE` (subtract) triggers, or replace the incremental
  upsert with a periodic full recompute (which is, at that point, just a
  materialized view with extra steps).
- **Open question:** whether an incrementally-correct trigger is worth
  the added operational complexity versus simply refreshing a materialized
  view on the same schedule — see the decision record below.

### Issue 2: `daily_revenue_by_operator` has no initial backfill

- **Evidence:** the baseline run (before any experiment case) shows the
  direct query/function/materialized view already reporting `36.00 / 1`
  for OP-METRO on 2026-09-01 — from `PAYMENT-1`, seeded in week 36 — while
  `daily_revenue_by_operator` starts at **0 rows**. The trigger only fires
  on new inserts, so it never sees rows that existed before it was created.
- **Problem:** deploying this trigger against an already-populated
  `payments` table silently starts the summary table at zero instead of at
  the true historical total.
- **Consequence:** the table is wrong from the moment it is created, not
  only after a later correction — cases 1–6 measure *drift going forward*,
  but the table is already behind on day one.
- **Specific improvement:** a one-off backfill statement (`INSERT ...
  SELECT ... FROM payments WHERE status = 'Captured' GROUP BY ...`) run
  once, in the same migration, immediately after `CREATE TRIGGER`.
- **Open question:** none of this lab's migrations for week 37 add that
  backfill — kept out deliberately here so the gap stays visible as
  evidence, per `docs/week37-reporting.md`'s own note not to patch the
  trigger silently. A real deployment must not skip it.

## Decision record: recommendation for this case

**Recommendation:** serve operator reports from the **materialized view**
(`daily_captured_revenue`), refreshed on a fixed schedule (for example
every 5–15 minutes), with the **direct query/function** kept available as
the ground-truth fallback for reconciliation or an "as of right now" check.
Do **not** adopt the trigger-maintained table as supplied.

**Why, tied to the workload (see the design brief, "Reporting"):**
"Reporting can tolerate more latency than purchase and validation. Reports
do not need to reflect every operational write immediately." That is
exactly what a materialized view trades away (a few minutes of staleness)
for a cheap, simple, always-rebuildable read path — `DROP`/`CREATE` or
`REFRESH` gets you back to a known-correct state from `payments` at any
time, with no bespoke recovery logic.

The trigger-table, as supplied, does not meet even the *correctness* bar,
only the *freshness* one, and only for inserts — issue 1 shows it silently
diverges the moment a payment is corrected or deleted, which is routine in
this domain (failed-then-retried payments, refunds). Making it actually
correct means an `AFTER UPDATE` and an `AFTER DELETE` trigger, at which
point it has all the operational complexity of a materialized view (a
piece of logic to keep in sync with the schema) plus its own extra risk:
any future writer that bypasses these triggers (a bulk import, a manual
fix, a new service) reintroduces the drift with no warning.

If true near-real-time revenue is ever required, the trigger approach is
worth revisiting — but only alongside a documented reconciliation job that
can detect and repair drift against the direct query, since a trigger can
be added to correctly but cannot prove it stayed correct.

## Evidence log (verified 2026-09-22)

Run against a freshly recreated container (`docker compose down -v &&
docker compose up -d`), migrations 011, 020, 021, 022 applied in order.
`database/postgres/experiments/reporting_cases.sql` only contained the
baseline `select` and the writes themselves — the commented instruction to
compare all four approaches after every case was not itself executable
SQL, so it was extended locally (direct query + `captured_revenue_for_day`
+ `daily_captured_revenue` refreshed + `daily_revenue_by_operator`, after
every case) to actually capture each comparison point. Figures below are
`captured_amount / captured_payments` for OP-METRO, 2026-09-01 (OP-BUS is
untouched by every case and stays at `36.00 / 1` throughout).

| After case | Direct query / function / materialized view | `daily_revenue_by_operator` | Agree? |
| --- | --- | --- | --- |
| Baseline (before any case) | 36.00 / 1 | **0 rows** | ❌ — issue 2 (no backfill), not predicted as a separate case but caught by this run |
| 1. Captured insert (+36) | 72.00 / 2 | 36 / 1 | ✅ (same delta; absolute totals still offset by issue 2) |
| 2. Failed insert (+50, ignored) | 72.00 / 2 | 36 / 1 | ✅ |
| 3. Failed → Captured correction (+50) | 122.00 / 3 | 36 / 1 (unchanged) | ❌ — predicted disagreement confirmed: no `AFTER UPDATE` trigger |
| 4. Captured → Refunded (case 1's payment, −36) | 86.00 / 2 | 36 / 1 (unchanged) | ❌ — predicted disagreement confirmed: trigger-table still shows the refunded amount as Captured |
| 5. Delete the (now-Captured) failed payment (−50) | 36.00 / 1 | 36 / 1 | ✅ — but by coincidence: the direct query's 36 is `PAYMENT-1` (the original seed row); the trigger-table's 36 is case 1's `PAY-CASE-CAPTURED`, which the direct query has *already excluded* since case 4's refund. Same number, different underlying row — an aggregate that looks right while being wrong underneath. |
| 6. Duplicate `external_payment_reference` (Captured) | insert rejected: `duplicate key value violates unique constraint "payments_external_reference_captured_unique"` | 36 / 1 (never reached) | ✅ as expected — none of the four reporting mechanisms ever saw the row; the week-36 constraint stopped it first |

Both predicted disagreements (cases 3 and 4) occurred exactly as reasoned
from the trigger's definition. The run additionally surfaced issue 2 (no
initial backfill), which the original prediction table did not list as its
own row, and the case-5 "agreement" turned out to be coincidental rather
than both sides being correct — recorded above rather than smoothed over,
since that distinction matters more than the raw match/mismatch column.
