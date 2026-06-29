param([int]$Target = 1)

$dir = Split-Path $MyInvocation.MyCommand.Definition -Parent

# IPC: switch keyboard (runs in background while HID++ runs)
$kbJob = Start-Process powershell -ArgumentList "-ExecutionPolicy","Bypass","-File",
    "$env:LOCALAPPDATA\InputSwitcher\switch_kb.ps1","-TargetHost",$Target -PassThru -NoNewWindow

# HID++: switch mouse — all slots in parallel
$lastByte = "0x{0:X2}" -f $Target
$procs = foreach ($slot in 0x02,0x03,0x04,0x05,0x06,0x07,0x08) {
    $hex = "0x{0:X2}" -f $slot
    Start-Process "$dir\hidapitester.exe" -ArgumentList (
        "--vidpid","046D:C548","--usagePage","0xFF00","--usage","0x0001",
        "--open","--length","7","--send-output","0x10,$hex,0x0A,0x1E,$lastByte"
    ) -PassThru -NoNewWindow
}

$procs | ForEach-Object { $_.WaitForExit(3000) } | Out-Null
$kbJob.WaitForExit(5000) | Out-Null
