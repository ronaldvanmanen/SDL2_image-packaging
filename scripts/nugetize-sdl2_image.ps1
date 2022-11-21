function New-Directory([string[]] $Path) {
  if (!(Test-Path -Path $Path)) {
    New-Item -Path $Path -Force -ItemType "Directory" | Out-Null
  }
}

function Copy-File([string[]] $Path, [string] $Destination, [switch] $Force) {
  if (!(Test-Path -Path $Destination)) {
    New-Item -Path $Destination -Force:$Force -ItemType "Directory" | Out-Null
  }
  Copy-Item -Path $Path -Destination $Destination -Force:$Force
}

try {
  $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."

  $PackagesDir = Join-Path -Path $RepoRoot -ChildPath "packages"

  $ArtifactsDir = Join-Path -Path $RepoRoot -ChildPath "artifacts"
  New-Directory -Path $ArtifactsDir

  $ArtifactsPkgDir = Join-Path $ArtifactsDir -ChildPath "pkg"
  New-Directory -Path $ArtifactsPkgDir

  $StagingDir = Join-Path -Path $RepoRoot -ChildPath "staging"
  New-Directory -Path $StagingDir

  $DownloadsDir = Join-Path -Path $RepoRoot -ChildPath "downloads"
  New-Directory -Path $DownloadsDir

  & dotnet tool restore

  $GitVersion = dotnet gitversion /output json | ConvertFrom-Json
  $MajorMinorPatch = $GitVersion.MajorMinorPatch
  $PackageVersion = $GitVersion.NuGetVersion

  Write-Host "Get SDL2_image release for version $MajorMinorPatch..." -ForegroundColor Yellow
  $LatestRelease = Invoke-RestMethod -Headers @{ 'Accept'='application/vnd.github+json'} -Uri "https://api.github.com/repos/libsdl-org/SDL_image/releases/tags/release-$MajorMinorPatch"
  $LatestVersion = $LatestRelease.name
  $LatestAsset = $LatestRelease.assets | Where-Object { $_.name -Like "SDL2_image-devel-*-VC.zip" }
  $LatestAssetName = $LatestAsset.name
  $BrowserDownloadUrl = $LatestAsset.browser_download_url

  $ZipDownloadPath = Join-Path $DownloadsDir $LatestAssetName

  if (!(Test-Path $ZipDownloadPath)) {
    Write-Host "Downloading SDL2_image development libraries version '$LatestVersion' from '$BrowserDownloadUrl'..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $BrowserDownloadUrl -OutFile $ZipDownloadPath
  }

  Write-Host "Extracting SDL2_image development libraries to '$DownloadsDir'..." -ForegroundColor Yellow
  $ExpandedFiles = Expand-Archive -Path $ZipDownloadPath -DestinationPath $DownloadsDir -Force -Verbose *>&1

  Write-Host "Staging SDL2_image development libraries to '$StagingDir'..." -ForegroundColor Yellow
  Copy-Item -Path $PackagesDir\SDL2_image -Destination $StagingDir -Force -Recurse
  Copy-Item -Path $PackagesDir\SDL2_image.runtime.win-x64 -Destination $StagingDir -Force -Recurse
  Copy-Item -Path $PackagesDir\SDL2_image.runtime.win-x86 -Destination $StagingDir -Force -Recurse

  $ExpandedFiles | Foreach-Object {
    if ($_.message -match "Created '(.*)'.*") {
      $ExpandedFile = $Matches[1]
        
      if (($ExpandedFile -like '*\CHANGES.txt') -or
          ($ExpandedFile -like '*\LICENSE.txt') -or
          ($ExpandedFile -like '*\README.txt')) {
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image -Force
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image.runtime.win-x64 -Force
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image.runtime.win-x86 -Force
      }
      elseif ($ExpandedFile -like '*\docs\*.md') {
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image\docs -Force
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image.runtime.win-x64\docs -Force
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image.runtime.win-x86\docs -Force
      }
      elseif ($ExpandedFile -like '*\include\*.h') {
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image\lib\native\include -Force
      }
      elseif ($ExpandedFile -like '*\lib\x64\*.dll') {
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image.runtime.win-x64\runtimes\win-x64\native -Force
      }
      elseif ($ExpandedFile -like '*\lib\x86\*.dll') {
        Copy-File -Path $ExpandedFile -Destination $StagingDir\SDL2_image.runtime.win-x86\runtimes\win-x86\native -Force
      }
    }
  }

  Write-Host "Replace variable `$version`$ in runtime.json with value '$PackageVersion'..." -ForegroundColor Yellow
  $RuntimeContent = Get-Content $StagingDir\SDL2_image\runtime.json -Raw
  $RuntimeContent = $RuntimeContent.replace('$version$', $PackageVersion)
  Set-Content $StagingDir\SDL2_image\runtime.json $RuntimeContent

  Write-Host "Build 'SDL2_image' package..." -ForegroundColor Yellow
  & nuget pack $StagingDir\SDL2_image\SDL2_image.nuspec -Properties version=$PackageVersion -OutputDirectory $ArtifactsPkgDir
  if ($LastExitCode -ne 0) {
    throw "'nuget pack' failed for 'SDL2_image.nuspec'"
  }
  
  Write-Host "Build 'SDL2_image.runtime.win-x64' package..." -ForegroundColor Yellow
  & nuget pack $StagingDir\SDL2_image.runtime.win-x64\SDL2_image.runtime.win-x64.nuspec -Properties version=$PackageVersion -OutputDirectory $ArtifactsPkgDir
  if ($LastExitCode -ne 0) {
    throw "'nuget pack' failed for 'SDL2_image.runtime.win-x64.nuspec'"
  }
  
  Write-Host "Build 'SDL2_image.runtime.win-x86' package..." -ForegroundColor Yellow
  & nuget pack $StagingDir\SDL2_image.runtime.win-x86\SDL2_image.runtime.win-x86.nuspec -Properties version=$PackageVersion -OutputDirectory $ArtifactsPkgDir
  if ($LastExitCode -ne 0) {
    throw "'nuget pack' failed for 'SDL2_image.runtime.win-x86.nuspec'"
  }
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
