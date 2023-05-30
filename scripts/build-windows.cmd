@ECHO OFF

IF "%1"=="-architecture" (
    SET architecture=%2
) ELSE (
    ECHO.
    ECHO NAME
    ECHO     %~dpnx0
    ECHO.
    ECHO SYNOPSIS
    ECHO     Builds Windows native NuGet package for SDL2_image.
    ECHO.
    ECHO.
    ECHO SYNTAX
    ECHO     %~dpnx0 -architecture ^<String^>
    ECHO.
    ECHO.
    ECHO DESCRIPTION
    ECHO     Builds Windows native NuGet package for SDL2_image.
    ECHO.
    ECHO.
    ECHO PARAMETERS
    ECHO     -architecture ^<String^>
    ECHO.
    EXIT /B -1
)

call "%~dp0vcvarsall.cmd" %architecture%
call pwsh.exe -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0build-windows.ps1""" %*"
EXIT /B %ERRORLEVEL%
