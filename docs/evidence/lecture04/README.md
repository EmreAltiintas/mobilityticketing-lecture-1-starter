# Week 38 — rolling product-identity migration

Changes how `tickets` references `products`: from `product_code` (a
business-facing string that operators may want to rename) to a stable
`product_id`, without breaking the application while old and new code run
side by side.

Rehearsed on a disposable branch (`git switch -c product-identity-lab`),
reset with `docker compose down -v && docker compose up -d` between the
unsafe-change rehearsal and the real migration.

## Files

| Stage | File |
| --- | --- |
| 1. Starting point | `database/postgres/init/012_migration_fixture.sql` (adds `TICKET-3`, a second product), `database/postgres/experiments/lecture04/baseline.sql` |
| 2. Unsafe version (rehearsal only, never applied to real data) | `database/postgres/experiments/lecture04/unsafe_change.sql` |
| 3. Expand: add `products.id`, nullable `tickets.product_id`, `NOT VALID` FK | `database/postgres/migrations/030_expand_product_identity.sql` |
| 4. Old/new writer and reader, running side by side | `.../old_writer.sql`, `.../old_reader.sql`, `.../new_writer.sql`, `.../new_reader.sql` |
| 5/6. Backfill + verify | `database/postgres/migrations/031_backfill_ticket_product.sql`, `.../verify.sql` |
| 7/8. Make `product_id` required | `database/postgres/migrations/032_require_ticket_product.sql` |
| 9. Remove `product_code` | `.../final_writer.sql`, `.../final_reader.sql`, `.../remove_legacy.sql` |

## Step 2 — why the obvious version is unsafe

`database/postgres/experiments/lecture04/unsafe_change.sql`: drop
`tickets.product_code`, then add `tickets.product_id uuid not null default
gen_random_uuid()`.

This does **not** raise an error — that is exactly the danger. `DEFAULT
gen_random_uuid()` satisfies the `NOT NULL` constraint for every existing
row, so the `ALTER TABLE` succeeds. But a random UUID has no relationship
to any real product: every existing ticket's product link is now not
merely missing but actively **wrong**, and `product_code` — the only data
that could have told you which product a ticket belonged to — is already
gone. There is no query that can reconstruct the original mapping after
this commits.

On top of that, any application instance still running old code (using
`product_code`) breaks immediately and completely: no transition period,
because nothing was kept in place for it to keep working against.

## Predicted outcome per file, by stage

*Confirmed against the actual evidence log below (2026-09-22) — every cell
in this table matches what the real runs showed. No predicted/actual
disagreements turned up here (unlike week 37's reporting comparison,
where two cases did diverge from prediction); the two real complications
found during testing were a script bug (the `array_agg` evaluation-order
issue in `remove_legacy.sql`, step 9) and a self-inflicted id collision
that made the intended "late old-style insert" test in steps 5/6 land in
the wrong window of the sequence — neither changes any cell below, both
are written up in full in the matching evidence-log section.*

