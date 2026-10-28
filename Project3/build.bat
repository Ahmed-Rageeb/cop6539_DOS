@echo off
REM Compile Project 3. Run once before project3.bat.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erlc.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erlc project3.erl main.erl pastry_init.erl pastry_node.erl route.erl deliver.erl forward.erl new_leafs.erl node_state.erl rtable.erl pastry_util.erl failure.erl experiments.erl report.erl
if errorlevel 1 (
  echo.
  echo BUILD FAILED
  exit /b 1
)
echo Build OK.
