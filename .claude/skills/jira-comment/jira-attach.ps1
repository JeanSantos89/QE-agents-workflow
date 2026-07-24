# Attaches one local PDF to each of the given tracker tickets, via the REST API.
# The file is read from disk here, so its content never passes through the model.
#
# Usage:
#   .\jira-attach.ps1 -Keys PROJ-123,PROJ-124 -Pattern 'Run 123*.pdf'
#
# Requires the environment variables JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN.
# EVIDENCE_DIR is optional and defaults to the user's Documents folder.
#
# Note: PowerShell 5.1 reads this file as ANSI, so no accented path is written literally
# here on purpose -- the PDF is located by pattern instead.

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]] $Keys,
  [Parameter(Mandatory)][string]   $Pattern
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$site  = $env:JIRA_SITE
$email = $env:JIRA_EMAIL
$token = $env:JIRA_TOKEN
$root  = if ($env:EVIDENCE_DIR) { $env:EVIDENCE_DIR } else { "$env:USERPROFILE\Documents" }

foreach ($pair in @{ JIRA_SITE = $site; JIRA_EMAIL = $email; JIRA_TOKEN = $token }.GetEnumerator()) {
  if ([string]::IsNullOrWhiteSpace($pair.Value)) { throw "$($pair.Key) is not set in this session." }
}

$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$email`:$token"))

$found = @(Get-ChildItem -LiteralPath $root -Recurse -Filter $Pattern -File)
if ($found.Count -ne 1) { throw "Expected exactly 1 PDF matching '$Pattern', found $($found.Count)." }
$file  = $found[0].FullName
$name  = $found[0].Name
"File: $file ($($found[0].Length) bytes)"
$bytes = [IO.File]::ReadAllBytes($file)

foreach ($key in $Keys) {
  $client = New-Object System.Net.Http.HttpClient
  $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Basic', $auth)
  $client.DefaultRequestHeaders.Add('X-Atlassian-Token', 'no-check')

  $form = New-Object System.Net.Http.MultipartFormDataContent
  $fc = New-Object System.Net.Http.ByteArrayContent($bytes, 0, $bytes.Length)
  $fc.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('application/pdf')
  $form.Add($fc, 'file', $name)

  $resp = $client.PostAsync("https://$site/rest/api/3/issue/$key/attachments", $form).Result
  $body = $resp.Content.ReadAsStringAsync().Result
  "$key -> $($resp.StatusCode)"
  if ($resp.IsSuccessStatusCode) {
    foreach ($a in ($body | ConvertFrom-Json)) { "  id=$($a.id) filename=$($a.filename) size=$($a.size)" }
  } else {
    "  ERROR: $body"
  }
  $client.Dispose()
}
