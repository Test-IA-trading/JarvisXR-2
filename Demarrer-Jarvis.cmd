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
call :frameworkRef System.Net.Http JARVIS_HTTP
call :frameworkRef System.Web.Extensions JARVIS_JSON
call :frameworkRef System.Management JARVIS_WMI
pushd "%~dp0companion\windows" || goto :failed
"%JARVIS_COMPILER%" /nologo /codepage:65001 /optimize+ /target:exe /out:"%JARVIS_BIN%\JarvisXR-Chat.exe" /reference:"%JARVIS_HTTP%" /reference:"%JARVIS_JSON%" /reference:"%JARVIS_WMI%" /resource:web\index.html,Jarvis.index.html /resource:web\app.css,Jarvis.app.css /resource:web\chat.js,Jarvis.chat.js Program.cs LocalHttp.cs OllamaChat.cs
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

:frameworkRef
set "%~2=%~1.dll"
for /d %%G in ("%SystemRoot%\Microsoft.NET\assembly\GAC_MSIL\%~1\v4.0_*") do if exist "%%~fG\%~1.dll" set "%~2=%%~fG\%~1.dll"
exit /b 0

:failed
if not defined CI pause
exit /b 1
