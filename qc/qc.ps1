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
    [ValidateSet('all', 'bugbind', 'flaky', 'syncdocs', 'receipt', 'coverage', 'layout', 'lint', 'size', 'arch', 'signals', 'docs', 'test', 'selftest', 'report', 'snapshot', 'import', 'setup', 'artifacts', 'coldstart')]
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
$script:GateFailed = $false

function Add-Count([string]$Key, $Value) { $script:Counts[$Key] = [int]$Value }

function Get-GodotBin {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }
    if (Test-Path $LocalCfg) {
        $cfg = [System.IO.File]::ReadAllText($LocalCfg, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
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
    $exclude = '\\addons\\|\\.godot\\|\\archive\\|\\verification\\|\\tools\\|\\qc\\|\\dev\\'
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
    ## P5（迭代125）：豁免清单对账 —— 实际产出与 qc/config/lint_exemptions.json **双向**必须一致。
    ##   ① 未登记的产出 = 新债；② 未命中的豁免 = 陈旧；③ 日志声明数 ≠ 解析数 = 日志被截断。
    $exemptCfg = Join-Path $QcRoot 'config\lint_exemptions.json'
    $exemptOut = Join-Path $Out 'lint_exempt.json'
    $exemptOk = $true
    if ((Test-Path $exemptCfg) -and (Test-Path $log)) {
        & $Py (Join-Path $QcRoot 'lib\lint_exempt_check.py') --log $log --exemptions $exemptCfg --repo $Repo --out $exemptOut |
            ForEach-Object { Write-Host ('[qc] ' + $_) }
        $exemptOk = ($LASTEXITCODE -eq 0)
        if (Test-Path $exemptOut) {
            $ej = [System.IO.File]::ReadAllText($exemptOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            Add-Count 'lint:exemptions' (@($ej.exemptions).Count)
            Add-Count 'lint:unregistered' (@($ej.unregistered).Count)
        }
    }

    Add-Count 'lint:total' $total
    $n = $files.Count
    Write-Host ('[qc] lint   files={0}  problems={1}  (明细 {2})' -f $n, $total, $log)
    # ⚠️ 不把"有 lint 问题"当硬失败：本仓有 25 条**已裁定接受**的历史债（理由写在迭代记录里），
    #    lint 的增量由棘轮（qc/baseline.json）把关 —— 涨一条就红。
    #    硬失败的闸是那些"零容忍"的：体积门禁 / 加载环 / 信号问题 / 测试失败。
    #    P5：**豁免对账**属零容忍 —— 不一致即判红。
    return $exemptOk
}

function Invoke-Arch {
    Assert-Python
    $cruiser = Join-Path $Venv 'Scripts\gdcruiser.exe'
    if (-not (Test-Path $cruiser)) { Write-Host '[qc] gdcruiser 缺失：跑 setup' -ForegroundColor Yellow; exit 2 }

    $graph = Join-Path $Out 'graph.json'
    $archOut = Join-Path $Out 'arch.json'
    & $cruiser $Repo -f json --exclude addons --exclude archive --exclude '\.godot' --exclude qc --exclude tests --exclude dev -o $graph 2>&1 | Out-Null
    & $Py (Join-Path $QcRoot 'lib\arch_check.py') --graph $graph --rules $RulesFile --out $archOut | ForEach-Object { Write-Host ('[qc] ' + $_) }

    $arch = [System.IO.File]::ReadAllText($archOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Add-Count 'arch:cycles' $arch.cycles
    Add-Count 'arch:type_cycles' $arch.type_cycles
    Add-Count 'arch:layer_violations' $arch.layer_violations
    Add-Count 'arch:unresolved_edges' $arch.unresolved
    return (([int]$arch.cycles -eq 0) -and ([int]$arch.layer_violations -eq 0) -and ([int]$arch.reach_violations -eq 0) -and ([int]$arch.unresolved -eq 0))
}

function Invoke-Signals {
    Assert-Python
    $sigOut = Join-Path $Out 'signals.json'
    $sigAccept = Join-Path $QcRoot 'config\signals_undetectable.json'
    $sigArgs = @((Join-Path $QcRoot 'lib\signals_check.py'), '--repo', $Repo, '--out', $sigOut)
    if (Test-Path $sigAccept) { $sigArgs = $sigArgs + @('--accept', $sigAccept) }
    & $Py @sigArgs | ForEach-Object { Write-Host ('[qc] ' + $_) }

    $sigRc = $LASTEXITCODE
    ## ⚠️ 迭代095 假绿修复：检查器**没跑成**（总线文件被改名 / 崩溃）时不会产出 JSON，
    ##   而此前直接 ReadAllText ⇒ $sig=$null ⇒ [int]$null=0 ⇒ 闸门"全绿"。
    if (-not (Test-Path $sigOut)) {
        Write-Host ("[qc] 信号闸：检查器未产出结果（rc=" + $sigRc + "）—— 判红") -ForegroundColor Red
        return $false
    }
    $sig = $null
    try { $sig = [System.IO.File]::ReadAllText($sigOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $sig = $null }
    if ($null -eq $sig) {
        Write-Host "[qc] 信号闸：结果不是合法 JSON —— 判红" -ForegroundColor Red
        return $false
    }
    $dead = @($sig.dead).Count
    $unsub = @($sig.unsubscribed).Count
    $unemit = @($sig.unemitted).Count
    Add-Count 'signals:problems' $sig.problems
    Add-Count 'signals:dead' $dead
    Add-Count 'signals:unsubscribed' $unsub
    Add-Count 'signals:unemitted' $unemit
    Add-Count 'signals:undetectable' ([int]$sig.undetectable_emit + [int]$sig.undetectable_connect)
    Add-Count 'signals:declared' $sig.declared_signals
    $ok = ([int]$sig.problems -eq 0) -and ($sigRc -eq 0)
    if (-not $ok) {
        Write-Host ("[qc] 信号闸：problems=" + [int]$sig.problems + " rc=" + $sigRc + " —— 判红") -ForegroundColor Red
    }
    return $ok
}


## 文档基线漂移（迭代116）：把《当前状态》的「基线快照」行与 counts.json 对账。
##   ⚠️ 路径相对**游戏仓根**；文档不存在则 skip（便于在其他机器/单独克隆上运行）。
function Invoke-Docs {
    param([switch]$Standalone)
    Assert-Python
    $docOut = Join-Path $Out 'docs.json'
    $docPath = Join-Path $Repo '../../项目规划蓝图/当前状态.md'
    ## 防御（迭代120）：**全闸模式**下本闸必须在回归闸之后 —— 否则 test:* 计数还没入表，会拿 0 去对账。
    ##   ⚠️ 单跑（`qc docs`）时不会跑回归闸 ⇒ 复用上一轮 counts.json 对账，并**明说**这是旧数据。
    $nowCounts = Join-Path $Out 'counts.now.json'
    if (-not $script:Counts.Contains('test:passing')) {
        if ($Standalone -and (Test-Path $CountsFile)) {
            Write-Host '[qc] 单跑 docs：用上一轮 counts.json 对账（全闸模式不允许这样）' -ForegroundColor Yellow
            $nowCounts = $CountsFile
        } else {
            Write-Host '[qc] 文档闸：缺少 test:passing 计数 —— 说明它被排在回归闸之前（顺序错误）' -ForegroundColor Red
            return $false
        }
    } else {
        ## ⚠️ 必须用**本轮内存计数**（迭代120 冷启动实测）：counts.json 是在 Invoke-Ratchet 里才写的，
        ##   早先直接读它会拿到**上一轮**的数字（甚至冷启动时根本不存在 ⇒ 闸判红/崩溃）。
        ($script:Counts | ConvertTo-Json -Depth 4) | Out-File -FilePath $nowCounts -Encoding utf8
    }
    ## ⚠️ 必须用**本轮内存计数**（迭代120 冷启动实测）：counts.json 是在 Invoke-Ratchet 里才写的，
    ##   早先直接读它会拿到**上一轮**的数字（甚至冷启动时根本不存在 ⇒ 闸判红/崩溃）。
    $o = & $Py (Join-Path $QcRoot 'lib\docs_check.py') --counts $nowCounts --doc $docPath --out $docOut 2>&1
    $rc = $LASTEXITCODE
    $o | ForEach-Object { Write-Host ('[qc] ' + $_) }
    Add-Count 'docs:drift' ($(if ($rc -eq 1) { 1 } else { 0 }))
    return ($rc -eq 0)
}
function Invoke-GutRun([string]$GodotBin) {
    return @(& $GodotBin --headless --path $Repo -s 'addons/gut/gut_cmdln.gd' -gdir='res://tests' -gexit '-gjunit_xml_file=res://qc/out/gut.junit.xml' 2>&1 | ForEach-Object { $_.ToString() })
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
    $raw = @(Invoke-GutRun $godot)
    $text = ($raw -join ' ')

    # 自愈：编辑器实例先于 addon 启动时会回写 class 缓存，导致 GUT 报 class_name 未注册。
    # 这是环境问题、不是测试失败 —— 由程序自动重跑一次 --import 再试（人不需要记任何命令）。
    if ($text -match 'have not been imported') {
        Write-Host '[qc] GUT class_name 未注册（编辑器回写了 .godot 缓存）→ 自动 --import 后重试一次' -ForegroundColor Yellow
        $proj = Join-Path $Repo 'project.godot'
        $before = (Get-FileHash $proj -Algorithm SHA256).Hash
        & $godot --headless --path $Repo --import 2>&1 | Out-Null
        $after = (Get-FileHash $proj -Algorithm SHA256).Hash
        if ($before -ne $after) {
            Write-Host '[qc] 注意：import 期间 project.godot 被改写（编辑器/插件行为），按 T11 核对' -ForegroundColor Yellow
        }
        $raw = @(Invoke-GutRun $godot)
        $text = ($raw -join ' ')
    }

    $raw | Set-Content -Path $log -Encoding UTF8

    ## P1（迭代124）：GUT 结果校验 —— 解析错误 / 脚本少加载 一律判红。
    ##   背景：测试文件语法错时 GUT 只是"少加载一个脚本"，passing 变小、退出码仍 0（本会话两次踩到）。
    $gutChk = Join-Path $Out 'gutcheck.json'
    & $Py (Join-Path $QcRoot 'lib\gut_check.py') --log $log --tests-dir (Join-Path $Repo 'tests') --out $gutChk |
        ForEach-Object { Write-Host ('[qc] ' + $_) }
    $gutRc = $LASTEXITCODE

    ## 自愈（迭代161）：目录搬迁/新增脚本后 .godot 的 class_name 缓存会过期，
    ##   GUT 只加载部分脚本（本会话实测 20 → 6），报错形如 "Could not resolve external class member"。
    ##   这不是测试失败，而是缓存问题 ⇒ 自动 --import 后重跑一次；仍不行才判红。
    if (Test-Path $gutChk) {
        $gc0 = [System.IO.File]::ReadAllText($gutChk, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if (([int]$gc0.scripts_loaded) -lt ([int]$gc0.scripts_on_disk)) {
            Write-Host ('[qc] GUT 少加载脚本（{0}/{1}）—— class_name 缓存过期，自动 --import 后重跑一次' -f $gc0.scripts_loaded, $gc0.scripts_on_disk) -ForegroundColor Yellow
            & $godot --headless --path $Repo --import 2>&1 | Out-Null
            $raw = @(Invoke-GutRun $godot)
            $text = ($raw -join ' ')
            $raw | Set-Content -Path $log -Encoding UTF8
            & $Py (Join-Path $QcRoot 'lib\gut_check.py') --log $log --tests-dir (Join-Path $Repo 'tests') --out $gutChk | Out-Null
            $gutRc = $LASTEXITCODE
        }
    }

    $harnessErrors = 0
    if ($gutRc -ne 0) { $harnessErrors = 1 }
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
    if (Test-Path $gutChk) {
        $gc = [System.IO.File]::ReadAllText($gutChk, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Add-Count 'test:scripts_loaded' ([int]$gc.scripts_loaded)
        Add-Count 'test:scripts_on_disk' ([int]$gc.scripts_on_disk)
    }
    ## S2/WS7（迭代159）：测试健康 —— junit 里的单测耗时 + 隔离名单校验
    $healthOut = Join-Path $Out 'health.json'
    $healthCfg = Join-Path $QcRoot 'config\test_health.json'
    $junit = Join-Path $Out 'gut.junit.xml'
    $healthOk = $true
    if (Test-Path $junit) {
        & $Py (Join-Path $QcRoot 'lib\test_health.py') --junit $junit --config $healthCfg --out $healthOut |
            ForEach-Object { Write-Host ('[qc] ' + $_) }
        $healthOk = ($LASTEXITCODE -eq 0)
        if (Test-Path $healthOut) {
            $hj = [System.IO.File]::ReadAllText($healthOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            Add-Count 'test:slowest_ms' $hj.counts.slowest_ms
            Add-Count 'test:total_ms' $hj.counts.total_ms
            Add-Count 'test:quarantined' $hj.counts.quarantined
            Add-Count 'test:health_violations' $hj.counts.health_violations
        }
    } else {
        Write-Host '[qc] 没有 junit（GUT 未生成）—— 健康检查跳过' -ForegroundColor Yellow
    }
    Write-Host ('[qc] test   passing={0} failing={1} asserts={2}  (明细 {3})' -f $passing, $failing, $asserts, $log)
    if ($harnessErrors -ne 0) { Write-Host '[qc] 回归闸未能正常执行（不是测试失败），见上方提示与 gut.log' -ForegroundColor Red }
    return (($failing -eq 0) -and ($harnessErrors -eq 0) -and $healthOk)
}

function Invoke-Size {
    Assert-Python
    # ① 行数/体积硬门禁（迭代082）：单文件上限 + 祖父条款只许变小
    $policy = Join-Path $QcRoot 'config\size_policy.json'
    $sizeBase = Join-Path $QcRoot 'config\size_baseline.json'
    $sizeOut = Join-Path $Out 'size.json'
    if (Test-Path $policy) {
        & $Py (Join-Path $QcRoot 'lib\size_check.py') --repo $Repo --policy $policy --baseline $sizeBase --out $sizeOut |
            ForEach-Object { Write-Host ('[qc] ' + $_) }
        $gateOk = ($LASTEXITCODE -eq 0)
        if (Test-Path $sizeOut) {
            $sj = [System.IO.File]::ReadAllText($sizeOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            Add-Count 'size:over_cap_files' $sj.over_cap
            Add-Count 'size:max_lines' $sj.max_code_lines
            Add-Count 'size:max_bytes' $sj.max_code_bytes
            Add-Count 'size:violations' (@($sj.violations).Count)
            ## P3（迭代127）：soft 预警（只记录，不判红）
            Add-Count 'size:warn_files' (@($sj.warnings).Count)
        }
    } else {
        Write-Host '[qc] size   未配置 size_policy.json —— 跳过硬门禁' -ForegroundColor Yellow
        $gateOk = $true
    }
    # ② 单体行数看板（3 个关注文件；报告曲线用）
    $cfgPath = Join-Path $QcRoot 'config\size_watch.json'
    if (Test-Path $cfgPath) {
        $cfg = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($w in $cfg.watch) {
            $p = Join-Path $Repo ($w.path -replace '/', '\')
            if (-not (Test-Path $p)) { Add-Count ('size:' + $w.key) 0; continue }
            $n = @(Get-Content $p -Encoding UTF8).Count
            Add-Count ('size:' + $w.key) $n
        }
        $summary = ($cfg.watch | ForEach-Object { $_.key + '=' + $script:Counts['size:' + $_.key] }) -join '  '
        Write-Host ('[qc] size   ' + $summary)
    }
    return $gateOk
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


## 产物完整性（迭代135）：一次全闸必须**重建**这些产物；缺一个 ⇒ 判红。
##   为什么需要：2026-10-23 冷启动实测抓到"文档闸读上一轮 counts.json"的 bug ——
##   那类问题只在"清空产物再跑"时出现，而这条路径此前**没有可执行入口**（只写在手册里）。
function Confirm-Artifacts {
    $required = @(
        'lint.log', 'size.json', 'arch.json', 'graph.json', 'signals.json',
        'docs.json', 'gutcheck.json', 'gut.log', 'counts.json'
    )
    $missing = @()
    foreach ($f in $required) {
        $fp = Join-Path $Out $f
        if (-not (Test-Path $fp)) { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        Write-Host ("[qc] 产物缺失 {0} 个：{1}" -f $missing.Count, ($missing -join ", ")) -ForegroundColor Red
        return $false
    }
    Write-Host ("[qc] 产物齐全：{0} 个 / {1}" -f $required.Count, $Out)
    return $true
}

## 冷启动：清空产物 → 跑全闸 → 校验产物齐全（"依赖上一轮产物"的假绿只能在冷启动暴露）
function Invoke-Coldstart {
    Write-Host '=== qc · 冷启动验证（清空产物后重跑全闸） ===' -ForegroundColor Cyan
    if (Test-Path $Out) { Get-ChildItem $Out -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    $script:Counts = [ordered]@{}
    $script:GateFailed = $false
    Invoke-Gates
    $r = Invoke-Ratchet
    $artOk = Confirm-Artifacts
    $rcOk = $false
    if (-not $script:GateFailed -and $r -eq 0 -and $artOk) { $rcOk = Invoke-Receipt }
    if ($script:GateFailed -or $r -ne 0 -or (-not $artOk) -or (-not $rcOk)) { return 1 }
    return 0
}
function Invoke-Selftest {
    # 门禁自检（迭代089）：造已知坏输入，断言每个闸真会红 —— 专治"假绿"复发。
    # 本仓已发现三个「失败路径从未被执行」的 Bug，故把它变成每次 qc all 都会走的常规路径。
    Assert-Python
    $out = @(& $Py (Join-Path $QcRoot 'lib\selftest_gates.py') 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
    foreach ($line in $out) { Write-Host ('[qc] ' + $line) }
    $fails = @($out | Where-Object { $_ -match '\[FAIL\]' }).Count
    Add-Count 'qc:selftest_failures' $fails
    ## 总数（"合计 N 项"）—— 供《当前状态》收尾状态行对账（迭代139）
    $total = 0
    foreach ($line in $out) { if ($line -match '合计\s+(\d+)\s+项') { $total = [int]$matches[1] } }
    Add-Count 'qc:selftest_total' $total
    return ($code -eq 0 -and $fails -eq 0)
}


function Invoke-Layout {
    Assert-Python
    # M6（迭代155）：源码布局闸 —— 目录白名单 + 四条禁止规则（详见 lib\layout_check.py 头注释）
    $outL = Join-Path $Out 'layout.json'
    & $Py (Join-Path $QcRoot 'lib\layout_check.py') --repo $Repo --out $outL |
        ForEach-Object { Write-Host ('[qc] ' + $_) }
    $ok = ($LASTEXITCODE -eq 0)
    if (Test-Path $outL) {
        $lj = [System.IO.File]::ReadAllText($outL, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Add-Count 'layout:violations' $lj.counts.total
        Add-Count 'layout:unknown_tops' $lj.counts.unknown_tops
        Add-Count 'layout:scene_gd' $lj.counts.scene_gd
        Add-Count 'layout:qc_gd' $lj.counts.qc_gd
        Add-Count 'layout:deprecated' $lj.counts.deprecated
        Add-Count 'layout:prod_refers_dev' $lj.counts.prod_refers_dev
    }
    return $ok
}


function Invoke-BugBind {
    Assert-Python
    # 第三轮 S1 / WS5（迭代156）：缺陷-用例绑定硬闸 —— baseline 之后每个 [fix] 提交都必须登记用例
    $outB = Join-Path $Out 'bugbind.json'
    & $Py (Join-Path $QcRoot 'lib\bug_binding_check.py') --repo $Repo --config (Join-Path $QcRoot 'config\bug_regressions.json') --out $outB |
        ForEach-Object { Write-Host ('[qc] ' + $_) }
    $ok = ($LASTEXITCODE -eq 0)
    if (Test-Path $outB) {
        $bj = [System.IO.File]::ReadAllText($outB, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Add-Count 'bugs:fix_commits' $bj.counts.fix_commits
        Add-Count 'bugs:entries' $bj.counts.entries
        Add-Count 'bugs:unbound' $bj.counts.unbound
        Add-Count 'bugs:bad_tests' $bj.counts.bad_tests
    }
    return $ok
}


## 数字单一来源（迭代157 · S1/WS6）：跑全闸后用**本轮计数**重写《当前状态》两行。
##   为什么必须跑全闸：counts 只有在各闸执行后才齐（尤其回归闸的 test:*）。
function Invoke-SyncDocs {
    param([string]$Iteration = "")
    Assert-Python
    Invoke-Gates -SkipDocs
    if ($script:GateFailed) { Write-Host "[qc] 有闸未通过 —— 先修闸再同步文档" -ForegroundColor Red; return $false }
    $nowCounts = Join-Path $Out 'counts.now.json'
    ($script:Counts | ConvertTo-Json -Depth 4) | Out-File -FilePath $nowCounts -Encoding utf8
    $docPath = Join-Path $Repo '../../项目规划蓝图/当前状态.md'
    $args = @((Join-Path $QcRoot 'lib\sync_docs.py'), '--counts', $nowCounts, '--doc', $docPath)
    if ($Iteration -ne '') { $args += @('--iteration', $Iteration) }
    & $Py @args 2>&1 | ForEach-Object { Write-Host ('[qc] ' + $_) }
    if ($LASTEXITCODE -ne 0) { return $false }
    ## 同步后再用文档闸复验（证明写进去的和 counts 真的一致）
    return (Invoke-Docs -Standalone)
}

function Invoke-Flaky {
    param([int]$Runs = 3)
    Assert-Python
    $godot = Get-GodotBin
    if (-not $godot) { Write-Host '[qc] 找不到 Godot' -ForegroundColor Yellow; exit 2 }
    $files = @()
    for ($i = 1; $i -le $Runs; $i++) {
        $jf = Join-Path $Out ("gut.run$i.junit.xml")
        & $godot --headless --path $Repo -s 'addons/gut/gut_cmdln.gd' -gdir='res://tests' -gexit "-gjunit_xml_file=res://qc/out/gut.run$i.junit.xml" 2>&1 |
            Select-String -Pattern 'Passing Tests|Failing Tests' | ForEach-Object { Write-Host ('[qc] run' + $i + ' ' + $_.Line) }
        $files += $jf
    }
    $list = ($files | ForEach-Object { if (Test-Path $_) { $_ } }) -join ','
    & $Py (Join-Path $QcRoot 'lib\flaky_check.py') --junit $list --out (Join-Path $Out 'flaky.json') |
        ForEach-Object { Write-Host ('[qc] ' + $_) }
    return ($LASTEXITCODE -eq 0)
}


## 交付证据链（迭代160 · S2/WS8）：写 receipt.json（manifest + counts + git），并当场校验一次。
function Invoke-Receipt {
    param([string]$VerifyOnly = "")
    Assert-Python
    $rcOut = Join-Path $Out 'receipt.json'
    $counts = Join-Path $Out 'counts.json'
    if (-not (Test-Path $counts)) { $counts = Join-Path $Out 'counts.now.json' }
    $docsRepo = (Resolve-Path (Join-Path $Repo '../../')).Path
    $lib = Join-Path $QcRoot 'lib\receipt.py'
    if ($VerifyOnly -ne '') {
        & $Py $lib --repo $Repo --counts $counts --out $rcOut --verify $VerifyOnly | ForEach-Object { Write-Host ('[qc] ' + $_) }
        return ($LASTEXITCODE -eq 0)
    }
    & $Py $lib --repo $Repo --docs-repo $docsRepo --counts $counts --out $rcOut --iteration $Iteration | ForEach-Object { Write-Host ('[qc] ' + $_) }
    $writeOk = ($LASTEXITCODE -eq 0)
    if (Test-Path $rcOut) {
        $rj = [System.IO.File]::ReadAllText($rcOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Add-Count 'delivery:manifest_files' (@($rj.manifest).Count)
    }
    $verifyOk = $false
    if ($writeOk -and (Test-Path $rcOut)) {
        & $Py $lib --repo $Repo --counts $counts --out $rcOut --verify $rcOut | ForEach-Object { Write-Host ('[qc] ' + $_) }
        $verifyOk = ($LASTEXITCODE -eq 0)
    }
    Add-Count 'delivery:receipt_ok' ($(if ($verifyOk) { 1 } else { 0 }))
    return ($writeOk -and $verifyOk)
}

## 差异覆盖（迭代162 · S4/WS1）：注入探针 → 跑回归 → **必定还原** → 报告。
##   不进 all（会临时改写 66 个源文件 + project.godot），由人/批次显式触发。
function Invoke-Coverage {
    param([string]$Ref = "HEAD")
    Assert-Python
    $godot = Get-GodotBin
    if (-not $godot) { Write-Host '[qc] 找不到 Godot' -ForegroundColor Yellow; exit 2 }
    $lib = Join-Path $QcRoot 'lib\coverage_probe.py'
    & $Py $lib --repo $Repo inject | ForEach-Object { Write-Host ('[qc] ' + $_) }
    if ($LASTEXITCODE -ne 0) { Write-Host '[qc] 注入失败（要求 src/ 与 project.godot 干净）' -ForegroundColor Red; return $false }
    try {
        & $godot --headless --path $Repo --import 2>&1 | Out-Null
        $raw = @(Invoke-GutRun $godot)
        $raw | Set-Content -Path (Join-Path $Out 'gut.coverage.log') -Encoding UTF8
        $line = ($raw | Where-Object { $_ -match 'Passing Tests' } | Select-Object -First 1)
        Write-Host ('[qc] coverage run: ' + $line)
    } finally {
        & $Py $lib --repo $Repo restore | ForEach-Object { Write-Host ('[qc] ' + $_) }
    }
    $rep = @(& $Py $lib --repo $Repo report --ref $Ref 2>&1 | ForEach-Object { $_.ToString() })
    foreach ($l in $rep) { Write-Host ('[qc] ' + $l) }
    $covRc = $LASTEXITCODE
    $covOut = Join-Path $Out 'coverage.json'
    if (Test-Path $covOut) {
        $cj = [System.IO.File]::ReadAllText($covOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Add-Count 'coverage:funcs_total' $cj.total
        Add-Count 'coverage:funcs_covered' $cj.covered
        Add-Count 'coverage:changed_uncovered' (@($cj.changed_uncovered).Count)
        Add-Count 'coverage:percent' $cj.percent
    }
    ## 报告用完即删备份：陈旧的 .cov-backup 若被误 restore，会把旧代码写回去
    $bk = Join-Path $Repo '.cov-backup'
    if (Test-Path $bk) { Remove-Item $bk -Recurse -Force }
    return ($covRc -eq 0)
}

function Invoke-Gates {
    param([switch]$SkipDocs)
    # 钩子自检：core.hooksPath 是**本地配置**，新克隆不会自动生效 → 每次全闸都提醒一次
    $hp = (& git -C $Repo config --get core.hooksPath 2>$null)
    if ((("$hp").Trim()) -ne 'qc/hooks') {
        Write-Host '[qc] ⚠ 提交钩子未安装（core.hooksPath != qc/hooks）—— 跑 qc/install-hooks.ps1 才能"每次提交自动执行"' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '=== qc · 门禁自检 ===' -ForegroundColor Cyan
    $selfOk = Invoke-Selftest
    if (-not $selfOk) { $script:GateFailed = $true }
    Write-Host ''
    Write-Host '=== qc · 四道闸 ===' -ForegroundColor Cyan
    # 每一闸的返回值都要收集：门禁失败必须让退出码非零，不能只靠棘轮比较计数
    if (-not (Invoke-Layout))   { $script:GateFailed = $true }
    if (-not (Invoke-BugBind))  { $script:GateFailed = $true }
    if (-not (Invoke-Lint))     { $script:GateFailed = $true }
    if (-not (Invoke-Size))     { $script:GateFailed = $true }
    if (-not (Invoke-Arch))     { $script:GateFailed = $true }
    if (-not (Invoke-Signals))  { $script:GateFailed = $true }
    if (-not (Invoke-Test))     { $script:GateFailed = $true }
    if (-not $SkipDocs) { if (-not (Invoke-Docs)) { $script:GateFailed = $true } }
    Write-Host ''
    if ($script:GateFailed) { Write-Host '[qc] 有闸未通过（见上方红色/明细）—— 退出码将非零' -ForegroundColor Red }
}

function Show-Report {
    if (-not (Test-Path $Baseline)) { Write-Host '[qc] 还没有基线：先跑 snapshot' -ForegroundColor Yellow; return }
    # ⚠️ 必须 .NET UTF8 读取：PS 5.1 的 Get-Content -Raw 按 ANSI 解码，中文注释会让 ConvertFrom-Json 失败
    $doc = [System.IO.File]::ReadAllText($Baseline, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
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
    # 单体行数看板（B5 切片专用）：B5 的"降幅"只有它看得见
    $sizeKeys = @($doc.counts.PSObject.Properties | Where-Object { $_.Name -like 'size:*' } | ForEach-Object { $_.Name } | Sort-Object)
    if ($sizeKeys.Count -gt 0) {
        Write-Host ''
        Write-Host '单体行数看板（size:*）：'
        $hdr = '  {0,-18}' -f 'iteration'
        foreach ($k in $sizeKeys) { $hdr += (' {0,-14}' -f $k.Replace('size:', '')) }
        Write-Host $hdr
        foreach ($h in $doc.history) {
            $line = '  {0,-18}' -f $h.iteration
            foreach ($k in $sizeKeys) {
                $v = $h.counts.PSObject.Properties[$k]
                # 该指标尚未引入时显示 "-"，不要显示 0（0 会被误读成"文件空了"）
                $cell = '-'
                if ($null -ne $v) { $cell = [string]$v.Value }
                $line += (' {0,-14}' -f $cell)
            }
            Write-Host $line
        }
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
    # 单闸的退出码必须反映该闸结果 —— 曾一律 exit 0，导致"单闸永远绿"的假象（迭代082 修）
    'layout'   { if (Invoke-Layout)  { exit 0 } else { exit 1 } }
    'bugbind'  { if (Invoke-BugBind) { exit 0 } else { exit 1 } }
    'flaky'    { if (Invoke-Flaky -Runs 3) { exit 0 } else { exit 1 } }
    'syncdocs' { if (Invoke-SyncDocs -Iteration $Iteration) { exit 0 } else { exit 1 } }
    'lint'     { if (Invoke-Lint)    { exit 0 } else { exit 1 } }
    'size'     { if (Invoke-Size)    { exit 0 } else { exit 1 } }
    'arch'     { if (Invoke-Arch)    { exit 0 } else { exit 1 } }
    'signals'  { if (Invoke-Signals) { exit 0 } else { exit 1 } }
    'docs'     { if (Invoke-Docs -Standalone) { exit 0 } else { exit 1 } }
    'test'     { if (Invoke-Test)    { exit 0 } else { exit 1 } }
    'selftest' { if (Invoke-Selftest) { exit 0 } else { exit 1 } }
    'report'   { Show-Report; exit 0 }
    'import'   { Invoke-Import; exit 0 }
    'setup'    { Invoke-Setup; exit 0 }
    'artifacts' { if (Confirm-Artifacts) { exit 0 } else { exit 1 } }
    'receipt'   { if (Invoke-Receipt) { exit 0 } else { exit 1 } }
    'coverage'  { if (Invoke-Coverage) { exit 0 } else { exit 1 } }
    'coldstart' { exit (Invoke-Coldstart) }
    'all'      { Invoke-Gates; $r = Invoke-Ratchet; if ($script:GateFailed) { exit 1 } else { exit $r } }
    'snapshot' { Invoke-Gates; $r = Invoke-Ratchet -Update; if (-not $script:GateFailed) { & $Py (Join-Path $QcRoot 'lib\size_check.py') --repo $Repo --policy (Join-Path $QcRoot 'config\size_policy.json') --baseline (Join-Path $QcRoot 'config\size_baseline.json') --out (Join-Path $Out 'size.json') --tighten | ForEach-Object { Write-Host ('[qc] ' + $_) } } if ($script:GateFailed) { exit 1 } else { exit $r } }
}
exit 0
