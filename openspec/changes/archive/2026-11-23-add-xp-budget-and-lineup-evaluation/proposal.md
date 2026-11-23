# Proposal

## Why

Build-order step 2 is to implement and test the 2024 XP calculator. Every
generated encounter is bounded by an XP budget, and the design says Rails must
revalidate every final lineup instead of trusting LLM output. Both rules are
plain domain logic that the step 4 `evaluate_lineup` MCP tool and the step 5
generation flow will call. Building them now, against the catalog from step 1,
lets step 4 be pure plumbing and gets the design's failure cases tested early.

## What Changes

- Add a 2024 XP budget calculator. It takes the party's character levels and a
  difficulty (Low, Moderate, or High) and returns the sum of the per-character
  budgets from the 2024 "XP Budget per Character" table. Three level-5 PCs give
  Low 1,500, Moderate 2,250, and High 3,300.
- Reject invalid parties (no characters, or a level that isn't an integer from
  1 to 20) and unknown difficulties with clear errors.
- Add a lineup evaluation service. Given a budget and a proposed lineup (catalog
  IDs with quantities), it returns total XP (the sum of monster XP times
  quantity), the budget, remaining XP, whether the lineup is valid, and specific
  feedback for every problem.
- Validation rules: every ID exists in the catalog, every quantity is a positive
  integer, every record is eligible for generation, each ID appears once, at most
  one variant of a creature is used (for example, not both Apes), the lineup isn't
  empty, and the total doesn't exceed the budget (a ceiling).
- No UI, MCP, or LLM work. Those are steps 4 and 5.

## Capabilities

### New Capabilities
- `xp-budget`: Computing the 2024 encounter XP budget for a party and difficulty.
- `lineup-evaluation`: Validating a proposed monster lineup against the catalog
  and a budget, and reporting its total, remaining XP, and problems.

### Modified Capabilities
None. `monster-catalog` is used as-is: evaluation reads each record's XP,
eligibility, and name.

## Impact

- New services in `app/services/encounter/` that both Rails and the future MCP
  server will call. There are no new models, routes, or gems.
- Tests: a pure unit test of the budget table (including the boat-example
  reference values) and Mongo-backed lineup evaluation tests using catalog
  records from the existing SRD fixture.
- Docs: the design doc's mixed-level assumption stays as written. The 2024 rules
  only describe parties whose characters share one level.
