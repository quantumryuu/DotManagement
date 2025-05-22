function Push-Dot {
    param(
        [string]$CommitMessage = $("Update dotfiles " + (Get-Date -Format 'yyyy-MM-dd'))
    )
    # Ensure the script is run as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "❌ This script must be run as Administrator to create symlinks." -ForegroundColor Red
        return
    }
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $localPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $localPath 'dotfiles.config.json'

    if (-not (Test-Path $configPath)) {
        Write-Host "❌ Config file not found at $configPath. Please run Init-Dots first." -ForegroundColor Red
        return
    }

    $config = Get-Content $configPath | ConvertFrom-Json
    $repoUrl = $config.Repo

    if (-not $repoUrl) {
        Write-Host "❌ Repo URL not found in config." -ForegroundColor Red
        return
    }

    if (-not (Test-Path (Join-Path $localPath '.git'))) {
        Write-Host "❌ No git repo found in $localPath. Please run Init-Dots first." -ForegroundColor Red
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Git is not installed or not in PATH." -ForegroundColor Red
        return
    }

    Push-Location $localPath

    # Stage all changes
    $add = git add -A 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to stage files:" -ForegroundColor Red
        Write-Host $add -ForegroundColor DarkRed
        Pop-Location
        return
    }

    # Commit changes
    $commit = git commit -m $CommitMessage 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($commit -match 'nothing to commit') {
            Write-Host "ℹ️ No changes to commit." -ForegroundColor Yellow
        }
        else {
            Write-Host "❌ Commit failed:" -ForegroundColor Red
            Write-Host $commit -ForegroundColor DarkRed
            Pop-Location
            return
        }
    }
    else {
        Write-Host "✅ Committed changes with message: '$CommitMessage'" -ForegroundColor Green
    }

    # Get current branch name
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($branch)) {
        Write-Host "❌ Could not determine current git branch." -ForegroundColor Red
        Pop-Location
        return
    }
    Write-Host "ℹ️ Current branch: $branch" -ForegroundColor Green

    # Check if remote origin already set
    $remotes = git remote 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to get git remotes:" -ForegroundColor Red
        Write-Host $remotes -ForegroundColor DarkRed
        Pop-Location
        return
    }

    if ($remotes -notcontains "origin") {
        $addRemote = git remote add origin $repoUrl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to add remote origin:" -ForegroundColor Red
            Write-Host $addRemote -ForegroundColor DarkRed
            Pop-Location
            return
        }
        Write-Host "✅ Added remote origin $repoUrl" -ForegroundColor Green
    }
    else {
        Write-Host "ℹ️ Remote origin already set." -ForegroundColor Green
    }

    # Push the current branch
    $push = git push -u origin $branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to push to remote:" -ForegroundColor Red
        Write-Host $push -ForegroundColor DarkRed
        Pop-Location
        return
    }
    Write-Host "✅ Successfully pushed branch '$branch' to $repoUrl" -ForegroundColor Green
    Pop-Location
}
