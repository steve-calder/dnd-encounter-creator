# Tasks

## 1. XP budget calculator

- [x] 1.1 Implement `Encounters::XpBudget` in `app/services/encounters/xp_budget.rb`. It has the 2024 table for levels 1–20 as one constant with a source comment, `DIFFICULTIES`, and `.for(levels:, difficulty:)`, which sums the per-character budgets. It raises `InvalidParty` or `InvalidDifficulty` (both `ArgumentError` subclasses) with messages that name the bad value. Verify with `test/services/encounters/xp_budget_test.rb`, which covers every scenario in `specs/xp-budget/spec.md`: the full level-5 row, the level-1 and level-20 High corners, the boat example (1,500 / 2,250 / 3,300), the mixed party (975), an empty party, levels 21, 0, 4.5, and "five", case-insensitive difficulty, and "Deadly" rejected.

## 2. Lineup evaluation

- [x] 2.1 Implement `Encounters::LineupEvaluation` in `app/services/encounters/lineup_evaluation.rb`, with `Result`, `Problem`, and `Entry` `Data` value objects (each with `to_h`). `.call(entries:, budget:)` accepts String or Symbol keys and raises `ArgumentError` for a budget that isn't a positive Integer. It loads all referenced records in one query, collects every problem (`empty_lineup`, `invalid_entry`, `unknown_id`, `invalid_quantity`, `ineligible`, `duplicate_entry`, `multiple_variants`, `over_budget`), and totals resolvable entries per design §3. Verify with `test/services/encounters/lineup_evaluation_test.rb` against catalog records imported from the SRD fixture. It covers every scenario in `specs/lineup-evaluation/spec.md`: 1 Giant Shark plus 9 Acolytes at 2,250 is valid with 0 remaining; Giant Shark plus Knight is 250 over; exactly on budget is valid; an unknown ID is reported and excluded from the total; quantities 0, -2, 1.5, "3", and missing each produce a problem; Draconic Spirit is ineligible with its reasons; a repeated ID gives `duplicate_entry`; the two Apes give `multiple_variants`; an empty lineup is invalid with total 0; several problems are reported together; a valid lineup has no problems.
- [x] 2.2 Add an integration-style test of the design doc's acceptance check. For three level-5 PCs at Moderate, `XpBudget.for` feeds `LineupEvaluation.call`: a sea-creature lineup within 2,250 (for example, 1 Giant Shark plus 4 Reef Sharks = 2,200) is valid with 50 remaining, and 2 Giant Sharks (3,600) fail as over budget. Add Reef Shark (2014) to `test/fixtures/files/srd_monsters_sample.json` from `db/data/srd_monsters.json`, keep `record_count` in sync, and confirm the existing catalog tests still pass.

## 3. Integration

- [x] 3.1 Note in `DND_ENCOUNTER_CREATOR_DESIGN.md`, under Generation flow step 2, that the 2024 rules give no mixed-level guidance, so summing per-character budgets stays the v1 assumption. Also note that `evaluate_lineup` will call `Encounters::LineupEvaluation`, which returns problem codes. Verify that the doc reads correctly and no other section contradicts it.
- [x] 3.2 Run `bin/ci` and confirm every step passes.

## Workflow follow-up

- Sync the `xp-budget` and `lineup-evaluation` specs and archive the change after review.
