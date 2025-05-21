function Push-Dot {
    param(
        [string]$CommitMessage = $("Update dotfiles " + (Get-Date -Format 'yyyy-MM-dd'))
    )
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $localPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $localPath 'dotfiles.config.json'

    if (-not (Test-Path $configPath)) {
        Write-Output "❌ Config file not found at $configPath. Please run Init-Dots first." -ForegroundColor Red
        return
    }

    $config = Get-Content $configPath | ConvertFrom-Json
    $repoUrl = $config.Repo

    if (-not $repoUrl) {
        Write-Output "❌ Repo URL not found in config." -ForegroundColor Red
        return
    }

    if (-not (Test-Path (Join-Path $localPath '.git'))) {
        Write-Output "❌ No git repo found in $localPath. Please run Init-Dots first." -ForegroundColor Red
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Output "❌ Git is not installed or not in PATH." -ForegroundColor Red
        return
    }

    Push-Location $localPath

    # Stage all changes
    $add = git add -A 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "❌ Failed to stage files:" -ForegroundColor Red
        Write-Output $add -ForegroundColor DarkRed
        Pop-Location
        return
    }

    # Commit changes
    $commit = git commit -m $CommitMessage 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($commit -match 'nothing to commit') {
            Write-Output "ℹ️ No changes to commit."
        }
        else {
            Write-Output "❌ Commit failed:" -ForegroundColor Red
            Write-Output $commit -ForegroundColor DarkRed
            Pop-Location
            return
        }
    }
    else {
        Write-Output "✅ Committed changes with message: '$CommitMessage'"
    }

    # Get current branch name
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($branch)) {
        Write-Output "❌ Could not determine current git branch." -ForegroundColor Red
        Pop-Location
        return
    }
    Write-Output "ℹ️ Current branch: $branch"

    # Check if remote origin already set
    $remotes = git remote 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "❌ Failed to get git remotes:" -ForegroundColor Red
        Write-Output $remotes -ForegroundColor DarkRed
        Pop-Location
        return
    }

    if ($remotes -notcontains "origin") {
        $addRemote = git remote add origin $repoUrl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Output "❌ Failed to add remote origin:" -ForegroundColor Red
            Write-Output $addRemote -ForegroundColor DarkRed
            Pop-Location
            return
        }
        Write-Output "✅ Added remote origin $repoUrl"
    }
    else {
        Write-Output "ℹ️ Remote origin already set."
    }

    # Push the current branch
    $push = git push -u origin $branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "❌ Failed to push to remote:" -ForegroundColor Red
        Write-Output $push -ForegroundColor DarkRed
        Pop-Location
        return
    }
    Write-Output "✅ Successfully pushed branch '$branch' to $repoUrl"
    Pop-Location
}
