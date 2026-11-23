# Tasks

## 1. Curated SRD dataset

- [x] 1.1 Write `script/extract_srd_monsters.rb` (stdlib only; pinned repo, commit `649f7f9…`, path, and upstream SHA-256 in constants, plus a `BOOKS` constant). It downloads from the commit URL or reads a local path given as an argument, verifies the SHA-256 and aborts on a mismatch, filters to `BOOKS`, keeps records verbatim, sorts by book and then name, and writes `{ "source": {...}, "monsters": [...] }` as pretty JSON atomically. Keep the filter and checksum logic in methods testable without the network. Verify with `test/script/extract_srd_monsters_test.rb`, which uses a tiny upstream-style fixture with one non-SRD record: the non-SRD record is excluded, a checksum mismatch leaves the output untouched, and the header fields are correct.
- [x] 1.2 Run the extractor against the pinned upstream to generate and commit `db/data/srd_monsters.json`. Verify the header shows 379 records and both books, then run the extractor a second time and confirm `shasum -a 256 db/data/srd_monsters.json` is unchanged (reproducible output).

## 2. Monster model

- [x] 2.1 Add `app/models/monster.rb` (Mongoid, collection `monsters`, string `_id`, fields per design §3, indexes on `eligible`, `xp`, and `name`). Verify with `test/models/monster_test.rb`, which saves and reloads a record with a string ID and nested stat-block arrays.
- [x] 2.2 Add a test helper that clears the `monsters` collection before each test. Use `delete_all`, never drop the collection. Verify by running the model test twice in parallel with no leftover-data failures.

## 3. Pure normalization and rules

- [x] 3.1 Create `test/fixtures/files/srd_monsters_sample.json` in the committed dataset's header-plus-records format, with about 7 records copied from `db/data/srd_monsters.json` (Giant Shark 2014, Ape 2014 and 2024, Frog, Draconic Spirit, a `"1/4"` CR record, a `"1,800"`-style XP record) and a matching `record_count`. Verify the file parses and each case is present.
- [x] 3.2 Implement `Catalog::CrXp` (2014/2024 CR-to-XP table, fractional CRs, no value for CR 0 because it is worth 0 or 10 XP). Verify with a unit test of representative CRs, including 1/8, 1/4, 1/2, 5, and 30, and that CR 0 returns nil.
- [x] 3.3 Implement `Catalog::Normalizer` (raw record → attrs: CR parsing, XP comma stripping and derivation with provenance, AC and HP display and number, abilities, JSON-encoded traits, actions, bonus actions, reactions, legendary actions, and spells, lore stripping, `content_hash` with `VERSION`). Verify with unit tests for every "Normalized fields" and "XP provenance" scenario in `specs/monster-catalog/spec.md`.
- [x] 3.4 Implement `Catalog::Eligibility` (reasons `cr_unresolved`, `xp_unresolved`, `xp_zero`, `incomplete_stat_block`). Verify with unit tests for the Draconic Spirit, Giant Shark, and Frog scenarios.
- [x] 3.5 Implement `Catalog::RecordId` (`srd-2014--giant-shark`). Verify with unit tests for both books, punctuation in names (for example `Animated Object (Small or Medium)`), and same-name variants yielding distinct IDs.

## 4. Dataset loading and importer

- [x] 4.1 Implement `Catalog::Dataset.load` (defaults to `db/data/srd_monsters.json`, returns the header and records, raises on a missing header or a `record_count` mismatch, no network code). Verify with unit tests for a valid fixture, a missing header, and a count mismatch, each reporting the expected and actual values.
- [x] 4.2 Implement `Catalog::Importer` and `Catalog::ImportReport` (imports every dataset record, upserts by ID, created/updated/unchanged via `content_hash`, records the upstream commit and checksum on each record and in the report, raises on an in-run ID collision, reports stale IDs, eligible and ineligible counts by reason). Verify with `test/services/catalog/importer_test.rb` against the fixture: the first import creates all fixture records; the second reports 0 created, all unchanged, and the count unchanged; an integrity failure writes nothing.
- [x] 4.3 Add `lib/tasks/catalog.rake` with `catalog:import`, which prints the report. Verify by running `bin/rails catalog:import` with networking unavailable or unused: 379 created, 372 eligible, 7 ineligible. Run it again and confirm 379 unchanged.
- [x] 4.4 Document in `README.md` the import command, the committed dataset and its provenance header, the SRD-only scope, and how to regenerate the dataset with `script/extract_srd_monsters.rb` (and that the extractor is dev-only). Verify that the documented commands run as written.

## 5. Catalog and stat block UI

- [x] 5.1 Add routes (`resources :monsters, only: [ :index, :show ]`, root → `monsters#index`) and `MonstersController#index` with the escaped, case-insensitive name filter. Verify with controller tests: the listing shows both Ape variants with their books, ineligible records are marked, "shark" filters correctly, and `.*` returns none.
- [x] 5.2 Add the show action and stat block views (header, AC/HP/speed, ability table with computed modifiers, defenses, senses and languages, CR/XP, and the traits, actions, bonus actions, reactions, legendary actions, and spells sections, omitting empty ones), plus the source, XP provenance, and ineligibility reasons. Verify with controller tests for the Giant Shark scenario, no empty headings, and the ineligible Draconic Spirit reasons.
- [x] 5.3 Verify the 404 and escaping behavior. Add a controller test that an unknown ID returns 404 and a test that `<script>` in a trait description renders as literal text. Add a `rescue_from` only if the Mongoid railtie mapping is absent.
- [x] 5.4 Add the `_srd_attribution` partial (CC-BY-4.0 notice for SRD 5.1 and 5.2) to the layout. Verify with a controller test asserting the notice on the index and show pages.

## 6. Docs and integration

- [x] 6.1 Update `DND_ENCOUNTER_CREATOR_DESIGN.md` "Catalog and retrieval" to state the SRD-only scope (Free Basic Rules 2014 and 2024, why, and how to widen it via the extractor's `BOOKS`) and that the catalog ships as the committed `db/data/srd_monsters.json`. In its build order, note the step-3 vector index filter follow-up from design.md. Verify the doc no longer says "no book restrictions" or implies downloading at import time.
- [x] 6.2 Run `bin/ci` (rubocop, audits, brakeman, tests) and confirm it passes. Rubocop must cover `script/`.
- [x] 6.3 With Mongo running and the real catalog imported, open `/monsters`, filter "shark", and open Giant Shark. Confirm the stat block matches the spec scenario and the attribution shows.

## Workflow follow-up

- Archive the change after review, which syncs `monster-catalog` and `monster-stat-blocks` into `openspec/specs/`.
