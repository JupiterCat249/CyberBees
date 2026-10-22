<#
  qc.ps1 —— 电子蜂质量门禁唯一入口（判定权归程序，不依赖 AI）

  兼容：Windows PowerShell 5.1+（本机无 pwsh；脚本以 UTF-8 BOM 保存）
  子命令：
    all       跑四道闸并与基线比较（只判不改）—— 默认
    lint / arch / signals / test   单闸信息性运行（退出码恒 0）
    report    读基线并打印债务曲线（不跑闸）
    snapshot  跑全闸 + 无上升项则写回基线（迭代收尾用）
    import    一次性：注册 addon 的 class_name（新增/升级 GUT 后必跑）
    setup     一次性：建 venv、装 pinned 依赖、下载 GUT、写 local.json

  退出码：0 通过；1 上升项或测试失败；2 环境缺失
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('all', 'lint', 'arch', 'signals', 'test', 'report', 'snapshot', 'import', 'setup')]
    [string]$Command = 'all',

    [string]$Iteration = ''
)

$ErrorActionPreference = 'Continue'
# 控制台与子进程统一 UTF-8，否则中文输出在 5.1 下变乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$env:PYTHONIOENCODING = 'utf-8'   # 原生程序写 stderr 时 Stop 模式会误判；判定一律靠退出码

$QcRoot     = $PSScriptRoot
$Repo       = (Resolve-Path (Join-Path $QcRoot '..')).Path
$Out        = Join-Path $QcRoot 'out'
$Venv       = Join-Path $QcRoot '.venv'
$Py         = Join-Path $Venv 'Scripts\python.exe'
$Baseline   = Join-Path $QcRoot 'baseline.json'
$CountsFile = Join-Path $Out 'counts.json'
$RulesFile  = Join-Path $QcRoot 'config\arch_rules.json'
$LocalCfg   = Join-Path $QcRoot 'config\local.json'

$GdtoolkitVersion = '4.5.0'
$GdcruiserVersion = '1.8.0'
$GutVersion       = '9.6.1'

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$script:Counts = [ordered]@{}

function Add-Count([string]$Key, $Value) { $script:Counts[$Key] = [int]$Value }

function Get-GodotBin {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }
    if (Test-Path $LocalCfg) {
        $cfg = Get-Content $LocalCfg -Raw | ConvertFrom-Json
        if ($cfg.godot_bin -and (Test-Path $cfg.godot_bin)) { return $cfg.godot_bin }
    }
    $known = @(
        'E:\Godot_v4.7.2_stable\Godot_v4.7.2-stable_win64_console.exe',
        'E:\Godot_v4.7.2_stable\Godot_v4.7.2-stable_win64.exe'
    )
    foreach ($k in $known) { if (Test-Path $k) { return $k } }
    return $null
}

function Get-SourceFiles {
    $exclude = '\\addons\\|\\\.godot\\|\\archive\\|\\verification\\|\\tools\\|\\qc\\'
    @(Get-ChildItem -Path $Repo -Filter *.gd -Recurse -File |
        Where-Object { $_.FullName -notmatch $exclude } |
        ForEach-Object { $_.FullName })
}

function Get-TestFiles {
    $t = Join-Path $Repo 'tests'
    if (-not (Test-Path $t)) { return @() }
    @(Get-ChildItem -Path $t -Filter *.gd -Recurse -File | ForEach-Object { $_.FullName })
}

function Assert-Python {
    if (-not (Test-Path $Py)) {
        Write-Host '[qc] 缺少 Python 环境（qc/.venv）。先跑： powershell -File qc/qc.ps1 setup' -ForegroundColor Yellow
        exit 2
    }
}

