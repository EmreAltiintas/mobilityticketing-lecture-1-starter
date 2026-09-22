-- Step 3: add the new columns without removing the old ones. Every product
-- gets a stable ID; tickets get a nullable product_id with a NOT VALID
-- foreign key (checked for new/updated rows, not yet enforced against
-- existing rows -- that happens explicitly in 032, after backfill).
--
-- On a much larger table: the UPDATE that fills gen_random_uuid() into
-- every existing product row rewrites the whole table and holds locks
-- while it runs. products is tiny here, so this is instant; on a large
-- table you would batch the UPDATE (e.g. by primary-key range) so no
-- single statement holds a lock for long, and you would consider doing
-- the ADD COLUMN and the backfill in separate deploys. The NOT VALID
-- foreign key is exactly this pattern applied to tickets.product_id: add
-- and enforce it for new writes immediately, without an expensive full
-- table scan against every existing row until 032 explicitly validates it.

begin;
set local lock_timeout = '3s';

alter table products add column id uuid;

update products
set id = gen_random_uuid()
where id is null;

alter table products
alter column id set default gen_random_uuid();

alter table products
alter column id set not null;

alter table products
add constraint products_id_unique unique (id);

alter table tickets
add column product_id uuid;

alter table tickets
add constraint tickets_product_id_fk
foreign key (product_id)
references products(id)
not valid;

commit;
