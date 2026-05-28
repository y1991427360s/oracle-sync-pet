Set fso = CreateObject("Scripting.FileSystemObject")
Set s = CreateObject("WScript.Shell")
ps = """" & fso.GetParentFolderName(WScript.ScriptFullName) & "\pet.ps1"""
s.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & ps, 0, False
