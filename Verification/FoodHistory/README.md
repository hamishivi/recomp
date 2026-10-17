# Meal history verification — October 17, 2026

Food entry now offers **Meal history** alongside **Your usuals**. It searches the full local diary, newest first, across names, ingredient names/portions, meal types, and notes. Search ignores case and diacritics, supports multiple words across fields, and has no recent-meal cutoff. Deleted entries, future entries, and the entry currently being edited are excluded.

Selection fills the current draft and requires Save to log. It preserves the current date, timezone, meal type, notes, and photos, copies the reviewed ingredient breakdown and estimate status, and supports portion adjustments and Undo. Old photos, photo references, follow-up questions, entry IDs, and Health export receipts are not copied. Favourites change only through the existing explicit save-as-usual action. No schema or storage migration is needed.

## Completed checks

- 447 core tests passed in Debug and Release, including five history-query tests covering older records, sorting, multi-field search, and exclusions.
- 70 composer checks passed with the production model/store and mocked observation, AI, and Health, including copy identity, ingredient provenance, Undo, draft isolation, persistence, and manual values beyond the AI schema.
- 41 existing composer polish regressions and 158 interface/source checks passed.
- Debug simulator app/widget and signed Release iPhone app/widget builds passed.
- Four focused simulator UI cases passed: search/reuse across diary days while keeping usuals separate; replacement/Undo/discard; empty states/search cancellation/editing exclusion; and dark appearance with the largest accessibility text size.

The screenshots below use synthetic records in the isolated simulator diary. History row metadata uses the theme's explicit muted colour so button styling does not fade it to a low-contrast tint. Raw result bundles and device backups remain local and are excluded from Git.

- [Search for a meal from an older diary day](history-search-light.png)
- [Dark appearance with the largest accessibility text size](history-dark-largest-text.png)
