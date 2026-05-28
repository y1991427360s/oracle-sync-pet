Set s = CreateObject("WScript.Shell")
ps = """" & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\open-sync-folder.ps1"""
s.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & ps, 0, False
