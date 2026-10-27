# cpu_sample.ps1 <name> <seconds> —— 采样进程 CPU 占比
param([string]$Name = 'runtime_check', [int]$Secs = 5)
$p = Get-Process $Name -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Host 'not running'; exit 1 }
$c1 = $p.TotalProcessorTime.TotalSeconds
Start-Sleep -Seconds $Secs
$p.Refresh()
$c2 = $p.TotalProcessorTime.TotalSeconds
$cpu = [math]::Round(($c2 - $c1) / $Secs * 100, 1)
$cores = [Environment]::ProcessorCount
Write-Host "$Name CPU%: $cpu (of 1 core=${cores} logical)"
