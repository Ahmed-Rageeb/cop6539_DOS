@echo off
REM COP6539 Project 1 -- distributed bitcoin miner.
REM
REM   mine 4                  server, mining coins with 4 leading zeros
REM   mine 4 30               server, stopping after 30 seconds with a summary
REM   mine 4 30 192.168.1.7   server, advertising that exact IP to workers
REM   mine 10.22.13.155       worker, joining the server at that address
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
REM Note: -pa "." and not -pa "%~dp0". %~dp0 ends in a backslash, and a
REM backslash immediately before a closing quote escapes that quote on
REM Windows, which silently corrupts every argument that follows.
erl -noshell -pa "." -run app main %* -s init stop
