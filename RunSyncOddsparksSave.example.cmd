@echo off
setlocal

set WORLD=
set PLAYER=
set FOLDER_URL=
set CLIENT_JSON=%~dp0client_secret.json

powershell.exe ^
  -NoProfile ^
  -ExecutionPolicy Bypass ^
  -File "%~dp0SyncOddsparksSave.ps1" ^
  -World "%WORLD%" ^
  -Player "%PLAYER%" ^
  -FolderUrl "%FOLDER_URL%" ^
  -ClientJson "%CLIENT_JSON%" ^
  %*

pause
