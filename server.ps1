# Kuber Alpha Research - Lightweight Local Office Server (Zero Install)
$port = 8080

# Auto-detect local Wi-Fi or Ethernet IPv4
$localIP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.' -and $_.IPAddress -notmatch '^127\.' } | 
            Select-Object -First 1).IPAddress

if (-not $localIP) { $localIP = "localhost" }

$dbDir = Join-Path $PSScriptRoot "data"
if (-not (Test-Path $dbDir)) { New-Item -ItemType Directory -Path $dbDir | Out-Null }
$dbFile = Join-Path $dbDir "employees.json"
if (-not (Test-Path $dbFile)) { "{}" | Out-File -FilePath $dbFile -Encoding utf8 }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")

# Attempt to bind local IP for office phones/Wi-Fi
try {
    $listener.Prefixes.Add("http://$localIP`:$port/")
} catch {}

try {
    $listener.Start()
} catch {
    Write-Host "[!] Could not bind to port $port. It might already be in use." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Read-Host "Press Enter to exit"
    exit
}

Clear-Host
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "      KUBER ALPHA RESEARCH - JOINING & ONBOARDING SERVER" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [HR PC Access]     : http://localhost:$port" -ForegroundColor Green
Write-Host " [Candidate Mobile] : http://$localIP`:$port?mode=candidate" -ForegroundColor White
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " * Tip: Print the Reception QR Code from the HR Dashboard."
Write-Host " * Candidate scans QR on mobile -> forms auto-fill -> submits to HR."
Write-Host " * Server is actively running. Press Ctrl+C in this window to stop."
Write-Host "--------------------------------------------------------------------"

# Open HR Dashboard automatically
Start-Process "http://localhost:$port"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $rawUrl = $request.RawUrl.Split('?')[0]

        if ($rawUrl -eq "/api/employees" -and $request.HttpMethod -eq "GET") {
            $json = [System.IO.File]::ReadAllText($dbFile, [System.Text.Encoding]::UTF8)
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            continue
        }

        if ($rawUrl -eq "/api/submit" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()

            try {
                $subEmp = $body | ConvertFrom-Json
                $currentJson = [System.IO.File]::ReadAllText($dbFile, [System.Text.Encoding]::UTF8)
                $dataObj = @{}
                try {
                    $parsed = $currentJson | ConvertFrom-Json
                    if ($parsed) {
                        foreach ($prop in $parsed.PSObject.Properties) {
                            $dataObj[$prop.Name] = $prop.Value
                        }
                    }
                } catch {}

                if ($subEmp.id) {
                    $dataObj[$subEmp.id] = $subEmp
                    $updatedJson = $dataObj | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($dbFile, $updatedJson, [System.Text.Encoding]::UTF8)
                    Write-Host "[+] New Joiner Submitted: $($subEmp.name) ($($subEmp.position))" -ForegroundColor Green
                }
            } catch {
                Write-Host "[!] Error parsing submission: $_" -ForegroundColor Red
            }

            $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"ok"}')
            $response.ContentType = "application/json"
            $response.ContentLength64 = $resBytes.Length
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.Close()
            continue
        }

        # Serve static index.html
        $filePath = Join-Path $PSScriptRoot "index.html"
        if (Test-Path $filePath) {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
        }
        $response.Close()
    }
} finally {
    $listener.Stop()
}
