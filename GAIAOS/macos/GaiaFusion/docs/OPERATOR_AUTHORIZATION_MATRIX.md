# Operator Authorization Matrix — GaiaFusion Access Control

**Authority**: FDA 21 CFR Part 11 §11.10(d)(g), EU Annex 11  
**Version**: 1.0  
**Last Updated**: 2026-04-14

---

## Section 1: Authorization Levels

GaiaFusion uses a 3-level authorization hierarchy:

| Level | Name | How Established | Capabilities |
|-------|------|-----------------|--------------|
| L1 | Operator | Active session with valid credentials | Monitor telemetry, emergency stop, basic actions |
| L2 | Senior Operator | L1 + role assertion at login | L1 + parameter changes, shot initiation, plant swap |
| L3 | Supervisor | L2 + supervisor credential | L2 + maintenance mode, authorization settings, dual-auth approval |

**Hierarchy:** L3 ≥ L2 ≥ L1

**Special roles:**
- **INSTRUCTOR**: Training mode authorization (separate from L1/L2/L3)
- **AUDITOR**: Export audit logs (separate permission, requires L2 minimum)
- **MAINTENANCE_TECH**: L3 equivalent for maintenance sessions only

---

## Section 2: Menu Authorization Table

Every menu item has defined authorization and plant state requirements:

### File Menu

| Item | Auth Level | Plant States Allowed | Action |
|------|------------|---------------------|--------|
| New Session | L1 | IDLE, TRAINING | Start new operator session |
| Open Plant Configuration... | L2 | IDLE, MAINTENANCE | Load saved plant config |
| Save Snapshot | L1 | Any | Save current state to file |
| Export Audit Log... | L2 + AUDITOR | Any | Export compliance logs |
| Quit GaiaFusion | L1 | IDLE, TRAINING | Exit application |

### Cell Menu

| Item | Auth Level | Plant States Allowed | Action |
|------|------------|---------------------|--------|
| Swap Plant... | L2 | IDLE, MAINTENANCE | Change plant topology (tokamak → stellarator, etc.) |
| Arm Ignition | L2 + L3 (dual) | MOORED | Arm plasma ignition circuit |
| Emergency Stop | L1 | RUNNING | Immediate plasma shutdown |
| Reset Trip... | L2 + L3 (dual) | TRIPPED | Clear trip condition after review |
| Acknowledge Alarm | L2 | CONSTITUTIONAL_ALARM | Acknowledge constitutional violation |

### Mesh Menu

| Item | Auth Level | Plant States Allowed | Action |
|------|------------|---------------------|--------|
| Toggle Wireframe | L1 | Any | Show/hide wireframe overlay |
| Set Wireframe Color... | L1 | Any (except CONSTITUTIONAL_ALARM) | Custom wireframe color |
| Show Bounding Box | L1 | Any | Debug: show geometry bounds |
| Reset Camera | L1 | Any | Return camera to default position |

### Config Menu

| Item | Auth Level | Plant States Allowed | Action |
|------|------------|---------------------|--------|
| Training Mode | L2 | IDLE | Enter training session (simulated plant) |
| Maintenance Mode | L3 | IDLE | Enter maintenance session |
| Authorization Settings... | L3 | IDLE | Manage operator roles and credentials |

### Help Menu

| Item | Auth Level | Plant States Allowed | Action |
|------|------------|---------------------|--------|
| About GaiaFusion | L1 | Any | Show version and license info |
| View Audit Log | L2 | Any | Read-only audit log viewer |

**Prohibited menus:**
- View (removed — mode switching is plant-state driven, not menu-driven)
- Window (removed — standard macOS window menu not needed)
- Edit (removed — no cut/copy/paste in fusion control system)

---

## Section 3: Dual Authorization Protocol

Required for safety-critical actions: Arm Ignition, Ignite, Reset Trip.

**Sequence:**

