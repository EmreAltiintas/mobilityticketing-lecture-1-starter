-- Step 5/7: after expansion and backfill, this must return zero rows
-- before 032 is allowed to make product_id required.
select t.id, t.product_code, t.product_id
from tickets t
left join products p on p.id = t.product_id
where t.product_id is null
or p.id is null
or t.product_code is distinct from p.code;
