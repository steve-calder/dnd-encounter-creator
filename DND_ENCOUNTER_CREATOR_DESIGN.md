# D&D Encounter Creator

## Goal and scope

A DM describes the party and situation in plain English, selects Low, Moderate, or High difficulty, and gets one thematically appropriate monster lineup. Each entry shows a quantity, source book, and full catalog stat block. Show total XP, the target budget, and a short explanation of the lineup's thematic fit. The project runs locally and provides hands-on experience with vector search, retrieval-augmented generation (RAG), and the Model Context Protocol (MCP).

The scene, party composition, and encounter objective guide monster selection. Party size and levels determine the XP budget. The app generates no scene mechanics, maps, or initiative tracker.

## Local architecture

- **Rails** handles the form, catalog import, encounter rules, model orchestration, and result rendering. Run Rails on the host for v1.
- **MongoDB** runs in Docker Compose with a persistent volume. Start with the self-contained `mongodb/mongodb-atlas-local` image, which includes vector search and runs on the local machine. Pin an image tag after verifying it on the development machine.
- **Ollama** runs locally and serves a tool-capable generation model and a separate embedding model. Verify the selected generation model can handle a multi-turn tool loop early.
- **MCP** provides the catalog and difficulty tools. Rails is the MCP client and translates Ollama's tool calls into MCP requests. Start with a local stdio server process that calls shared Rails application services. Generation runs locally after the models, container image, and source data are downloaded.

## Catalog and retrieval

Import the full [monster JSON](https://raw.githubusercontent.com/nick-aschenbach/dnd-data/refs/heads/main/data/monsters.json) with no book restrictions. Record a source revision or checksum. Inspect the raw file before committing to field mappings, particularly for stat blocks, CR, and XP.

Preserve each source record under a stable ID, including the original stat block content and source. Normalize available name, type, movement, CR, and XP fields. Keep same-name variants as distinct records and show which source was selected. Proposed v1 behavior is to use at most one version of a creature in a lineup. If XP is missing but CR maps unambiguously to XP, derive it and track its provenance. Keep records with unresolved XP or incomplete stat blocks in the catalog, but report and exclude them from generation.

Embed a short search document per record from available fields such as description, type, movement, and habitat. Store the embedding model identity and input hash. Use the same model for query and catalog embeddings, and skip unchanged records on reimport. Use structured filters for eligibility and XP, then rank candidates by vector similarity. Give the LLM compact retrieved summaries and IDs as its RAG context. Fetch full stat blocks directly from MongoDB after validating the lineup.

## Generation flow

1. The DM enters the party and scene and selects a difficulty. Ollama extracts party levels and summarizes the scene. Ask for clarification if headcount and levels are missing or inconsistent. Classes are optional.
2. Rails calculates a 2024 5e XP budget. For the requested difficulty, sum the per-character budgets for the party. Summing individual budgets for mixed-level parties is a v1 design assumption.
3. Ollama calls the following tools through Rails. Bind evaluation to the validated party and difficulty for that request.

| MCP tool | Input | Output |
| --- | --- | --- |
| `search_monsters` | Semantic query, optional catalog filters, maximum individual XP | Bounded shortlist of candidate IDs, names, sources, XP, and relevant traits |
| `evaluate_lineup` | Catalog IDs and positive integer quantities | Total XP, budget, remaining XP, and validation feedback |

4. Allow the model to refine its proposal within a bounded tool loop. It should aim to spend close to the budget while preserving thematic fit. Rails computes total XP as the sum of monster XP times quantity and revalidates the final IDs, quantities, eligibility, and budget. Use the selected budget as a ceiling and show any material shortfall.
5. Render the lineup with one stat block per distinct selected record. If the search yields no valid thematic lineup, explain that result and preserve the input for editing. Report model, database, or index failures as recoverable errors.

## Acceptance example

> Three level-5 PCs are on a boat and encountering a challenge of sea creatures in rough seas. The PCs are a fighter, wizard, and druid. The goal is to survive en route to their destination.

With **Moderate** selected, the budget is **2,250 XP**. Low is 1,500 XP and High is 3,300 XP. The creatures should plausibly threaten the party aboard or alongside the boat. The result includes the selected creatures, counts, source stat blocks, and validated XP total. Rough seas guide selection and introduce no storm mechanic.

Verify that unknown IDs, invalid quantities, and over-budget proposals fail validation. Verify that a repeated import preserves record counts and skips unchanged embeddings. Compare vector and keyword search on the boat prompt and a few distinct scenes to assess whether vector retrieval improves the candidate shortlist.

## Build order

1. Inspect and import a pinned dataset snapshot. Render a catalog stat block in Rails.
2. Implement and test the 2024 XP calculator against the boat example.
3. Generate embeddings locally, create the vector index, and inspect candidate rankings.
4. Expose search and validation through MCP and call both tools from Rails.
5. Wire in Ollama's tool loop and complete the generation screen. Run the acceptance example and failure cases end to end.

## References

- [Monster catalog repository](https://github.com/nick-aschenbach/dnd-data)
- [2024 D&D encounter-building rules](https://www.dndbeyond.com/sources/dnd/br-2024/dms-toolbox)
- [MongoDB local vector search with Docker Compose](https://www.mongodb.com/docs/search/self-managed/current/installation/quick-start/)
