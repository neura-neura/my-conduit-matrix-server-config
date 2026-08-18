#Requires -Version 5.1
param()
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$candidates = @(
  (Join-Path $here "neura-matrix-ca.crt"),
  (Join-Path (Split-Path -Parent $here) "certs\neura-matrix-ca.crt"),
  (Join-Path (Get-Location) "neura-matrix-ca.crt")
)
$certPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $certPath) {
  $download = Join-Path $env:TEMP "neura-matrix-ca.crt"
  Write-Host "Downloading the Matrix certificate..."
  Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.196.65:6167/trust/neura-matrix-ca.crt" -OutFile $download
  $certPath = $download
}

Write-Host "Installing the Matrix local certificate for the current Windows user..."
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\TrustedPeople | Out-Null
Write-Host "Done."
Write-Host "Close Cinny completely, then sign in again with http://192.168.196.65:6167"