function Invoke-Lint {
    Assert-Python
    $gdlint = Join-Path $Venv 'Scripts\gdlint.exe'
    if (-not (Test-Path $gdlint)) { Write-Host '[qc] gdlint 缺失：跑 setup' -ForegroundColor Yellow; exit 2 }

    $files = Get-SourceFiles
    $log = Join-Path $Out 'lint.log'
    # gdlint 只从**当前目录**向上找 .gdlintrc —— 必须在仓根执行，否则配置不生效（实测踩到）
    Push-Location $Repo
    try {
        $raw = @(& $gdlint @files 2>&1 | ForEach-Object { $_.ToString() })
    } finally {
        Pop-Location
    }
    $raw | Set-Content -Path $log -Encoding UTF8

    $byRule = @{}
    $total = 0
    foreach ($line in $raw) {
        if ($line -match '\.gd:[0-9]+: Error: .*\((?<rule>[a-z0-9\-]+)\)\s*$') {
            $total = $total + 1
            $r = $matches['rule']
            if ($byRule.ContainsKey($r)) { $byRule[$r] = $byRule[$r] + 1 } else { $byRule[$r] = 1 }
        }
    }
    foreach ($k in ($byRule.Keys | Sort-Object)) { Add-Count ('lint:' + $k) $byRule[$k] }
    Add-Count 'lint:total' $total
    $n = $files.Count
    Write-Host ('[qc] lint   files={0}  problems={1}  (明细 {2})' -f $n, $total, $log)
    return ($total -eq 0)
}

function Invoke-Arch {
    Assert-Python
    $cruiser = Join-Path $Venv 'Scripts\gdcruiser.exe'
    if (-not (Test-Path $cruiser)) { Write-Host '[qc] gdcruiser 缺失：跑 setup' -ForegroundColor Yellow; exit 2 }

    $graph = Join-Path $Out 'graph.json'
    $archOut = Join-Path $Out 'arch.json'
    & $cruiser $Repo -f json --exclude addons --exclude archive --exclude '\.godot' --exclude qc --exclude tests -o $graph 2>&1 | Out-Null
    & $Py (Join-Path $QcRoot 'lib\arch_check.py') --graph $graph --rules $RulesFile --out $archOut | ForEach-Object { Write-Host ('[qc] ' + $_) }

    $arch = Get-Content $archOut -Raw | ConvertFrom-Json
    Add-Count 'arch:cycles' $arch.cycles
    Add-Count 'arch:layer_violations' $arch.layer_violations
    Add-Count 'arch:unresolved_edges' $arch.unresolved
    return (([int]$arch.cycles -eq 0) -and ([int]$arch.layer_violations -eq 0) -and ([int]$arch.unresolved -eq 0))
}

function Invoke-Signals {
    Assert-Python
    $sigOut = Join-Path $Out 'signals.json'
    & $Py (Join-Path $QcRoot 'lib\signals_check.py') --repo $Repo --out $sigOut | ForEach-Object { Write-Host ('[qc] ' + $_) }

    $sig = Get-Content $sigOut -Raw | ConvertFrom-Json
    $dead = @($sig.dead).Count
    $unsub = @($sig.unsubscribed).Count
    $unemit = @($sig.unemitted).Count
    Add-Count 'signals:problems' $sig.problems
    Add-Count 'signals:dead' $dead
    Add-Count 'signals:unsubscribed' $unsub
    Add-Count 'signals:unemitted' $unemit
    Add-Count 'signals:undetectable' ([int]$sig.undetectable_emit + [int]$sig.undetectable_connect)
    Add-Count 'signals:declared' $sig.declared_signals
    return ([int]$sig.problems -eq 0)
}

