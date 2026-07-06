<#
.SYNOPSIS
    One-time interactive sign-in that authorizes the OneNote journal publisher.

.DESCRIPTION
    Runs the OAuth 2.0 device-code flow so you sign in once in a browser and
    consent delegated Notes.ReadWrite. The resulting refresh token is stored
    DPAPI-encrypted on this machine (see OneNoteAuth.ps1), after which the
    nightly publisher runs without prompting.

    Device-code flow is used because it works in any terminal (no embedded
    browser window required). You'll be shown a short URL and code to enter.

    Run this:
      - Once during setup.
      - Again only if publishing later fails with an expired/revoked token
        (e.g. the nightly job didn't run for >90 days, or sign-in was revoked).

.EXAMPLE
    pwsh .\Initialize-OneNoteAuth.ps1

.NOTES
    Part of onenote-claude-code-journal. MIT licensed.
#>

#Requires -Version 7.0

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "OneNoteAuth.ps1")

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $ts = Get-Date -Format "HH:mm:ss"
    switch ($Type) {
        "Success" { Write-Host "[$ts] OK  $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[$ts] !   $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "[$ts] X   $Message" -ForegroundColor Red }
        "Info"    { Write-Host "[$ts] i   $Message" -ForegroundColor Cyan }
        "Section" {
            Write-Host "`n=======================================" -ForegroundColor Cyan
            Write-Host "  $Message" -ForegroundColor Cyan
            Write-Host "=======================================`n" -ForegroundColor Cyan
        }
    }
}

$tenant       = $script:OneNoteTenantId
$clientId     = $script:OneNoteClientId
$scope        = $script:OneNoteScope
$deviceCodeEp = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/devicecode"
$tokenEp      = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"

# --- 1. Request a device code ------------------------------------------------
Write-Status "Requesting a device code from Azure AD..." -Type "Section"
$dc = Invoke-RestMethod -Method POST -Uri $deviceCodeEp `
    -Body @{ client_id = $clientId; scope = $scope } `
    -ContentType "application/x-www-form-urlencoded"

Write-Host ""
Write-Host "  ----------------------------------------------------------" -ForegroundColor Yellow
Write-Host "   To sign in, open: $($dc.verification_uri)" -ForegroundColor Yellow
Write-Host "   And enter code:   $($dc.user_code)" -ForegroundColor Yellow
Write-Host "  ----------------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
Write-Status "Sign in as the account whose OneNote should hold the journal." -Type "Info"
Write-Status "Waiting for you to complete sign-in..." -Type "Info"

# --- 2. Poll for the token ---------------------------------------------------
$interval = [int]$dc.interval
$deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
$tokenResp = $null

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    try {
        $tokenResp = Invoke-RestMethod -Method POST -Uri $tokenEp -ContentType "application/x-www-form-urlencoded" -Body @{
            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
            client_id   = $clientId
            device_code = $dc.device_code
        } -ErrorAction Stop
        break  # success
    } catch {
        $err = $null
        try { $err = ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { }
        switch ($err) {
            "authorization_pending" { continue }                       # not done yet
            "slow_down"             { $interval += 5; continue }        # back off
            "authorization_declined"{ throw "Sign-in was declined." }
            "expired_token"         { throw "The device code expired. Re-run this script." }
            "bad_verification_code" { throw "Bad verification code (internal). Re-run this script." }
            default                 { throw "Token request failed: $($_.ErrorDetails.Message)" }
        }
    }
}

if (-not $tokenResp) { throw "Timed out waiting for sign-in." }
if (-not $tokenResp.refresh_token) { throw "No refresh token returned (was 'offline_access' consented?)." }

# --- 3. Store the refresh token ----------------------------------------------
Save-OneNoteRefreshToken -Token $tokenResp.refresh_token
Write-Status "Refresh token stored (DPAPI-encrypted) at: $script:OneNoteTokenFile" -Type "Success"

# --- 4. Verify by listing notebooks ------------------------------------------
Write-Status "Verifying delegated OneNote access..." -Type "Section"
$access = Get-OneNoteAccessToken
$nb = Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/me/onenote/notebooks?`$select=displayName" `
    -Headers @{ Authorization = "Bearer $access" }
Write-Status "Success. OneNote is reachable. Existing notebooks: $($nb.value.displayName -join ', ')" -Type "Success"
Write-Status "Setup complete. The nightly publisher can now run unattended." -Type "Success"
