@echo off
REM COP6539 Project 2 -- gossip / push-sum simulator.
REM
REM   run 1000 full gossip
REM   run 1000 imp2D push-sum
REM   run 1000 line gossip death=0.1
REM
REM Note: -pa "." and not -pa "%~dp0". %~dp0 ends in a backslash, and a
REM backslash immediately before a closing quote escapes that quote on
REM Windows, silently corrupting every argument that follows.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erl -noshell -pa "." -run project2 main %* -s init stop
