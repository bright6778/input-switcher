Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & chr(34) & WshShell.CurrentDirectory & "\switch_to_2.ps1" & chr(34), 0
Set WshShell = Nothing
