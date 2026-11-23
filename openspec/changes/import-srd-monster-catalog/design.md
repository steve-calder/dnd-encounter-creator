# Design

## Context

- The app is greenfield. It has no models, no `app/services/`, and no routes
  except `/up`. It uses Mongoid only (no ActiveRecord), Minitest, and parallel
  tests against `dnd_encounter_creator_test`.
- `docker/mongo/init/01-vector-index.js` already creates a `monsters` collection
  with `monsters_vector_index` (path `embedding`, filters `challenge_rating` and
  `environment`). The `Monster` model must use that collection name and the
  `challenge_rating` field name, or step 3 will need to recreate the index.
- The pinned upstream file is a 30 MB JSON array of 11,463 objects with the keys
  `name`, `description`, `properties`, `publisher`, and `book`. The 379 SRD
  records come to about 1.3 MB of pretty-printed JSON, which is small enough to
  commit. The stat block lives in `properties`, with Roll20-style keys. Facts
  that shape the parser, from profiling the 379 SRD records:
  - `Challenge Rating` is an Integer (263 records) or a String (116), such as
    `"1/4"` or `"None"`. `data-CrNum` holds the numeric form.
  - `data-XP` is present on all 379 records, as an Integer or a comma-grouped
    String (`"1,800"`).
  - `AC` and `HP` are display strings (`"13 (Natural Armor)"`,
    `"126 (11d12+55)"`). `data-AcNum` and `data-HpNum` hold the numbers.
  - `data-Traits`, `data-Actions`, `data-Reactions`, `data-Bonus Actions`, and
    `data-Legendary Actions` are JSON-encoded arrays. Each element has
    `Name`/`Desc`, and attack actions add `Hit Bonus`, `Reach`, `Target`,
    `Damage`, `Damage Type`, and optional `Damage 2`/`Damage 2 Type`.
  - `data-Spells` is a JSON-encoded object (`{"spells": {"cantrips": [...]}}`).
    `Spell Book` is a comma-separated string.
  - Two complete records have no actions (Frog and Sea Horse). Seven 2024
    records are spell summons with CR `"None"` and XP 0.
  - In 323 of the 379 records, `description` starts with a Roll20 promotional
    paragraph, and it then repeats the traits and actions as prose.

## Goals / Non-Goals

**Goals:**
- Pure, unit-testable normalization and eligibility logic, separate from I/O.
- Services that a later MCP server can call unchanged.
- The import and the app never need the network. Only the dev-only extraction
  script downloads anything.

**Non-Goals:**
- Embeddings, the search document, or the vector index (step 3). The model must
  only not block them.
- Deleting records that disappear when the pin changes (see Risks).
- Pagination, sorting, or filters beyond name on the catalog page. 379 rows
  don't need them.

## Decisions

### 1. Committed curated dataset with a dev-only extractor
The catalog's source of truth is `db/data/srd_monsters.json`:

```json
{
  "source": {
    "repository": "nick-aschenbach/dnd-data",
    "commit": "649f7f964b20835852bff3659aa36875dd7c35df",
    "path": "data/monsters.json",
    "sha256": "cee519309b7241ed6cd45b2217f9e37e481d451aa3fd9ce251dfbd7a4ef302c7",
    "books": [ "Free Basic Rules (2014)", "Free Basic Rules (2024)" ],
    "record_count": 379,
    "generated_by": "script/extract_srd_monsters.rb (do not edit by hand)"
  },
  "monsters": [ /* upstream records, verbatim */ ]
}
```

- Records stay byte-for-byte upstream objects, so the "original source data"
  rule holds and parser fixes never require re-extraction.
- Records are sorted by `book` and then `name`, and the file is written as
  pretty-printed JSON with a trailing newline. Diffs stay reviewable, and
  regeneration is deterministic. The header has no timestamp.
