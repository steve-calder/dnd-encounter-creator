# Proposal

## Why

Every later step (vector search, MCP tools, generation) needs a trustworthy local
monster catalog. Build-order step 1 is to import a pinned snapshot and show a
stat block in Rails. Profiling the pinned snapshot showed that only the 379 SRD
records have playable stat blocks. All 379 come from Free Basic Rules 2014 and
2024. The other 11,084 records hold only lore and a CR (often malformed), so
importing them adds noise and no eligible monsters.

## What Changes

- Commit a curated dataset, `db/data/srd_monsters.json`. It holds the 379 SRD
  records (the books `Free Basic Rules (2014)` and `Free Basic Rules (2024)`),
  copied verbatim from commit `649f7f964b20835852bff3659aa36875dd7c35df` of
  `nick-aschenbach/dnd-data` (`data/monsters.json`, SHA-256
  `cee519309b7241ed6cd45b2217f9e37e481d451aa3fd9ce251dfbd7a4ef302c7`). A
  provenance header in the file records the upstream repo, commit, path,
  checksum, selected books, and record count.
- The import reads only that committed file. It makes no network requests and
  makes no decisions about which records to ingest. The file already holds
  exactly the catalog.
- Add a dev-only extraction script that regenerates the file byte-for-byte from
  the pinned upstream. It verifies the upstream checksum first. The import,
  tests, and CI never run it.
- Store each record under a stable, deterministic ID with the original source
  record unchanged, plus normalized fields: name, size, type, alignment, CR, XP,
  AC, HP, speed, ability scores, traits, actions, and reactions.
- Record XP provenance (from source data, or derived from CR). Mark records
  ineligible for generation, with reasons, when XP is unresolved or zero, CR is
  unparseable, or the stat block is incomplete. For example, the 7 spell-summon
  records with CR "None" become ineligible.
- Keep same-name variants (47 creatures appear in both editions) as distinct
  records labeled by source book.
- Make re-import idempotent: running it again upserts by stable ID and leaves the
  record count unchanged.
- Keep the pinned upstream and its checksum as the provenance record, as
  CLAUDE.md requires, while removing the runtime download.
- Add a catalog index page and a per-monster stat block page in Rails, with the
  SRD CC-BY-4.0 attribution.
- **Design doc conflict:** `DND_ENCOUNTER_CREATOR_DESIGN.md` says to import the
  full JSON "with no book restrictions". This change limits the catalog to the SRD
  at the user's direction, and it updates the design doc to match.

## Capabilities

### New Capabilities
- `monster-catalog`: The curated, committed SRD dataset and its extraction,
  importing it with stable record identity, normalized fields, XP provenance,
  generation eligibility, and idempotent re-import.
- `monster-stat-blocks`: Browsing the catalog and rendering a full stat block for
  a single record in the Rails UI.

### Modified Capabilities
None. No specs exist yet.

## Impact

- New: `db/data/srd_monsters.json` (about 1.3 MB, committed),
  `script/extract_srd_monsters.rb`, the `Monster` Mongoid document, the catalog
  import services in `app/services/`, a `catalog:import` rake task,
  `MonstersController` with views, and routes.
- Tests: extraction filter, dataset loading, importer, normalization, and
  eligibility tests against small fixture JSON (no network), plus controller and
  view tests.
- Only the extraction script uses the network (stdlib `Net::HTTP`). There are no
  new gems.
- Docs: update `DND_ENCOUNTER_CREATOR_DESIGN.md` (catalog scope and the committed
  dataset) and `README.md` (import command and how to regenerate the dataset).
- Out of scope: embeddings and the vector index (step 3), XP budgets (step 2),
  and generation.
