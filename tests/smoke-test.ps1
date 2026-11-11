
param([string]$BaseUrl = "http://localhost:5000")
$ProgressPreference = "SilentlyContinue"

$script:failed = 0

function Show-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        Write-Host ("[PASS] " + $Name) -ForegroundColor Green
    } else {
        Write-Host ("[FAIL] " + $Name + " " + $Detail) -ForegroundColor Red
        $script:failed++
    }
}

function Get-Status {
    param([string]$Url, [string]$Method = "GET", [string]$Body = "")
    try {
        if ($Method -eq "POST") {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Post -ContentType "application/json" -Body $Body
        } else {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $Url
        }
        return @{ Code = [int]$r.StatusCode; Text = [string]$r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($resp -ne $null) { return @{ Code = [int]$resp.StatusCode; Text = "" } }
        return @{ Code = 0; Text = $_.Exception.Message }
    }
}

$r = Get-Status "$BaseUrl/"
Show-Result "GET / returns the welcome message" (($r.Code -eq 200) -and $r.Text.StartsWith("Welcome to the Flask app! The current time is:")) $r.Text

$r = Get-Status "$BaseUrl/data" "POST" '{"sampleKey":"sampleValue"}'
Show-Result "POST /data inserts a document (201)" (($r.Code -eq 201) -and $r.Text.Contains("Data inserted")) ("got " + $r.Code)

$r = Get-Status "$BaseUrl/data"
Show-Result "GET /data returns the stored document" (($r.Code -eq 200) -and $r.Text.Contains("sampleKey")) ("got " + $r.Code)

$r = Get-Status "$BaseUrl/data" "POST" "notjson"
Show-Result "POST with a bad body is rejected (400)" ($r.Code -eq 400) ("got " + $r.Code)

$r = Get-Status "$BaseUrl/healthz"
Show-Result "GET /healthz (liveness)" ($r.Code -eq 200) ("got " + $r.Code)

$r = Get-Status "$BaseUrl/ready"
Show-Result "GET /ready (readiness, pings mongodb)" ($r.Code -eq 200) ("got " + $r.Code)

$dns = (kubectl exec deploy/flask-app -- python -c "import socket; print(socket.gethostbyname('mongodb-service'))" 2>&1 | Out-String).Trim()
$svc = (kubectl get svc mongodb-service -o jsonpath='{.spec.clusterIP}' | Out-String).Trim()
Show-Result ("mongodb-service resolves to its ClusterIP (" + $svc + ")") (($dns -eq $svc) -and ($svc -ne "")) ("got " + $dns)

$out = (kubectl exec mongodb-0 -- mongosh --quiet --eval "db.getSiblingDB('test').getCollectionNames()" 2>&1 | Out-String)
Show-Result "mongosh without credentials is rejected" ($out -match "requires authentication") $out

Write-Host ""
if ($script:failed -eq 0) { Write-Host "all checks passed" -ForegroundColor Green }
else { Write-Host ($script:failed.ToString() + " check(s) failed") -ForegroundColor Red; exit 1 }
