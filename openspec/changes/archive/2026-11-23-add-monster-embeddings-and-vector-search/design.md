# Design

## Context

- **Catalog:** 379 `Monster` documents with string IDs, `eligible`, `xp`,
  `challenge_rating`, `speed`, `senses`, `traits` and `actions` (arrays of hashes
  with `name`/`desc`), and `lore` (at most 654 characters). `Catalog::Importer`
  upserts changed records with `upsert(replace: true)`, which would wipe any
  extra fields such as an embedding. `Normalizer::VERSION` is 1.
- **Ollama:** runs locally (0.40.17) with `embeddinggemma` installed. A probe of
  `/api/embed` returned 768-number, unit-length vectors; the context window is
  2,048 tokens. The model expects task prefixes: documents as
  `title: <name> | text: <doc>`, queries as `task: search result | query: <q>`.
- **Index drift:** the dev database's `monsters_vector_index` is `READY` but
  defined with **1,536** dimensions and filters `challenge_rating` and
  `environment`. The init script ran once, when the volume was created with a
  different value, and never again. Per-worker test databases have no search
  indexes at all.
- **Driver:** Mongo Ruby driver 2.26.2 has
  `collection.search_indexes.create_one(definition, name:, type:)`,
  `update_one(definition, name:)`, and iteration that yields `status`,
  `queryable`, and `latestDefinition`.
- **Search engine availability:** `mongodb-atlas-local` (`mongot`) serves
  `$vectorSearch` and `$search` locally and in the GitHub Actions service.
  Search indexes build asynchronously, and newly written documents become
  searchable shortly after the write.

## Goals / Non-Goals

**Goals:**
- One retrieval service with the shape step 4's `search_monsters` will expose.
- Index definitions in Ruby, versioned with the code, and applied idempotently
  to any database.
- Deterministic tests without Ollama: a stub client and fixed vectors.

**Non-Goals:**
- Hybrid or reranked retrieval. The keyword path is only a baseline for
  comparison.
- Background jobs. Embedding is a manual rake task over 379 records.
- Tuning the search document beyond a reasonable first version. The comparison
  report is how we judge it.

## Decisions

### 1. Configuration in one place: `Catalog::EmbeddingConfig`
It reads `EMBEDDING_MODEL` (default `embeddinggemma`), `EMBEDDING_DIMENSIONS`
(default 768), and `OLLAMA_URL` (default `http://localhost:11434`). It also owns
the per-model prompt templates: `embeddinggemma` uses the prefixes above,
`nomic-embed-text` uses `search_document: ` / `search_query: `, and other models
use none. Every caller (embedder, searches, index definitions) reads the same
values, so the query and the catalog can't drift apart.

### 2. `Ollama::Client`: stdlib `Net::HTTP`
`embed(model:, inputs:)` posts `{model, input: [...]}` to `/api/embed` and
returns `embeddings`. It uses a 2 s open timeout and a 120 s read timeout.
Connection refused, a timeout, a non-2xx response (including "model not found"),
or malformed JSON each raise `Ollama::Error` with the URL, model, and cause.
Tests run it against an in-process `TCPServer` fake, so there's no network and
no new gem.
- *Alternative:* the `ollama-ai` gem. Rejected, since CLAUDE.md prefers plain Ruby
  and the API surface needed here is one endpoint.

### 3. The search document is built at import, stored on the record
`Catalog::SearchDocument.call(attrs)` is pure and builds:
```
Giant Shark. Huge beast, Unaligned.
Movement: Swim 50 ft.
Senses: Blindsight 60 Ft.
Traits: Blood Frenzy: The shark has advantage on melee attack rolls against... Water Breathing: The shark can breathe only underwater.
Actions: Bite.
A giant shark is 30 feet long and normally found in deep oceans...
```
- Trait descriptions are cut to 160 characters each. Attack actions contribute
  only their names, and non-attack actions add a cut description.
- Roll20 macro fragments (`@{...}`, `[[...]]`) are removed.
- The whole document is capped at 2,000 characters, cutting lore first.

The importer stores it as `search_document`, so the keyword index works without
Ollama and the embedder just reads it. `Normalizer::VERSION` goes to 2, so the
next import updates every record once to add the field.
- *Alternative:* build the document inside the embedder. Rejected, because then
  keyword search would depend on an embedding run.

### 4. The importer stops replacing documents
`upsert(replace: true)` becomes `upsert(replace: false)`, which `$set`s every
normalized field and leaves `embedding`, `embedding_model`,
`embedding_input_hash`, and `embedded_at` alone. This satisfies the new
monster-catalog requirement and the design doc's "repeated import ... skips
unchanged embeddings". The normalizer always emits every field, nil included, so
`$set` still overwrites stale values.

### 5. `Catalog::Embedder`: hash-gated, batched, validated
- The input is the prompt-templated text: `title: <name> | text: <search_document>`.
- The hash is `SHA-256("<model>\n<input>")`.
- A record is pending when its stored `embedding_model` or
  `embedding_input_hash` differs.
- Pending records are sent in batches of 32. Each batch checks the response
  count and that every vector's length equals `EMBEDDING_DIMENSIONS` *before*
  writing anything from that batch.
- Each record is written with a targeted `$set` of `embedding`,
  `embedding_model`, `embedding_input_hash`, and `embedded_at`.
- A failure raises after earlier batches have been saved, so a rerun resumes.
- It returns `EmbedReport(model:, dimensions:, embedded:, skipped:)`. The client
  is injected, so tests pass a stub that returns fixed vectors.

