@echo off
REM Build results\Report.html from the CSVs, then print it to Report.pdf
REM using headless Edge. No Python, LaTeX or charting tool required.
setlocal
set "ERLBIN=C:\Program Files\Erlang OTP\bin"
if exist "%ERLBIN%\erl.exe" set "PATH=%PATH%;%ERLBIN%"
cd /d "%~dp0"
erl -noshell -pa "." -run report main -s init stop
if errorlevel 1 exit /b 1

set "EDGE=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=C:\Program Files\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" (
  echo Edge not found. Open results\Report.html in a browser and use Ctrl+P - Save as PDF.
  exit /b 1
)
"%EDGE%" --headless --disable-gpu --no-pdf-header-footer ^
  --print-to-pdf="%~dp0..\results\Report.pdf" "%~dp0..\results\Report.html"
echo Wrote results\Report.pdf
