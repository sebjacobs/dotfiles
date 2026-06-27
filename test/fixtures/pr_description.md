## Summary

A request came in to add a new **vendor** to our curated list. This list is used to populate the dropdown menu on the catalog form.

I have taken this opportunity to also:
- make future requests easier to service.
- clean up some dead code in the Catalog model.

## Key changes

- removed the unused `Catalog#vendor_name_select` method.
- `config/vendor_manufacturers.yml` — extracted from `Catalog::MANUFACTURERS`.
- `config/vendor_suppliers.yml` — extracted from `Catalog::SUPPLIERS` (for consistency).
- added `Globex` to the list of vendors.

## Out-of-scope / Follow-ups

I would like to audit the production catalog data to understand if there are any other key vendors missing from this list.
