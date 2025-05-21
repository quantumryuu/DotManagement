# Automatically dot-source all .ps1 files in the Functions folder

$functionsPath = Join-Path $PSScriptRoot 'Functions'

Get-ChildItem -Path $functionsPath -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}