- `script/extract_srd_monsters.rb` (stdlib only) downloads the raw file from the
  pinned commit URL, or reads a local path given as an argument. It verifies the
  upstream SHA-256 and aborts with expected and actual values on a mismatch. It
  filters to the books in its `BOOKS` constant, sorts, and writes atomically
  (temp file, then rename). The pin and the book list live in this script only.
- `Catalog::Dataset.load(path = Rails.root.join("db/data/srd_monsters.json"))`
  parses the file and checks that the header exists and that
  `monsters.size == record_count`. It returns the header and records. It has no
  network code.

Alternatives considered:
- *Download at import time and filter (the previous plan).* Rejected because
  every import depended on the network and redid the scope decision.
- *Commit the full 30 MB upstream file.* Rejected because 97% of it would never
  be used.
- *Normalize during extraction (our own schema).* Rejected because it loses the
  verbatim source and couples every parser change to re-extraction.
- *Generate once and discard the script.* Rejected because the file then can't be
  reproduced and is hard to widen later.

### 2. Stable ID: `<book-key>--<name-slug>`
The book key maps `Free Basic Rules (2014)` to `srd-2014` and
`Free Basic Rules (2024)` to `srd-2024`, giving IDs like
`srd-2014--giant-shark`. This is the string `_id`. IDs are readable in URLs and
MCP payloads, and they're deterministic. Profiling found no slug collisions. The
importer still raises if two records in one run map to the same ID, so it never
overwrites silently.

- *Alternative:* a hash of the raw record. Rejected because the ID would change
  whenever upstream fixes a typo.

### 3. Model shape: one flat `Monster` document
The `Monster` document has these fields:
- `_id` (String)
- `name`, `book`, `publisher`
- `size`, `creature_type`, `alignment`
- `challenge_rating` (Float), `challenge_rating_display`
- `xp` (Integer), `xp_source` (`"source"` or `"derived_from_cr"`)
- `armor_class`, `armor_class_display`, `hit_points`, `hit_points_display`,
  `speed`
- `abilities` (Hash of six Integers)
- `saving_throws`, `skills`, `immunities`, `condition_immunities`,
  `resistances`, `vulnerabilities`, `senses`, `languages`
- `traits`, `actions`, `bonus_actions`, `reactions`, `legendary_actions`
  (Arrays of Hashes), `spells` (Hash)
- `lore` (String)
- `eligible` (Boolean), `ineligibility_reasons` (Array of Strings)
- `source` (the raw Hash, verbatim)
- `content_hash`, `source_revision`, `source_checksum`

The stat-block sections are plain arrays of hashes, not embedded documents,
because they're read-only display data. It uses `type` → `creature_type` to
avoid Mongoid's `_type` confusion. Indexes cover `eligible`, `xp`, and `name`.

### 4. Pipeline of small services in `app/services/catalog/`
```
script/extract_srd_monsters.rb   (dev only, network)
     |  pinned upstream -> verify sha256 -> filter books -> sort
     v
db/data/srd_monsters.json        (committed)
     |
Dataset.load  ->  header + records   (checks header and record_count)
     |
     v
Importer: for each raw record
     |-- Normalizer.call(raw)     -> attrs        (pure)
     |-- Eligibility.call(attrs)  -> reasons      (pure)
     |-- CrXp.xp_for(cr)          -> derive if XP missing
     '-- upsert by _id, compare content_hash -> created/updated/unchanged
     v
ImportReport (value object; printed by the rake task)
```
`content_hash` = SHA-256 of the canonical JSON of the raw record plus
`Normalizer::VERSION`. Bumping the version forces records to update when the
parsing logic changes, even if the source didn't.

### 5. Normalization details
- **CR:** use Integer as-is. Parse `"a/b"` as a rational. Use `data-CrNum` as a
  cross-check. `"None"`, `"-"`, and `"—"` give nil, with reason `cr_unresolved`.
- **XP:** strip commas and convert to an integer. If it's missing, derive it via
  the CR-to-XP table (CR 0 → 10). The derived and source cases record
  provenance.
- **Ability modifiers:** compute them at render time as `(score - 10) / 2`
  (floor), and ignore the source's `data-*-mod` strings.
