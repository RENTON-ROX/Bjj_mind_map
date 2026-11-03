# ============================================================================
# serve_app.ps1 - tiny localhost static file server for the mind map app.
#
# Why this exists: the app's AI auto-fill calls the Ollama API from the
# browser, and the Ollama server only allows requests from http:// pages
# (a file:// page sends Origin: null and gets HTTP 403). So the app is
# served from http://127.0.0.1:<port>/ instead of being opened from disk.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File serve_app.ps1
#         (or just double-click Run_App.bat, which does this for you)
# Stop:   close this window, or press Ctrl+C
# ============================================================================
param(
  [int]$Port = 8471,
  [string]$Root = (Split-Path -Parent $MyInvocation.MyCommand.Path),
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$rootFull = (Resolve-Path $Root).Path

# Try the requested port, then the next nine in case one is taken.
$listener = $null
foreach ($p in ($Port..($Port+9))) {
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$p/")
  try { $l.Start(); $listener = $l; $Port = $p; break }
  catch { try { $l.Close() } catch {} }
}
if (-not $listener) {
  Write-Host "Could not bind http://127.0.0.1:$Port - is another server using these ports?"
  exit 1
}

Write-Host ''
Write-Host '  BJJ Mind Map is running'
Write-Host ("  App   : http://127.0.0.1:{0}/index.html" -f $Port)
Write-Host ("  Files : {0}" -f $rootFull)
Write-Host ''
Write-Host '  Leave this window open while you use the app.'
Write-Host '  Close it (or Ctrl+C) to stop the server.'
Write-Host ''

function Get-ContentType([string]$path) {
  switch -Regex ($path.ToLower()) {
    '\.html?$'  { 'text/html; charset=utf-8' }
    '\.js$'     { 'text/javascript; charset=utf-8' }
    '\.css$'    { 'text/css; charset=utf-8' }
    '\.json$'   { 'application/json; charset=utf-8' }
    '\.svg$'    { 'image/svg+xml' }
    '\.png$'    { 'image/png' }
    '\.jpe?g$'  { 'image/jpeg' }
    '\.gif$'    { 'image/gif' }
    '\.ico$'    { 'image/x-icon' }
    default     { 'application/octet-stream' }
  }
}

# Open the app in the default browser right away (best effort).
if (-not $NoBrowser) { try { Start-Process ("http://127.0.0.1:{0}/index.html" -f $Port) } catch {} }

while ($true) {
  $ctx = $null
  try { $ctx = $listener.GetContext() } catch { break }
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
    if ($rel -eq '') { $rel = 'index.html' }
    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($full -ne $rootFull -and $full.ToLower() -notlike ($rootFull.ToLower() + $sep + '*')) {
      $res.StatusCode = 403
    } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $res.ContentType = Get-ContentType $full
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $res.StatusCode = 404
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    try { $res.Close() } catch {}
  }
}

try { $listener.Close() } catch {}
Write-Host 'Server stopped.'