1. **L2 operator initiates action**
   - System enters `PENDING_DUAL_AUTH` state
   - Dialog appears showing:
     - Action being requested
     - Initiator ID and timestamp
     - Authorization timeout (30 seconds)
   - All other controls locked until resolved

2. **L3 supervisor authenticates independently**
   - Must be a different user ID (self-approval prohibited)
   - Supervisor enters credentials
   - System verifies L3 role

3. **Resolution:**
   - **If approved:** Action proceeds, both IDs logged
   - **If rejected:** Action cancelled, rejection logged
   - **If timeout (30s):** Action auto-cancelled, timeout logged

**Audit log entry format:**
```json
{
  "entry_id": "UUID",
  "timestamp": "ISO8601",
  "action": "ARM_IGNITION",
  "initiator_id": "operator_user_id",
  "initiator_level": "L2",
  "supervisor_id": "supervisor_user_id",
  "supervisor_level": "L3",
  "timestamp_initiated": "ISO8601",
  "timestamp_approved": "ISO8601",
  "plant_state_at_action": "MOORED",
  "result": "APPROVED",
  "session_id": "UUID"
}
```

**Prohibited:**
- Self-approval (initiator_id == supervisor_id)
- Timeout bypass
- Manual approval without L3 credentials

---

## Section 4: Universal Audit Log Entry Format

Every action, every time:

```json
{
  "entry_id": "UUID",
  "timestamp": "ISO8601 with milliseconds",
  "user_id": "string",
  "user_level": "L1 | L2 | L3",
  "session_id": "UUID",
  "plant_state": "PlantOperationalState.rawValue",
  "action": "ACTION_TYPE_CONSTANT",
  "layout_mode": "currentMode.rawValue",
  "payload": {},
  "training_mode": false
}
```

**Required fields:**
- `entry_id` — unique, never reused
- `timestamp` — ISO8601 with milliseconds
- `user_id` — operator identity
- `plant_state` — plant operational state at time of action
- `action` — standardized constant (all caps, underscore-separated)

**Special handling:**
- When `training_mode: true`, mark entries as non-operative in compliance exports
- Audit entries are write-once, never modified or deleted
- Log file rotation maintains full history (no truncation)

---

## Section 5: Action Authorization Check Implementation

Every menu action, button press, or keyboard shortcut must include authorization check:

```swift
Button("Arm Ignition") {
    guard session.userLevel.isAtLeast(.l2) else {
        auditLog.write(AuditEntry(
            action: "UNAUTHORIZED_ATTEMPT_ARM_IGNITION",
            payload: ["user_level": session.userLevel.rawValue]
        ))
        showAlert("Insufficient authorization. L2 required.")
        return
    }
    guard operationalState == .moored else {
        auditLog.write(AuditEntry(
            action: "INVALID_STATE_ARM_IGNITION",
            payload: ["plant_state": operationalState.rawValue]
        ))
        showAlert("Cannot arm ignition. Plant must be in MOORED state.")
        return
    }
    // Proceed with dual-auth protocol...
}
.disabled(!operationalState.allows(.armIgnition) || !session.userLevel.isAtLeast(.l2))
```

**Pattern:**
1. Check authorization level first
2. Check plant state validity second
3. Log any failure with specific reason
4. Use `.disabled()` modifier to gray out invalid menu items

---

## Section 6: Prohibited Actions

No authorization level permits these:

1. **Deleting audit log entries**
   - Audit log is append-only
   - Regulatory requirement

2. **Modifying audit log entries after creation**
   - Write-once semantics
   - Any modification is a compliance violation

3. **Overriding `.constitutionalAlarm` mode while alarm is active**
   - Mode is forced by WASM substrate
   - Operator cannot dismiss until violation resolved

4. **Bypassing dual-auth timeout**
   - 30-second timeout is firm
   - No administrative override

5. **Self-approval in dual-auth protocol**
   - Initiator and approver must be different users
   - System must enforce `initiator_id != supervisor_id`

