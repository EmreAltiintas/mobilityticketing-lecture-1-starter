# Lecture 1 dossier

## Route-stop primary key

Key: `(route_id, stop_id)`.

A route-stop row records that a route calls at a stop, and where in the
sequence. In this slice a route calls at any stop at most once, so the
`(route_id, stop_id)` pair already identifies the row. `stop_sequence` is an
attribute of that pair, constrained unique per route so the ordering has no
gaps in meaning or ties.

A stop may **not** occur more than once on the same route under this key. Real
loop routes and out-and-back services do revisit a stop; supporting them means
moving the key to `(route_id, stop_sequence)` and letting `stop_id` repeat.

## SQL model vs. ER diagram

- Entities match: operators, routes, stops, route_stops (associative), trips.
- Cardinalities match: operator 1..* routes; route *..* stops via route_stops;
  route 1..* trips.
- Difference: the ER diagram leaves the route-stop identity implicit ("a stop
  on a route"). The SQL model makes it explicit as `(route_id, stop_id)` and
  thereby encodes the "at most once" assumption that the diagram did not state.
- `city_id` on routes and stops is a plain text attribute here, not a foreign
  key to a `cities` entity that the diagram implies. No `cities` table exists
  in this slice.

## One functional dependency

`stop_id -> city_id, name` in `stops`: a stop determines its city and name.
`route_id -> operator_id, city_id, mode, short_name` in `routes` likewise.

In `route_stops`, `(route_id, stop_id) -> stop_sequence` and
`(route_id, stop_sequence) -> stop_id`. There is no dependency from part of the
key alone, so the table is already normalized; storing `stop.name` or
`route.short_name` in `route_stops` would introduce a partial dependency and
allow the same stop to carry two different names. Normalization prevents that
update anomaly.

## Assumption that may change later

A route visits each stop at most once. Loop lines (for example an airport
circulator) and out-and-back branches break this, and would force the
route-stop key to `(route_id, stop_sequence)`. Direction of travel is also
folded into a single route today; splitting inbound/outbound into separate
routes or adding a `direction` column is the likely next change.
