# xp-budget Specification

## Purpose

Computes the XP budget for an encounter from the party's character levels and
the chosen difficulty, following the 2024 5e encounter-building rules. The
budget is the ceiling every generated lineup must stay within.

## Requirements

### Requirement: Per-character budget table
The system SHALL use the 2024 "XP Budget per Character" table for levels 1 through 20 and the Low, Moderate, and High difficulties.

#### Scenario: Level 5 values
- **WHEN** the budget is requested for one level-5 character
- **THEN** it is 500 for Low, 750 for Moderate, and 1,100 for High

#### Scenario: Table bounds
- **WHEN** the budget is requested for one level-1 character and for one level-20 character at High
- **THEN** they are 100 and 22,000

### Requirement: Party budget is the sum of per-character budgets
The party's budget for a difficulty SHALL be the sum of each character's per-character budget at that difficulty. This applies to parties with mixed levels too.

#### Scenario: Boat example reference
- **WHEN** the party is three level-5 characters
- **THEN** the budget is 1,500 for Low, 2,250 for Moderate, and 3,300 for High

#### Scenario: Mixed-level party
- **WHEN** the party is one level-3 and one level-5 character at Moderate
- **THEN** the budget is 975 (225 + 750)

### Requirement: Party validation
The calculator SHALL reject a party with no characters or with any level that is not an integer from 1 to 20, and SHALL say which input is invalid.

#### Scenario: Empty party
- **WHEN** the budget is requested for a party with no characters
- **THEN** it fails with an error saying the party needs at least one character

#### Scenario: Level out of range
- **WHEN** the party includes a level-21 character
- **THEN** it fails with an error naming the invalid level 21

#### Scenario: Non-integer level
- **WHEN** the party includes level 4.5 or the string "five"
- **THEN** it fails with an error naming the invalid level

### Requirement: Difficulty selection
The calculator SHALL accept exactly the difficulties Low, Moderate, and High, case-insensitively, and SHALL reject any other difficulty.

#### Scenario: Case-insensitive difficulty
- **WHEN** the difficulty is given as "moderate" or "MODERATE"
- **THEN** it is treated as Moderate

#### Scenario: Unknown difficulty
- **WHEN** the difficulty is "Deadly"
- **THEN** it fails with an error listing the accepted difficulties
