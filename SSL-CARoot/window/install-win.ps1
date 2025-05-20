<#
.SYNOPSIS
    Imports a CA Root certificate into Windows and Firefox trust stores.
.DESCRIPTION
    This script imports a specified CA Root certificate (.crt file) into the Windows system trust store
    and also imports it into the Firefox browser trust store.
.PARAMETER CertPath
    Full path to the CA Root certificate file (.crt format)
.PARAMETER FirefoxProfilePath
    Path to Firefox profile directory (optional - script will attempt to locate it if not provided)
.EXAMPLE
    .\Import-CARootCertificate.ps1 -CertPath "C:\certs\my-ca-root.crt"
.NOTES
    Requires administrative privileges for Windows trust store import
    Firefox must be closed during the import process
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$CertPath,
    
    [Parameter(Mandatory=$false)]
    [string]$FirefoxProfilePath
)

function Import-ToWindowsTrustStore {
    param (
        [string]$CertPath
    )
    
    Write-Host "Importing certificate to Windows trust store..." -ForegroundColor Green
    
    # Check if file exists
    if (-not (Test-Path $CertPath)) {
        Write-Host "ERROR: Certificate file not found at path: $CertPath" -ForegroundColor Red
        return $false
    }
    
    try {
        # Import to Root CA store
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("ROOT", "LocalMachine")
        $store.Open("ReadWrite")
        $store.Add($cert)
        $store.Close()
        
        Write-Host "Successfully imported certificate to Windows Root CA store." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "ERROR: Failed to import certificate to Windows trust store: $_" -ForegroundColor Red
        return $false
    }
}

function Find-FirefoxProfiles {
    $profilesPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
    
    if (Test-Path $profilesPath) {
        $profiles = Get-ChildItem -Path $profilesPath -Directory
        return $profiles
    }
    
    return $null
}

function Import-ToFirefoxTrustStore {
    param (
        [string]$CertPath,
        [string]$ProfilePath
    )
    
    Write-Host "Importing certificate to Firefox trust store..." -ForegroundColor Green
    
    # Check if Firefox is running
    $firefoxProcess = Get-Process -Name "firefox" -ErrorAction SilentlyContinue
    if ($firefoxProcess) {
        Write-Host "WARNING: Firefox is currently running. Please close Firefox before continuing." -ForegroundColor Yellow
        $confirmation = Read-Host "Do you want to attempt to close Firefox? (y/n)"
        if ($confirmation -eq 'y') {
            $firefoxProcess | Stop-Process -Force
            Start-Sleep -Seconds 2
        } else {
            Write-Host "Please close Firefox manually and run this script again." -ForegroundColor Yellow
            return $false
        }
    }
    
    # If profile path is not provided, try to locate it
    if (-not $ProfilePath) {
        $profiles = Find-FirefoxProfiles
        
        if (-not $profiles) {
            Write-Host "ERROR: Firefox profiles not found. Firefox may not be installed or no profiles exist." -ForegroundColor Red
            return $false
        }
        
        if ($profiles.Count -gt 1) {
            Write-Host "Multiple Firefox profiles found. Please select one:" -ForegroundColor Yellow
            for ($i=0; $i -lt $profiles.Count; $i++) {
                Write-Host "[$i] $($profiles[$i].Name)"
            }
            
            $selection = Read-Host "Enter the number of the profile"
            if ($selection -ge 0 -and $selection -lt $profiles.Count) {
                $ProfilePath = $profiles[$selection].FullName
            } else {
                Write-Host "Invalid selection." -ForegroundColor Red
                return $false
            }
        } else {
            $ProfilePath = $profiles[0].FullName
        }
    }
    
    Write-Host "Using Firefox profile: $ProfilePath" -ForegroundColor Green
    
    # Check if cert9.db exists (newer Firefox versions)
    $certDbPath = Join-Path -Path $ProfilePath -ChildPath "cert9.db"
    $certDbExists = Test-Path $certDbPath
    
    # Check if cert8.db exists (older Firefox versions)
    $oldCertDbPath = Join-Path -Path $ProfilePath -ChildPath "cert8.db"
    $oldCertDbExists = Test-Path $oldCertDbPath
    
    if (-not ($certDbExists -or $oldCertDbExists)) {
        Write-Host "ERROR: Firefox certificate database not found in profile." -ForegroundColor Red
        return $false
    }
    
    try {
        # Use NSS tools to import certificate
        # Note: This would require certutil from NSS tools to be available
        # Since we don't have direct access to it, we'll use a Firefox built-in method
        
        # Create a simple Firefox preference file to import the certificate
        $prefPath = Join-Path -Path $env:TEMP -ChildPath "cert_import_prefs.js"
        $prefContent = @"
// Automatically generated by Import-CARootCertificate.ps1
// This file will add a trusted CA certificate to Firefox

// Location of the certificate to import
pref("security.enterprise_roots.enabled", true);
"@
        Set-Content -Path $prefPath -Value $prefContent
        
        $targetPrefsPath = Join-Path -Path $ProfilePath -ChildPath "user.js"
        
        # Backup existing user.js if it exists
        if (Test-Path $targetPrefsPath) {
            Copy-Item -Path $targetPrefsPath -Destination "$targetPrefsPath.backup"
        }
        
        # Append our preferences to user.js
        Add-Content -Path $targetPrefsPath -Value $prefContent
        
        # Copy the certificate to the Firefox profile directory
        $certFileName = Split-Path -Path $CertPath -Leaf
        $targetCertPath = Join-Path -Path $ProfilePath -ChildPath $certFileName
        Copy-Item -Path $CertPath -Destination $targetCertPath
        
        Write-Host @"
Certificate has been prepared for Firefox import.

To complete the Firefox import:
1. Start Firefox
2. Go to Settings (hamburger menu) > Privacy & Security > Certificates > View Certificates
3. In the Certificate Manager, Authorities tab, click on "Import..."
4. Browse to: $targetCertPath
5. Check "Trust this CA to identify websites" and click OK

Alternatively, you can also enable "security.enterprise_roots.enabled" in about:config
to make Firefox use the Windows certificate store.
"@ -ForegroundColor Yellow
        
        return $true
    }
    catch {
        Write-Host "ERROR: Failed to prepare Firefox certificate import: $_" -ForegroundColor Red
        return $false
    }
}

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires administrative privileges to import certificates to the Windows trust store." -ForegroundColor Red
    Write-Host "Please run this script as an administrator." -ForegroundColor Yellow
    exit
}

# Main execution
$windowsResult = Import-ToWindowsTrustStore -CertPath $CertPath
$firefoxResult = Import-ToFirefoxTrustStore -CertPath $CertPath -ProfilePath $FirefoxProfilePath

# Summary
Write-Host "`n----- Import Summary -----" -ForegroundColor Cyan
Write-Host "Certificate Path: $CertPath" -ForegroundColor White
if ($windowsResult) {
    Write-Host "Windows Trust Store: SUCCESS" -ForegroundColor Green
} else {
    Write-Host "Windows Trust Store: FAILED" -ForegroundColor Red
}
if ($firefoxResult) {
    Write-Host "Firefox Trust Store: PREPARED" -ForegroundColor Yellow
} else {
    Write-Host "Firefox Trust Store: FAILED" -ForegroundColor Red
}

if ($firefoxResult) {
    Write-Host "`nNOTE: The Firefox import requires manual steps to complete. See instructions above." -ForegroundColor Yellow
}