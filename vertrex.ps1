# ============================================================
#  __   __ ___ ___ _____ _______  __
#  \ \ / /| __| _ \_   _| __\ \/ /
#   \ V / | _||   / | | | _| >  <
#    \_/  |___|_|_\ |_| |___/_/\_\
#
#  Vertex - KeyAuth Authentication System
#  Version: 1.0.0
# ============================================================

# ─── KEYAUTH CONFIG ─────────────────────────────────────────
$KA_NAME    = "Vertrex"
$KA_OWNERID = "h73NBoWgLW"
$KA_VERSION = "1.0"
$KA_URL     = "https://keyauth.win/api/1.3/"

# ─── RUNTIME STATE ──────────────────────────────────────────
$MAX_ATTEMPTS     = 3
$script:SessionID = ""

# ─── HELPER: GET HWID ───────────────────────────────────────
function Get-HWID {
    try {
        $id = (Get-CimInstance -Class Win32_ComputerSystemProduct -ErrorAction Stop).UUID
        if ($id -and $id -ne "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") { return $id }
    } catch {}
    $serial = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue).VolumeSerialNumber
    return "$env:COMPUTERNAME-$env:USERNAME-$serial"
}

# ─── KEYAUTH: INIT SESSION ──────────────────────────────────
function Invoke-KeyAuthInit {
    try {
        $uri  = "${KA_URL}?type=init&ver=${KA_VERSION}&name=${KA_NAME}&ownerid=${KA_OWNERID}"
        $resp = Invoke-RestMethod -Uri $uri -Method GET -UseBasicParsing -TimeoutSec 10
        if ($resp.success) {
            $script:SessionID = $resp.sessionid
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

# ─── KEYAUTH: LICENSE LOGIN ─────────────────────────────────
function Invoke-KeyAuthLicense {
    param([string]$Key)
    try {
        $hwid = Get-HWID
        $uri  = "${KA_URL}?type=license&key=${Key}&sessionid=${script:SessionID}&name=${KA_NAME}&ownerid=${KA_OWNERID}&hwid=${hwid}"
        $resp = Invoke-RestMethod -Uri $uri -Method GET -UseBasicParsing -TimeoutSec 10
        return $resp
    } catch {
        return [PSCustomObject]@{ success = $false; message = "Connection error: $_" }
    }
}

# ─── UI: BANNER ─────────────────────────────────────────────
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +==================================================+" -ForegroundColor Cyan
    Write-Host "  |  __   __ ___ ___ _____ _________                 |" -ForegroundColor White
    Write-Host "  |  \ \ / /| __| _ \_   _| __\ \/ /                 |" -ForegroundColor White
    Write-Host "  |   \ V / | _||   / | | | _| >  <                  |" -ForegroundColor White
    Write-Host "  |    \_/  |___|_|_\ |_| |___/_/\_\                 |" -ForegroundColor White
    Write-Host "  |                                                  |" -ForegroundColor Cyan
    Write-Host "  |  Powered by InsideX  v$KA_VERSION                        |" -ForegroundColor DarkGray
    Write-Host "  +==================================================+" -ForegroundColor Cyan
    Write-Host ""
}

# ─── UI: READ KEY (masked) ───────────────────────────────────
function Read-LicenseKey {
    Write-Host "  > Enter your License Key : " -NoNewline -ForegroundColor Yellow
    $secure = Read-Host -AsSecureString
    $ptr    = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain  = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    return $plain.Trim()
}

# ─── CORE: LOGIN FLOW ───────────────────────────────────────
function Start-LoginFlow {
    $attempts = 0

    Show-Banner
    Write-Host "  Connecting to CenterX..." -ForegroundColor DarkGray
    $initOK = Invoke-KeyAuthInit
    if (-not $initOK) {
        Write-Host ""
        Write-Host "  [!] Failed to connect to CenterX server." -ForegroundColor Red
        Write-Host "  [!] Check your internet connection and try again." -ForegroundColor Red
        Write-Host ""
        Start-Sleep -Seconds 3
        exit 1
    }

    while ($attempts -lt $MAX_ATTEMPTS) {
        Show-Banner
        $remaining = $MAX_ATTEMPTS - $attempts
        Write-Host "  Attempts remaining: " -NoNewline -ForegroundColor DarkGray
        Write-Host $remaining -ForegroundColor Yellow
        Write-Host ""

        if ($attempts -gt 0) {
            Write-Host "  [X] Invalid key. Please try again." -ForegroundColor Red
            Write-Host ""
        }

        $key = Read-LicenseKey

        if ([string]::IsNullOrWhiteSpace($key)) {
            $attempts++
            continue
        }

        Write-Host ""
        Write-Host "  Validating key..." -ForegroundColor DarkGray

        $result = Invoke-KeyAuthLicense -Key $key
        $attempts++

        if ($result.success) {
            return $result
        } else {
            Write-Host ""
            Write-Host "  [!] $($result.message)" -ForegroundColor Red

            # Re-init session for next attempt
            $script:SessionID = ""
            $initOK = Invoke-KeyAuthInit
            if (-not $initOK) { break }
        }
    }

    Show-Banner
    Write-Host "  +---------------------------------------+" -ForegroundColor Red
    Write-Host "  |  Access Denied - Too many attempts.   |" -ForegroundColor Red
    Write-Host "  +---------------------------------------+" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

# ─── POST-LOGIN: DASHBOARD ──────────────────────────────────
function Show-Dashboard {
    param($AuthResult)

    $username = if ($AuthResult.info.username) { $AuthResult.info.username } else { "N/A" }
    $subname  = if ($AuthResult.info.subscriptions) {
        ($AuthResult.info.subscriptions | Select-Object -First 1).subscription
    } else { "N/A" }
    $expiry   = if ($AuthResult.info.subscriptions) {
        $unixExp = ($AuthResult.info.subscriptions | Select-Object -First 1).expiry
        if ($unixExp) {
            [DateTimeOffset]::FromUnixTimeSeconds([long]$unixExp).LocalDateTime.ToString("dd/MM/yyyy HH:mm")
        } else { "Never" }
    } else { "N/A" }
    $createdate = if ($AuthResult.info.createdate) {
        [DateTimeOffset]::FromUnixTimeSeconds([long]$AuthResult.info.createdate).LocalDateTime.ToString("dd/MM/yyyy")
    } else { "N/A" }

    Show-Banner
    Write-Host "  +-------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  [OK] Authentication Successful           |" -ForegroundColor Green
    Write-Host "  |  User    : " -NoNewline -ForegroundColor Green
    Write-Host $username -NoNewline -ForegroundColor White
    Write-Host "                              |" -ForegroundColor Green
    Write-Host "  |  Sub     : " -NoNewline -ForegroundColor Green
    Write-Host $subname -NoNewline -ForegroundColor Cyan
    Write-Host "                              |" -ForegroundColor Green
    Write-Host "  |  Expires : $expiry                |" -ForegroundColor Green
    Write-Host "  |  Created : $createdate                         |" -ForegroundColor Green
    Write-Host "  +-------------------------------------------+" -ForegroundColor Green
    Write-Host ""

    Write-Host "  +-------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  Available Features                       |" -ForegroundColor Cyan
    Write-Host "  |  [1] x                   |" -ForegroundColor Cyan
    Write-Host "  |  [2] x                       |" -ForegroundColor Cyan
    Write-Host "  |  [3] x                 |" -ForegroundColor Cyan
    Write-Host "  |  [0] Exit                                 |" -ForegroundColor Cyan
    Write-Host "  +-------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    do {
        Write-Host "  > Select option: " -NoNewline -ForegroundColor Yellow
        $choice = Read-Host

        switch ($choice) {
            "1" { Show-SystemInfo }
            "2" { Show-NetworkStatus }
            "3" { Show-AdvancedDiag }
            "0" {
                Write-Host ""
                Write-Host "  Goodbye. Session ended." -ForegroundColor DarkGray
                Write-Host ""
                exit 0
            }
            default { Write-Host "  [X] Invalid option." -ForegroundColor Red }
        }
        Write-Host ""
    } while ($true)
}

# ─── FEATURE: SYSTEM INFO ───────────────────────────────────
function Show-SystemInfo {
    Write-Host ""
    Write-Host "  -- System Information --------------------------" -ForegroundColor Cyan
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $ram = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    Write-Host "  OS      : $($os.Caption)"
    Write-Host "  CPU     : $cpu"
    Write-Host "  RAM     : ${ram} GB"
    Write-Host "  Host    : $env:COMPUTERNAME"
    Write-Host "  User    : $env:USERNAME"
    Write-Host "  HWID    : $(Get-HWID)"
    Write-Host "  ------------------------------------------------"
}

# ─── FEATURE: NETWORK STATUS ────────────────────────────────
function Show-NetworkStatus {
    Write-Host ""
    Write-Host "  -- Network Status ------------------------------" -ForegroundColor Cyan
    $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike "127.*" } |
                Select-Object -First 3
    foreach ($a in $adapters) {
        Write-Host "  Interface : $($a.InterfaceAlias)"
        Write-Host "  IP        : $($a.IPAddress)"
        Write-Host "  ----------------------------------------"
    }
    $ping   = Test-Connection "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
    $status = if ($ping) { "Online"  } else { "Offline" }
    $color  = if ($ping) { "Green"   } else { "Red"     }
    Write-Host "  Internet  : " -NoNewline
    Write-Host $status -ForegroundColor $color
    Write-Host "  ------------------------------------------------"
}

# ─── FEATURE: ADVANCED DIAGNOSTICS ─────────────────────────
function Show-AdvancedDiag {
    Write-Host ""
    Write-Host "  -- Advanced Diagnostics ------------------------" -ForegroundColor Yellow
    $procs  = (Get-Process).Count
    $disk   = Get-PSDrive C | Select-Object Used, Free
    $usedGB = [math]::Round($disk.Used / 1GB, 2)
    $freeGB = [math]::Round($disk.Free / 1GB, 2)
    Write-Host "  Running Processes : $procs"
    Write-Host "  Disk C: Used      : ${usedGB} GB"
    Write-Host "  Disk C: Free      : ${freeGB} GB"
    Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host "  Uptime            : $([math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours,1)) hours"
    Write-Host "  ------------------------------------------------"
}

# ════════════════════════════════════════════════════════════
#  ENTRY POINT
# ════════════════════════════════════════════════════════════
$authResult = Start-LoginFlow
Show-Dashboard -AuthResult $authResult