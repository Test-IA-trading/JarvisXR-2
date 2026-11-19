@echo off
setlocal
pushd "%~dp0" || exit /b 1
set "JARVIS_ROOT=%CD%"
set "OLLAMA_HOST=http://127.0.0.1:11434"
set "PATH=%LOCALAPPDATA%\Programs\Ollama;%LOCALAPPDATA%\Microsoft\WinGet\Links;%USERPROFILE%\.local\bin;%USERPROFILE%\.claude\local;%PATH%"
where.exe ollama.exe >nul 2>nul || goto :missing
where.exe claude >nul 2>nul || goto :missing
set "JARVIS_HAS_MODEL="
for /f "tokens=1" %%M in ('ollama.exe list') do if /i "%%M"=="qwen3:8b" set "JARVIS_HAS_MODEL=1"
if not defined JARVIS_HAS_MODEL (
  echo Ouvre Ollama et verifie que qwen3:8b figure dans ollama list.
  goto :failed
)
if /i "%~1"=="coder" goto :code
if /i "%~1"=="leger" goto :light
if /i "%~1"=="reprendre" goto :resume
if not "%~1"=="" (
  echo Utilisation : Agent-Jarvis.cmd [reprendre, coder ou leger]. Sans argument : essai manuel.
  goto :failed
)

set "JARVIS_TRIAL=%USERPROFILE%\JarvisAI-Test\Essai-%RANDOM%-%RANDOM%-%RANDOM%"
if exist "%JARVIS_TRIAL%" goto :failed
mkdir "%JARVIS_TRIAL%" || goto :failed
pushd "%JARVIS_TRIAL%" || goto :failed
>entree.txt echo JARVIS-%RANDOM%-%RANDOM%-%RANDOM%-%RANDOM%
if not exist entree.txt goto :trialfailed
echo Essai dans "%CD%".
echo Autorise l'ecriture une fois lorsque Claude la propose. A la fin, tape /exit pour verifier le fichier.
ollama.exe launch claude --model qwen3:8b -- --permission-mode default --settings "%JARVIS_ROOT%\dev\claude\essai.json" --strict-mcp-config --tools "Read,Write" -- "Utilise Read pour lire le fichier %CD%\entree.txt. Utilise ensuite Write pour creer %CD%\sortie.txt avec la meme ligne. Apres la demande d'autorisation, termine sans autre action."
if errorlevel 1 goto :trialfailed
if not exist sortie.txt goto :trialfailed
powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; $a=@(Get-Content -LiteralPath 'entree.txt'); $b=@(Get-Content -LiteralPath 'sortie.txt'); if ($a.Count -ne 1 -or $b.Count -ne 1 -or $a[0] -cne $b[0]) {exit 1}"
if errorlevel 1 goto :trialfailed
echo FICHIER VERIFIE. La ligne relue dans sortie.txt correspond a entree.txt.
ollama.exe ps
popd
popd
pause
exit /b 0

:trialfailed
echo ESSAI INCOMPLET. Verifie la demande Write et les fichiers dans "%CD%".
popd
goto :failed

:code
ollama.exe launch claude --model qwen3:8b -- --permission-mode default
goto :finish

:resume
ollama.exe launch claude --model qwen3:8b -- --permission-mode default -- "Reprends JarvisXR. A partir de la fiche AGENTS.md, indique la priorite, le dernier resultat verifie et la prochaine action possible sur cette machine."
goto :finish

:light
ollama.exe launch claude --model qwen3:8b -- --permission-mode default --tools "Read,Glob,Grep,Edit,Write,Bash"
:finish
if errorlevel 1 goto :failed
popd
exit /b 0

:missing
echo Verifie que Claude Code et Ollama, deja installes, sont accessibles depuis Windows.
:failed
popd
pause
exit /b 1
