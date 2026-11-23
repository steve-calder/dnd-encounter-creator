# Tasks

## 1. Configuration and Ollama client

- [x] 1.1 Add `Catalog::EmbeddingConfig` (`EMBEDDING_MODEL`, `EMBEDDING_DIMENSIONS`, and `OLLAMA_URL` with defaults; per-model document and query templates per design §1). Verify with unit tests for the defaults, env overrides, the embeddinggemma and nomic templates, and no prefix for an unknown model.
- [x] 1.2 Add `Ollama::Client#embed(model:, inputs:)` and `Ollama::Error` (design §2). Verify with `test/services/ollama/client_test.rb` against an in-process `TCPServer` fake: a successful embed returns the vectors, and connection refused, a 404 "model not found", and malformed JSON each raise `Ollama::Error` naming the URL and model.

## 2. Search document and importer

- [x] 2.1 Add `Catalog::SearchDocument.call(attrs)` (design §3: format, 160-character trait cut, macro stripping, 2,000-character cap). Verify with unit tests covering the Giant Shark scenario, determinism, Draconic Spirit (macros removed), and a synthetic long record staying within 2,000 characters.
- [x] 2.2 Add the `search_document`, `embedding`, `embedding_model`, `embedding_input_hash`, and `embedded_at` fields to `Monster`. Have the importer store `search_document`, bump `Normalizer::VERSION` to 2, and switch to `upsert(replace: false)`. Verify with importer tests: `search_document` is set; an embedded record keeps its embedding fields after an unchanged re-import and after an updated re-import; the existing importer tests still pass.

## 3. Embedding

- [x] 3.1 Implement `Catalog::Embedder` and its `EmbedReport` (design §5: templated input, hash, batches of 32, count and dimension checks before writing, targeted `$set`, injected client). Verify with `test/services/catalog/embedder_test.rb` using a stub client: first run embeds every record; second run embeds 0 and makes no client calls; a model change re-embeds all; one changed `search_document` re-embeds one; 1,024-dimension vectors raise naming 768 and 1,024 with nothing written; an `Ollama::Error` in batch 2 keeps batch 1's writes.
- [x] 3.2 Add the `catalog:embed` rake task (prints the report; rescues `Ollama::Error` into a one-line abort). Verify against local Ollama: after `bin/rails catalog:import` (379 updated, embeddings preserved), `bin/rails catalog:embed` embeds 379 and a second run skips 379. With `OLLAMA_URL=http://localhost:1`, it aborts with a message naming the URL and model.

## 4. Search indexes

- [x] 4.1 Implement `Catalog::SearchIndexes.ensure!` (design §6: definitions, normalized comparison, create, update, or leave unchanged, optional wait). Verify with `test/services/catalog/search_indexes_test.rb` in the per-worker test DB: a fresh run creates both indexes and they become queryable; a second run reports both unchanged; an index pre-created with 1,536 dimensions and an `environment` filter is updated to the desired definition with documents intact.
- [x] 4.2 Add the `catalog:search_indexes` rake task. Verify against the dev database: it reports `monsters_vector_index` updated (1,536 → 768) and `monsters_text_index` created, then unchanged on a second run.
- [x] 4.3 Remove index creation from `docker/mongo/init/` (delete `01-vector-index.js`, keep the directory with `.keep`) and the `EMBEDDING_DIMENSIONS` entry from `compose.yaml`. Verify that `docker compose config` is valid and that `grep -r EMBEDDING_DIMENSIONS compose.yaml docker/` finds nothing.

## 5. Search

- [x] 5.1 Add `test/test_helpers/search_index_helper.rb` (design §9: provision once per worker, one-hot fixture vectors under `"test-model"`, a poll-until-searchable helper, a stub query client). Verify with a smoke test that indexes a fixture vector and finds it through `$vectorSearch` within the timeout.
- [x] 5.2 Implement `Catalog::MonsterSearch.vector`, `Candidate`, and `Catalog::SearchUnavailable` (design §7). Verify with tests for every vector-search scenario in `specs/monster-search/spec.md`: shark ranks first; an ineligible closest match is excluded; `max_xp` 1,000 excludes Giant Shark; other-model embeddings are excluded; a limit of 100 is clamped to 25; the compact shape has no embedding or actions; a missing index and missing embeddings each raise naming the right task.
- [x] 5.3 Implement `Catalog::MonsterSearch.keyword` (design §7). Verify with a test that "shark" returns Giant Shark and Reef Shark from the fixture, excludes ineligible records, and respects `max_xp`.
- [x] 5.4 Add the `catalog:search` and `catalog:compare_search` rake tasks (design §8). Verify by running both against the real embedded catalog. `catalog:search["sea creatures attacking a ship",2250]` prints 10 eligible results, none above 2,250 XP. `catalog:compare_search` prints all five scenes side by side.
- [x] 5.5 Record a short summary of the comparison (whether vector search surfaced thematically better candidates than keyword search for each scene, with two or three named examples) in `DND_ENCOUNTER_CREATOR_DESIGN.md` under "Catalog and retrieval", and remove the now-done "revise the index's filter fields" note from build-order step 3. Verify that the doc reflects the actual report output.

## 6. Docs and CI

- [x] 6.1 Update `README.md` (setup steps: import, search indexes, embed; `OLLAMA_URL`, `EMBEDDING_MODEL`, and `EMBEDDING_DIMENSIONS` now read by Rails; `embeddinggemma`; the new rake tasks) and `CLAUDE.md` ("Vector search gotchas": Rails owns the index definitions through `catalog:search_indexes`; the model is `embeddinggemma`; no `down -v` needed for dimension changes). Verify that every documented command runs as written.
- [x] 6.2 Run `bin/ci` and confirm every step passes, including the search-index tests running in parallel workers.

## Workflow follow-up

- Sync the `monster-embeddings`, `monster-search`, and `monster-catalog` specs and archive the change after review.
