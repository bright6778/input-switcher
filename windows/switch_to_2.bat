@echo off
cd /d "%~dp0"

REM K855 + any IPC-switchable device → PC2 (must run before HID commands)
powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\InputSwitcher\switch_kb.ps1" -TargetHost 1

REM M750 mouse via HID++ (Bolt receiver slot broadcast)
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x02,0x0A,0x1E,0x01
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x03,0x0A,0x1E,0x01
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x04,0x0A,0x1E,0x01
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x05,0x0A,0x1E,0x01
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x06,0x0A,0x1E,0x01
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x07,0x0A,0x1E,0x01
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x08,0x0A,0x1E,0x01
