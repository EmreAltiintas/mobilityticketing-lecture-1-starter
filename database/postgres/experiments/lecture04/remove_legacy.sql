-- Step 9 rehearsal: find what still depends on tickets.product_code before
-- touching it, then try dropping it WITHOUT cascade. Rolled back at the
-- end so this can be re-run in the lab database; a real rollout commits
-- once every dependency below is confirmed clear.

begin;
set local lock_timeout = '3s';

-- Views referencing product_code anywhere in their definition.
select schemaname, viewname
from pg_views
where definition ilike '%product_code%';

-- Functions referencing tickets.product_code in their body -- covers the
-- week-37 reporting objects and this week's own writer/reader functions.
--
-- The `public`-schema and prokind='f' filters below must be forced to run
-- BEFORE pg_get_functiondef() is called: Postgres does not guarantee a
-- WHERE clause is evaluated left-to-right, and pg_get_functiondef() raises
-- "... is an aggregate function" for any aggregate's oid (e.g. array_agg
-- in pg_catalog) regardless of schema. An unqualified join+ilike lets the
-- planner apply the ilike/pg_get_functiondef predicate to catalog rows
-- before the schema filter narrows anything, which aborts the whole
-- rehearsal transaction. `WITH ... AS MATERIALIZED` forces the candidate
-- set to be computed first, so pg_get_functiondef only ever sees the one
-- ordinary function actually in `public`.
with candidate_functions as materialized (
  select p.oid, p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'  -- ordinary functions only; excludes aggregates/procedures/window fns
)
select proname
from candidate_functions
where pg_get_functiondef(oid) ilike '%tickets%product_code%';

-- Expect zero rows from both checks above: week 37's reporting objects
-- (captured_revenue_for_day, daily_captured_revenue,
-- add_inserted_payment_to_daily_revenue) join through tickets.trip_id and
-- tickets.id only, never tickets.product_code, and this week's own
-- new_writer.sql/new_reader.sql/final_writer.sql/final_reader.sql already
-- avoid it or degrade to product_id-only.

alter table tickets drop column product_code;

-- Confirm the migrated reader/writer still work with the column gone:
--   \i database/postgres/experiments/lecture04/final_reader.sql
--   \i database/postgres/experiments/lecture04/final_writer.sql
-- And confirm the OLD ones no longer do:
--   \i database/postgres/experiments/lecture04/old_reader.sql
--   \i database/postgres/experiments/lecture04/old_writer.sql

rollback;
-- Kept as a rehearsal: this leaves product_code in place so the lab
-- database can be reused. A real rollout commits this step -- only once
-- every writer and reader in production has been confirmed to run on
-- product_id alone, and only after the checks above are re-run against
-- the real schema (this script cannot know about application code outside
-- the database).
