-- Step 4: represents an application instance that has NOT been rewritten
-- yet. Inserts using only product_code, exactly as before migration 030.
-- Must still work at every stage up to (but not including) 032.
\set ticket_id 'LAB04-OLD-1'
\set ticket_code 'LAB04-CODE-OLD-1'

insert into tickets
    (id, user_id, trip_id, ticket_code, status, product_code,
     valid_from_utc, valid_to_utc, price, currency)
select :'ticket_id', user_id, trip_id, :'ticket_code', status, product_code,
       valid_from_utc, valid_to_utc, price, currency
from tickets
where id = 'TICKET-1';
