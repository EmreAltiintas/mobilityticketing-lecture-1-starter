# Week 36 integrity map: SQL constraints and operations

Migration: `database/postgres/migrations/011_ticketing_integrity.sql`
Negative tests: `database/postgres/experiments/constraints_should_fail.sql`
Starter (unmodified): `database/postgres/init/010_ticketing_draft.sql`

## Integrity map

| Invariant | Affected tables and columns | Current protection | Missing protection or limitation | Expected failure behaviour | Evidence |
| --- | --- | --- | --- | --- | --- |
| Capacity cannot be negative | `trips.capacity` | `CHECK trips_capacity_non_negative` | none | `23514` check_violation | experiments #1 |
| Reserved seats cannot be negative or exceed capacity | `trips.reserved_seats`, `trips.capacity` | `CHECK trips_reserved_seats_valid` | does not arbitrate two *concurrent* purchases racing for the same seat (issue 1) | `23514` check_violation | experiments #2 |
| A ticket must reference an existing user | `tickets.user_id` → `users.id` | `FOREIGN KEY tickets_user_fk` | none | `23503` foreign_key_violation | manual: insert with unknown `user_id` |
| A ticket must reference an existing trip | `tickets.trip_id` → `trips.id` | `FOREIGN KEY tickets_trip_fk` | none | `23503` foreign_key_violation | experiments #3 |
| A ticket must reference an existing product | `tickets.product_code` → `products.code` | `FOREIGN KEY tickets_product_fk` | none | `23503` foreign_key_violation | manual: insert with unknown `product_code` |
| Ticket validity cannot end before it begins | `tickets.valid_from_utc`, `tickets.valid_to_utc` | `CHECK tickets_valid_window` | does not check the window actually overlaps the trip's own departure time | `23514` check_violation | experiments #4 |
| Ticket codes must identify a ticket unambiguously | `tickets.ticket_code` | `UNIQUE tickets_ticket_code_unique` | none | `23505` unique_violation | experiments #5 |
| Ticket status must come from an accepted set | `tickets.status` | `CHECK tickets_status_allowed` | the set is fixed at migration time; a new status needs a new migration, not a config change | `23514` check_violation | experiments #6 |
| Product price cannot be negative | `products.price` | `CHECK products_price_non_negative` | none | `23514` check_violation | experiments #7 |
| A payment must reference an existing ticket | `payments.ticket_id` → `tickets.id` | `FOREIGN KEY payments_ticket_fk` | none | `23503` foreign_key_violation | experiments #8 |
| Payment amount cannot be negative | `payments.amount` | `CHECK payments_amount_non_negative` | none | `23514` check_violation | manual: update to a negative amount |
| A captured payment's external reference must not repeat | `payments.external_payment_reference`, `payments.status` | partial `UNIQUE payments_external_reference_captured_unique` (`WHERE status = 'Captured'`) | only rows with `status = 'Captured'` are protected; two `Pending`/`Failed` attempts can still share a reference before either is captured (deliberate, see below) | `23505` unique_violation | experiments #9 |
| A validation must name one real ticket by id *and* by code together | `validations.ticket_id`, `validations.ticket_code` → `tickets.id`, `tickets.ticket_code` | composite `FOREIGN KEY validations_ticket_fk` | none | `23503` foreign_key_violation | experiments #10 |
| Currency must be present and consistently shaped | `products.currency`, `tickets.currency`, `payments.currency` | `NOT NULL` + `CHECK ... ~ '^[A-Z]{3}$'` | only checks the *shape* (3 upper-case letters), not that it is a real ISO 4217 code, and not that a ticket's currency actually matches its product's currency | `23514` check_violation / `23502` not_null_violation | manual: insert `currency = 'dkk'` or `currency = NULL` |

**Why the captured-only unique index, not a plain `UNIQUE` column:** a plain `UNIQUE(external_payment_reference)` would also block a legitimate retry, a `Failed` attempt followed by a new attempt with a fresh gateway reference is fine, but some gateways return the *same* reference for a retried authorization before capture. Restricting the uniqueness to `status = 'Captured'` enforces the actual business rule ("one captured charge, recorded once") without rejecting retries that never captured. This is a modelling decision, not the only defensible one, see the issue register.

## Issue register

Invariants that this migration deliberately does **not** enforce, kept for the transactions lecture.

### Issue 1: concurrent seat reservation

