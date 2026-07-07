<#
.SYNOPSIS
    Publishes a daily Claude Code journal entry as a OneNote page via Microsoft Graph.

.DESCRIPTION
    The OneNote counterpart to the Obsidian summarizer. Instead of writing a
    Markdown file into a vault, this creates (or idempotently updates) a single
    OneNote page per day inside a dedicated notebook, organized one section per
    month.

    Order of operations:
      1. Acquire a DELEGATED Microsoft Graph access token from the refresh token
         stored by Initialize-OneNoteAuth.ps1 (no prompt). The OneNote API no
         longer accepts app-only/certificate tokens (retired March 31 2025), so
         a one-time interactive sign-in is required up front; after that this
         runs unattended.
      2. Find-or-create the target notebook (default "Claude Journal").
      3. Find-or-create the month section (named "yyyy-MM", e.g. "2026-06").
      4. Find a page whose title is the ISO date (e.g. "2026-06-30").
           - If absent, POST a new page (HTML body).
           - If present, PATCH-replace the page body (so nightly re-runs are
             idempotent and never duplicate the day).
      5. Emit the OneNote web/client URLs for the page.

    The caller (the nightly summarizer) supplies only the BODY fragment — the
    five journal sections as HTML. This script wraps it into a full OneNote
    page document and sets the title/heading from the date.

    Prerequisite: run Initialize-OneNoteAuth.ps1 once to sign in (device code)
    and store the refresh token. If this script reports an expired/revoked
    token, re-run that bootstrap.

.PARAMETER BodyHtmlPath
    Path to a file containing the inner HTML for the page body (the journal
    sections). Mutually exclusive with -BodyHtml.

.PARAMETER BodyHtml
    The inner HTML for the page body, passed directly as a string. Mutually
    exclusive with -BodyHtmlPath.

.PARAMETER Date
    The journal date as yyyy-MM-dd. Defaults to today in the local timezone.
    Drives both the page title and the month section name.

.PARAMETER NotebookName
    Display name of the notebook to write into. Created if it does not exist.
    Default: "Claude Journal".

.EXAMPLE
    .\Publish-JournalToOneNote.ps1 -BodyHtmlPath "C:\Temp\journal-body.html"
    Publishes today's page from an HTML fragment file.

.EXAMPLE
    .\Publish-JournalToOneNote.ps1 -Date 2026-06-29 -BodyHtml "<h2>...</h2>..."
    Publishes (or updates) the page for a specific date.

.NOTES
    Part of obsidian-claude-code-journal. MIT licensed.
    Version: 1.0
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = "Path")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Path")]
    [string]$BodyHtmlPath,

    [Parameter(Mandatory = $true, ParameterSetName = "Inline")]
    [string]$BodyHtml,

    [Parameter(Mandatory = $false)]
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),

    [Parameter(Mandatory = $false)]
    [string]$NotebookName = "Claude Journal"
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $timestamp = Get-Date -Format "HH:mm:ss"
    switch ($Type) {
        "Success" { Write-Host "[$timestamp] OK  $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[$timestamp] !   $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "[$timestamp] X   $Message" -ForegroundColor Red }
        "Info"    { Write-Host "[$timestamp] i   $Message" -ForegroundColor Cyan }
        "Section" {
            Write-Host "`n=======================================" -ForegroundColor Cyan
            Write-Host "  $Message" -ForegroundColor Cyan
            Write-Host "=======================================`n" -ForegroundColor Cyan
        }
    }
}

# OData string-literal escaping: single quotes are doubled.
function Format-ODataString { param([string]$s) return $s.Replace("'", "''") }

# ---------------------------------------------------------------------------
# 1. Resolve inputs
# ---------------------------------------------------------------------------
try { $parsedDate = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null) }
catch { throw "Date '$Date' is not in yyyy-MM-dd format." }

$pageTitle    = $parsedDate.ToString('yyyy-MM-dd')                 # stable, filterable
$prettyDate   = $parsedDate.ToString('dddd, MMMM d, yyyy')         # human heading
$sectionName  = $parsedDate.ToString('yyyy-MM')                    # one section / month
$createdStamp = $parsedDate.ToString('yyyy-MM-ddTHH:mm:ssK')

if ($PSCmdlet.ParameterSetName -eq "Path") {
    if (-not (Test-Path $BodyHtmlPath)) { throw "BodyHtmlPath not found: $BodyHtmlPath" }
    $BodyHtml = Get-Content -Path $BodyHtmlPath -Raw -Encoding UTF8
}
if ([string]::IsNullOrWhiteSpace($BodyHtml)) { throw "No body HTML supplied." }

