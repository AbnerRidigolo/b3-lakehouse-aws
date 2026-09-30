# Offline only: no credential reads, installation or AWS API calls.
$ErrorActionPreference = 'Stop'
$results = @()
$toolsToCheck = @(
    @{ Name = 'Git'; Command = 'git'; Arguments = @('--version') },
    @{ Name = 'Python'; Command = 'python'; Arguments = @('--version') },
    @{ Name = 'Terraform'; Command = 'terraform'; Arguments = @('version') },
    @{ Name = 'Docker CLI'; Command = 'docker'; Arguments = @('--version') }
)
foreach ($tool in $toolsToCheck) {
    $resolved = Get-Command $tool.Command -ErrorAction SilentlyContinue
    if (-not $resolved) {
        $results += [pscustomobject]@{ Tool = $tool.Name; Status = 'MISSING'; Version = '' }
        continue
    }
    try {
        $versionOutput = & $resolved.Source @($tool.Arguments) 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Version check failed' }
        $versionLine = $versionOutput | Where-Object { $_.ToString() -match '^(git version|Python |Terraform v|Docker version)' } | Select-Object -First 1
        if (-not $versionLine) { throw 'Version not recognized' }
        $results += [pscustomobject]@{ Tool = $tool.Name; Status = 'OK'; Version = $versionLine.ToString() }
    } catch {
        $results += [pscustomobject]@{ Tool = $tool.Name; Status = 'BROKEN'; Version = '' }
    }
}
$awsBinary = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'
if (-not (Test-Path -LiteralPath $awsBinary)) {
    $resolvedAws = Get-Command aws -ErrorAction SilentlyContinue
    $awsBinary = if ($resolvedAws) { $resolvedAws.Source } else { $null }
}
if ($awsBinary) {
    try {
        $awsVersion = & $awsBinary --version 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'AWS version check failed' }
        $versionText = ($awsVersion | Select-Object -First 1).ToString()
        $status = if ($versionText -match '^aws-cli/2\.') { 'OK' } else { 'NEEDS_V2' }
        $results += [pscustomobject]@{ Tool = 'AWS CLI v2'; Status = $status; Version = $versionText }
    } catch {
        $results += [pscustomobject]@{ Tool = 'AWS CLI v2'; Status = 'BROKEN'; Version = '' }
    }
} else {
    $results += [pscustomobject]@{ Tool = 'AWS CLI v2'; Status = 'MISSING'; Version = '' }
}
$results | Format-Table -AutoSize
Write-Output 'Offline check only. SSO authentication and cloud access were not tested.'
if (@($results | Where-Object { $_.Status -ne 'OK' }).Count -gt 0) { exit 1 }