- **Evidence:** `trips_reserved_seats_valid` (`reserved_seats between 0 and capacity`) is a row-level check. It is correct for a single atomic `UPDATE trips SET reserved_seats = reserved_seats + 1 WHERE id = ... AND reserved_seats < capacity`, but it does **not** protect a purchase flow that first `SELECT`s the remaining capacity, decides in the application that a seat is free, and only then issues the `UPDATE`.
- **Problem:** under `READ COMMITTED` (Postgres's default), two concurrent transactions can both read the same "1 seat left" state before either commits, and both proceed to sell a ticket for it.
- **Consequence:** the trip can be sold over capacity even though every individual row always satisfies the check.
- **Specific improvement:** use an atomic conditional update (`... WHERE reserved_seats < capacity`) or `SELECT ... FOR UPDATE` / `SERIALIZABLE` isolation around the purchase transaction, so the seat count and the ticket insert are decided from the same locked read.
- **Open question:** whether seat reservation should be pessimistic (lock the trip row) or optimistic (retry on conflict) is a transaction-design decision for the next lecture, not a schema decision.

### Issue 2: payment capture is a two-system operation

- **Evidence:** `payments` records the *result* of a call to an external payment gateway; the gateway and this database are two separate systems with no shared transaction.
- **Problem:** the gateway can capture a charge while the local `INSERT` into `payments` fails or never runs (crash, network drop), or the reverse, where a local row exists but the gateway never actually captured funds.
- **Consequence:** no CHECK, FOREIGN KEY or UNIQUE constraint inside this database can guarantee that a `payments` row and the external charge it names are consistent with each other.
- **Specific improvement:** an idempotency key on the outgoing gateway call plus a reconciliation job that compares gateway records against `payments` rows, not a database constraint.
- **Open question:** left for the transactions/workflow-design lecture, as the lab instructions call out explicitly.

### Issue 3: disabled-user purchases

- **Evidence:** `users.is_disabled` exists in the schema, but nothing currently stops a disabled user's ticket from being inserted.
- **Problem:** "a disabled user may not purchase a new ticket" is a *cross-table* rule (it reads `users.is_disabled` while writing `tickets`), a plain `CHECK` on one table cannot express it. It would need a trigger, or enforcement at the transaction/application layer.
- **Consequence:** currently, database or column check disabled, so a disabled user can still buy tickets.
- **Specific improvement:** either a `BEFORE INSERT` trigger on `tickets` that rejects the row when `users.is_disabled`, or an explicit application-level guard inside the purchase transaction.
- **Open question:** whether "disabled" should even block *new* purchases, or only block future validations of tickets already held, is a domain decision this lab does not answer.

## State-transition trace

### Ticket purchase

1. Read the target trip; confirm `status = 'Scheduled'` and that a seat is available (`reserved_seats < capacity`). This decision is made outside the database, see issue 1.
2. Read the chosen `product` by `code` to get the current price and currency.
3. `INSERT` the `tickets` row (`user_id`, `trip_id`, `ticket_code`, `status = 'Active'`, `product_code`, `valid_from_utc`, `valid_to_utc`, `price`, `currency` copied from the product). Evaluates `tickets_user_fk`, `tickets_trip_fk`, `tickets_product_fk`, `tickets_ticket_code_unique`, `tickets_id_ticket_code_unique`, `tickets_valid_window`, `tickets_price_non_negative`, `tickets_currency_iso4217`, `tickets_status_allowed`.
4. `UPDATE trips SET reserved_seats = reserved_seats + 1 WHERE id = ...`. Evaluates `trips_reserved_seats_valid` against the trip's current `capacity`.
5. `INSERT` the `payments` row once the gateway confirms capture (`status = 'Captured'`, `amount` = ticket price). Evaluates `payments_user_fk`, `payments_ticket_fk`, `payments_amount_non_negative`, `payments_currency_iso4217`, `payments_status_allowed`, `payments_external_reference_captured_unique`.
6. Steps 3 to 5 belong in one transaction so that a failure partway through (no seats, gateway decline) leaves no ticket or payment visible to any other reader, not implemented by this migration; flagged for the transactions lecture.

### Ticket validation

1. Look up the ticket by the `ticket_code` presented at boarding; obtain its `id`.
2. `INSERT` a `validations` row with that `ticket_id` **and** the same `ticket_code`, plus `vehicle_id`, `stop_id`, `device_id`, `result`. Evaluates `validations_ticket_fk` (the composite check that `ticket_id` and `ticket_code` name the same real ticket) and `validations_result_allowed`.
3. No `trips` or `tickets` row changes as part of validation, matches the lab brief's note that reporting does not need to be updated before validation can complete.

## Delete and update behaviour

No `ON DELETE`/`ON UPDATE` clause is added anywhere in this migration, which leaves every foreign key at Postgres's default (`NO ACTION`, effectively **restrict**). That default is a deliberate choice, not an oversight:

- `trips` → `tickets`: **restrict.** A trip with issued tickets cannot be deleted. Timetable maintenance that "replaces" a route should insert new trip rows and set the old trip's `status` (e.g. `'Cancelled'`), never delete a trip that tickets reference.
- `tickets` → `payments`, `tickets` → `validations`: **restrict.** A ticket with a recorded payment or validation cannot be deleted. Refunds and cancellations are a `status` change (`'Cancelled'` / `'Refunded'`), not a row deletion.
- `users` → `tickets`, `users` → `payments`: **restrict.** A user with any purchase history cannot be deleted. Account closure is represented by `users.is_disabled = true`, which keeps the historical rows intact.
- `products` → `tickets`: **restrict.** A product referenced by any ticket cannot be deleted; discontinuing a product needs its own availability/status column, which does not exist in this slice.

Summary: every relationship that touches `tickets`, `payments` or `validations` defaults to restrict, because compliance and reporting need the full history. Nothing in this slice is cascaded or soft-deleted, and no retention/archival policy (e.g. "drop validations older than N years") is defined yet, that is an open question, not a decision made here.

## What every writer can safely assume after this migration

- A row that exists in `tickets`, `payments` or `validations` always names a real, currently-existing user/trip/product/ticket, the foreign keys guarantee referential integrity regardless of which application or script performs the write.
- `trips.reserved_seats` never exceeds `trips.capacity` *as a stored value*, but a writer must still use an atomic conditional update (not read-then-write) to avoid overselling under concurrency (issue 1).
- `tickets.ticket_code` and the `(ticket_id, ticket_code)` pair on any `validations` row are always genuine, a validation can never be attributed to the wrong ticket.
- Every `Captured` payment has a reference that appears in exactly one captured row.
- What is **not** guaranteed: that a `payments` row matches reality at the external gateway (issue 2), that a disabled user is blocked from purchasing (issue 3), or that concurrent purchases cannot race past capacity (issue 1).

## Evidence log (verified 2026-09-22)

Run against a freshly recreated container (`docker compose down -v && docker compose up -d`):

1. **Successful writes:** `database/postgres/init/011_ticketing_seed.sql` runs automatically at container start, before the migration is applied. Applying `migrations/011_ticketing_integrity.sql` immediately afterward completed with no error (`BEGIN` / 5×`ALTER TABLE` / `CREATE INDEX` / `ALTER TABLE` / `COMMIT`), since every `ADD CONSTRAINT` and `ALTER COLUMN ... SET NOT NULL` is checked against the existing rows at migration time, this is itself evidence that every seeded trip, product, user, ticket, payment and validation row already satisfies all 14 rules. `\d tickets` confirmed the constraint list: 1 primary key, 2 unique constraints, 4 check constraints, 3 outgoing foreign keys (`user_id`, `trip_id`, `product_code`), plus 2 incoming foreign keys from `payments` and `validations`.
2. **Rejected writes:** all 10 statements in `database/postgres/experiments/constraints_should_fail.sql` were rejected, each by the specific named constraint the comment predicted:

   | # | Constraint | Kind |
   | --- | --- | --- |
   | 1 | `trips_capacity_non_negative` | check |
   | 2 | `trips_reserved_seats_valid` | check |
   | 3 | `tickets_trip_fk` | foreign key |
   | 4 | `tickets_valid_window` | check |
   | 5 | `tickets_ticket_code_unique` | unique |
   | 6 | `tickets_status_allowed` | check |
   | 7 | `products_price_non_negative` | check |
   | 8 | `payments_ticket_fk` | foreign key |
   | 9 | `payments_external_reference_captured_unique` | unique |
   | 10 | `validations_ticket_fk` | composite foreign key |

   10/10 expected failures observed; every error's `DETAIL` line matched the violated rule.
