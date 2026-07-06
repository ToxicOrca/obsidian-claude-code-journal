<#
.SYNOPSIS
    Shared delegated-auth helpers for the OneNote journal publisher.

.DESCRIPTION
    Dot-source this file to get Get-OneNoteAccessToken. The OneNote API no longer
    accepts app-only (certificate / client-credentials) tokens (Microsoft retired
    that March 31 2025), so the journal uses a DELEGATED (app+user) token:

      - A one-time interactive device-code sign-in (Initialize-OneNoteAuth.ps1)
        obtains a refresh token and stores it DPAPI-encrypted on this machine.
      - Get-OneNoteAccessToken silently exchanges that refresh token for a fresh
        access token on each run (and re-stores the rotated refresh token).

    The refresh token is encrypted with Windows DPAPI (CurrentUser scope), so it
    can only be decrypted by the same user on the same machine. It is stored
    outside the repo and is never synced anywhere.

    Client: the well-known "Microsoft Graph Command Line Tools" public client
    (no app registration or secret needed). Scope: delegated Notes.ReadWrite.

    Tenant: read from config.json ("tenantId") if present, else "common"
    (works for both work/school and personal Microsoft accounts).

.NOTES
    Part of onenote-claude-code-journal. MIT licensed.
#>

#Requires -Version 7.0

# Microsoft Graph Command Line Tools — Microsoft's first-party public client,
# present in every tenant, supports device-code flow + offline_access.
$script:OneNoteClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
$script:OneNoteScope    = "https://graph.microsoft.com/Notes.ReadWrite offline_access openid profile"

# Tenant: "common" works for any account. Override via config.json at repo root.
$script:OneNoteTenantId = "common"
$cfgPath = Join-Path $PSScriptRoot "..\config.json"
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.tenantId) { $script:OneNoteTenantId = $cfg.tenantId }
    } catch { }
}

# DPAPI-encrypted refresh-token store (per-user, machine-bound, outside the repo).
$script:OneNoteTokenFile = Join-Path $env:LOCALAPPDATA "OneNoteClaudeJournal\onenote-refresh.dat"

function Save-OneNoteRefreshToken {
    param([Parameter(Mandatory)][string]$Token)
    $dir = Split-Path $script:OneNoteTokenFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # ConvertFrom-SecureString uses DPAPI (CurrentUser) when no key is supplied.
    # Write the exact hex string with no trailing newline so the read-back parses.
    $enc = ConvertTo-SecureString $Token -AsPlainText -Force | ConvertFrom-SecureString
    [System.IO.File]::WriteAllText($script:OneNoteTokenFile, $enc)
}

function Get-OneNoteRefreshToken {
    if (-not (Test-Path $script:OneNoteTokenFile)) { return $null }
    try {
        $enc = ([System.IO.File]::ReadAllText($script:OneNoteTokenFile)).Trim()
        return (ConvertTo-SecureString $enc | ConvertFrom-SecureString -AsPlainText)
    } catch {
        throw "Stored OneNote refresh token could not be decrypted (different user/machine?). Re-run Initialize-OneNoteAuth.ps1. ($($_.Exception.Message))"
    }
}

function Get-OneNoteTokenEndpoint {
    return "https://login.microsoftonline.com/$($script:OneNoteTenantId)/oauth2/v2.0/token"
}

# Exchange the stored refresh token for a fresh access token. Re-stores the
# rotated refresh token Azure AD returns so the credential stays alive.
function Get-OneNoteAccessToken {
    $rt = Get-OneNoteRefreshToken
    if (-not $rt) {
        throw "No stored OneNote refresh token. Run Initialize-OneNoteAuth.ps1 once to sign in."
    }
    $body = @{
        client_id     = $script:OneNoteClientId
        grant_type    = "refresh_token"
        refresh_token = $rt
        scope         = $script:OneNoteScope
    }
    try {
        $resp = Invoke-RestMethod -Method POST -Uri (Get-OneNoteTokenEndpoint) `
            -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
    } catch {
        $detail = $_.ErrorDetails.Message
        throw "Refresh-token exchange failed. The token may have expired (>90 days idle) or been revoked — re-run Initialize-OneNoteAuth.ps1. Detail: $detail"
    }
    if ($resp.refresh_token) { Save-OneNoteRefreshToken -Token $resp.refresh_token }
    return $resp.access_token
}
