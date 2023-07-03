@ECHO OFF
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0build-multiplatform.ps1""" %*"
EXIT /B %ERRORLEVEL%
