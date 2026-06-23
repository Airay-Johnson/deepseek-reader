Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ""D:\JetBrains\IntelliJ IDEA 2025.1.3\project\QDBMS\mcp-server\agent.ps1""", 0, False
