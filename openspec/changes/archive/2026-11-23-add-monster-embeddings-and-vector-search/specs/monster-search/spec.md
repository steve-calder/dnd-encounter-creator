# Spec Delta

## Purpose

Finds catalog monsters that fit a described scene. It applies structured filters
first (eligibility, maximum individual XP, embedding model), then ranks by vector
similarity and returns compact candidate summaries. It also provides a keyword
baseline and a report comparing the two.

## ADDED Requirements

### Requirement: Search indexes provisioned idempotently
A provisioning task SHALL create the vector index `monsters_vector_index` (cosine similarity on `embedding` with `EMBEDDING_DIMENSIONS` dimensions, plus filters on `eligible`, `xp`, `challenge_rating`, and `embedding_model`) and the full-text index `monsters_text_index` in the current database. It SHALL update an index whose definition differs and leave a matching index unchanged.

#### Scenario: Fresh database
- **WHEN** provisioning runs against a database with no search indexes
- **THEN** both indexes exist and become queryable

#### Scenario: Stale definition updated
- **WHEN** `monsters_vector_index` exists with 1,536 dimensions and a filter on `environment`
- **THEN** provisioning updates it to 768 dimensions with the four required filters, without deleting the collection or its documents

#### Scenario: Already current
- **WHEN** provisioning runs twice
- **THEN** the second run reports both indexes as unchanged

### Requirement: Filtered vector search
Vector search SHALL embed the query with the configured model and return only records that are eligible, whose XP is at most the given maximum (when given), and whose embedding was produced by the same model. Results SHALL be ordered by descending similarity.

#### Scenario: Ranking by similarity
- **WHEN** the query vector is closest to Giant Shark's embedding
- **THEN** Giant Shark is the first result

#### Scenario: Ineligible records excluded
- **WHEN** an ineligible record's embedding is the closest match to the query
- **THEN** that record does not appear in the results

#### Scenario: Maximum XP applied
- **WHEN** the maximum individual XP is 1,000
- **THEN** no result has XP above 1,000, so Giant Shark (1,800) is excluded even if it is the closest match

#### Scenario: Other models excluded
- **WHEN** a record's embedding was produced by a different model than the configured one
- **THEN** that record does not appear in the results

### Requirement: Bounded compact results
Search SHALL return at most the requested number of results (default 10, maximum 25). Each result SHALL contain the catalog ID, name, source book, size and type, CR, XP, movement, trait names, and similarity score, and SHALL NOT include the full stat block or the embedding.

#### Scenario: Limit enforced
- **WHEN** a search asks for 100 results
- **THEN** at most 25 are returned

#### Scenario: Compact shape
- **WHEN** a search returns Giant Shark
- **THEN** its result includes `srd-2014--giant-shark`, "Giant Shark", "Free Basic Rules (2014)", CR 5, XP 1,800, its swim movement, its trait names, and a score, and has no embedding or action details

### Requirement: Keyword baseline search
Keyword search SHALL match query terms against record names and search documents using the full-text index, apply the same eligibility and maximum-XP filters, and return results in the same compact shape, ordered by relevance.

#### Scenario: Keyword match
- **WHEN** a keyword search for "shark" runs over the catalog
- **THEN** the results include Giant Shark, Hunter Shark, and Reef Shark, and no ineligible records

### Requirement: Search comparison report
A report task SHALL run vector and keyword search for a fixed set of scenes, including the design doc's boat prompt, and print each scene's top results from both methods side by side with names, XP, and scores. It SHALL also accept a custom query.

#### Scenario: Boat prompt comparison
- **WHEN** the comparison report runs with embeddings and indexes in place
- **THEN** it prints, for the boat prompt with a maximum individual XP of 2,250, the top vector and keyword results side by side

### Requirement: Recoverable search failures
When the embedding model is unreachable, a required index is missing or not yet queryable, or no records have embeddings for the configured model, search SHALL fail with an error that says which of these happened and how to fix it (for example, which task to run).

#### Scenario: Index missing
- **WHEN** vector search runs in a database without `monsters_vector_index`
- **THEN** it fails with an error saying the index is missing and naming the provisioning task

#### Scenario: No embeddings yet
- **WHEN** vector search runs before any record has been embedded with the configured model
- **THEN** it fails with an error naming the embedding task
