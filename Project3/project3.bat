@echo off
REM Run Project 3, for example:  project3 1000 10
REM Uses -pa "." because %~dp0 ends in a backslash, which escapes the quote.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erl -noshell -pa "." -run project3 main %* -s init stop