- **Lore:** remove the known Roll20 lead-in paragraphs, then cut at the first
  `" Traits "` or `" Actions "` section marker so the stat block doesn't repeat
  itself. This is best effort, and the raw text is kept in `source`.

### 6. Eligibility
Eligibility is a pure function that returns a list of reasons:
- `cr_unresolved`
- `xp_unresolved`
- `xp_zero`
- `incomplete_stat_block`, when any of AC, HP, speed, or the six abilities is
  missing

A record is eligible when the list is empty. Actions are not required (see
Frog).

### 7. Rails UI
- `resources :monsters, only: [ :index, :show ]`, with root pointing to
  `monsters#index` for now.
- The index filters with `Regexp.new(Regexp.escape(q), Regexp::IGNORECASE)`.
- The show view renders partials per stat-block section. ERB escaping is left
  on, and the code never calls `html_safe` or `raw` on source text.
- `Mongoid::Errors::DocumentNotFound` maps to 404. The Mongoid railtie
  registers this in `rescue_responses`, and a controller test verifies it.
- A shared `_srd_attribution` partial in the layout footer covers both SRD 5.1
  and SRD 5.2.

### 8. Testing
- Unit tests for the normalizer, eligibility, and CR-to-XP use a small,
  hand-trimmed fixture at `test/fixtures/files/srd_monsters_sample.json`. It
  uses the same header-plus-records format as the committed dataset and holds
  about 7 SRD records: Giant Shark 2014, Ape 2014 and 2024, Frog, Draconic
  Spirit, a fractional-CR record, and a string-XP record.
- Extraction filtering and checksum logic are tested against a tiny upstream-style
  array fixture that includes one non-SRD record. Those tests pass local paths
  and make no network calls.
- `Dataset.load` tests cover a valid header, a missing header, and a record-count
  mismatch.
- The importer test runs against Mongo with the fixture dataset. It covers
  create, re-import with everything unchanged, and an integrity failure that
  writes nothing.
- Controller tests cover index, the name filter (including `.*`), show,
  the 404, and escaping.
- Each test cleans the `monsters` collection.

## Risks / Trade-offs

- **[Risk] A pin change orphans records that are no longer in the dataset.**
  → The importer reports IDs in the DB that are missing from the dataset as
  `stale` and leaves them in place. Pruning can come later.
- **[Risk] Someone hand-edits the committed dataset, so it drifts from its
  provenance.** → The header says it is generated. The importer checks the
  record count. Re-running the extractor and running `git diff` reveals any
  drift, since output is deterministic.
- **[Trade-off] Committing about 1.3 MB of data adds weight to the repo.** →
  That's small and changes rarely. Only a pin or book-list change rewrites it.
- **[Risk] Lore stripping cuts real lore that contains the word "Actions".**
  → The marker must be surrounded by spaces, so the worst case is a shorter
  lore text. The raw text is always in `source`.
- **[Trade-off] SRD-only leaves a small pool of 372 eligible records** and drops
  the original "no book restrictions" goal. → To widen it, edit the extractor's
  `BOOKS` constant and regenerate the file. Eligibility already handles
  incomplete records.
- **[Risk] Parsing the 30 MB upstream with `JSON.parse` takes a few hundred MB
  of RAM.** → Only the occasional extractor run does this. Importing the 1.3 MB
  dataset is cheap.
- **[Follow-up for step 3]** The vector index filters on `environment`, a field
  that doesn't exist in this data, and lacks `eligible` and `xp`, which the
  retrieval order requires. Step 3 should revise the index definition. It is
  out of scope here.

## Migration Plan

There is no existing data. Run `docker compose up -d --wait`, then
`bin/rails db:mongoid:create_indexes`, then `bin/rails catalog:import`. No
download step is needed, because the dataset ships in the repo. To roll
back, delete the documents (`Monster.delete_all`). Don't drop the collection:
that also drops `monsters_vector_index`, and the init script recreates the index
only on an empty volume.
