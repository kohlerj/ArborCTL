; arbor-daemon.g - ArborCtl daemon control file
; This file runs the appropriate VFD control file and handles spindle stability monitoring

if { !exists(global.arborctlLdd) || !global.arborctlLdd || !exists(global.arborVFDConfig) || global.arborVFDConfig == null }
    M99

while { iterations < limits.spindles }
    if { spindles[iterations].state == "unconfigured" }
        continue

    ; Ensure VFD is configured for this spindle
    if { global.arborVFDConfig[iterations] == null }
        continue

    var spindleModel   = { global.arborVFDConfig[iterations][0] }
    var spindleChannel = { global.arborVFDConfig[iterations][1] }
    var spindleAddr    = { global.arborVFDConfig[iterations][2] }

    if { var.spindleModel == null || var.spindleChannel == null || var.spindleAddr == null }
        continue

    var modelFile = { "arborctl/control/" ^ var.spindleModel ^ ".g" }

    if { !fileexists("0:/sys/" ^ var.modelFile ) }
        echo { "ArborCtl: VFD model file not found for spindle " ^ iterations ^ "!" }
        continue

    ; Run the appropriate VFD control file for the given spindle
    M98 P{var.modelFile} S{iterations} C{var.spindleChannel} A{var.spindleAddr}

    ; Check for unexpected spindle instability
    ; This happens when:
    ; 1. The spindle was stable (from last iteration)
    ; 2. The spindle is now unstable
    ; 3. No command change was issued
    ; 4. There's a job running

    var vfdRunning    = { global.arborVFDStatus[iterations] != null ? global.arborVFDStatus[iterations][0] : false }
    var errorDetected = { global.arborState[iterations][4] }
    var wasStable     = { global.arborState[iterations][2] }
    var isStable      = { global.arborVFDStatus[iterations] != null ? global.arborVFDStatus[iterations][4] : false }
    var commandChange = { global.arborState[iterations][1] }
    var jobRunning    = { job.file.fileName != null && !(state.status == "resuming" || state.status == "pausing" || state.status == "paused") }

    ; Enhanced error handling with communication resilience
    if { var.errorDetected }
        ; Get communication health metrics
        var consecFailures = { global.arborCommHealth[iterations][0] }
        var isHighRisk = { var.vfdRunning && spindles[iterations].current > 100 }
        
        ; Determine response based on failure severity and risk level
        if { var.consecFailures >= global.arborMaxConsecFailures && var.isHighRisk }
            ; High risk scenario - persistent communication loss with spindle running
            echo { "ArborCtl: CRITICAL - Communication lost with spindle " ^ iterations }
            echo { "ArborCtl: Initiating controlled stop for safety" }
            M5 P{iterations}
            
            if { var.jobRunning }
                echo { "ArborCtl: Pausing job" }
                M25
                M291 R"ArborCtl Communication Error" P{"Spindle " ^ iterations ^ " communication lost. Check RS485 connection and cable routing."} S2
        elif { var.consecFailures >= global.arborMaxConsecFailures * 2 }
            ; Extended communication loss even at low risk - stop anyway
            echo { "ArborCtl: Extended communication loss on spindle " ^ iterations ^ " - stopping" }
            M5 P{iterations}
            if { var.jobRunning }
                M25
        elif { var.consecFailures > 0 }
            ; Warning level - operating on cached data
            echo { "ArborCtl: Spindle " ^ iterations ^ " operating on cached data (" ^ var.consecFailures ^ " consecutive failures)" }
            echo { "ArborCtl: Check RS485 cable routing, shielding, and termination if this persists" }
    elif { var.wasStable && !var.isStable && !var.commandChange }
        ; Check for unexpected instability (but only if no communication errors)
        echo { "ArborCtl: Spindle " ^ iterations ^ " instability detected" }
        ; Note: With retry logic, transient read failures are now handled gracefully
        ; Only genuine instability should trigger this path

    ; Get spindle load if available
    var spindleLoad = { global.arborVFDPower[iterations] != null ? global.arborVFDPower[iterations][1] : 0 }

    ; If spindle is running and stable, check for load
    ; If load is higher than global.arborMaxLoad, reduce the speed factor
    if { var.vfdRunning && var.isStable && var.spindleLoad > global.arborMaxLoad }
        var speedFactor = { move.speedFactor * 0.95 }
        echo { "ArborCtl: Spindle load is " ^ var.spindleLoad ^ "% - reducing feed to " ^ var.speedFactor * 100 ^ "% to counteract" }
        M220 S{var.speedFactor}