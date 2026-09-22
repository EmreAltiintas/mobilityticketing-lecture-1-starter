-- Step 6: only run this after EVERY ticket has a valid product_id (verify.sql
-- returns zero rows). Validates the NOT VALID foreign key added in 030
-- (a full scan against existing rows, done explicitly and deliberately
-- rather than implicitly at ADD COLUMN time), then makes the column
-- required. After this, an insert that supplies only product_code fails --
-- the old writer is no longer a valid caller.

begin;
set local lock_timeout = '3s';

alter table tickets
validate constraint tickets_product_id_fk;

alter table tickets
alter column product_id set not null;

commit;
