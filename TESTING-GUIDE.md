# ArborCTL Communication Resilience - Testing Guide

## Implementation Summary

✅ **Changes Applied**:
1. Added communication health tracking to `sys/arborctl-vars.g`
2. Implemented retry logic with caching in `macro/private/control/shihlin-sl3.g`
3. Updated daemon error handling in `macro/private/arborctl-daemon.g`
4. Created diagnostics macro `macro/gcodes/G8002.g`

## Before Testing

### 1. Restart Your Duet Controller
Power cycle or run `M999` to reload the updated configuration:
```gcode
M999
```

### 2. Verify ArborCtl Loads
Check console for any errors during startup. You should see ArborCtl version message.

### 3. Run Initial Diagnostics
```gcode
G8002
```
This will show baseline communication statistics (should all be zeros initially).

## Testing Scenarios

### Test 1: Normal Operation (Baseline)
**Goal**: Verify system works normally with no failures

**Steps**:
1. Start spindle: `M3 S12000 P0` (adjust speed as appropriate)
2. Wait 30 seconds
3. Run diagnostics: `G8002`
4. Stop spindle: `M5 P0`

**Expected Results**:
- Spindle starts and runs normally
- `G8002` shows:
  - Success Rate: 100%
  - Consecutive Failures: 0
  - Health: ✓ GOOD

---

### Test 2: Single Transient Failure (Low Severity)
**Goal**: Verify retry logic handles brief communication glitch

**Steps**:
1. Enable debug logging: `set global.arborCommDebug = true`
2. Start spindle: `M3 S12000 P0`
3. **Briefly touch/wiggle RS485 cable** (1-2 seconds) to create intermittent connection
4. Observe console messages
5. Run diagnostics: `G8002`
6. Verify spindle still running normally

**Expected Results**:
- Console shows: "ArborCtl: Spindle 0 status read OK (attempt 2)" or similar
- System retries and succeeds
- No job interruption
- `G8002` shows:
  - Success Rate: >95%
  - Consecutive Failures: 0 (resets after success)
  - Total Failures: 1-5
  - Health: ✓ GOOD

---

### Test 3: Intermittent Failures (Warning Level)
**Goal**: Verify caching mechanism works during multiple transient failures

**Steps**:
1. Start spindle: `M3 S12000 P0`
2. **Partially disconnect RS485 cable** (loose connection)
3. Observe for 5-10 seconds
4. Reconnect firmly
5. Run diagnostics: `G8002`

**Expected Results**:
- Console shows warnings:
  - "ArborCtl: WARNING - Spindle 0 communication failed after 3 attempts"
  - "ArborCtl: Using cached data (age: 0.4s)"
  - "Consecutive failures: 1" (or 2)
- Spindle continues running
- No emergency stop
- `G8002` shows:
  - Success Rate: 85-95%
  - Consecutive Failures: 1-2 (less than threshold of 3)
  - Health: ⚠ WARNING

---

### Test 4: Sustained Communication Loss (Critical)
**Goal**: Verify controlled shutdown after threshold exceeded

**Steps**:
1. Start spindle: `M3 S12000 P0`
2. **Fully disconnect RS485 cable**
3. Wait 2-3 seconds (3 daemon cycles @ 200ms each)
4. Observe console and spindle behavior
5. Reconnect cable
6. Run diagnostics: `G8002`

**Expected Results**:
- Console shows progressive warnings:
  ```
  ArborCtl: WARNING - Spindle 0 communication failed after 3 attempts
  ArborCtl: Consecutive failures: 1
  ArborCtl: Using cached data (age: 0.4s)
  [200ms later]
  ArborCtl: WARNING - Spindle 0 communication failed after 3 attempts
  ArborCtl: Consecutive failures: 2
  ArborCtl: Using cached data (age: 0.6s)
  [200ms later]
  ArborCtl: WARNING - Spindle 0 communication failed after 3 attempts
  ArborCtl: Consecutive failures: 3
  ArborCtl: CRITICAL - Communication lost with spindle 0
  ArborCtl: Initiating controlled stop for safety
  ```
- Spindle stops gracefully (not emergency stop)
- If job running, it pauses with dialog box
- `G8002` shows:
  - Consecutive Failures: 3+
  - Health: ✗ CRITICAL

---

### Test 5: Recovery After Reconnection
**Goal**: Verify system recovers after cable reconnected

**Steps**:
1. After Test 4, cable should be reconnected
2. Clear error state: `M292` (if dialog showing)
3. Wait 5 seconds
4. Run diagnostics: `G8002`
5. Try starting spindle again: `M3 S12000 P0`

**Expected Results**:
- After cable reconnected, next successful read resets consecutive failures
- `G8002` shows:
  - Consecutive Failures: 0 (reset on success)
  - Last Successful Read: <5s ago
  - Health: ✓ GOOD (recovered)
- Spindle can be restarted normally

---

### Test 6: Communication Failure While Idle
**Goal**: Verify lower-risk response when spindle not running

**Steps**:
1. **Ensure spindle is stopped**: `M5 P0`
2. Disconnect RS485 cable
3. Wait 5 seconds
4. Run diagnostics: `G8002`
5. Reconnect cable

