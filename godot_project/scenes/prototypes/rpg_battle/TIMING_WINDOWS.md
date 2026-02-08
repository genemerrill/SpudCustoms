# RPG Battle Timing Windows

This document describes the timing windows in the RPG battle system where effects can trigger.

## Turn Flow Diagram

```
TURN START
    │
    ▼
┌─────────────────────────────────────┐
│  TIMING: START_OF_TURN              │
│  - Regeneration                      │
│  - Status effect ticks (burn, etc.)  │
│  - "At start of turn" abilities      │
└─────────────────────────────────────┘
    │
    ▼
  ACTION PHASE (Hero uses DEX for moves/attacks)
    │
    ├── MOVE: costs 1 DEX
    │     └── TIMING: POST_MOVE
    │
    ├── ATTACK: costs ALL remaining DEX
    │     │
    │     ├── TIMING: PRE_ATTACK (before dice roll)
    │     │     - Bones Ultimate check (5+ bones = INSTA-KILL)
    │     │     - "Before Attack" effects trigger
    │     │
    │     ├── DICE ROLL (ON_ATTACK)
    │     │     - Hits deal damage
    │     │     - Bones (5-6) add to Bones meter
          |     - "On Attack" and "During Attack" effects trigger
    │     │
    │     └── TIMING: POST_ATTACK (after damage resolved)
    │           - "On hit" effects
    │           - Lifesteal, etc.
    │           - "After Attack" effects trigger
    │
    └── WAIT: ends turn immediately
    │
    ▼
  DEX EXHAUSTED (current_dex == 0)
    │
    ▼
┌─────────────────────────────────────┐
│  TIMING: PRE_END_TURN               │
│  - "End of hero's turn" effects         │
│  - "Before end of turn" effects      │
│  - Delayed abilities trigger         │
│  - Poison/DoT final tick             │
└─────────────────────────────────────┘
    │
    ▼
  END_TURN
    │
    ▼
  NEXT UNIT'S TURN
```

## Implementation Status

| Timing Window | Status | Location |
|---------------|--------|----------|
| `PRE_ATTACK` | ✅ Implemented | `attack_unit()` - Bones Ultimate check |
| `POST_ATTACK` | 🔜 Placeholder | `attack_unit()` - after damage |
| `PRE_END_TURN` | 🔜 Placeholder | `check_hero_turn_end()` |
| `START_OF_TURN` | 🔜 Not yet | `_on_turn_changed()` |
| `POST_MOVE` | 🔜 Not yet | After `move_active_unit()` |

## Adding New Effects

### Example: Poison (PRE_END_TURN)

```gdscript
# In check_hero_turn_end():
func trigger_pre_end_turn_effects():
    for effect in active_unit.status_effects:
        if effect.timing == "PRE_END_TURN":
            effect.apply(active_unit)
```

### Example: Lifesteal (POST_ATTACK)

```gdscript
# In attack_unit(), after damage applied:
for effect in attacker.status_effects:
    if effect.timing == "POST_ATTACK":
        effect.apply(attacker, target, total_damage)
```

## Bones Ultimate Timing

The Bones Ultimate (INSTA-KILL) uses a specific timing rule:
- **Trigger window**: `PRE_ATTACK`
- **Requirement**: 5+ bones accumulated BEFORE the attack
- **Bones rolled during the attack** count toward the NEXT ultimate

This prevents "rolling into" an INSTA-KILL within the same attack.
