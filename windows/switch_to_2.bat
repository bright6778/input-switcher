@echo off

rem Device 1: e.g. MX Keys S connected to Unifying receiver
rem Refer to the README.md for details on how to find the correct 
rem values for your setup
set KEYS_PID=C52B
set KEYS_USAGE_PAGE=0xFF00
set KEYS_USAGE=0x0001
set KEYS_INDEX=0x01
set KEYS_COMMAND1=0x0A
set KEYS_COMMAND2=0x10
set KEYS_CHANNEL=0x01

rem Switch Device 1 to channel 2
.\hidapitester.exe --vidpid 046D:%KEYS_PID% --usagePage %KEYS_USAGE_PAGE% --usage %KEYS_USAGE% --open --length 20 --send-output 0x11,%KEYS_INDEX%,%KEYS_COMMAND1%,%KEYS_COMMAND2%,%KEYS_CHANNEL%

rem Device 2: e.g. MX Anywhere 3 connected to Unifying receiver
rem Refer to the README.md for details on how to find the correct 
rem values for your setup
set MOUSE_PID=C52B
set MOUSE_USAGE_PAGE=0xFF00
set MOUSE_USAGE=0x0001
set MOUSE_INDEX=0x01
set MOUSE_COMMAND1=0x0A
set MOUSE_COMMAND2=0x10
set MOUSE_CHANNEL=0x01

rem Switch Device 1 to channel 2
.\hidapitester.exe --vidpid 046D:%MOUSE_PID% --usagePage %MOUSE_USAGE_PAGE% --usage %MOUSE_USAGE% --open --length 20 --send-output 0x11,%MOUSE_INDEX%,%MOUSE_COMMAND1%,%MOUSE_COMMAND2%,%MOUSE_CHANNEL%