---

## Section 7: Authorization Level Comparison

```swift
enum OperatorLevel: Int, Comparable, Codable {
    case l1 = 1  // Operator
    case l2 = 2  // Senior Operator
    case l3 = 3  // Supervisor
    
    static func < (lhs: OperatorLevel, rhs: OperatorLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    func isAtLeast(_ required: OperatorLevel) -> Bool {
        self >= required
    }
}
```

**Usage in menu/button authorization:**
```swift
.disabled(!session.userLevel.isAtLeast(.l2))
```

---

## Section 8: Plant State Authorization Matrix

| Plant State | L1 Can | L2 Can | L3 Can |
|-------------|--------|--------|--------|
| IDLE | Monitor, configure (read-only) | Monitor, configure, open config, start training | All L2 + maintenance mode, auth settings |
| MOORED | Monitor, emergency stop | Monitor, stop, adjust parameters, arm ignition (with L3) | All L2 + approve ignition |
| RUNNING | Monitor, emergency stop | Monitor, emergency stop only | Monitor, emergency stop only |
| TRIPPED | Monitor | Monitor, view trip log | Monitor, reset trip (with L2) |
| CONSTITUTIONAL_ALARM | Monitor, view violation | Monitor, acknowledge alarm | Monitor, acknowledge alarm, force reset |
| MAINTENANCE | Monitor | Monitor | Monitor, all maintenance actions |
| TRAINING | All actions (simulated) | All actions (simulated) | All actions (simulated) + end session |

**Key principle:** RUNNING state locks most controls for all levels. Only emergency stop remains available.

---

## Section 9: Keyboard Shortcut Authorization

| Shortcut | Action | Auth Required | Plant State Check |
|----------|--------|---------------|-------------------|
| Cmd+1 | Switch to dashboardFocus | L1 | Allowed if keyboardShortcutsEnabled |
| Cmd+2 | Switch to geometryFocus | L1 | Allowed if keyboardShortcutsEnabled AND plant state allows |
| Cmd+Q | Quit | L1 | Only in IDLE or TRAINING |
| Cmd+E | Emergency Stop | L1 | Only in RUNNING |

**Important:** Keyboard shortcuts can be disabled by plant state. When `keyboardShortcutsEnabled == false` (e.g., in TRIPPED or CONSTITUTIONAL_ALARM), shortcuts have no effect.

---

## Section 10: Implementation Checklist

To implement authorization:

- [ ] Define `OperatorLevel` enum (L1, L2, L3)
- [ ] Add `userLevel` to session object
- [ ] Implement `PlantOperationalState.allows(action:)` method
- [ ] Add authorization check before every action
- [ ] Add `.disabled()` modifier to every menu item per Section 2
- [ ] Implement dual-auth dialog for actions requiring L2+L3
- [ ] Log all authorization failures
- [ ] Add unit tests for authorization matrix

---

## Appendix: Authorization Failure Examples

**Example 1: L1 tries to arm ignition**
```
Audit log entry:
{
  "action": "UNAUTHORIZED_ATTEMPT_ARM_IGNITION",
  "user_id": "operator_123",
  "user_level": "L1",
  "timestamp": "2026-04-14T15:30:45.123Z",
  "plant_state": "MOORED",
  "result": "DENIED_INSUFFICIENT_AUTH"
}
```

**Example 2: L2 tries to switch to geometry mode during RUNNING**
```
Audit log entry:
{
  "action": "INVALID_MODE_REQUEST_GEOMETRY",
  "user_id": "senior_operator_456",
  "user_level": "L2",
  "timestamp": "2026-04-14T15:35:12.456Z",
  "plant_state": "RUNNING",
  "layout_mode": "dashboard_focus",
  "result": "DENIED_UNSAFE_STATE"
}
```

Both attempts are logged. Neither succeeds. The system's state is unchanged.