**Expected Results**:
- Warnings appear but less severe
- No automatic spindle stop (since not running)
- System operates in degraded mode
- Extended loss (6+ consecutive failures) may trigger warning but not emergency

---

## Troubleshooting During Testing

### Issue: "Still getting emergency stops"

**Check 1**: Verify timeout is adequate
```gcode
set global.arborModbusTimeout = 75  ; Increase from 50ms
```

**Check 2**: Increase failure threshold
```gcode
set global.arborMaxConsecFailures = 5  ; Increase from 3
```

**Check 3**: Enable debug logging
```gcode
set global.arborCommDebug = true
```
Watch console to see which attempt succeeds.

---

### Issue: "Communication seems slow"

This is expected - we've added 40-50ms per cycle for better reliability.

If unacceptable:
```gcode
set global.arborModbusTimeout = 30    ; Reduce timeout
set global.arborMaxRetries = 2        ; Fewer retries
```

---

### Issue: "Constant warnings even with good connection"

This indicates real RS485 issues:

**Physical Layer Checks**:
1. ✓ Separate Modbus cable from motor cables (>30cm apart)
2. ✓ Verify 120Ω termination resistors at BOTH ends
3. ✓ Use shielded twisted pair cable
4. ✓ Ground shield at ONE end only
5. ✓ Check for loose connections
6. ✓ Verify cable quality (proper RS485-rated cable)
7. ✓ Keep cable runs as short as practical

**Software Tuning**:
```gcode
set global.arborModbusTimeout = 75     ; Give VFD more time
set global.arborCacheValidityPeriod = 3.0  ; Longer cache validity
```

---

## Advanced Testing

### Stress Test: Run a Job
1. Load a simple G-code file
2. Start the job
3. During job, briefly disconnect/reconnect RS485 cable 2-3 times
4. Job should NOT pause (retries succeed)
5. Check `G8002` after job completes

### Logging Test: Monitor Success Rate
Create a monitoring script:
```gcode
; monitor.g - Run periodically to log comm health
while { iterations < 10 }
    G4 P5000  ; Wait 5 seconds
    G8002     ; Show stats
```

Run with: `M98 P"monitor.g"`

---

## Configuration Tuning for Your Environment

### Clean Environment (Low EMI)
```gcode
set global.arborMaxConsecFailures = 2   ; More sensitive
set global.arborMaxRetries = 2          ; Fewer retries needed
set global.arborModbusTimeout = 40      ; Shorter timeout OK
```

### Noisy Environment (High EMI)
```gcode
set global.arborMaxConsecFailures = 5   ; More tolerant
set global.arborMaxRetries = 3          ; More retries
set global.arborModbusTimeout = 75      ; Longer timeout
set global.arborCacheValidityPeriod = 3.0  ; Trust cache longer
```

### Production (Conservative)
```gcode
set global.arborMaxConsecFailures = 3   ; Balanced
set global.arborMaxRetries = 3          ; Standard
set global.arborModbusTimeout = 50      ; Standard
set global.arborCommDebug = false       ; Less console spam
```

### Debug/Development
```gcode
set global.arborMaxConsecFailures = 3
set global.arborMaxRetries = 3
set global.arborModbusTimeout = 50
set global.arborCommDebug = true        ; Show all details
```

---

## Success Criteria

Your implementation is working correctly when:

✅ **Normal Operation**: Spindle starts/stops reliably with no warnings

✅ **Transient Failures**: Brief cable disconnect shows retry messages but continues operating

✅ **Caching Works**: Multiple failed reads use cached data without stopping

✅ **Controlled Shutdown**: Only after 3+ consecutive failures does system stop spindle

✅ **Recovery**: After reconnecting cable, system automatically recovers

✅ **Diagnostics**: `G8002` shows meaningful statistics

✅ **No False Positives**: Hours of operation without unnecessary stops

---

## Before/After Comparison

### Before Implementation
- Mean time between false stops: 6-7 seconds during operation
- Every transient failure caused stop
- No visibility into communication health
- No retry mechanism

### After Implementation (Expected)
- Mean time between false stops: Hours to days
- 95%+ of transient failures handled automatically
- Clear warnings before any action
- Comprehensive diagnostics available
- Configurable thresholds

---

## Next Steps

1. ✅ Test each scenario above
2. ✅ Tune configuration for your environment
3. ✅ Run production job with monitoring
4. ✅ Document your optimal settings
5. ✅ Consider applying same changes to Huanyang VFD if used

---

## Rollback (If Needed)

If you need to revert changes:

```bash
cd /Users/julien/Sources/ArborCTL
git diff sys/arborctl-vars.g
git diff macro/private/control/shihlin-sl3.g
git diff macro/private/arborctl-daemon.g

# To restore original files:
git checkout sys/arborctl-vars.g
git checkout macro/private/control/shihlin-sl3.g
git checkout macro/private/arborctl-daemon.g
rm macro/gcodes/G8002.g

# Then restart Duet
M999
```

---

## Support & Feedback

When reporting issues, please include:
1. Output of `G8002`
2. Console messages (with `global.arborCommDebug = true`)
3. Your configuration settings
4. Description of physical setup (cable lengths, routing, etc.)

---

**Testing Time Estimate**: 30-60 minutes  
**Expected Result**: 95%+ reduction in false stops
