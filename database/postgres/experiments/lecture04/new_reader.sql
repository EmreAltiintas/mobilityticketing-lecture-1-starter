-- Step 4/5: works both before and after existing tickets have product_id
-- filled in. Falls back to resolving through product_code only when
-- product_id is still null.
select t.id,
       coalesce(p_new.id, p_old.id) as resolved_product_id,
       t.price,
       t.currency
from tickets t
left join products p_new
    on p_new.id = t.product_id
left join products p_old
    on t.product_id is null
    and p_old.code = t.product_code
order by t.id;