### 6. `Catalog::SearchIndexes`: Ruby-owned definitions, ensured idempotently
```ruby
VECTOR = { fields: [
  { type: "vector", path: "embedding", numDimensions: <dims>, similarity: "cosine" },
  { type: "filter", path: "eligible" }, { type: "filter", path: "xp" },
  { type: "filter", path: "challenge_rating" }, { type: "filter", path: "embedding_model" } ] }
TEXT = { mappings: { dynamic: false, fields: {
  name: { type: "string" }, search_document: { type: "string" },
  eligible: { type: "boolean" }, xp: { type: "number" } } } }
```
`ensure!(wait: true, timeout: 120)` works like this:
1. Create the collection if it's missing.
2. For each index, compare the normalized `latestDefinition` with the desired
   definition (fields sorted by path), then `create_one`, `update_one`, or leave
   it.
3. Optionally poll until both indexes are `queryable`.

It returns a per-index status: `created`, `updated`, or `unchanged`. The rake
task `catalog:search_indexes` wraps it. The init script's index creation is
removed. `docker/mongo/init/` keeps a `.keep`, and `compose.yaml` stops passing
`EMBEDDING_DIMENSIONS`.
- *Alternative:* always drop and recreate the index on a mismatch. Rejected as
  the default, because `update_one` keeps the index live on Atlas.
- **Found during implementation:** `mongodb-atlas-local` 8.0 rejects
  `updateSearchIndex` for `vectorSearch` indexes (`"mappings" is required`),
  while text-index updates work. On that error the service drops and recreates
  the vector index under the same name. That takes under a second locally and
  leaves the collection and documents untouched.

### 7. `Catalog::MonsterSearch`: preflight, then filter-first `$vectorSearch`
`MonsterSearch.vector(query:, max_xp: nil, limit: 10, client:)`:
- **Preflight:** the vector index exists and is queryable, and at least one
  record has `embedding_model == config.model`. Otherwise it raises
  `Catalog::SearchUnavailable` with the task to run.
- **Query:** it embeds `task: search result | query: <query>`, then runs
  `$vectorSearch` with
  `filter: { eligible: true, embedding_model: model, xp: { $lte: max_xp } }`
  (the XP clause only when given), `numCandidates: [limit * 20, 200].max`, and a
  `limit` clamped to 1–25.
- **Projection:** a `$project` keeps only the summary fields, plus
  `score: { $meta: "vectorSearchScore" }`.

`MonsterSearch.keyword(query:, max_xp: nil, limit: 10)` runs `$search` on
`monsters_text_index`. It's a `compound` that `must` match `text` on
`[name, search_document]` and filters with `equals eligible: true` and
`range xp lte`. It uses the same projection with `searchScore`.

Both return `Candidate` `Data` objects (`id, name, book, size_type,
challenge_rating, xp, movement, traits, score`) with `to_h`, ready to serve as
step 4's tool output.

### 8. Rake tasks
- `catalog:embed` prints the `EmbedReport`.
- `catalog:search_indexes` prints each index's status and waits until it's
  queryable.
- `catalog:search["<query>",<max_xp>]` prints the vector top 10.
- `catalog:compare_search` covers the boat prompt plus four contrasting scenes
  (a crypt, a forest-road ambush, a frozen pass, and a volcanic cave), all with
  `max_xp` 2,250. It prints vector and keyword top 8 side by side as text
  columns: name, XP, and score.

Each task rescues `Ollama::Error` and `Catalog::SearchUnavailable` into a
one-line `abort` message.

### 9. Search tests use real indexes with fixed vectors
- A `SearchIndexHelper` provisions the indexes once per test process (per-worker
  DB) with `ensure!(wait: true)`.
- Fixture records get one-hot 768-dimension vectors with model `"test-model"`.
  Tests override `EmbeddingConfig.model` to match.
- A helper polls the search until it returns the expected count (30 s timeout),
  because `mongot` indexes new writes asynchronously.
- The stub client maps known query strings to fixed vectors, for example "shark"
  to Giant Shark's one-hot vector.

## Risks / Trade-offs

- **[Risk] Search-index tests are slow or flaky:** the index build and
  eventual consistency take seconds. → Provision once per worker, poll with a
  bounded timeout instead of sleeping, and keep search-index tests in a few
  test classes.
- **[Risk] Prompt prefixes are model-specific;** a wrong prefix quietly degrades
  ranking. → The prefixes live only in `EmbeddingConfig`, the model name is part
  of the input hash, and unknown models get no prefix.
- **[Trade-off] Bumping `Normalizer::VERSION` touches all 379 records once.** →
  This is intended, to add `search_document`. Embeddings survive (Decision 4),
  and only records whose embedding input changed are re-embedded.
- **[Risk] The keyword baseline is weak by construction:** scene prompts rarely
  contain monster names. → That's the point of the comparison, and the report
  shows both honestly.
- **[Breaking for existing dev setups]** The init script no longer creates the
  index. → Running `bin/rails catalog:search_indexes` updates the existing
  1,536-dimension index in place. The README's setup steps include it.

## Migration Plan

1. Pull the code, then run `bin/rails catalog:import`. This is a one-time update
   of all 379 records that adds `search_document` and keeps nothing else
   changed.
2. Run `bin/rails catalog:search_indexes`. This updates `monsters_vector_index`
   from 1,536 to 768 dimensions with the new filters, and creates
   `monsters_text_index`.
3. Run `bin/rails catalog:embed`, which embeds 379 records. A second run should
   skip all 379.
4. Run `bin/rails catalog:compare_search`.

To roll back, revert the code. The extra fields and the text index are harmless
to the step 1–2 code.

## Open Questions

- Whether to tune the search document (for example, weighting movement or
  habitat words) depends on what the comparison report shows. Any change is a
  follow-up and doesn't alter these specs.
