function Get-Dot {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Repo,

        [switch]$Force
    )
    # Ensure the script is run as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "❌ This script must be run as Administrator to create symlinks." -ForegroundColor Red
        return
    }
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $dotfilesPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $dotfilesPath 'dotfiles.config.json'
    $backupFolder = Join-Path $dotfilesPath 'backups'

    # Determine full repo URL
    $repoUrl = if ($Repo -match '^https?://|^git@') { $Repo } else { "https://github.com/$Repo/dotfiles.git" }

    # Remove existing dotfiles folder if -Force is specified
    if ($Force -and (Test-Path $dotfilesPath)) {
        Write-Host "🗑️ Removing existing dotfiles folder at $dotfilesPath due to -Force switch..." -ForegroundColor Yellow
        try {
            Remove-Item -Path $dotfilesPath -Recurse -Force -ErrorAction Stop
            Write-Host "✅ Removed existing dotfiles folder." -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to remove dotfiles folder. $_" -ForegroundColor Red
            return
        }
    }

    # Fail if dotfiles folder exists and -Force was not provided
    if (Test-Path $dotfilesPath) {
        Write-Host "❌ Dotfiles folder already exists. Use -Force to overwrite it." -ForegroundColor Red
        return
    }

    # Clone repo
    Write-Host "📥 Cloning $repoUrl into $dotfilesPath..." -ForegroundColor Yellow
    git clone $repoUrl $dotfilesPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Git clone failed." -ForegroundColor Red
        return
    }

    # Load config
    if (-not (Test-Path $configPath)) {
        Write-Host "❌ Config file not found at $configPath." -ForegroundColor Red
        return
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "❌ Failed to parse config JSON. $_" -ForegroundColor Red
        return
    }

    if (-not $config.Files) {
        Write-Host "⚠️ No files mapped in config." -ForegroundColor Yellow
        return
    }

    # Ensure hash format
    if ($config.Files -is [PSCustomObject]) {
        $tempHash = @{}
        foreach ($prop in $config.Files.PSObject.Properties) {
            $tempHash[$prop.Name] = $prop.Value
        }
        $config.Files = $tempHash
    }

    # Prepare backup structure
    if (-not (Test-Path $backupFolder)) {
        New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
    }
    $backupZip = Join-Path $backupFolder ("backup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".zip")
    $backupStaging = Join-Path $backupFolder "staging"
    New-Item -Path $backupStaging -ItemType Directory -Force | Out-Null

    # Process each mapping
    foreach ($relativePath in $config.Files.Keys) {
        $linkPath = $config.Files[$relativePath]
        $dotfileFullPath = Join-Path $dotfilesPath $relativePath

        $linkPathResolved = if ($linkPath -like '$HOME*') {
            Join-Path $homePath $linkPath.Substring(5).TrimStart('\', '/')
        }
        else {
            $linkPath
        }

        # Backup and remove existing non-symlink items
        if (Test-Path $linkPathResolved) {
            $existingItem = Get-Item $linkPathResolved -Force
            $isSymlink = $existingItem.Attributes.ToString().Contains("ReparsePoint")

            if (-not $isSymlink) {
                $backupDest = Join-Path $backupStaging ([IO.Path]::GetFileName($linkPathResolved))
                try {
                    Copy-Item $linkPathResolved -Destination $backupDest -Recurse -Force
                    Write-Host "📦 Backed up $linkPathResolved" -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ Failed to backup $linkPathResolved" -ForegroundColor Red
                    continue
                }
            }
            Remove-Item $linkPathResolved -Force -Recurse
        }
        else {
            $parentDir = Split-Path -Parent $linkPathResolved
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
        }

        # Create symlink
        try {
            New-Item -ItemType SymbolicLink -Path $linkPathResolved -Target $dotfileFullPath -Force | Out-Null
            Write-Host "✅ Linked '$linkPathResolved'" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to link '$linkPathResolved'. $_" -ForegroundColor Red
        }
    }

    # Archive backup if needed
    if ((Get-ChildItem $backupStaging).Count -gt 0) {
        Compress-Archive -Path "$backupStaging\*" -DestinationPath $backupZip -Force
        Remove-Item $backupStaging -Recurse -Force
        Write-Host "📦 Backup saved to $backupZip" -ForegroundColor Green
    }
    else {
        Remove-Item $backupStaging -Recurse -Force
        Write-Host "🧹 No backups needed." -ForegroundColor Green
    }
}
