# Persistent background service for K855 keyboard switching.
#
# Problem this solves: every hotkey press used to launch a brand new
# `powershell.exe -File switch_kb.ps1`. On a machine where an EDR agent
# (e.g. SentinelOne) deep-scans every new PowerShell process, that launch
# cost (often ~1s) is paid on *every single switch*.
#
# This script is started once (e.g. at logon, via Scheduled Task) and stays
# resident. It listens on a named pipe; each incoming request runs
# switch_kb.ps1 inside a fresh, throwaway Runspace *within this same
# process* (no new powershell.exe is spawned), so the EDR-scan cost is only
# paid once per logon instead of once per switch.
#
# switch_kb.ps1 itself is untouched — it is invoked exactly as it would be
# from the command line, including its own `exit $exitCode`. Running it in
# a separate Runspace (rather than dot-sourcing/`&` in this script's own
# scope) means that `exit` only tears down that inner Runspace, not this
# service process.

param(
    [string]$PipeName = "InputSwitcherService"
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "InputSwitcher"
$scriptPath = Join-Path $stateDir "switch_kb.ps1"
$serviceLog = Join-Path $stateDir "switch_service.log"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

function Log($msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    "$ts $msg" | Out-File -Append -FilePath $serviceLog -Encoding utf8
}

function Invoke-SwitchInIsolatedRunspace([int]$TargetHost) {
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $ps = $null
    try {
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddCommand($scriptPath).AddParameter("TargetHost", $TargetHost)
        [void]$ps.Invoke()
        if ($ps.HadErrors) {
            $errText = ($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "; "
            return "FAIL: $errText"
        }
        return "OK"
    }
    catch {
        return "FAIL: $($_.Exception.Message)"
    }
    finally {
        if ($ps) { $ps.Dispose() }
        $rs.Close()
        $rs.Dispose()
    }
}

Log "--- switch_kb_service starting (pipe=$PipeName, script=$scriptPath) ---"

while ($true) {
    $pipeServer = [System.IO.Pipes.NamedPipeServerStream]::new(
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous
    )
    try {
        $pipeServer.WaitForConnection()
        $reader = [System.IO.StreamReader]::new($pipeServer)
        $writer = [System.IO.StreamWriter]::new($pipeServer)
        $writer.AutoFlush = $true

        $line = $reader.ReadLine()
        if ($null -eq $line) {
            continue
        }
        Log "request: $line"

        if ($line -match '^[0-2]$') {
            $result = Invoke-SwitchInIsolatedRunspace -TargetHost ([int]$line)
            Log "result: $result"
            $writer.WriteLine($result)
        }
        else {
            $writer.WriteLine("BAD_REQUEST")
        }
    }
    catch {
        Log "pipe error: $($_.Exception.Message)"
    }
    finally {
        $pipeServer.Dispose()
    }
}
