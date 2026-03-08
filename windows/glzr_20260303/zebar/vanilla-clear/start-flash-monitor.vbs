Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & CreateObject("WScript.Shell").ExpandEnvironmentStrings("%USERPROFILE%") & "\.glzr\zebar\vanilla-clear\flash-monitor.ps1""", 0, False
