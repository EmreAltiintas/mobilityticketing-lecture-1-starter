-- Step 5: fill in product_id for tickets that already exist. Resolves only
-- rows where product_id is still null, matching on the existing
-- product_code -- safe to run any number of times: once every matching
-- ticket has its product_id set, a repeat run updates zero rows, and a
-- fresh old-style ticket (written after this first runs) is picked up by
-- the next run without touching anything already assigned.
update tickets t
set product_id = p.id
from products p
where t.product_id is null
and p.code = t.product_code;
