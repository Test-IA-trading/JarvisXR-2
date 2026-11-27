@echo off
rem Jarvis PC : double-cliquez pour lancer Jarvis sur ce PC.
rem La premiere fois, il prepare son propre environnement Python (pc\.venv) et ses modeles.
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Preparation de Jarvis PC, une seule fois...
    py -3.12 -m venv .venv 2>nul || python -m venv .venv
    if not exist ".venv\Scripts\python.exe" (
        echo Python 3.12 est introuvable : installez-le depuis python.org puis relancez Jarvis.bat.
        pause
        exit /b 1
    )
    ".venv\Scripts\python.exe" -m pip install --upgrade pip --quiet
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt --quiet
)
".venv\Scripts\python.exe" -m jarvis_pc %*
pause
