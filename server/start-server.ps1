# Lancer le serveur (installe automatiquement les deps si besoin) et affiche l'IP locale
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot
if (!(Test-Path node_modules)) {
  Write-Host "Installing npm dependencies..."
  npm install
}
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "vEthernet*" -and $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*" } | Select-Object -ExpandProperty IPAddress | Select-Object -First 1)
Write-Host "Server starting on http://$ip:3000"
node server.js