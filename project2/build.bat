@echo off
REM Compile Project 2. Run this once before run.bat.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erlc.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erlc topology.erl gossip.erl push_sum.erl project2.erl experiments.erl report.erl
if errorlevel 1 (
  echo.
  echo BUILD FAILED
  exit /b 1
)
echo Build OK.
