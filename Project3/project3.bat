@echo off
REM COP6539 Project 3 -- Pastry.
REM
REM   project3 1000 10
REM   project3 1000 3 kill=0.2 resilient
REM
REM -pa "." rather than -pa "%~dp0": %~dp0 ends in a backslash, and a
REM backslash right before a closing quote escapes it on Windows, silently
REM corrupting every argument that follows.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erl -noshell -pa "." -run project3 main %* -s init stop
