-- Step 9: the fully migrated reader. Joins through product_id only, and
-- must survive product_code's removal from tickets.
select t.id,
       p.code as product_code,
       p.price as catalogue_price,
       t.price as price_paid,
       t.currency
from tickets t
join products p on p.id = t.product_id
order by t.id;
