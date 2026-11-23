# Spec Delta

## ADDED Requirements

### Requirement: Re-import preserves embeddings
Re-importing the catalog SHALL keep each record's embedding, embedding model, and embedding input hash, whether the record is unchanged or updated. The embedding run then decides whether the record needs re-embedding.

#### Scenario: Unchanged record keeps its embedding
- **WHEN** an embedded record is re-imported with no changes
- **THEN** its embedding, embedding model, and input hash are exactly as before

#### Scenario: Updated record keeps its embedding until re-embedded
- **WHEN** an embedded record's source data changes and it is re-imported
- **THEN** its normalized fields are updated and its embedding fields are still present, so the next embedding run can compare input hashes
