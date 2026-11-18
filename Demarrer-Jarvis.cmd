@echo off
setlocal
set "JARVIS_COMPILER=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%JARVIS_COMPILER%" set "JARVIS_COMPILER=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%JARVIS_COMPILER%" (
  echo Le compilateur .NET Framework de Windows est introuvable.
  goto :failed
)
set "JARVIS_BIN=%LOCALAPPDATA%\JarvisXR\Companion"
if not exist "%JARVIS_BIN%\" mkdir "%JARVIS_BIN%"
if not exist "%JARVIS_BIN%\" goto :failed
pushd "%~dp0companion\windows" || goto :failed
"%JARVIS_COMPILER%" /nologo /codepage:65001 /optimize+ /target:exe /out:"%JARVIS_BIN%\JarvisXR-Chat.exe" /reference:System.Net.Http.dll /reference:System.Web.Extensions.dll /reference:System.Management.dll /resource:web\index.html,Jarvis.index.html /resource:web\app.css,Jarvis.app.css /resource:web\chat.js,Jarvis.chat.js Program.cs LocalHttp.cs OllamaChat.cs
if errorlevel 1 (
  popd
  echo Ferme toute fenetre Jarvis deja ouverte avant de relancer.
  goto :failed
)
popd
if /i "%~1"=="--build-only" exit /b 0
"%JARVIS_BIN%\JarvisXR-Chat.exe" %*
if errorlevel 1 goto :failed
exit /b 0

:failed
if not defined CI pause
exit /b 1
