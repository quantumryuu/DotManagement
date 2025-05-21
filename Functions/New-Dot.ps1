function New-Dot {
    param (
        [string]$Repo,
        [switch]$Overwrite
    )

    $homePath   = [Environment]::GetFolderPath('UserProfile')
    $localPath  = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $localPath 'dotfiles.config.json'

    # Prompt if repo not supplied
    if (-not $Repo) {
        $Repo = Read-Host "Enter GitHub username or full repo URL (for future push)"
    }

    # Build repo URL for config
    if ($Repo -match '^https?://|^git@') {
        $repoUrl = $Repo
    } else {
        $repoUrl = "https://github.com/$Repo/dotfiles.git"
    }

    # Check if dotfiles folder exists
    if (Test-Path $localPath) {
        if ($Overwrite) {
            $confirmation = Read-Host "WARNING: This will DELETE the existing '$localPath' folder and all its contents. Type 'YES' to confirm"
            if ($confirmation -ne 'YES') {
                Write-Output "❌ Overwrite cancelled by user."
                return
            }
            try {
                Remove-Item -Path $localPath -Recurse -Force
                Write-Output "🗑️ Existing folder '$localPath' deleted due to -Overwrite switch."
            } catch {
                Write-Error "❌ Failed to delete existing folder '$localPath': $_"
                return
            }
        } else {
            Write-Output "⚠️ Directory $localPath already exists. Use -Overwrite to delete and recreate."
            return
        }
    }

    # Create dotfiles folder
    New-Item -ItemType Directory -Path $localPath | Out-Null
    Write-Output "📁 Created directory $localPath"

    # Initialize git repo
    Push-Location $localPath
    git init | Out-Null

    # Initial commit with empty README.md
    New-Item -Path "$localPath\README.md" -ItemType File -Value "# My Dotfiles" | Out-Null
    git add README.md
    git commit -m "Initial commit: Initialize dotfiles repo" | Out-Null
    Pop-Location

    Write-Output "✅ Initialized new git repo and committed initial README.md"

    # Create config JSON file using new structure
    $config = @{
        Repo  = $repoUrl
        Files = @{}
    }

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    Write-Output "📝 Config file created at $configPath"
}
