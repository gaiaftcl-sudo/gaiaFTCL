# GAMP5-OQ-EVIDENCE-002
Protocol reference: GAMP5-OQ-PROTOCOL-002 v1.0
Execution ID: OQ-EXEC-20260502T225811Z
Hardware: Chip: Apple M4 Max
macOS: 26.4.1

## Test Results (from live DB — not assumed)

OQ-SR-001 (review_cycles row count): 2
Pass criterion: >= 1
Result: PASS

OQ-SR-002 (domain_improvement receipt count): 2
Pass criterion: >= 1
Result: PASS

OQ-SR-003 (prior < post health score rows):
30680435-EEA9-4BEF-82BA-F995B16FBBE0|fusion|0.0498000010848045|0.0623000040650368
EC1C0BE5-1A2D-4A1A-9E52-CDEE3E19633E|health|0.0498000010848045|0.0623000040650368
Pass criterion: >= 1 row with post > prior
Result: PASS

OQ-SR-004 (weights > 1.0 count):
0 rows
Pass criterion: 0 rows
Result: PASS

OQ-SR-005 (improvement receipts — new > old weight):
59560909-5364-495D-93B2-9580D14DEBEF|{"cycle_id":"30680435-EEA9-4BEF-82BA-F995B16FBBE0","dimension_improved":"s1","domain":"fusion","new_weight":0.55,"old_weight":0.5,"prior_health_score":0.049800001084804535,"sha256":"f4ea1a80627167b3f26bd5bea70e29c989000f394d0f7e5e7279cf08a061679d"}
A487BBE2-77F9-4259-B912-99195CD583D8|{"cycle_id":"EC1C0BE5-1A2D-4A1A-9E52-CDEE3E19633E","dimension_improved":"s1","domain":"health","new_weight":0.55,"old_weight":0.5,"prior_health_score":0.049800001084804535,"sha256":"f4ea1a80627167b3f26bd5bea70e29c989000f394d0f7e5e7279cf08a061679d"}
Pass criterion: all rows show new_weight > old_weight
Result: PASS

## Known limitations
OQ-CONST-002: DEFERRED — single Apple Silicon generation
OQ-FW-005: PASS (nats monologue confirmed in prior session)

## Signatory
Rick Gillespie, Founder and CEO, FortressAI Research Institute

## Git commit SHA
COMMIT_SHA_TBD