function Invoke-Test {
    $files = Get-TestFiles
    if ($files.Count -eq 0) {
        Add-Count 'test:passing' 0
        Add-Count 'test:asserts' 0
        Add-Count 'test:failures' 0
        Write-Host '[qc] test   无 tests/*.gd —— 跳过（回归闸尚未铺设）'
        return $true
    }

    $godot = Get-GodotBin
    if (-not $godot) { Write-Host '[qc] 找不到 Godot：设 GODOT_BIN 或写 qc/config/local.json' -ForegroundColor Yellow; exit 2 }
    $gut = Join-Path $Repo 'addons\gut\gut_cmdln.gd'
    if (-not (Test-Path $gut)) { Write-Host '[qc] 缺少 addons/gut：跑 setup' -ForegroundColor Yellow; exit 2 }

    $log = Join-Path $Out 'gut.log'
    $raw = @(& $godot --headless --path $Repo -s 'addons/gut/gut_cmdln.gd' -gdir='res://tests' -gexit 2>&1 | ForEach-Object { $_.ToString() })
    $raw | Set-Content -Path $log -Encoding UTF8
    $text = ($raw -join ' ')

    $harnessErrors = 0
    if ($text -match 'have not been imported') { $harnessErrors = 1; Write-Host '[qc] GUT class_name 未注册 —— 先跑 qc/qc.ps1 import（新增/升级 addon 后必做）' -ForegroundColor Yellow }
    if ($text -notmatch 'Passing Tests') { $harnessErrors = 1 }

    $passing = 0; $failing = 0; $asserts = 0
    if ($text -match 'Passing Tests\s+(\d+)') { $passing = [int]$matches[1] }
    if ($text -match 'Failing Tests\s+(\d+)') { $failing = [int]$matches[1] }
    if ($text -match 'Asserts\s+(\d+)') { $asserts = [int]$matches[1] }

    Add-Count 'test:passing' $passing
    Add-Count 'test:asserts' $asserts
    Add-Count 'test:failures' $failing
    Add-Count 'test:harness_errors' $harnessErrors
    Write-Host ('[qc] test   passing={0} failing={1} asserts={2}  (明细 {3})' -f $passing, $failing, $asserts, $log)
    if ($harnessErrors -ne 0) { Write-Host '[qc] 回归闸未能正常执行（不是测试失败），见上方提示与 gut.log' -ForegroundColor Red }
    return (($failing -eq 0) -and ($harnessErrors -eq 0))
}

