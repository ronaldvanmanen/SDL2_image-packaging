<#
  .SYNOPSIS
  Builds Windows native NuGet package for SDL2_image.

  .DESCRIPTION
  Builds Windows native NuGet package for SDL2_image.

  .PARAMETER runtime
  The runtime identifier to use for the native package (e.g. x64, x86).

  .INPUTS
  None.

  .OUTPUTS
  None.

  .EXAMPLE
  PS> .\build-sdl2_image -architecture x64

  .EXAMPLE
  PS> .\build-sdl2_image -architecture x86
#>

[CmdletBinding(PositionalBinding=$false)]
Param(
  [Parameter(Mandatory)][ValidateSet("x64", "x86")][string] $architecture = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function New-Directory([string[]] $Path) {
  if (!(Test-Path -Path $Path)) {
    New-Item -Path $Path -Force -ItemType "Directory" | Out-Null
  }
}

function Copy-File([string[]] $Path, [string] $Destination, [switch] $Force, [switch] $Recurse) {
  if (!(Test-Path -Path $Destination)) {
    New-Item -Path $Destination -Force:$Force -ItemType "Directory" | Out-Null
  }
  Copy-Item -Path $Path -Destination $Destination -Force:$Force -Recurse:$Recurse
}

try {
  $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

  $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."

  $SourceRoot = Join-Path -Path $RepoRoot -ChildPath "sources"

  $ArtifactsRoot = Join-Path -Path $RepoRoot -ChildPath "artifacts"
  New-Directory -Path $ArtifactsRoot

  $BuildRoot = Join-Path -Path $ArtifactsRoot -ChildPath "build"
  New-Directory -Path $BuildRoot

  $InstallRoot = Join-Path -Path $ArtifactsRoot -ChildPath "install"
  New-Directory -Path $InstallRoot

  $PackageRoot = Join-Path $ArtifactsRoot -ChildPath "pkg"
  New-Directory -Path $PackageRoot

  $Runtime = "win-$architecture"

  $DotNetInstallScriptUri = "https://dot.net/v1/dotnet-install.ps1"
  Write-Host "${ScriptName}: Downloading dotnet-install.ps1 script from $DotNetInstallScriptUri..." -ForegroundColor Yellow
  $DotNetInstallScript = Join-Path -Path $ArtifactsRoot -ChildPath "dotnet-install.ps1"
  Invoke-WebRequest -Uri $DotNetInstallScriptUri -OutFile $DotNetInstallScript -UseBasicParsing

  Write-Host "${ScriptName}: Installing dotnet 6.0..." -ForegroundColor Yellow
  $DotNetInstallDirectory = Join-Path -Path $ArtifactsRoot -ChildPath "dotnet"
  New-Directory -Path $DotNetInstallDirectory

  $env:DOTNET_CLI_TELEMETRY_OPTOUT = 1
  $env:DOTNET_MULTILEVEL_LOOKUP = 0
  $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 1

  # & $DotNetInstallScript -Channel 6.0 -Version latest -InstallDir $DotNetInstallDirectory

  $env:PATH="$DotNetInstallDirectory;$env:PATH"

  Write-Host "${ScriptName}: Restoring dotnet tools..." -ForegroundColor Yellow
  & dotnet tool restore
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed restore dotnet tools."
  }

  $SDL2PackageSource = "https://pkgs.dev.azure.com/ronaldvanmanen/SDL2Sharp/_packaging/SDL2Sharp/nuget/v3/index.json"
  
  if ($null -ne $env:NUGET_AUTH_TOKEN) {
    Write-Host "${ScriptName}: Settings API key for package source $SDL2PackageSource..." -ForegroundColor Yellow
    & nuget setapikey $env:NUGET_AUTH_TOKEN -Source $SDL2PackageSource
    if ($LastExitCode -ne 0) {
      throw "${ScriptName}: Failed to set API key for package source $SDL2PackageSource."
    }
  }

  $SDL2PackageName = "SDL2.devel.$Runtime"

  Write-Host "${ScriptName}: Installing SDL2 development package in $InstallRoot..." -ForegroundColor Yellow
  & nuget install "$SDL2PackageName" -DirectDownload -ExcludeVersion -NoCache -OutputDirectory $InstallRoot -PreRelease -Source $SDL2PackageSource
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to install SDL2 development package $InstallRoot."
  }

  $env:SDL2_DIR = Join-Path -Path $InstallRoot -ChildPath "$SDL2PackageName"

  Write-Host "${ScriptName}: Calculating SDL2_image package version..." -ForegroundColor Yellow
  $PackageVersion = dotnet gitversion /showvariable NuGetVersion /output json
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed calculate SDL2_image package version."
  }
  
  $SourceDir = Join-Path -Path $SourceRoot -ChildPath "SDL_image"
  $BuildDir = Join-Path -Path $BuildRoot -ChildPath "SDL2_image" -AdditionalChildPath "$Runtime"
  $InstallDir = Join-Path -Path $InstallRoot -ChildPath "SDL2_image" -AdditionalChildPath "$Runtime"
  $PlatformFlags = ""

  switch ($architecture) {
    "x64" { $PlatformFlags = "-A x64" }
    "x86" { $PlatformFlags = "-A Win32" }
  }

  Write-Host "${ScriptName}: Generating build system for SDL2_image in $BuildDir..." -ForegroundColor Yellow
  & cmake -S $SourceDir -B $BuildDir `
      -DCMAKE_INSTALL_LIBDIR="lib/$architecture" `
      -DCMAKE_INSTALL_BINDIR="lib/$architecture" `
      -DCMAKE_INSTALL_INCLUDEDIR="include" `
      -DBUILD_SHARED_LIBS=ON `
      -DCMAKE_BUILD_TYPE=Release `
      -DSDL2IMAGE_SAMPLES=ON `
      -DSDL2IMAGE_TESTS_INSTALL=ON `
      -DSDL2IMAGE_JXL=ON `
      -DSDL2IMAGE_TIF=ON `
      -DSDL2IMAGE_WEBP=ON `
      -DSDL2IMAGE_VENDORED=ON `
      $PlatformFlags
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to generate build system in $BuildDir."
  }

  Write-Host "${ScriptName}: Building SDL2_image in $BuildDir..." -ForegroundColor Yellow
  & cmake --build $BuildDir --config Release
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2_image in $BuildDir."
  }

  Write-Host "${ScriptName}: Installing SDL2_image in $InstallDir..." -ForegroundColor Yellow
  & cmake --install $BuildDir --prefix $InstallDir
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to install SDL2_image in $InstallDir."
  }

  $RuntimePackageName="SDL2_image.runtime.$Runtime"
  $RuntimePackageBuildDir = Join-Path -Path $PackageRoot -ChildPath $RuntimePackageName
  $DevelPackageName="SDL2_image.devel.$Runtime"
  $DevelPackageBuildDir = Join-Path -Path $PackageRoot -ChildPath $DevelPackageName

  Write-Host "${ScriptName}: Producing SDL2_image runtime package folder structure in $RuntimePackageBuildDir..." -ForegroundColor Yellow
  Copy-File -Path "$RepoRoot\packages\$RuntimePackageName\*" -Destination $RuntimePackageBuildDir -Force -Recurse
  Copy-File -Path "$SourceDir\LICENSE.txt" $RuntimePackageBuildDir
  Copy-File -Path "$SourceDir\README.txt" $RuntimePackageBuildDir
  Copy-File -Path "$InstallDir\lib\$architecture\*.dll" "$RuntimePackageBuildDir\runtimes\$Runtime\native" -Force

  Write-Host "${ScriptName}: Building SDL2_image runtime package..." -ForegroundColor Yellow
  & nuget pack $RuntimePackageBuildDir\$RuntimePackageName.nuspec -Properties version=$PackageVersion -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2_image runtime package."
  }

  Write-Host "${ScriptName}: Producing SDL2_image development package folder structure in $DevelPackageBuildDir..." -ForegroundColor Yellow
  Copy-File -Path "$RepoRoot\packages\$DevelPackageName\*" -Destination $DevelPackageBuildDir -Force -Recurse
  Copy-File -Path "$SourceDir\CHANGES.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\LICENSE.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\README.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$InstallDir\cmake\*" "$DevelPackageBuildDir\cmake" -Force
  Copy-File -Path "$InstallDir\include\SDL2\*" "$DevelPackageBuildDir\include\SDL2" -Force
  Copy-File -Path "$InstallDir\lib\$architecture\*.lib" "$DevelPackageBuildDir\lib\$architecture" -Force
  Copy-File -Path "$InstallDir\lib\$architecture\*.dll" "$DevelPackageBuildDir\lib\$architecture" -Force

  Write-Host "${ScriptName}: Building SDL2_image development package..." -ForegroundColor Yellow
  & nuget pack $DevelPackageBuildDir\$DevelPackageName.nuspec -Properties version=$PackageVersion -Properties NoWarn="NU5103;NU5128" -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2_image development package."
  }
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
