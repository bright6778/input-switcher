@echo off
cd /d "%~dp0"

.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x01,0x0A,0x1E,0x00
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x02,0x0A,0x1E,0x00
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x03,0x0A,0x1E,0x00
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x06,0x0A,0x1E,0x00
timeout /t 1 /nobreak > nul
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x01,0x0A,0x1E,0x00
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x02,0x0A,0x1E,0x00
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x03,0x0A,0x1E,0x00
.\hidapitester.exe --vidpid 046D:C548 --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x06,0x0A,0x1E,0x00

REM Switch K855 to PC1 (host 0) via Logi Options+ IPC
powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\InputSwitcher\switch_kb.ps1" -TargetHost 0
