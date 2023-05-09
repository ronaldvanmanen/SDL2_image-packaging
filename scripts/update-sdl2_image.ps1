function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Get-GitHubLatestRelease([string] $Owner, [string] $Repo, [string] $Bearer) {
    $Uri = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $Headers = @{
        'Accept'='application/vnd.github+json'
        'Authorization'="Bearer $Bearer"
        'X-GitHub-Api-Version'='2022-11-28'
    }
    Invoke-RestMethod -Headers $Headers -Uri $Uri
}

function New-GitHubPullRequest([string] $Owner, [string] $Repo, [string] $Title, [string] $Head, [string] $Base, [string] $Bearer) {
    $Body = "{""title"":""$Title"",""head"":""$Head"",""base"":""$Base""}"
    $Headers = @{
        'Accept'='application/vnd.github+json'
        'Authorization'="Bearer $Bearer"
        'X-GitHub-Api-Version'='2022-11-28'
    }
    $Uri = "https://api.github.com/repos/$Owner/$Repo/pulls"
    Invoke-RestMethod -Body $Body -Headers $Headers -Method Post -Uri $Uri
}

$LibraryName = 'SDL_image'
$LibraryRepoOwner = 'libsdl-org'
$LibraryRepo = 'SDL_image'

$PackageName = 'SDL2_image'
$PackagingRepoOwner = 'ronaldvanmanen'
$PackagingRepo = 'SDL2_image-packaging'

$RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."

$WorkTreeRoot = Join-Path -Path $RepoRoot -ChildPath ".."

$LatestLibraryRelease = Get-GitHubLatestRelease -Owner $LibraryRepoOwner -Repo $LibraryRepo -Bearer $Env:GITHUB_TOKEN
$LatestLibraryVersion = $LatestLibraryRelease.name
Write-Host "Latest release of library $LibraryName is '$LatestLibraryVersion'" -ForegroundColor Yellow

$LatestPackageRelease = Get-GitHubLatestRelease -Owner $PackagingRepoOwner -Repo $PackagingRepo -Bearer $Env:GITHUB_TOKEN
$LatestPackageVersion = $LatestPackageRelease.name
Write-Host "Latest release of package $PackageName is '$LatestPackageVersion'" -ForegroundColor Yellow

if ($LatestPackageVersion -eq $LatestLibraryVersion) {
    Write-Host "We're up-to-date... nothing to do" -ForegroundColor Yellow
    Break
}

$WorkTreePath = "$WorkTreeRoot\$PackagingRepo-bump_to_$LatestLibraryVersion"

& git worktree add $WorkTreePath main

Push-Location $WorkTreePath

$GitVersionPath = "$WorkTreePath\GitVersion.yml"
$GitVersionContent = $GitVersionContent -Replace 'next-version: ([^\r\n]+)', "next-version: $LatestLibraryVersion"
Set-Content $GitVersionPath $GitVersionContent -NoNewline

$GitBranchName = "release/$LatestLibraryVersion"
& git checkout -b $GitBranchName
& git add $GitVersionPath
& git commit -m "Bump $PackageName from $LatestPackageVersion to $LatestLibraryVersion"
& git push --set-upstream origin $GitBranchName

$PullRequestTitle = "Bump $PackageName from $LatestPackageVersion to $LatestLibraryVersion"

New-GitHubPullRequest -Owner $PackagingRepoOwner -Repo $PackagingRepo -Title $PullRequestTitle -Head $GitBranchName -Base 'main' -Bearer $Env:GITHUB_TOKEN

Write-Host $GitHubPullRequestResponse

Pop-Location

& git worktree remove $WorkTreePath