# ---------------------------------------------------------------------------
# 2. Connect to Graph (delegated — the OneNote API no longer accepts app-only
#    tokens). Get a fresh access token from the stored refresh token, then hand
#    it to the Graph SDK so the Invoke-MgGraphRequest calls below are authorized.
# ---------------------------------------------------------------------------
Write-Status "Acquiring delegated OneNote access token..." -Type "Section"
. (Join-Path $PSScriptRoot "OneNoteAuth.ps1")
$accessToken = Get-OneNoteAccessToken
Connect-MgGraph -AccessToken (ConvertTo-SecureString $accessToken -AsPlainText -Force) -NoWelcome -ErrorAction Stop
Write-Status "Connected (delegated) as $((Get-MgContext).Account)" -Type "Success"

# Delegated context => the signed-in user's own OneNote lives under /me.
$base = "https://graph.microsoft.com/v1.0/me/onenote"

# ---------------------------------------------------------------------------
# 3. Find-or-create notebook
# ---------------------------------------------------------------------------
Write-Status "Resolving notebook '$NotebookName'..." -Type "Info"
$nbFilter = [uri]::EscapeDataString("displayName eq '$(Format-ODataString $NotebookName)'")
$nb = (Invoke-MgGraphRequest -Method GET -Uri "$base/notebooks?`$filter=$nbFilter" -OutputType PSObject).value | Select-Object -First 1
if (-not $nb) {
    Write-Status "Notebook not found - creating it." -Type "Warning"
    $nb = Invoke-MgGraphRequest -Method POST -Uri "$base/notebooks" `
        -Body (@{ displayName = $NotebookName } | ConvertTo-Json) `
        -ContentType "application/json" -OutputType PSObject
}
Write-Status "Notebook id: $($nb.id)" -Type "Success"

# ---------------------------------------------------------------------------
# 4. Find-or-create month section
# ---------------------------------------------------------------------------
Write-Status "Resolving section '$sectionName'..." -Type "Info"
$secFilter = [uri]::EscapeDataString("displayName eq '$(Format-ODataString $sectionName)'")
$sec = (Invoke-MgGraphRequest -Method GET -Uri "$base/notebooks/$($nb.id)/sections?`$filter=$secFilter" -OutputType PSObject).value | Select-Object -First 1
if (-not $sec) {
    Write-Status "Section not found - creating it." -Type "Warning"
    $sec = Invoke-MgGraphRequest -Method POST -Uri "$base/notebooks/$($nb.id)/sections" `
        -Body (@{ displayName = $sectionName } | ConvertTo-Json) `
        -ContentType "application/json" -OutputType PSObject
}
Write-Status "Section id: $($sec.id)" -Type "Success"

# ---------------------------------------------------------------------------
# 5. Find existing page for this date
# ---------------------------------------------------------------------------
Write-Status "Checking for an existing page titled '$pageTitle'..." -Type "Info"
$pgFilter = [uri]::EscapeDataString("title eq '$(Format-ODataString $pageTitle)'")
$existing = (Invoke-MgGraphRequest -Method GET -Uri "$base/sections/$($sec.id)/pages?`$filter=$pgFilter" -OutputType PSObject).value | Select-Object -First 1

# ---------------------------------------------------------------------------
# 6. Create or update
# ---------------------------------------------------------------------------
if (-not $existing) {
    Write-Status "Creating new page '$pageTitle'..." -Type "Section"
    $fullDoc = @"
<!DOCTYPE html>
<html>
  <head>
    <title>$pageTitle</title>
    <meta name="created" content="$createdStamp" />
  </head>
  <body data-absolute-enabled="true">
    <h1>$prettyDate</h1>
$BodyHtml
  </body>
</html>
"@
    $page = Invoke-MgGraphRequest -Method POST -Uri "$base/sections/$($sec.id)/pages" `
        -Body $fullDoc -ContentType "application/xhtml+xml" -OutputType PSObject
    Write-Status "Page created (id: $($page.id))" -Type "Success"
    $links = $page.links
}
else {
    Write-Status "Page exists - replacing its body (idempotent re-run)..." -Type "Section"
    # OneNote PATCH replaces the matched target with new content. Target the
    # body so the whole day's content is refreshed in place.
    $wrapped = "<div><h1>$prettyDate</h1>`n$BodyHtml</div>"
    $commands = @(
        @{ target = "body"; action = "replace"; content = $wrapped }
    )
    Invoke-MgGraphRequest -Method PATCH -Uri "$base/pages/$($existing.id)/content" `
        -Body ($commands | ConvertTo-Json -Depth 5 -AsArray) `
        -ContentType "application/json" | Out-Null
    Write-Status "Page updated (id: $($existing.id))" -Type "Success"
    $links = $existing.links
}

# ---------------------------------------------------------------------------
# 7. Report
# ---------------------------------------------------------------------------
if ($links.oneNoteWebUrl.href) {
    Write-Status "Web:    $($links.oneNoteWebUrl.href)" -Type "Info"
}
if ($links.oneNoteClientUrl.href) {
    Write-Status "Client: $($links.oneNoteClientUrl.href)" -Type "Info"
}
Write-Status "Done. Notebook '$NotebookName' > Section '$sectionName' > Page '$pageTitle'." -Type "Success"

Disconnect-MgGraph | Out-Null
