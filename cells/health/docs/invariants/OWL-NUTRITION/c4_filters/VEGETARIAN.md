# C4 filter — VEGETARIAN

**Filter ID:** `C4-NUTR-VEGETARIAN`  
**Scope:** Excludes meat/fish/poultry; eggs/dairy policy **user-tunable** (lacto-ovo vs lacto vs vegan handled by composite with [`VEGAN.md`](VEGAN.md)).

## Permitted S4 (default)

Plant foods, dairy/eggs if user declares lacto-ovo.

## Forbidden S4 (projection must refuse or sanitize)

Meat, poultry, fish, gelatin from animal sources **[I]** detail per user subtype.

## Invariant gaps (monitoring)

B12, iron bioavailability, zinc, omega-3 DHA/EPA, vitamin D — see [`sub_invariants/`](../sub_invariants/).

## Authority **[I]**

Dietary pattern definitions — Academy of Nutrition and Dietetics / WHO references; **CAB nutritionist** sign-off on encoded rules.
