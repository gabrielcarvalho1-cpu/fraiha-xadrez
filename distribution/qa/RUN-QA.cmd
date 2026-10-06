@echo off
title FRAIHA Distribution QA
rem fail-closed (auditoria R46): devolve o codigo do PowerShell depois do pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN-QA.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo QA FALHOU (codigo %RC%)
if not defined FRAIHA_NO_PAUSE pause
exit /b %RC%
