@echo off
REM Compile the project. Run this once before mine.bat.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erlc.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erlc project1.erl actors.erl app.erl
if errorlevel 1 (
  echo.
  echo BUILD FAILED
  exit /b 1
)
echo Build OK.
