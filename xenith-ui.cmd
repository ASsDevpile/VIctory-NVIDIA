@echo off
rem The graphical XENITH VI launcher, this fork's copy: Windows PowerShell
rem with WPF, nothing to install. The command-line one stays xenith.cmd;
rem both share xenith.ini.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0xenith-ui.ps1"
