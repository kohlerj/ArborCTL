; G8002.g - ArborCtl Communication Diagnostics
; Usage: G8002 (or M98 P"gcodes/G8002.g")
;
; This macro displays detailed communication statistics and health information
; for all configured spindles. Use this to troubleshoot Modbus communication issues.

echo { "========================================" }
echo { "  ArborCtl Communication Diagnostics   " }
echo { "========================================" }
echo { "" }

; Check if ArborCtl is initialized
if { !exists(global.arborVFDConfig) || global.arborVFDConfig == null }
    echo { "ArborCtl not initialized!" }
    M99

; Iterate through all spindles
while { iterations < limits.spindles }
    if { global.arborVFDConfig[iterations] != null }
        echo { "Spindle " ^ iterations ^ " (" ^ global.arborVFDConfig[iterations][0] ^ "):" }
        echo { "  Channel: " ^ global.arborVFDConfig[iterations][1] ^ ", Address: " ^ global.arborVFDConfig[iterations][2] }
        
        ; Spindle operational status
        if { global.arborVFDStatus[iterations] != null }
            var running = { global.arborVFDStatus[iterations][0] }
            var speed = { global.arborVFDStatus[iterations][3] }
            var stable = { global.arborVFDStatus[iterations][4] }
            echo { "  Status: " ^ (var.running ? "Running at " ^ var.speed ^ " RPM" : "Stopped") }
            echo { "  Stable: " ^ (var.stable ? "Yes" : "No") }
        else
            echo { "  Status: Unknown (no data)" }
        
        ; Communication health statistics
        if { global.arborCommHealth[iterations] != null }
            var totalAttempts = { global.arborCommHealth[iterations][3] }
            var totalFailures = { global.arborCommHealth[iterations][2] }
            var consecFailures = { global.arborCommHealth[iterations][0] }
            var lastSuccess = { state.upTime - global.arborCommHealth[iterations][1] }
            var cacheAge = { state.upTime - global.arborCommHealth[iterations][5] }
            var successRate = { var.totalAttempts > 0 ? (var.totalAttempts - var.totalFailures) / var.totalAttempts * 100 : 100 }
            
            echo { "" }
            echo { "  Communication Statistics:" }
            echo { "    Success Rate: " ^ var.successRate ^ "%" }
            echo { "    Total Attempts: " ^ var.totalAttempts }
            echo { "    Total Failures: " ^ var.totalFailures }
            echo { "    Consecutive Failures: " ^ var.consecFailures }
            echo { "    Last Successful Read: " ^ var.lastSuccess ^ "s ago" }
            echo { "    Cached Data Age: " ^ var.cacheAge ^ "s" }
            
            ; Health assessment
            echo { "" }
            if { var.consecFailures == 0 }
                echo { "  Health: ✓ GOOD - Communication stable" }
            elif { var.consecFailures < global.arborMaxConsecFailures }
                echo { "  Health: ⚠ WARNING - Intermittent failures detected" }
                echo { "           Using cached data. Check RS485 wiring." }
            else
                echo { "  Health: ✗ CRITICAL - Communication lost!" }
                echo { "           Check RS485 connection immediately." }
            
            ; Communication quality indicators
            if { var.successRate < 90 }
                echo { "" }
                echo { "  ⚠ Poor communication quality detected!" }
                echo { "    Recommendations:" }
                echo { "    - Separate Modbus cable from motor cables (>30cm)" }
                echo { "    - Verify 120Ω termination at both ends" }
                echo { "    - Use shielded twisted pair cable" }
                echo { "    - Check for loose connections" }
                echo { "    - Verify proper grounding (single-point)" }
        else
            echo { "  No communication statistics available" }
        
        ; Error state
        if { global.arborState[iterations][4] }
            echo { "" }
            echo { "  Error: Active error condition detected" }
        
        echo { "" }
        echo { "----------------------------------------" }

echo { "" }
echo { "Configuration:" }
echo { "  Max Consecutive Failures: " ^ global.arborMaxConsecFailures }
echo { "  Max Retries per Read: " ^ global.arborMaxRetries }
echo { "  Modbus Timeout: " ^ global.arborModbusTimeout ^ "ms" }
echo { "  Cache Validity Period: " ^ global.arborCacheValidityPeriod ^ "s" }
echo { "  Debug Logging: " ^ (global.arborCommDebug ? "Enabled" : "Disabled") }

echo { "" }
echo { "To enable debug logging: set global.arborCommDebug = true" }
echo { "To increase tolerance: set global.arborMaxConsecFailures = 5" }
echo { "To increase timeout: set global.arborModbusTimeout = 75" }
echo { "" }
echo { "========================================" }
