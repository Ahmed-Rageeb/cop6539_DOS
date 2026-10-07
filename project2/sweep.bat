@echo off
REM Run the experiments and write results\project2.csv.
REM   sweep core    size sweep across all topologies and both algorithms
REM   sweep bonus   failure-model sweep
REM   sweep all     both
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
if "%1"=="" (erl -noshell -pa "." -run experiments main core -s init stop) else (erl -noshell -pa "." -run experiments main %* -s init stop)
