# Spec Delta

## Purpose

Validates a proposed monster lineup against the catalog and an XP budget, and
reports its total XP, remaining budget, and every problem found. This is the
check that keeps an untrusted lineup, such as one proposed by an LLM, from being
accepted.

## ADDED Requirements

### Requirement: Lineup totals
Evaluating a lineup SHALL report its total XP as the sum of each resolvable entry's catalog XP times its quantity, the budget it was evaluated against, and the remaining XP (budget minus total, which is negative when over budget).

#### Scenario: Totals for a valid lineup
- **WHEN** a lineup of 1 Giant Shark (1,800 XP) and 9 Acolytes (50 XP each) is evaluated against a budget of 2,250
- **THEN** the total is 2,250, the remaining XP is 0, and the lineup is valid

#### Scenario: Totals still reported when invalid
- **WHEN** a lineup contains 1 Giant Shark and an unknown ID, evaluated against 2,250
- **THEN** the total is 1,800, counting only the resolvable entry, and the lineup is invalid

### Requirement: Budget is a ceiling
A lineup whose total XP exceeds the budget SHALL be invalid, and the feedback SHALL state the amount over budget. A total equal to the budget SHALL be valid.

#### Scenario: Over budget
- **WHEN** a lineup of 1 Giant Shark and 1 Knight (700 XP) is evaluated against 2,250
- **THEN** the lineup is invalid with an over-budget problem stating it is 250 XP over

#### Scenario: Exactly on budget
- **WHEN** a lineup's total equals the budget
- **THEN** the lineup is valid

### Requirement: Catalog IDs must exist
Every entry SHALL reference an existing catalog record. Each unknown ID SHALL produce its own problem naming that ID.

#### Scenario: Unknown ID
- **WHEN** a lineup includes the ID `srd-2014--tarrasque-jr`, which is not in the catalog
- **THEN** the lineup is invalid with an unknown-ID problem naming `srd-2014--tarrasque-jr`

### Requirement: Quantities must be positive integers
Every entry's quantity SHALL be an integer of at least 1. Zero, negative numbers, fractions, strings, and missing quantities SHALL each produce a problem for that entry.

#### Scenario: Invalid quantities
- **WHEN** entries have quantities 0, -2, 1.5, "3", or no quantity
- **THEN** each one produces an invalid-quantity problem naming its ID and the value given

### Requirement: Records must be eligible
Every entry SHALL reference a record that is eligible for generation. An ineligible record SHALL produce a problem that includes its exclusion reasons.

#### Scenario: Ineligible record
- **WHEN** a lineup includes the Draconic Spirit (`srd-2024--draconic-spirit`)
- **THEN** the lineup is invalid with an ineligible-record problem listing its exclusion reasons

### Requirement: One entry per record and one variant per creature
Each catalog ID SHALL appear at most once in a lineup, and a lineup SHALL use at most one variant of a creature, where variants are records with the same name from different source books.

#### Scenario: Repeated ID
- **WHEN** a lineup lists `srd-2014--giant-shark` twice
- **THEN** the lineup is invalid with a duplicate-entry problem naming that ID

#### Scenario: Two variants of one creature
- **WHEN** a lineup includes both `srd-2014--ape` and `srd-2024--ape`
- **THEN** the lineup is invalid with a multiple-variants problem naming the creature "Ape" and both IDs

### Requirement: Lineup must not be empty
A lineup with no entries SHALL be invalid.

#### Scenario: Empty lineup
- **WHEN** an empty lineup is evaluated
- **THEN** the lineup is invalid with an empty-lineup problem and a total of 0

### Requirement: Machine-readable feedback
Each problem SHALL include a stable code, the catalog ID it concerns (when there is one), and a human-readable message, so callers can show it to a DM or return it to a model to revise the lineup. A valid lineup SHALL report no problems.

#### Scenario: Several problems reported together
- **WHEN** a lineup has an unknown ID, an invalid quantity, and is over budget
- **THEN** the result lists all three problems, each with its code, ID where applicable, and message
