@echo off
rem qc.cmd — 双击或在任意 shell 里跑同一套门禁（不依赖 AI）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0qc.ps1" %*
exit /b %ERRORLEVEL%
