# monster-embeddings Specification

## Purpose

Gives every catalog record a vector embedding of a short, descriptive search
document, produced by a local embedding model. It records which model and input
produced each vector so that retrieval only compares like with like and
unchanged records are never re-embedded.

## Requirements

### Requirement: Search document per record
Each catalog record SHALL have a deterministic plain-text search document built from its name, size, creature type, movement modes, senses, trait and action names with short descriptions, and lore. It SHALL contain no markup and be at most 2,000 characters.

#### Scenario: Giant Shark document
- **WHEN** the search document is built for Giant Shark (2014)
- **THEN** it contains "Giant Shark", "Huge beast", the swim movement, "Blood Frenzy", "Water Breathing", "Bite", and its lore about deep oceans

#### Scenario: Deterministic and bounded
- **WHEN** the search document is built twice for the same record, including a record with long trait text
- **THEN** both results are identical and neither exceeds 2,000 characters

### Requirement: Embeddings generated with a configured local model
An embedding run SHALL embed each record's search document with the configured embedding model (default `embeddinggemma`) served by the local Ollama instance, and SHALL store the vector, the model name, and a SHA-256 hash of the exact text sent to the model.

#### Scenario: First embedding run
- **WHEN** the embedding run processes a catalog with no embeddings
- **THEN** every record has an embedding of `EMBEDDING_DIMENSIONS` numbers, its `embedding_model` is the configured model, and its input hash is set

### Requirement: Unchanged records are skipped
An embedding run SHALL skip a record whose stored model and input hash match the current model and search document, and SHALL re-embed a record when either differs. It SHALL report how many records were embedded and skipped.

#### Scenario: Second run skips everything
- **WHEN** the embedding run executes twice with no catalog or model changes
- **THEN** the second run embeds 0 records, skips all of them, and makes no model calls

#### Scenario: Model change re-embeds
- **WHEN** the configured embedding model changes
- **THEN** the next run re-embeds every record with the new model

#### Scenario: Changed record re-embedded
- **WHEN** one record's search document changes
- **THEN** the next run re-embeds only that record

### Requirement: Dimension check
An embedding run SHALL reject any vector whose length differs from `EMBEDDING_DIMENSIONS`, SHALL NOT store it, and SHALL report the expected and actual sizes.

#### Scenario: Wrong-sized vector
- **WHEN** the model returns 1,024-number vectors while `EMBEDDING_DIMENSIONS` is 768
- **THEN** the run stops with an error naming 768 and 1,024, and no record's stored embedding changes

### Requirement: Recoverable model failures
When the embedding model cannot be reached or returns an error, the run SHALL stop with an error that names the model service URL and the model, SHALL keep embeddings already written in earlier batches, and SHALL be safe to rerun.

#### Scenario: Ollama not running
- **WHEN** the embedding run starts and nothing is listening at the configured Ollama URL
- **THEN** it fails with an error naming the URL and model, and a later run after Ollama starts completes normally
