# Design

## Context

- Step 1 left a `Monster` catalog of 379 SRD records. Each has a string `_id`
  such as `srd-2014--giant-shark`, plus `name`, `book`, `xp` (an Integer),
  `eligible`, and `ineligibility_reasons`. 372 records are eligible. Services
  live in `app/services/` (currently `Catalog::*`), and tests share an SRD
  fixture through `SrdFixture`.
- The 2024 table was checked against the D&D Beyond 2024 Basic Rules,
  "DM's Toolbox", Step 2: Determine Your XP Budget. That page says to multiply
  the table value by the number of characters. It gives no rule for mixed
  levels, so summing per-character values is the design doc's stated v1
  assumption and matches the uniform-level rule.
- Step 4 exposes `evaluate_lineup` through MCP, where inputs arrive as parsed
  JSON (string keys and arbitrary value types). Step 5 calls the same services
  from the generation flow. Neither exists yet.

## Goals / Non-Goals

**Goals:**
- Two plain-Ruby services with no Rails UI or MCP dependency, safe to call with
  untrusted input.
- Feedback precise enough for a model to revise a lineup: one problem per
  defect, each with a stable code.

**Non-Goals:**
- Extracting a party from free text, or asking for clarification (step 5).
- Binding an evaluation to a particular request's party and difficulty. Callers
  pass the budget they computed; step 4 holds that binding.
- Judging thematic fit or "material shortfall" presentation (step 5 display).
- Encounter multipliers or other 2014-era adjustments. The 2024 rules have none.

## Decisions

### 1. Namespace `Encounters::`, not `Encounter::`
The services are `Encounters::XpBudget` and `Encounters::LineupEvaluation` in
`app/services/encounters/`. A future `Encounter` model (for example, saved
results) would clash with an `Encounter` module.
- *Alternative:* a top-level `XpBudget`. Rejected so related encounter rules stay
  grouped, just as `Catalog::` groups the import.

### 2. `XpBudget`: a constant table plus a validating sum
```ruby
Encounters::XpBudget::TABLE      # { 1 => { low: 50, moderate: 75, high: 100 }, ..., 20 => {...} }
Encounters::XpBudget::DIFFICULTIES # [ :low, :moderate, :high ]
Encounters::XpBudget.for(levels: [ 5, 5, 5 ], difficulty: "moderate") # => 2250
```
- A comment on the table cites its source.
- `difficulty` accepts a String or Symbol, case-insensitively.
- `levels` must be a non-empty Array of Integers from 1 to 20. Floats and
  numeric strings are rejected, not coerced, because callers parse untrusted
  input and should coerce explicitly.
- Errors are `Encounters::XpBudget::InvalidParty` and `InvalidDifficulty`, both
  `ArgumentError` subclasses. Their messages name the offending value.
- *Alternative:* take a `{ level => count }` hash. Rejected because an array of
  levels maps directly to "the party" and handles mixed levels naturally.

### 3. `LineupEvaluation`: validate, then total what resolves
```ruby
result = Encounters::LineupEvaluation.call(
  entries: [ { "id" => "srd-2014--giant-shark", "quantity" => 1 } ],  # String or Symbol keys
  budget: 2250
)
result.valid?        # problems.empty?
result.total_xp      # Integer
result.budget        # Integer
result.remaining_xp  # budget - total_xp (may be negative)
result.problems      # [ Problem(code:, id:, message:) ]
result.entries       # [ Entry(id:, name:, book:, xp:, quantity:, subtotal:) ] for resolvable entries
```
- `budget` must be a positive Integer, or the call raises `ArgumentError`. That
  is a caller bug, not lineup feedback.
- One `Monster.in(_id: ids).only(...)` query loads every referenced record.
- Each entry is checked independently, and every problem is collected rather
  than stopping at the first.
- A **resolvable** entry has an existing ID and a valid quantity. Only
  resolvable entries count toward `total_xp`, so an over-budget problem reflects
  what the lineup would cost once fixed. Ineligible records still count toward
  the total. Their own problem makes the lineup invalid, and counting them keeps
  the total honest about what was proposed.
- Problem codes: `empty_lineup`, `invalid_entry` (not a hash, or the ID is
  missing or not a String), `unknown_id`, `invalid_quantity`, `ineligible`,
  `duplicate_entry`, `multiple_variants`, `over_budget`.
- **Variants:** resolvable records are grouped by case-insensitive `name`. More
  than one distinct ID in a group gives one `multiple_variants` problem naming
  the creature and its IDs. A repeated identical ID is `duplicate_entry`
  instead, and each occurrence still counts toward the total.
- `Result` and `Problem` are `Data` value objects with a `to_h` suitable for MCP
  JSON in step 4.
- *Alternative:* raise on the first invalid entry. Rejected because the model
  needs all the feedback at once to revise efficiently.

## Risks / Trade-offs

- **[Risk] Name-based variant grouping misses creatures that were renamed
  between editions** (for example, "Giant Sea Horse" vs. "Giant Seahorse").
  → Such pairs are allowed together. That's harmless for budget correctness,
  and an alias list can be added if it matters in practice.
- **[Trade-off] Strict integer typing rejects `"3"` from a sloppy caller.** →
  This is deliberate. The step 4 MCP schema declares integers, and a model
  sending strings should get feedback rather than silent coercion.
- **[Risk] A transcription error in the 20-row table.** → The tests pin every
  value on the level-5 row, both table corners (level 1 and level 20), and the
  boat example. The table is kept in one literal that is easy to review.
- **[Assumption] Mixed-level parties sum per-character budgets.** The official
  text covers only uniform levels. The design doc already calls this a v1
  assumption.
