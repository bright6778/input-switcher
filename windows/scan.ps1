$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=== Bolt Receiver (046D:C548) - Scanning device slots ===" -ForegroundColor Cyan
Write-Host "Sends a host-query to each slot; RESPONDED = a device is paired there." -ForegroundColor Gray
Write-Host ""

foreach ($di in 1..8) {
    $hex = "0x{0:X2}" -f $di
    $result = & ".\hidapitester.exe" --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output "0x10,$hex,0x0A,0x1E,0x01,0x00,0x00" --read-input 500 2>&1
    $responded = ($result | Select-String "read [1-9]").Count -gt 0
    $raw = ($result | Where-Object { $_ -match "^read" }) -join " "
    Write-Host "  slot $hex : $(if ($responded) { "RESPONDED  $raw" } else { '---' })"
}

Write-Host ""
Write-Host "Slots that RESPONDED have a device paired. Compare with switch_to_2.bat" -ForegroundColor Yellow
Write-Host "to confirm all needed slots are covered." -ForegroundColor Yellow
