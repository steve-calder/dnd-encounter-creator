# Spec Delta

## Purpose

Lets a DM browse the imported monster catalog and read a complete, legible stat
block for any record. The same stat block view is reused later to present
generated encounter lineups.

## ADDED Requirements

### Requirement: Catalog listing
The app SHALL provide a catalog page that lists every catalog record, showing its name, source book, size and type, CR, XP, and whether it is eligible for generation. Each entry SHALL link to that record's stat block.

#### Scenario: Listing shows variants separately
- **WHEN** a DM opens the catalog page after import
- **THEN** both "Ape" records appear, each labeled with its source book and linking to its own stat block

#### Scenario: Ineligible records marked
- **WHEN** the catalog includes "Animated Object (Tiny)", which is ineligible
- **THEN** its listing entry is visibly marked as not eligible for generation

### Requirement: Catalog filtering by name
The catalog page SHALL let the DM filter the listing by a case-insensitive substring of the monster name, and SHALL treat the filter text as literal text rather than a pattern.

#### Scenario: Name filter
- **WHEN** the DM filters by "shark"
- **THEN** only records whose names contain "shark" (for example Giant Shark, Hunter Shark, Reef Shark) are listed

#### Scenario: Special characters are literal
- **WHEN** the DM filters by `.*`
- **THEN** only records whose names literally contain ".*" are listed, which is none

### Requirement: Stat block page
The app SHALL render a stat block for a single record showing name, size, type, alignment, AC, HP, speed, the six ability scores with modifiers, any saving throws, skills, damage and condition immunities, resistances, vulnerabilities, senses, languages, CR, XP, and every trait, action, bonus action, reaction, and legendary action.

#### Scenario: Giant Shark stat block
- **WHEN** a DM opens the stat block for Giant Shark (2014)
- **THEN** the page shows AC 13 (Natural Armor), HP 126 (11d12+55), Swim 50 ft., STR 23 (+6), CR 5, XP 1,800, the traits Blood Frenzy and Water Breathing, and a Bite action with +9 to hit and 3d10 + 6 piercing damage

#### Scenario: Sections without entries omitted
- **WHEN** a record has no reactions or legendary actions
- **THEN** the stat block shows no empty Reactions or Legendary Actions headings

### Requirement: Source and eligibility shown on stat block
The stat block page SHALL show the record's source book and publisher, its XP provenance, and, for an ineligible record, every reason it is excluded from generation.

#### Scenario: Ineligible stat block explains why
- **WHEN** a DM opens the stat block for "Draconic Spirit"
- **THEN** the page states it is not eligible for generation and lists the reasons

### Requirement: Unknown record handling
Requesting a stat block for an ID that is not in the catalog SHALL return a not-found response and SHALL NOT raise an unhandled error.

#### Scenario: Missing ID
- **WHEN** a DM requests the stat block for an ID that does not exist
- **THEN** the app responds with HTTP 404

### Requirement: Safe rendering of source text
Source text (descriptions, trait and action text) SHALL be rendered as escaped plain text, never as HTML.

#### Scenario: Markup in source text
- **WHEN** a record's trait description contains `<script>`
- **THEN** the stat block shows the literal text and no script runs

### Requirement: SRD attribution
Catalog and stat block pages SHALL display the CC-BY-4.0 attribution required by the System Reference Document.

#### Scenario: Attribution visible
- **WHEN** a DM opens any catalog or stat block page
- **THEN** the page includes the SRD CC-BY-4.0 attribution notice