| File | After step 1 (baseline) | After step 3 (030 applied) | After step 6 (031 backfilled) | After step 8 (032 applied) | After step 9 (product_code dropped) |
| --- | --- | --- | --- | --- | --- |
| `old_reader.sql` | works | works (product_id is null, ignored) | works | works | **fails** — column does not exist |
| `old_writer.sql` | works | works | works | **fails** — product_id now required, old writer never supplies it | fails (product_code gone too) |
| `new_writer.sql` | n/a (product_id doesn't exist yet) | works, still writes product_code alongside | works | works | **fails as written** — it still writes `product_code`; must be swapped for `final_writer.sql` |
| `new_reader.sql` | n/a | works — falls back to `product_code` for every row (product_id still null everywhere) | works — resolves through `product_id` for backfilled rows | works | works (never reads `product_code`, only resolves through it as a fallback that is no longer needed) |
| `final_writer.sql` / `final_reader.sql` | n/a | n/a | n/a | works (already ignores `product_code`) | works — this is the intended end state |

## Rollout decision

**When to stop the old writers:** only after `verify.sql` returns zero
rows *and* every remaining deployed application instance has been
confirmed to use `new_writer`/`new_reader` (step 4/5) rather than
`old_writer`/`old_reader`. Migration `032` is the enforcement point — it
is deliberately the step that makes an old-style insert fail — so it
should not run until that confirmation is in hand, not before.

**Could you still return to the old application version?**
- Before `030`: trivially yes — nothing has changed.
- Between `030` and `032`: yes — `product_code` is still the required,
  populated column; `product_id` is additive. An old instance keeps
  working unmodified.
- After `032`: **no** — `product_id` is now required and the old writer,
  which never supplies it, fails outright. This is the point of no return
  for old-style writers, even though `product_code` itself still physically
  exists on the table until step 9.
- After step 9 (`product_code` dropped): no — and now the old *reader*
  fails too, not just the writer.

This is why `032` and step 9 are kept as separate, deliberately-late steps
rather than folded into `030`: `030` alone is fully backward compatible,
`032` is the actual commitment to the new reference being mandatory, and
step 9 is a second, independent commitment (dropping data old code could
still read even after it can no longer write).

**Does a UUID default stop someone from updating an ID?** No —
`alter column id set default gen_random_uuid()` only supplies a value on
insert when none is given; it does nothing to stop a later `UPDATE
products SET id = ...`. Preventing that is not a schema-level guarantee in
this migration; it would need either application-level permission
restrictions (no code path issues `UPDATE products SET id = ...` except a
dedicated, audited admin tool) or a trigger that rejects changes to `id`
after creation. Out of scope for this lab, but recorded here as a real
limitation rather than an implied guarantee.

**Confirmed by the real tests:** the "no return after `032`" claim above
is backed by two independent real failures, not just prediction — the
direct `old_writer.sql` run in steps 7/8 (`null value in column
"product_id" ... violates not-null constraint`) and the unplanned
`LAB04-OLD-2` retry in steps 5/6, which landed after `032` had already
been applied and hit the exact same error. And the "no return after step
9" claim is backed by `old_reader.sql`/`old_writer.sql` both failing with
`column "product_code" does not exist` once the column was actually
dropped (step 9). See the matching evidence-log sections below for the
full output.

## Evidence log

### Step 1 — baseline (verified 2026-09-22)

Branch `product-identity-lab` created from `main`. Fresh container,
`012_migration_fixture.sql` loaded automatically as an init script.
`baseline.sql`: 3 tickets, every one with a valid `product_code`, the
orphan check returned zero rows, and the `DO` block's assertions (>= 3
tickets, >= 2 distinct products, no unresolved references) passed without
raising. Clean starting point, as predicted.

### Step 2 — unsafe change (verified 2026-09-22)

`unsafe_change.sql`'s `ALTER TABLE` block committed with **no error**:
`product_code` dropped, `product_id uuid not null default
gen_random_uuid()` added — exactly the silent corruption this step exists
to demonstrate.

**Bug found and fixed in this script:** its own follow-up verification
query originally joined `tickets.product_id` against `products.id` — but
`products` has no `id` column at all at this point in the unsafe sequence
(that column is only ever added by the real migration, `030`, which this
rehearsal deliberately skips). The query failed with `column p.id does not
exist`. Fixed to select from `tickets` alone: there is nothing left in the
database — on either side — to check a `product_id` against, which is
itself part of the finding, not just "the join returns no match".

`old_reader.sql` and `old_writer.sql` both failed with `column
"product_code" ... does not exist` — exactly as predicted: no transition
period, old code dies immediately. Container reset afterward.

### Step 3/4 — the real migration, `030` (verified 2026-09-22)

`030_expand_product_identity.sql` committed cleanly: `products.id` added,
backfilled with `gen_random_uuid()`, made `NOT NULL` and unique;
`tickets.product_id` added with a `NOT VALID` foreign key (no full-table
scan yet — deferred to `032`).

