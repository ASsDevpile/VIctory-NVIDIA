@echo off
rem The graphical XENITH VI launcher, this fork's copy: Windows PowerShell
rem with WPF, nothing to install. The window's layout is scripts\xenith.xaml
rem and its behavior is scripts\xenith-ui.ps1, both on top of the launcher's
rem back end, scripts\xenith-core.ps1. The command-line one stays xenith.cmd;
rem they share xenith.ini.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0scripts\xenith-ui.ps1"
