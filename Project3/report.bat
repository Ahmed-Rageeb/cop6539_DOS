@echo off
REM Build results\Report.html and Report-bonus.html from the CSVs, then
REM print both to PDF with headless Edge. No Python, LaTeX or charting tool.
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
REM One at a time: two headless Edge instances started together can race,
REM and one of the PDFs silently fails to appear.
"%EDGE%" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="%~dp0results\Report.pdf" "%~dp0results\Report.html"
REM ping rather than timeout: timeout refuses to run when stdin is not a
REM console (e.g. when launched from a script), so the pause silently vanishes.
ping -n 4 127.0.0.1 >nul
"%EDGE%" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="%~dp0results\Report-bonus.pdf" "%~dp0results\Report-bonus.html"
echo Wrote results\Report.pdf and results\Report-bonus.pdf
