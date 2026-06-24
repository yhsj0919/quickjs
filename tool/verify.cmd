@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" %*
