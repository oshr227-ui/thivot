$root = $PSScriptRoot
$port = 8765
$LIMIT = 100000
$countFile = Join-Path $root "count.txt"
$keyFile = Join-Path $root "key.txt"

Add-Type @"
using System.Runtime.InteropServices;
public class KeyState {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
}
"@

$script:count = 0
if (Test-Path $countFile) {
  $t = (Get-Content $countFile -Raw).Trim()
  if ($t -match '^\d+$') { $script:count = [int]$t }
}
$script:vk = 119
$script:code = "F8"
if (Test-Path $keyFile) {
  $t = (Get-Content $keyFile -Raw).Trim()
  if ($t -match '^(\d+),(\w+)$') { $script:vk = [int]$Matches[1]; $script:code = $Matches[2] }
}

function Save-Count { Set-Content -Path $countFile -Value $script:count -Encoding ASCII }

$types = @{ ".html" = "text/html; charset=utf-8"; ".png" = "image/png" }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try { $listener.Start() } catch {
  Write-Host "Port $port is busy. Close the other window of this program and try again."
  pause
  exit
}
Write-Host "Running at http://localhost:$port/"
Write-Host "Counting works even when this browser is not in focus."
Write-Host "Close this window to stop."
Start-Process "http://localhost:$port/"

$prev = $false
$task = $listener.GetContextAsync()
while ($true) {
  if ($task.AsyncWaitHandle.WaitOne(15)) {
    $ctx = $task.Result
    $task = $listener.GetContextAsync()
    $req = $ctx.Request
    $res = $ctx.Response
    $path = $req.Url.AbsolutePath
    $bytes = $null
    $ctype = "text/plain"
    $code = 200
    try {
      switch ($path) {
        "/state" {
          $bytes = [Text.Encoding]::UTF8.GetBytes("$($script:count),$($script:vk),$($script:code)")
          $res.Headers.Add("Cache-Control", "no-store")
        }
        "/add" {
          $script:count++
          if ($script:count -ge $LIMIT) { $script:count = 0 }
          Save-Count
          $bytes = [Text.Encoding]::UTF8.GetBytes("ok")
        }
        "/sub" {
          if ($script:count -gt 0) { $script:count-- }
          Save-Count
          $bytes = [Text.Encoding]::UTF8.GetBytes("ok")
        }
        "/reset" {
          $script:count = 0
          Save-Count
          $bytes = [Text.Encoding]::UTF8.GetBytes("ok")
        }
        "/key" {
          $sr = New-Object IO.StreamReader($req.InputStream)
          $body = $sr.ReadToEnd().Trim()
          if ($body -match '^(\d+),(\w+)$') {
            $script:vk = [int]$Matches[1]
            $script:code = $Matches[2]
            Set-Content -Path $keyFile -Value "$($script:vk),$($script:code)" -Encoding ASCII
          }
          $bytes = [Text.Encoding]::UTF8.GetBytes("ok")
        }
        { $_ -eq "/" -or $_ -eq "/index.html" } {
          $bytes = [IO.File]::ReadAllBytes((Join-Path $root "index.html"))
          $ctype = $types[".html"]
        }
        "/boxes.png" {
          $bytes = [IO.File]::ReadAllBytes((Join-Path $root "boxes.png"))
          $ctype = $types[".png"]
        }
        default {
          $code = 404
          $bytes = [Text.Encoding]::UTF8.GetBytes("not found")
        }
      }
    } catch {
      $code = 500
      $bytes = [Text.Encoding]::UTF8.GetBytes("error")
    }
    try {
      $res.StatusCode = $code
      $res.ContentType = $ctype
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.OutputStream.Close()
    } catch {}
  }

  # בדיקה גלובלית של המקש, גם כשהדפדפן לא בפוקוס
  $down = ([KeyState]::GetAsyncKeyState($script:vk) -lt 0)
  if ($down -and -not $prev) {
    $script:count++
    if ($script:count -ge $LIMIT) { $script:count = 0 }
    Save-Count
  }
  $prev = $down
}
