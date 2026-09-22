-- Step 2: the "obvious" but unsafe version of this migration, rehearsed on
-- a DISPOSABLE database only (docker compose down -v && docker compose up
-- -d first -- never run this against data you want to keep).
--
-- Prediction before running: dropping product_code destroys the only link
-- between an existing ticket and its product. Adding product_id as NOT
-- NULL with a generated default does not restore that link -- it just
-- gives every ticket a random, unrelated UUID. Nothing here raises an
-- error; the danger is that it looks like it worked.

begin;
set local lock_timeout = '3s';

alter table tickets drop column product_code;

alter table tickets
    add column product_id uuid not null default gen_random_uuid();

commit;

-- Observe the damage. NOTE: products has no id column at all at this
-- point -- that only gets added by the real migration (030), which this
-- rehearsal deliberately skips -- so there is nothing to even join
-- against. That is itself the finding: not merely "the join returns no
-- match", but "there is no concept of product identity left to check
-- against, on either side".
select t.id, t.product_id
from tickets t
order by t.id;
-- Every row shows a random UUID with nothing in the database that could
-- confirm or deny which product it was ever supposed to mean. Compare
-- against the ticket list baseline.sql printed before this rehearsal --
-- that mapping cannot be reconstructed from this state.

-- The old reader and writer are broken outright, with no transition
-- period: run these next and note the exact error.
--   \i database/postgres/experiments/lecture04/old_reader.sql
--   \i database/postgres/experiments/lecture04/old_writer.sql
-- Both fail with: column "product_code" of relation "tickets" does not
-- exist -- there was no way for any code that had not been rewritten yet
-- to keep working, because nothing was kept in place during the change.

-- Reset the disposable database before continuing with the real migration:
--   docker compose down -v && docker compose up -d