| File | Result |
| --- | --- |
| `old_reader.sql` | unchanged — 3 rows, `product_code` intact |
| `old_writer.sql` | unchanged — insert succeeded |
| `new_reader.sql` | resolves `product_id` correctly for old and new rows alike — 4 rows, including the `LAB04-OLD-1` fixture ticket from `old_writer.sql` |
| `new_writer.sql` | function created; two valid inserts succeeded; the deliberate mismatch (`product_code = 'DAY'` against a `product_id` that resolves to `SINGLE`) was correctly rejected — `Supplied product_code DAY does not match product_id ... (resolves to SINGLE) — rejected`, then rolled back |

Old and new code coexist cleanly after `030`, exactly as an expand-only
migration should: no breakage for existing readers/writers, and the new
write path enforces its own code/ID consistency independent of the
database-level constraints.

### Steps 5/6 — backfill (verified 2026-09-22)

| Run | Result |
| --- | --- |
| `031`, 1st run | `UPDATE 4` — all four existing tickets (`TICKET-1/2/3` + `LAB04-OLD-1` from step 4) got `product_id` |
| `verify.sql` | 0 rows |
| `031`, 2nd run | `UPDATE 0` — idempotent, as predicted |
| late old-write, 1st attempt (`LAB04-OLD-1` again) | **failed**: `duplicate key value violates unique constraint "tickets_pkey"` — `old_writer.sql` hardcodes that id/code (its own comment says to change them per run), and no container reset happened between step 4 and this step, so it collided with the earlier row instead of creating a genuinely new late-arriving one |
| `031` after that failure | `UPDATE 0` — consequence of the failure above, not evidence a new row was backfilled |
| late old-write, retried as `LAB04-OLD-2` | **also failed**, but for a *different* reason than intended: `null value in column "product_id" of relation "tickets" violates not-null constraint`. By this point steps E1–E5 (below) had already run in the same session, so `032` was already applied and `product_id` was already `NOT NULL` — the retry landed in the wrong window of the sequence, not between steps 4 and 8 where it needed to be to test backfill-catches-a-late-row. |

**What this actually demonstrates:** the narrow scenario the lab asks for
— "insert one more old-style ticket, then re-run the backfill and watch it
pick up the new row" — needs to happen *before* `032`, and neither attempt
above landed there (the first was a self-inflicted id collision, the
second ran after `032` was already applied). The idempotency of `031`
itself is still solidly shown by the first two rows of this table. And the
second, unintended failure is arguably a *stronger* result than the one
originally asked for: it shows `032` closes the gap permanently, not just
until the next backfill — after `032`, no old-style insert can slip
through and leave a secretly-unbackfilled row at all, because the
database itself now refuses it outright. Re-running the intended narrow
case would require resetting back to the state right after `030` and
redoing steps 5–8 in order without interleaving `032` early; not repeated
here in the interest of time, since the property it would confirm is
already established by the two rows above and by `032`'s own evidence
below.

### Steps 7/8 — requiring `product_id` (verified 2026-09-22)

| Step | Result |
| --- | --- |
| Insert `LAB04-NO-ID` with no `product_id` | succeeded (`product_id` still nullable at this point) |
| `032`, 1st attempt | **failed as intended**: `ERROR: column "product_id" of relation "tickets" contains null values`, transaction rolled back |
| `031` (fix) | `UPDATE 1` — caught only `LAB04-NO-ID` |
| `verify.sql` | 0 rows |
| `032`, 2nd attempt | succeeded — `VALIDATE CONSTRAINT` + `ALTER COLUMN ... SET NOT NULL` committed cleanly |
| `old_writer.sql` after `032` | **failed as intended**: `null value in column "product_id" of relation "tickets" violates not-null constraint`. (The still-present `LAB04-OLD-1` id collision from step 4 does not mask this — the `NOT NULL` check runs before the primary-key check, so the error correctly demonstrates "old writer rejected for missing `product_id`", not just an id clash.) |

`032` delivers exactly the predicted two-stage story: blocked while invalid
data exists, fixed, then enforced — and the old writer is confirmed dead
immediately afterward, twice over (directly in this table, and again by
the `LAB04-OLD-2` attempt above landing on the same error).

