-- Step 4: represents the old application's read path. Must keep working
-- at every stage up to (but not including) step 9 (product_code removal).
select id, product_code, price, currency
from tickets
order by id;
