# monster-catalog Specification

## Purpose

Maintains the local monster catalog that encounter generation draws from. It
imports a curated SRD dataset, committed to the repository with its upstream
provenance, into normalized records with stable IDs, XP provenance, and explicit
generation eligibility.

## Requirements

### Requirement: Committed catalog dataset
The catalog dataset SHALL be a file committed to the repository. It SHALL contain the selected upstream monster records and a provenance header naming the upstream repository, commit, file path, upstream SHA-256, selected source books, and record count.

#### Scenario: Provenance header present
- **WHEN** a developer opens the committed dataset file
- **THEN** its header names commit `649f7f964b20835852bff3659aa36875dd7c35df`, upstream SHA-256 `cee519309b7241ed6cd45b2217f9e37e481d451aa3fd9ce251dfbd7a4ef302c7`, the books `Free Basic Rules (2014)` and `Free Basic Rules (2024)`, and a record count of 379

### Requirement: Offline import from the committed dataset
The import SHALL read monster records only from the committed dataset file, SHALL make no network requests, and SHALL import every record in the file without applying its own source-book selection.

#### Scenario: Import without network
- **WHEN** the import runs on a machine with no network access
- **THEN** it completes and the catalog contains every record in the dataset file

#### Scenario: Dataset totals
- **WHEN** the committed dataset is imported into an empty catalog
- **THEN** the catalog contains 379 records

### Requirement: Dataset integrity check
Before writing any record, the import SHALL verify that the dataset file has a provenance header and that its number of records equals the header's record count. On failure it SHALL abort without writing.

#### Scenario: Record count mismatch
- **WHEN** the dataset file's header says 379 records but the file contains 378
- **THEN** the import aborts before writing any record and reports the expected and actual counts

#### Scenario: Missing header
- **WHEN** the dataset file has no provenance header
- **THEN** the import aborts before writing any record and reports the missing header

### Requirement: Dataset extraction
A developer tool SHALL regenerate the dataset file from the pinned upstream file. It SHALL verify the upstream SHA-256, keep only records from the selected books, and copy each record verbatim. The import, tests, and CI SHALL NOT run it.

#### Scenario: Non-SRD record excluded
- **WHEN** the upstream file contains a record from `Tome of Beasts 2`
- **THEN** the extracted dataset does not contain it

#### Scenario: Upstream checksum mismatch
- **WHEN** the downloaded upstream file's SHA-256 differs from the pinned checksum
- **THEN** extraction aborts, reports the expected and actual checksums, and leaves the existing dataset file unchanged

#### Scenario: Reproducible output
- **WHEN** extraction runs twice against the pinned upstream
- **THEN** both runs produce byte-identical dataset files

### Requirement: Stable record identity
Each catalog record SHALL have an ID derived deterministically from its source book and name, which stays the same across re-imports of the same dataset.

#### Scenario: Same ID on re-import
- **WHEN** the same dataset is imported twice
- **THEN** each record has the same ID after the second import as after the first

#### Scenario: Same-name variants stay distinct
- **WHEN** "Ape" appears in both `Free Basic Rules (2014)` and `Free Basic Rules (2024)`
- **THEN** the catalog holds two records with different IDs, each labeled with its source book

### Requirement: Original source data preserved
Each catalog record SHALL retain the original source record (name, description, properties, publisher, book) unmodified alongside its normalized fields.

#### Scenario: Raw record retained
- **WHEN** a record is imported
- **THEN** its stored original source data equals the dataset entry it came from, which equals the upstream entry

### Requirement: Normalized fields
Each record SHALL expose normalized name, source book, size, type, alignment, CR (as a number), XP (as an integer), AC, HP, speed, the six ability scores, and lists of traits, actions, bonus actions, reactions, and legendary actions parsed from the source.

#### Scenario: Fractional CR normalized
- **WHEN** a source record has Challenge Rating `"1/4"`
- **THEN** its normalized CR is 0.25

#### Scenario: XP with thousands separator
- **WHEN** a source record has XP `"1,800"`
- **THEN** its normalized XP is the integer 1800

#### Scenario: Structured actions parsed
- **WHEN** a source record's actions list contains a Bite with hit bonus, reach, and damage
- **THEN** the normalized actions include a Bite entry with those values

### Requirement: XP provenance
Each record with resolved XP SHALL record whether the XP came from the source data or was derived from CR using the standard CR-to-XP table. XP SHALL be derived only when the source XP is missing and the CR maps to exactly one XP value.

#### Scenario: Source XP present
- **WHEN** a source record includes an XP value
- **THEN** the record's XP provenance is "source"

#### Scenario: XP derived from CR
- **WHEN** a source record lacks XP and has CR 5
- **THEN** its XP is 1800 and its XP provenance is "derived from CR"

### Requirement: Generation eligibility
A record SHALL be eligible for generation only if it has parseable CR, XP greater than zero, and a complete stat block (AC, HP, speed, all six ability scores). Ineligible records SHALL stay in the catalog with every reason they are excluded.

#### Scenario: Spell summon excluded
- **WHEN** a record has Challenge Rating `"None"` and XP 0
- **THEN** it is stored, marked ineligible, and its reasons include unresolved CR and zero XP

#### Scenario: Complete record eligible
- **WHEN** a record has CR 5, XP 1800, and all stat block fields
- **THEN** it is marked eligible with no exclusion reasons

#### Scenario: No actions does not block eligibility
- **WHEN** a complete record such as "Frog" has no actions
- **THEN** it remains eligible

### Requirement: Idempotent re-import
Re-importing the same dataset SHALL update records in place by ID, SHALL NOT create duplicates, and SHALL report how many records were created, updated, and unchanged.

#### Scenario: Second import changes nothing
- **WHEN** the committed dataset is imported a second time with no changes
- **THEN** the record count is unchanged and the report shows 0 created and 379 unchanged

### Requirement: Import report
Each import run SHALL produce a report with the dataset's upstream commit and checksum, counts of created, updated, and unchanged records, and counts of eligible and ineligible records (ineligible grouped by reason).

#### Scenario: Report after first import
- **WHEN** the committed dataset is imported into an empty catalog
- **THEN** the report shows the upstream commit, 379 created, 372 eligible, and 7 ineligible