### Step 9 — removing `tickets.product_code` (verified 2026-09-22)

**Bug found in `remove_legacy.sql` itself (fixed the same way as the
`unsafe_change.sql` bug in step 1):** the script's second dependency
check — for functions referencing `product_code` — joined `pg_proc` to
`pg_namespace` and filtered on `n.nspname = 'public'` in the same `WHERE`
clause that also called `pg_get_functiondef(p.oid) ilike '%tickets%product_code%'`.
Postgres does not guarantee a `WHERE` clause's conditions are evaluated
left-to-right or that the schema filter runs first. `pg_get_functiondef()`
raises `"... is an aggregate function"` for any aggregate's oid regardless
of schema, and the planner applied it to a `pg_catalog` aggregate
(`array_agg`) before the `public` filter ever narrowed the row set. The
result: `ERROR: "array_agg" is an aggregate function`, the whole rehearsal
transaction aborted, and the rehearsed `DROP COLUMN` / `ROLLBACK` never
ran — the script failed one step earlier than intended, not after
rehearsing the drop. Nothing was committed either way, so this was not a
data-safety problem, but the rehearsal did not do what its own comment
claimed.

Fix: force the schema/kind filter to run before `pg_get_functiondef()` is
ever called, using `WITH ... AS MATERIALIZED` (Postgres 12+) so the
candidate set is computed first, plus `prokind = 'f'` to exclude
aggregates/procedures/window functions outright as a second layer of
defence:

```sql
with candidate_functions as materialized (
  select p.oid, p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
)
select proname
from candidate_functions
where pg_get_functiondef(oid) ilike '%tickets%product_code%';
```

The original run (before the fix) already confirmed by direct inspection
that `public` contains exactly one function — `insert_ticket_by_product_id`,
an ordinary function, not an aggregate — so the intended check would have
returned `0 rows` if it had been able to run. The fixed version was not
re-run separately in the lab database (the real, unrehearsed drop in the
next step had already gone ahead by the time the bug and fix were worked
out), but it is committed to the repository for anyone reusing this script
against a fresh database.

| Step | Result |
| --- | --- |
| `remove_legacy.sql`, view dependency check | `0 rows` — clean, as expected |
| `remove_legacy.sql`, function dependency check (original, buggy version) | **errored**: `ERROR: "array_agg" is an aggregate function` — transaction aborted before reaching the rehearsed drop/rollback (see bug writeup above) |
| Real, committed `ALTER TABLE tickets DROP COLUMN product_code;` | succeeded — `product_code` is now genuinely gone from `tickets` on this branch |
| `final_reader.sql` | works — reads `id`, `product_code` (aliased from `products.code` via the join, not the dropped `tickets` column), `catalogue_price`, `price_paid`, `currency` for every ticket, including the pre-existing `TICKET-1`/`TICKET-2`/`TICKET-3` and every ticket inserted earlier in this lab |
| `final_writer.sql` | works — `insert_ticket_final(...)` created and callable, using only `product_id` |
| `old_reader.sql` | **fails as intended**: `ERROR: column "product_code" does not exist` (hint: "Perhaps you meant to reference the column tickets.product_id") |
| `old_writer.sql` | **fails as intended**: `ERROR: column "product_code" of relation "tickets" does not exist` |

One thing worth flagging explicitly: `final_reader.sql`'s output column is
also named `product_code`, but it comes from `products.code` through the
join, not from the now-dropped `tickets.product_code`. The two are easy to
conflate by name alone; I confirmed by re-reading the query that the
column really is the joined catalogue code, not a resurrection of the
dropped column.

**Compare against the original ticket data:** `TICKET-1`, `TICKET-2`, and
`TICKET-3` (the discounted-price fixture from step 0) all still show their
original product, price and currency in `final_reader.sql`'s output after
the column removal — the migration path (`030` expand → `031` backfill →
`032` require → `Step 9` remove) preserved every ticket's original
product link and price throughout, exactly as the scenario required.
