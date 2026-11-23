# Proposal

## Why

Build-order step 3 is to generate embeddings locally, create the vector index,
and inspect candidate rankings. Steps 4 and 5 need a retrieval service that
applies structured filters (eligible, max XP) and then ranks by vector
similarity. The design doc also asks whether vector search actually beats
keyword search for scenes like the boat example. Today no record has an
embedding, and the existing index can't serve that query: it filters on
`environment` (a field that doesn't exist), lacks `eligible` and `xp`, and was
built for 1536 dimensions because the init script ran once with an older value.

## What Changes

- Build a short search document for each catalog record (name, size and type,
  movement modes, senses, trait and action names with brief descriptions, and
  lore), and embed it with the local Ollama model `embeddinggemma`
  (768 dimensions).
- Store on each record the embedding, the model name, and a hash of the exact
  embedding input. Re-running embedding skips records whose input and model are
  unchanged. Vectors whose size differs from `EMBEDDING_DIMENSIONS` are rejected.
- Re-importing the catalog keeps existing embedding fields, so an unchanged
  record is never re-embedded just because it was imported again.
- Rails owns the search index definitions. An idempotent task creates or updates
  `monsters_vector_index` (vector on `embedding`, filters `eligible`, `xp`,
  `challenge_rating`, and `embedding_model`) and a full-text index
  `monsters_text_index` (for the keyword baseline) in whichever database Rails
  points at, including the per-worker test databases. **BREAKING (dev setup):**
  the Mongo init script no longer creates the vector index, and the container no
  longer reads `EMBEDDING_DIMENSIONS`.
- Add a vector search service: filter by eligibility, max individual XP, and
  embedding model, rank by similarity, and return a bounded list of compact
  summaries (ID, name, source, size and type, CR, XP, movement, trait names,
  score). This is the shape step 4's `search_monsters` tool will return.
- Add a keyword search service over the same records and filters, used only as
  the comparison baseline.
- Add rake tasks: `catalog:embed`, `catalog:search_indexes`, `catalog:search`
  (ad hoc query), and `catalog:compare_search`, which prints vector and keyword
  top results side by side for the boat prompt and several other scenes.
- Ollama, index, and database failures surface as clear, recoverable errors.
  Unit tests never call Ollama; they use a stub client and fixed vectors.

## Capabilities

### New Capabilities
- `monster-embeddings`: The search document per record, generating and storing
  embeddings with model identity and input hash, skipping unchanged records, and
  dimension checks.
- `monster-search`: Provisioning search indexes, filtered vector search with
  compact results, the keyword baseline, and the side-by-side comparison report.

### Modified Capabilities
- `monster-catalog`: Re-import must preserve embedding fields on records it
  updates or leaves unchanged.

## Impact

- New: `app/services/ollama/client.rb`, `app/services/catalog/` additions
  (search document, embedder, search indexes, vector and keyword search),
  `Monster` embedding fields, and new rake tasks. There are no new gems; the
  Ollama client uses stdlib `Net::HTTP`.
- Changed: `Catalog::Importer` (keeps embedding fields), `test/test_helper.rb`
  (helpers for search-index tests), `compose.yaml` and
  `docker/mongo/init/01-vector-index.js` (index creation removed), and
  `CLAUDE.md` and `README.md` (model name, index ownership, new commands).
- New env vars: `OLLAMA_URL` (default `http://localhost:11434`) and
  `EMBEDDING_MODEL` (default `embeddinggemma`). `EMBEDDING_DIMENSIONS` (default
  768) moves from the container to Rails.
- CI: the existing `mongodb-atlas-local` service already supports search
  indexes. CI never needs Ollama.
- Out of scope: MCP (step 4), the generation UI and LLM tool loop (step 5), and
  a search box in the app.