function Invoke-Ratchet([switch]$Update) {
    Assert-Python
    $json = $script:Counts | ConvertTo-Json -Depth 4
    $json | Out-File -FilePath $CountsFile -Encoding utf8
    $ratchetArgs = @((Join-Path $QcRoot 'lib\ratchet.py'), '--baseline', $Baseline, '--current', $CountsFile)
    if ($Iteration -ne '') { $ratchetArgs = $ratchetArgs + @('--iteration', $Iteration) }
    if ($Update) { $ratchetArgs = $ratchetArgs + '--update' }
    & $Py @ratchetArgs | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

function Invoke-Gates {
    Write-Host ''
    Write-Host '=== qc · 四道闸 ===' -ForegroundColor Cyan
    Invoke-Lint | Out-Null
    Invoke-Arch | Out-Null
    Invoke-Signals | Out-Null
    Invoke-Test | Out-Null
    Write-Host ''
}

function Show-Report {
    if (-not (Test-Path $Baseline)) { Write-Host '[qc] 还没有基线：先跑 snapshot' -ForegroundColor Yellow; return }
    $doc = Get-Content $Baseline -Raw | ConvertFrom-Json
    Write-Host ('基线迭代：' + $doc.iteration + '   更新于：' + $doc.updated)
    Write-Host ''
    Write-Host '当前基线计数：'
    $doc.counts.PSObject.Properties | Sort-Object Name | ForEach-Object {
        Write-Host ('  {0,-34} {1}' -f $_.Name, $_.Value)
    }
    Write-Host ''
    Write-Host '债务曲线（每次 snapshot 追加一行）：'
    Write-Host ('  {0,-12} {1,-12} {2,-8} {3,-8} {4,-8} {5,-8} {6}' -f 'iteration', 'date', 'lint', 'cycles', 'signals', 'tests', 'asserts')
    foreach ($h in $doc.history) {
        $c = $h.counts
        $lint = 0; $cyc = 0; $sig = 0; $tp = 0; $ta = 0
        if ($null -ne $c.'lint:total') { $lint = $c.'lint:total' }
        if ($null -ne $c.'arch:cycles') { $cyc = $c.'arch:cycles' }
        if ($null -ne $c.'signals:problems') { $sig = $c.'signals:problems' }
        if ($null -ne $c.'test:passing') { $tp = $c.'test:passing' }
        if ($null -ne $c.'test:asserts') { $ta = $c.'test:asserts' }
        Write-Host ('  {0,-12} {1,-12} {2,-8} {3,-8} {4,-8} {5,-8} {6}' -f $h.iteration, $h.date, $lint, $cyc, $sig, $tp, $ta)
    }
}

function Invoke-Import {
    $godot = Get-GodotBin
    if (-not $godot) { Write-Host '[qc] 找不到 Godot' -ForegroundColor Yellow; exit 2 }
    $proj = Join-Path $Repo 'project.godot'
    $before = (Get-FileHash $proj -Algorithm SHA256).Hash
    Write-Host '[qc] --import（注册 addon class_name，约 40s）...'
    & $godot --headless --path $Repo --import 2>&1 | Select-Object -Last 6 | ForEach-Object { Write-Host ('[qc] ' + $_) }
    $after = (Get-FileHash $proj -Algorithm SHA256).Hash
    if ($before -ne $after) {
        Write-Host '[qc] 注意：project.godot 在 import 期间被改写（编辑器/插件行为），按 T11 纪律核对后经 MCP 恢复。' -ForegroundColor Yellow
        Write-Host ('     before=' + $before + '  after=' + $after)
    } else {
        Write-Host '[qc] project.godot 未被改动 OK'
    }
}

function Invoke-Setup {
    Write-Host '[qc] setup 开始'
    if (-not (Test-Path $Py)) {
        Write-Host '[qc] 创建 venv（Python 3.14）...'
        & py -3.14 -m venv $Venv
    }
    Write-Host '[qc] 安装 pinned 依赖 ...'
    & $Py -m pip install --quiet --disable-pip-version-check ('gdtoolkit==' + $GdtoolkitVersion) ('gdcruiser==' + $GdcruiserVersion)
    if ($LASTEXITCODE -ne 0) { Write-Host '[qc] pip 安装失败' -ForegroundColor Red; exit 2 }

    $gutDir = Join-Path $Repo 'addons\gut'
    if (-not (Test-Path $gutDir)) {
        Write-Host ('[qc] 下载 GUT ' + $GutVersion + ' ...')
        $zip = Join-Path $env:TEMP ('gut-' + $GutVersion + '.zip')
        Invoke-WebRequest ('https://codeload.github.com/bitwes/Gut/zip/refs/tags/v' + $GutVersion) -OutFile $zip -UseBasicParsing
        $tmp = Join-Path $env:TEMP ('gut-' + $GutVersion)
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $inner = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
        $addons = Join-Path $Repo 'addons'
        New-Item -ItemType Directory -Force -Path $addons | Out-Null
        Copy-Item (Join-Path $inner 'addons\gut') -Destination $addons -Recurse -Force
        Write-Host '[qc] GUT 已落到 addons/gut'
    }

    $godot = Get-GodotBin
    if ($godot) {
        $obj = New-Object PSObject -Property @{ godot_bin = $godot }
        ($obj | ConvertTo-Json) | Out-File -FilePath $LocalCfg -Encoding utf8
        Write-Host ('[qc] Godot: ' + $godot)
    } else {
        Write-Host '[qc] 未找到 Godot：设 GODOT_BIN 或写 qc/config/local.json' -ForegroundColor Yellow
    }
    Write-Host '[qc] setup 完成。下一步： import -> snapshot'
}

switch ($Command) {
    'lint'     { Invoke-Lint | Out-Null; exit 0 }
    'arch'     { Invoke-Arch | Out-Null; exit 0 }
    'signals'  { Invoke-Signals | Out-Null; exit 0 }
    'test'     { Invoke-Test | Out-Null; exit 0 }
    'report'   { Show-Report; exit 0 }
    'import'   { Invoke-Import; exit 0 }
    'setup'    { Invoke-Setup; exit 0 }
    'all'      { Invoke-Gates; exit (Invoke-Ratchet) }
    'snapshot' { Invoke-Gates; exit (Invoke-Ratchet -Update) }
}
exit 0
