@echo off
cd /d "%~dp0"

rem Pop Icon Key via Bolt Receiver (C548)
rem CHANNEL: 0x00=ch1, 0x01=ch2, 0x02=ch3
set KB_PID=C548
set KB_USAGE_PAGE=0xFF00
set KB_USAGE=0x0001
set KB_INDEX=0x01
set KB_COMMAND1=0x0A
set KB_COMMAND2=0x1E
set KB_CHANNEL=0x01

.\hidapitester.exe --vidpid 046D:%KB_PID% --usagePage %KB_USAGE_PAGE% --usage %KB_USAGE% --open --length 7 --send-output 0x10,%KB_INDEX%,%KB_COMMAND1%,%KB_COMMAND2%,%KB_CHANNEL%
timeout /t 1 /nobreak > nul

rem M750L via Bolt Receiver (C548)
set MS_PID=C548
set MS_USAGE_PAGE=0xFF00
set MS_USAGE=0x0001
set MS_INDEX=0x03
set MS_COMMAND1=0x0A
set MS_COMMAND2=0x1E
set MS_CHANNEL=0x01

.\hidapitester.exe --vidpid 046D:%MS_PID% --usagePage %MS_USAGE_PAGE% --usage %MS_USAGE% --open --length 7 --send-output 0x10,%MS_INDEX%,%MS_COMMAND1%,%MS_COMMAND2%,%MS_CHANNEL%
timeout /t 1 /nobreak > nul

rem M750 via Bolt Receiver (C548)
set M2_PID=C548
set M2_USAGE_PAGE=0xFF00
set M2_USAGE=0x0001
set M2_INDEX=0x05
set M2_COMMAND1=0x0A
set M2_COMMAND2=0x1E
set M2_CHANNEL=0x01

.\hidapitester.exe --vidpid 046D:%M2_PID% --usagePage %M2_USAGE_PAGE% --usage %M2_USAGE% --open --length 7 --send-output 0x10,%M2_INDEX%,%M2_COMMAND1%,%M2_COMMAND2%,%M2_CHANNEL%
