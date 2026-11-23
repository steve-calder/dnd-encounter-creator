# CLAUDE.md

D&D Encounter Creator: a DM describes a party and scene in plain English, picks a
difficulty (Low / Moderate / High), and gets a validated, thematic monster lineup
with stat blocks. Built to learn vector search, RAG, and MCP, and it runs entirely on
the local machine.

**Read [DND_ENCOUNTER_CREATOR_DESIGN.md](DND_ENCOUNTER_CREATOR_DESIGN.md) before any
feature work.** It is the source of truth for scope, the generation flow, the MCP
tools, and the build order. If a change conflicts with it, point out the conflict
and don't quietly diverge from it.

## Stack

- Rails 8.1 on Ruby 4.0.10 (`.ruby-version`), with Hotwire (Turbo and Stimulus),
  importmap, and Propshaft. No Node build step.
- **MongoDB via Mongoid. There is no ActiveRecord** (`active_record/railtie` is
  disabled in `config/application.rb`). Don't generate migrations, `schema.rb`, or
  `ApplicationRecord` models. Models `include Mongoid::Document`.
- MongoDB runs in Docker (`mongodb/mongodb-atlas-local`), which includes `mongot`,
  so `$vectorSearch` and search indexes work locally.
- Planned: Ollama for generation and embeddings, and an MCP stdio server that calls
  shared Rails services.

## Commands

```sh
docker compose up -d --wait   # start MongoDB (required for the app and tests)
bin/setup                     # first run: install gems, start server
bin/dev                       # start server afterwards
bin/rails test                # unit/integration tests (needs Mongo running)
bin/rails test test/models/monster_test.rb:42   # single test
bin/rubocop                   # lint (rubocop-rails-omakase)
bin/rubocop -a                # autocorrect safe offenses
bin/ci                        # full local CI: rubocop, audits, brakeman, tests
docker compose down -v && docker compose up -d --wait   # wipe DB and rerun init scripts
```

Before calling a task done, run `bin/rubocop` and `bin/rails test`. Prefer `bin/ci`
when the change touches security-relevant code or dependencies.

## Where things go

- `app/models/`: Mongoid documents (for example `Monster`). Keep them thin.
- `app/services/`: domain logic that both Rails and the MCP server call, such as
  the XP budget calculator, lineup evaluation, monster search, catalog import, and
  the Ollama client. **Both the MCP tools and the controllers must use the same
  services.** Don't duplicate rules in either place.
- `lib/tasks/`: rake tasks for catalog import and embedding (re)generation.
- `docker/mongo/init/`: scripts that run once, only on an empty data volume.
- `test/`: Minitest. Mirror the `app/` layout.

## Domain rules (don't get these wrong)

- XP budgets follow the **2024** 5e rules. For a mixed-level party, sum the
  per-character budgets for the chosen difficulty. Reference check: three level-5
  PCs give Low 1,500, Moderate 2,250, and High 3,300. Keep this as a test.
- Lineup total XP = Σ(monster XP × quantity). The budget is a **ceiling**. Rails
  revalidates every final lineup (IDs exist, quantities are positive integers,
  records are eligible, total ≤ budget). Never trust LLM output without this check.
- Catalog records keep a stable ID plus the original source data. Same-name variants
  stay distinct. Use at most one variant of a creature per lineup.
- XP derived from CR must record its provenance. Records with unresolved XP or
  incomplete stat blocks stay in the catalog but are excluded from generation.
- Retrieval order: apply structured filters (eligibility, max XP) first, then rank
  by vector similarity. Send the LLM compact summaries and IDs, and load full stat
  blocks from Mongo only after validation.

## Vector search gotchas

- The index `monsters_vector_index` is created by
  `docker/mongo/init/01-vector-index.js`. Its size comes from
  `EMBEDDING_DIMENSIONS` (default 768, for `nomic-embed-text`), which **must match
  the embedding model's output size.** If you switch models, update that variable
  and the README together, then recreate the volume.
- Init scripts run only on an empty volume. Editing them has no effect until you
  run `docker compose down -v`.
- Use the same embedding model for queries and the catalog. Store the model name and
  an input hash on each record, and skip records whose hash hasn't changed on reimport.
- Search indexes build asynchronously. Tests that query right after inserting data
  may need to wait until the index is queryable.

## Testing

- Tests run in parallel against `dnd_encounter_creator_test` on the same container.
  Clean up collections between tests and don't rely on data from the init script.
- Don't call real Ollama or the network in unit tests. Stub the model and embedding
  clients behind a small interface. Use fixed vectors for retrieval tests.
- In GitHub Actions, the `test` and `system-test` jobs start a
  `mongodb-atlas-local` service with the same defaults as `compose.yaml`. If you
  change the image tag or credentials, change them in both files.

## Conventions

- Follow rubocop-rails-omakase style (including spaces inside array brackets).
- Prefer plain Ruby service objects over new gems. Ask before adding a dependency.
- Surface model, database, and index failures to the user as recoverable errors,
  and keep the DM's form input so they can edit and retry.
- Keep scope to the design doc: no maps, initiative trackers, or invented scene
  mechanics.

## Data and secrets

- Local Mongo credentials (`admin`/`admin`) are for development only. Never put
  real credentials, API keys, or `config/master.key` in the repo, in commits, or in
  test fixtures. Use env vars or Rails credentials.
- The monster catalog is public data. Pin the snapshot (record its revision or
  checksum) instead of fetching `main` at import time.
