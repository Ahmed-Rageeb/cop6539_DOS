@echo off
REM Make the reports from the CSVs and print them to PDF with Edge.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erl -noshell -pa "." -run report main -s init stop
if errorlevel 1 exit /b 1

set "EDGE=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=C:\Program Files\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" (
  echo Edge not found. Open the HTML files in a browser and use Ctrl+P - Save as PDF.
  exit /b 1
)
REM print one at a time, two Edge instances at once can lose a PDF
"%EDGE%" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="%~dp0results\Report.pdf" "%~dp0results\Report.html"
REM short pause (timeout does not work when run from a script)
ping -n 4 127.0.0.1 >nul
"%EDGE%" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="%~dp0results\Report-bonus.pdf" "%~dp0results\Report-bonus.html"
echo Wrote results\Report.pdf and results\Report-bonus.pdf
