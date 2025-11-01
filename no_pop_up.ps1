param(
  [string]$EnvPath = ".\.env",
  [switch]$UseSsl,                 # Use HTTPS WinRM endpoint (recommended for Basic/NTLM across boundaries)
  [switch]$InsecureSkipCertCheck   # If using HTTPS with self-signed certs, skip CA/CN/revocation checks
)

# Make the run fully non-interactive
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$ConfirmPreference     = 'None'

function Load-DotEnv {
  param([string]$Path)
  if (-not (Test-Path -Path $Path)) { throw "Missing .env file at $Path" }
  $map = @{}
  foreach ($line in Get-Content -Path $Path) {
    $l = $line.Trim()
    if (-not $l -or $l.StartsWith('#')) { continue }
    $idx = $l.IndexOf('=')
    if ($idx -lt 0) { continue }
    $key = $l.Substring(0, $idx).Trim()
    $val = $l.Substring($idx + 1).Trim()
    if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Trim('"') }
    elseif ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Trim("'") }
    $map[$key] = $val
  }
  return $map
}

# Read .env without prompting
$envVars = Load-DotEnv -Path $EnvPath
$server  = $envVars.WIN_HOST
$user    = $envVars.WIN_USER
$pass    = $envVars.WIN_PASS

if (-not $server -or -not $user -or -not $pass) {
  throw "WIN_HOST, WIN_USER, and WIN_PASS must be set in $EnvPath"
}

# Build PSCredential silently from plain text password
$secure = ConvertTo-SecureString -String $pass -AsPlainText -Force
$cred   = [pscredential]::new($user, $secure)

# Session options (optionally skip cert checks for self-signed HTTPS)
$sessionOption = if ($UseSsl -and $InsecureSkipCertCheck) {
  New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -OperationTimeout 120000
} else {
  New-PSSessionOption -OperationTimeout 120000
}

# Invoke remote command with no confirmations or prompts
$icParams = @{
  ComputerName   = $server
  Credential     = $cred
  SessionOption  = $sessionOption
  ErrorAction    = 'Stop'
  ScriptBlock    = {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    [pscustomobject]@{
      ComputerName   = $env:COMPUTERNAME
      LastBootUpTime = $os.LastBootUpTime
      Uptime         = (Get-Date) - $os.LastBootUpTime
    }
  }
}

if ($UseSsl) { $icParams.UseSSL = $true }

$result = Invoke-Command @icParams
$result | Format-List
