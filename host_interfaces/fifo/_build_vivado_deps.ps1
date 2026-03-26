$ErrorActionPreference = 'Stop'

$rootsDir = 'C:\Users\ssantolu\Documents\LV Projects\Macallan Projects\FIFOs\ProjectExportForVivado\FIFO_VPE_D\NIProtectedFiles'
$encDir = 'C:\dev\github8\hdl-shared\deps\flexrio-deps\encrypted'
$outFile = 'C:\dev\github8\hdl-shared\host_interfaces\fifo\vivadoprojectdeps.txt'
$outDir = Split-Path -Parent $outFile
$baseUri = New-Object System.Uri(($outDir.TrimEnd('\\') + '\\'))

# Build local symbol tables from source NIProtectedFiles.
$srcEntityToFile = @{}
$srcPackageToFile = @{}
Get-ChildItem -LiteralPath $rootsDir -Recurse -Filter *.vhd | ForEach-Object {
  $fp = $_.FullName
  $txt = Get-Content -Raw -LiteralPath $fp

  [regex]::Matches($txt, '(?im)^\s*entity\s+([A-Za-z][A-Za-z0-9_]*)\s+is\b') | ForEach-Object {
    $n = $_.Groups[1].Value
    if (-not $srcEntityToFile.ContainsKey($n)) { $srcEntityToFile[$n] = $fp }
  }

  [regex]::Matches($txt, '(?im)^\s*package\s+([A-Za-z][A-Za-z0-9_]*)\s+is\b') | ForEach-Object {
    $n = $_.Groups[1].Value
    if (-not $srcPackageToFile.ContainsKey($n)) { $srcPackageToFile[$n] = $fp }
  }
}

function Get-FileDeps([string]$fp) {
  $t = Get-Content -Raw -LiteralPath $fp
  $entities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $packages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  [regex]::Matches($t, '(?im)\bentity\s+work\.([A-Za-z][A-Za-z0-9_]*)\b') | ForEach-Object {
    [void]$entities.Add($_.Groups[1].Value)
  }
  [regex]::Matches($t, '(?im)^\s*use\s+work\.([A-Za-z][A-Za-z0-9_]*)\.all\s*;') | ForEach-Object {
    [void]$packages.Add($_.Groups[1].Value)
  }

  [pscustomobject]@{ Entities = $entities; Packages = $packages }
}

# Resolve transitive symbols from root entities.
$needEntities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$needPackages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queue = [System.Collections.Generic.Queue[string]]::new()
$visitedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($root in @('DmaPortCommIfcInputFifoInterface', 'DmaPortCommIfcOutputFifoInterface')) {
  if ($srcEntityToFile.ContainsKey($root)) {
    $queue.Enqueue($root)
    [void]$needEntities.Add($root)
  }
}

while ($queue.Count -gt 0) {
  $e = $queue.Dequeue()
  if (-not $srcEntityToFile.ContainsKey($e)) { continue }

  $ef = $srcEntityToFile[$e]
  if ($visitedFiles.Contains($ef)) { continue }
  [void]$visitedFiles.Add($ef)

  $deps = Get-FileDeps $ef

  foreach ($p in $deps.Packages) {
    if ($needPackages.Add($p)) {
      if ($srcPackageToFile.ContainsKey($p)) {
        $pf = $srcPackageToFile[$p]
        if (-not $visitedFiles.Contains($pf)) {
          [void]$visitedFiles.Add($pf)
          $pdeps = Get-FileDeps $pf
          foreach ($pp in $pdeps.Packages) { [void]$needPackages.Add($pp) }
          foreach ($pe in $pdeps.Entities) {
            if ($needEntities.Add($pe) -and $srcEntityToFile.ContainsKey($pe)) {
              $queue.Enqueue($pe)
            }
          }
        }
      }
    }
  }

  foreach ($de in $deps.Entities) {
    if ($needEntities.Add($de) -and $srcEntityToFile.ContainsKey($de)) {
      $queue.Enqueue($de)
    }
  }
}

# Build encrypted symbol indexes.
$encEntityMap = @{}
$encPackageMap = @{}
Get-ChildItem -LiteralPath $encDir -Recurse -Filter *.vhd | ForEach-Object {
  $fp = $_.FullName
  $txt = Get-Content -Raw -LiteralPath $fp

  [regex]::Matches($txt, '(?im)^\s*entity\s+([A-Za-z][A-Za-z0-9_]*)\s+is\b') | ForEach-Object {
    $key = $_.Groups[1].Value.ToLowerInvariant()
    if (-not $encEntityMap.ContainsKey($key)) {
      $encEntityMap[$key] = New-Object System.Collections.Generic.List[string]
    }
    $encEntityMap[$key].Add($fp)
  }

  [regex]::Matches($txt, '(?im)^\s*package\s+([A-Za-z][A-Za-z0-9_]*)\s+is\b') | ForEach-Object {
    $key = $_.Groups[1].Value.ToLowerInvariant()
    if (-not $encPackageMap.ContainsKey($key)) {
      $encPackageMap[$key] = New-Object System.Collections.Generic.List[string]
    }
    $encPackageMap[$key].Add($fp)
  }
}

$allRelPaths = New-Object System.Collections.Generic.List[string]
$missingEntities = New-Object System.Collections.Generic.List[string]
$missingPackages = New-Object System.Collections.Generic.List[string]

foreach ($e in ($needEntities | Sort-Object)) {
  $k = $e.ToLowerInvariant()
  if ($encEntityMap.ContainsKey($k)) {
    foreach ($m in ($encEntityMap[$k] | Sort-Object -Unique)) {
      $u = New-Object System.Uri($m)
      $rel = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($u).ToString()) -replace '\\', '/'
      $allRelPaths.Add($rel)
    }
  } else {
    $missingEntities.Add($e)
  }
}

foreach ($p in ($needPackages | Sort-Object)) {
  $k = $p.ToLowerInvariant()
  if ($encPackageMap.ContainsKey($k)) {
    foreach ($m in ($encPackageMap[$k] | Sort-Object -Unique)) {
      $u = New-Object System.Uri($m)
      $rel = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($u).ToString()) -replace '\\', '/'
      $allRelPaths.Add($rel)
    }
  } else {
    $missingPackages.Add($p)
  }
}

$final = $allRelPaths | Sort-Object -Unique
Set-Content -LiteralPath $outFile -Value $final

Write-Output ('WROTE_PATHS=' + $final.Count)
Write-Output ('MISSING_ENTITIES=' + $missingEntities.Count)
Write-Output ('MISSING_PACKAGES=' + $missingPackages.Count)
if ($missingEntities.Count -gt 0) {
  Write-Output 'MISSING_ENTITY_NAMES:'
  $missingEntities | Sort-Object | ForEach-Object { Write-Output $_ }
}
if ($missingPackages.Count -gt 0) {
  Write-Output 'MISSING_PACKAGE_NAMES:'
  $missingPackages | Sort-Object | ForEach-Object { Write-Output $_ }
}
