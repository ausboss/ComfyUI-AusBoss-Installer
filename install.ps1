# ComfyUI AusBoss Installer for Windows
# Puts a portable ComfyUI, its own Python, ComfyUI-Manager and the AusBoss nodes in one folder.
# Run it through install.bat, or:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Dir C:\AI\ComfyUI-AusBoss] [-Update] [-Yes] [-TorchIndex cu128] [-NoShortcut] [-Plain]
param(
    [string]$Dir = "",
    [switch]$Update,
    [switch]$Yes,
    [switch]$NoShortcut,
    [switch]$Plain,
    [string]$TorchIndex = $env:TORCH_INDEX,
    [string]$PythonVersion = "3.12"
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Version = "1.0.0"
$Repo = "ausboss/ComfyUI-AusBoss-Installer"
$Raw = "https://raw.githubusercontent.com/$Repo/main"
$NeedGB = 15

# --------------------------------------------------------------------- look --
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$Fancy = -not [Console]::IsOutputRedirected
$Nice = [bool]$env:WT_SESSION          # Windows Terminal has every symbol; the old console font doesn't
function C($code) { [string][char]$code }
$H = C 0x2500; $V = C 0x2502; $TL = C 0x256D; $TR = C 0x256E; $BL = C 0x2570; $BR = C 0x256F
$Dot = C 0x00B7; $Ell = C 0x2026; $Full = C 0x2501; $Empty = C 0x2500
if ($Nice) {
    $OkC = C 0x2713; $BadC = C 0x2717; $TodoC = C 0x25CB
    $Spin = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F) | ForEach-Object { C $_ }
} else {
    $OkC = "+"; $BadC = "x"; $TodoC = "o"; $Spin = @("|", "/", "-", "\")
}
$Teal = "DarkCyan"; $Bright = "Cyan"; $Green = "Green"; $Amber = "Yellow"; $Rust = "Red"; $Ink = "White"; $Muted = "Gray"; $Faint = "DarkGray"

$script:Cols = 80; $script:Rows = 25; $W = 76
function Size {
    try { $script:Cols = [Console]::WindowWidth; $script:Rows = [Console]::WindowHeight } catch { }
    if (-not $script:Cols) { $script:Cols = 80 }
    $script:W = [Math]::Max(40, [Math]::Min(80, $script:Cols - 4))
}
Size
$script:Dash = $Fancy -and -not $Plain -and $script:Cols -ge 60 -and $script:Rows -ge 20

function Rep($c, $n) { if ($n -le 0) { return "" } return ($c * $n) }
function Fit($s, $n) { $s = "$s"; if ($s.Length -gt $n) { return $s.Substring(0, [Math]::Max(0, $n - 1)) + $Ell } return $s }
function FitEnd($s, $n) { $s = "$s"; if ($s.Length -gt $n) { return $Ell + $s.Substring($s.Length - $n + 1) } return $s }

# A line is a list of text, color pairs
function Say([object[]]$segs) {
    for ($i = 0; $i -lt $segs.Count; $i += 2) { Write-Host $segs[$i] -ForegroundColor $segs[$i + 1] -NoNewline }
    Write-Host ""
}

# _ ^ # stand for the lower half, upper half and full block
function LogoRow($row) {
    $map = @{ "_" = (C 0x2584); "^" = (C 0x2580); "#" = (C 0x2588) }
    $s = ""
    foreach ($ch in $row.ToCharArray()) { if ($map.ContainsKey([string]$ch)) { $s += $map[[string]$ch] } else { $s += $ch } }
    return $s
}
$Logo1 = LogoRow "_^# # # #^ #__ #^# #^ #^"; $Logo2 = LogoRow "#^# #_# _# #_# #_# _# _#"
function HeaderLines($sub) {
    return @(
        @("", "Gray"),
        @("  ", $Ink, $Logo1, $Bright, "   ComfyUI Installer", $Ink),
        @("  ", $Ink, $Logo2, $Teal, "   $sub", $Muted)
    )
}


# ---------------------------------------------------------------- the mark --
# The AusBoss mark as pixels: t is teal, a is amber. Each character cell shows two pixels with half blocks.
$MarkBig = @(
    "....................t...............",
    "....................tt..............",
    "...................ttt..............",
    "..................ttttt.............",
    "..................tttttt............",
    ".................ttttttt............",
    "................tttt.tttt...........",
    "................tttt..tttt..........",
    "...............tttt....ttt..........",
    "..............tttt.....tttt.........",
    "..............tttt......ttt.........",
    ".............tttt...aa...ttt........",
    ".............ttt...aaa...tttt.......",
    "............tttt...aaaa...ttt.......",
    "...........tttt...aaaaaa..tttt......",
    "...........ttt...aaaaaaa...ttt......",
    "..........tttt.............ttt......",
    ".........tttt.............ttt.......",
    ".........ttt....tttttttttttttttt....",
    "........tttt...tttttttttttttttttt...",
    ".......tttt....ttttttttttttttttttt..",
    ".......tttt...................tttt..",
    "......tttt.....................tttt.",
    ".....tttt...aaaaaaaaaaaaaaaa...ttttt",
    ".....tttt...aaaaaaaaaaaaaaa....ttttt",
    "....tttt...aaaaaaaaaaaaaaa....ttttt.",
    "....ttt....aaaaaaaaaaaaaa....ttttt..",
    "...tttt......................ttttt..",
    "..tttt......................ttttt...",
    "..tttttttttttttttttttttttttttttt....",
    ".tttttttttttttttttttttttttttttt.....",
    "ttttttttttttttttttttttttttttttt....."
)
$MarkSmall = @(
    "............t.........",
    "............tt........",
    "...........ttt........",
    "..........ttttt.......",
    "..........tt.ttt......",
    ".........tt...tt......",
    "........ttt....tt.....",
    "........tt..a..tt.....",
    ".......ttt.aaa..tt....",
    ".......tt..aaaa.tt....",
    "......tt........tt....",
    ".....ttt..tttttttttt..",
    ".....tt..ttttttttttt..",
    "....tt............ttt.",
    "...ttt..aaaaaaaaa..ttt",
    "...tt..aaaaaaaaa...ttt",
    "..ttt..aaaaaaaaa..ttt.",
    "..tt.............ttt..",
    ".ttttttttttttttttttt..",
    "ttttttttttttttttttt..."
)
$UseMark = $Fancy -and -not $Plain
$Upper = C 0x2580; $Lower = C 0x2584; $Block = C 0x2588
function PxC($p) { if ($p -eq 't') { return "DarkCyan" } elseif ($p -eq 'a') { return "Yellow" } return $null }
# Lines of the mark, each a list of (text, foreground, background) runs
function MarkLines($m) {
    $out = @()
    for ($y = 0; $y -lt $m.Count; $y += 2) {
        $segs = New-Object System.Collections.ArrayList
        $r1 = $m[$y]; $r2 = $m[$y + 1]; $cur = $null
        for ($x = 0; $x -lt $r1.Length; $x++) {
            $fa = PxC ([string]$r1[$x]); $fb = PxC ([string]$r2[$x]); $bg = $null
            if (-not $fa -and -not $fb) { $ch = " "; $fg = "Gray" }
            elseif (-not $fa) { $ch = $Lower; $fg = $fb }
            elseif (-not $fb) { $ch = $Upper; $fg = $fa }
            elseif ($fa -eq $fb) { $ch = $Block; $fg = $fa }
            else { $ch = $Upper; $fg = $fa; $bg = $fb }
            if ($cur -and $cur[1] -eq $fg -and $cur[2] -eq $bg) { $cur[0] += $ch }
            else { $cur = @($ch, $fg, $bg); [void]$segs.Add($cur) }
        }
        $out += , ($segs.ToArray())
    }
    return , $out
}
function WriteMark($line) {
    foreach ($sg in $line) {
        if ($sg[2]) { Write-Host $sg[0] -ForegroundColor $sg[1] -BackgroundColor $sg[2] -NoNewline }
        else { Write-Host $sg[0] -ForegroundColor $sg[1] -NoNewline }
    }
}
$script:SmallMark = $null
# The opening: the mark draws in from the top with the name beside it
function Splash($sub, [switch]$Small, [switch]$Still) {
    if (-not $UseMark -or $script:Cols -lt 56) { foreach ($l in (HeaderLines $sub)) { Say $l }; return }
    $m = $MarkBig
    if ($Small -or $script:Cols -lt 84 -or $script:Rows -lt 30) { $m = $MarkSmall }
    $ml = MarkLines $m
    $n = $ml.Count; $mid = [int][Math]::Floor($n / 2) - 2
    $rt = @{}
    $rt[$mid] = @($Logo1, $Bright); $rt[$mid + 1] = @($Logo2, $Teal)
    $rt[$mid + 3] = @("ComfyUI Installer", $Ink); $rt[$mid + 4] = @($sub, $Muted)
    Write-Host ""
    for ($r = 0; $r -lt $n; $r++) {
        Write-Host "  " -NoNewline; WriteMark $ml[$r]
        if ($rt.ContainsKey($r)) { Write-Host "    " -NoNewline; Write-Host $rt[$r][0] -ForegroundColor $rt[$r][1] -NoNewline }
        Write-Host ""
        if (-not $Still) { Start-Sleep -Milliseconds 25 }
    }
}

function Card($title, $color, [string[]]$rows) {
    $inner = $W - 2
    Say @("  $TL$H ", $color, $title, $Ink, (" " + (Rep $H ($inner - $title.Length - 3)) + $TR), $color)
    foreach ($row in $rows) {
        $i = $row.IndexOf("|"); $key = $row.Substring(0, $i); $val = FitEnd $row.Substring($i + 1) ($inner - 17)
        Say @("  $V  ", $color, $key.PadRight(14), $Muted, $val.PadRight($inner - 16), $Ink, $V, $color)
    }
    Say @(("  " + $BL + (Rep $H $inner) + $BR), $color)
}

# ------------------------------------------------------------------- steps --
$Steps = @("Tools", "Python", "ComfyUI", "PyTorch", "ComfyUI packages", "Node packs", "Finishing")
$Weight = @(3, 4, 8, 45, 15, 20, 5)      # share of the bar
$Expect = @(5, 20, 40, 180, 60, 60, 5)   # rough seconds, so the bar moves inside a step
$script:State = @("todo") * $Steps.Count; $script:Detail = @("") * $Steps.Count; $script:Warned = @($false) * $Steps.Count
$script:Cur = -1; $script:StepSw = $null; $script:T0 = [Diagnostics.Stopwatch]::StartNew()
$script:TaskLabel = ""; $script:TaskSw = $null; $script:Frame = 0; $script:Live = @()
$script:Warnings = @(); $script:Log = $null; $script:GpuShort = "Windows"; $script:Drawn = 0

function StepLines($ind = "    ", $dw = 0) {
    if ($dw -le 0) { $dw = $W - 26 }
    $out = @()
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $name = $Steps[$i].PadRight(19); $det = $script:Detail[$i]
        switch ($script:State[$i]) {
            "done" { $out += , @($ind, $Ink, $OkC, $Green, "  $name", $Ink, (Fit $det $dw), $Muted) }
            "warn" { $out += , @($ind, $Ink, "!", $Amber, "  $name", $Ink, (Fit $det $dw), $Muted) }
            "fail" { $out += , @($ind, $Ink, $BadC, $Rust, "  $name", $Ink, (Fit $det $dw), $Muted) }
            "run" {
                if ($script:TaskLabel) { $det = "{0}  {1}s" -f $script:TaskLabel, [int]$script:TaskSw.Elapsed.TotalSeconds }
                $out += , @($ind, $Ink, $Spin[$script:Frame % $Spin.Count], $Bright, "  $name", $Ink, (Fit $det $dw), $Bright)
            }
            default { $out += , @($ind, $Ink, $TodoC, $Faint, "  $name", $Faint) }
        }
    }
    return $out
}
function Percent {
    $total = 0; $done = 0
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $total += $Weight[$i]
        if ($script:State[$i] -eq "done" -or $script:State[$i] -eq "warn") { $done += $Weight[$i] * 100 }
    }
    if ($script:Cur -ge 0 -and $script:State[$script:Cur] -eq "run") {
        $part = [Math]::Min(95, [int]($script:StepSw.Elapsed.TotalSeconds * 100 / $Expect[$script:Cur]))
        $done += $Weight[$script:Cur] * $part
    }
    return [int]($done / $total)
}
function BarLine {
    $pct = Percent; $n = $W - 20; $fill = [int]($n * $pct / 100)
    $a = [int]($fill * 0.45); $b = [int]($fill * 0.8)
    $el = $script:T0.Elapsed
    return @("  ", $Ink, (Rep $Full $a), $Teal, (Rep $Full ($b - $a)), $Bright, (Rep $Full ($fill - $b)), $Green, (Rep $Empty ($n - $fill)), $Faint,
        ("  {0,3}%" -f $pct), $Ink, ("  {0}m {1:00}s" -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds), $Muted)
}
function LiveLines($n) {
    $lines = @()
    $files = @($script:Live) + @($script:Log)
    foreach ($f in $files) {
        if (-not $f) { continue }
        try { $lines += @(Get-Content $f -Tail 20 -ErrorAction SilentlyContinue) } catch { }
        if ($lines.Count -ge $n -and $f -ne $script:Log) { break }
    }
    $esc = [char]27
    $lines = @($lines | ForEach-Object { ($_ -replace "$esc\[[0-9;?]*[A-Za-z]", "" -split "`r")[-1].Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("---") -and -not $_.StartsWith("===") })
    if ($lines.Count -gt $n) { $lines = $lines[($lines.Count - $n)..($lines.Count - 1)] }
    return $lines
}

function Render {
    if (-not $script:Dash) { return }
    Size
    $lines = @()
    $marked = $UseMark -and $script:Cols -ge 72
    if ($marked) {
        # the mark on the left, the name and the steps beside it
        if (-not $script:SmallMark) { $script:SmallMark = MarkLines $MarkSmall }
        $top = @(@("ComfyUI Installer", $Ink), @("v$Version $Dot $($script:GpuShort)", $Muted), @("", "Gray"))
        $top += StepLines "" ([Math]::Min(50, $script:Cols - 51))
        $lines += , @("", "Gray")
    } else {
        $lines += HeaderLines "v$Version $Dot $($script:GpuShort)"
        $lines += , @("", "Gray")
        $lines += StepLines
    }
    $after = @()
    foreach ($w in $script:Warnings) { $after += , @("    ! " + (Fit $w ($W - 6)), $Amber) }
    $after += , @("", "Gray")
    $used = $lines.Count + $after.Count
    if ($marked) { $used += 10 }
    $n = [Math]::Max(2, [Math]::Min(10, $script:Rows - $used - 7))
    $lines = @($lines)
    $iw = $W - 4
    $after += , @("  $TL$H ", $Faint, "output", $Muted, (" " + (Rep $H ($W - 11)) + $TR), $Faint)
    $live = @(LiveLines $n)
    for ($i = 0; $i -lt $n; $i++) {
        $t = ""; if ($i -lt $live.Count) { $t = Fit $live[$i] $iw }
        $after += , @("  $V ", $Faint, $t.PadRight($iw), $Muted, " $V", $Faint)
    }
    $after += , @(("  " + $BL + (Rep $H ($W - 2)) + $BR), $Faint)
    $after += , @("", "Gray")
    $after += , (BarLine)
    try { [Console]::SetCursorPosition(0, 0) } catch { }
    $count = 0
    foreach ($l in $lines) {
        $len = 0
        for ($i = 0; $i -lt $l.Count; $i += 2) { Write-Host $l[$i] -ForegroundColor $l[$i + 1] -NoNewline; $len += "$($l[$i])".Length }
        Write-Host (Rep " " ($script:Cols - 1 - $len)); $count++
    }
    if ($marked) {
        for ($r = 0; $r -lt $script:SmallMark.Count; $r++) {
            Write-Host "  " -NoNewline; WriteMark $script:SmallMark[$r]; Write-Host "   " -NoNewline
            $len = 27; $l = @("", "Gray"); if ($r -lt $top.Count) { $l = $top[$r] }
            for ($i = 0; $i -lt $l.Count; $i += 2) { Write-Host $l[$i] -ForegroundColor $l[$i + 1] -NoNewline; $len += "$($l[$i])".Length }
            Write-Host (Rep " " ($script:Cols - 1 - $len)); $count++
        }
    }
    foreach ($l in $after) {
        $len = 0
        for ($i = 0; $i -lt $l.Count; $i += 2) { Write-Host $l[$i] -ForegroundColor $l[$i + 1] -NoNewline; $len += "$($l[$i])".Length }
        Write-Host (Rep " " ($script:Cols - 1 - $len)); $count++
    }
    for ($i = $count; $i -lt $script:Drawn; $i++) { Write-Host (Rep " " ($script:Cols - 1)) }
    $script:Drawn = $count
}
function DashOn { if ($script:Dash) { Clear-Host; try { [Console]::CursorVisible = $false } catch { } } }
function DashOff { if ($script:Dash) { Clear-Host; try { [Console]::CursorVisible = $true } catch { }; $script:Dash = $false } }
function Report {
    # Clear-Host took the first card away, so draw the mark and the name again
    Splash "v$Version $Dot $($script:GpuShort)" -Small -Still
    Write-Host ""
    foreach ($l in (StepLines)) { Say $l }
    foreach ($w in $script:Warnings) { Say @("    ! $w", $Amber) }
}

function EndStep {
    if ($script:Cur -ge 0 -and $script:State[$script:Cur] -eq "run") {
        if ($script:Warned[$script:Cur]) { $script:State[$script:Cur] = "warn" } else { $script:State[$script:Cur] = "done" }
    }
}
function Stage($t) {
    EndStep
    $script:Cur++; $script:State[$script:Cur] = "run"; $script:StepSw = [Diagnostics.Stopwatch]::StartNew(); $script:TaskLabel = ""
    if (-not $script:Dash) { Write-Host ""; Say @("  [$($script:Cur + 1)/$($Steps.Count)] $t", $Bright) }
    Render
}
function Ok($t, $extra = "") {
    $script:Detail[$script:Cur] = $t
    if (-not $script:Dash) { Say @("    $OkC ", $Green, $t, $Muted, $(if ($extra) { "  $extra" } else { "" }), $Faint) }
    Render
}
function Warn($t) {
    $script:Warnings += $t
    if ($script:Cur -ge 0) { $script:Warned[$script:Cur] = $true }
    if (-not $script:Dash) { Say @("    ! $t", $Amber) }
    Render
}
function Fatal($msg, $hint = "") {
    if ($script:Cur -ge 0) { $script:State[$script:Cur] = "fail" }
    $was = $script:Dash; DashOff
    if ($was) { Report }
    Write-Host ""
    if ($script:Log -and (Test-Path $script:Log)) {
        Say @("  Last lines of the log:", $Muted)
        Get-Content $script:Log -Tail 12 | ForEach-Object { Say @("    $V ", $Faint, $_, $Muted) }
        Write-Host ""
    }
    $rows = @("Problem|$msg")
    if ($hint) { $rows += "Try|$hint" }
    if ($script:Log) { $rows += "Full log|$script:Log" }
    Card "Install stopped" $Rust $rows
    Write-Host ""
    exit 1
}

function Quote([string[]]$a) {
    ($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join " "
}

# Run a program, its output going to the log. On the full-screen view the panel shows it live. Returns $true when it worked.
function Task($label, $exe, [string[]]$argv) {
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    Add-Content $script:Log "--- ${label}: $exe $(Quote $argv)"
    $script:TaskLabel = $label; $script:TaskSw = [Diagnostics.Stopwatch]::StartNew(); $script:Live = @($err, $out)
    if (-not $script:Dash) { Say @("    > $label", $Faint) }
    $p = Start-Process -FilePath $exe -ArgumentList (Quote $argv) -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle   # so ExitCode is filled in
    while (-not $p.HasExited) {
        if ($script:Dash) { $script:Frame++; Render }
        Start-Sleep -Milliseconds 150
    }
    $p.WaitForExit()
    $rc = $p.ExitCode
    $secs = [int]$script:TaskSw.Elapsed.TotalSeconds
    foreach ($f in $out, $err) { Get-Content $f -ErrorAction SilentlyContinue | Add-Content $script:Log; Remove-Item $f -ErrorAction SilentlyContinue }
    $script:Live = @(); $script:TaskLabel = ""
    if ($rc -eq 0) { Ok $label "${secs}s"; return $true }
    if (-not $script:Dash) {
        Say @("    $BadC $label", $Rust)
        Get-Content $script:Log -Tail 8 | ForEach-Object { Say @("      $_", $Faint) }
    }
    return $false
}

# ---------------------------------------------------------------- preflight --
$ScriptDir = $PSScriptRoot
if ($Update) { if (-not $Dir) { $Dir = $ScriptDir } }
elseif (-not $Dir) { $Dir = Join-Path (Get-Location) "ComfyUI-AusBoss" }
$Dir = $Dir.TrimEnd("\")
try { $Host.UI.RawUI.WindowTitle = "ComfyUI AusBoss Installer" } catch { }

if ($Dir -match " ") { Fatal "The install path has a space in it." "Put install.bat in a folder without spaces, like C:\AI." }
try { New-Item -ItemType Directory -Force -Path $Dir | Out-Null } catch { Fatal "Can't create $Dir" "Pick a folder you own, like C:\AI." }
$Dir = (Resolve-Path $Dir).Path
$Tools = Join-Path $Dir "tools"
New-Item -ItemType Directory -Force -Path $Tools | Out-Null
$script:Log = Join-Path $Dir "install.log"
Add-Content $script:Log "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ComfyUI AusBoss Installer v$Version (update=$Update)"

# Keep other Python setups (conda, pyenv, venvs) out of this install
foreach ($v in "PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV", "CONDA_PREFIX", "UV_PYTHON") { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
$env:UV_PYTHON_INSTALL_DIR = Join-Path $Tools "python"
$env:UV_CACHE_DIR = Join-Path $Tools "uv-cache"
$env:UV_LINK_MODE = "copy"; $env:UV_HTTP_TIMEOUT = "600"; $env:UV_PYTHON_PREFERENCE = "only-managed"
$env:GIT_TERMINAL_PROMPT = "0"; $env:GIT_LFS_SKIP_SMUDGE = "1"

# ----------------------------------------------------------------- hardware --
$gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
$GpuName = "no GPU found"; $GpuInfo = "runs on the CPU (slow)"; $Auto = "cpu"; $Device = "cpu"
if ($smi) {
    $q = (& nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits | Select-Object -First 1) -split ",\s*"
    $GpuName = $q[0].Trim(); $drv = $q[2].Trim()
    $GpuInfo = "{0} GB $Dot driver {1}" -f [int]([int]$q[1] / 1024), $drv
    $Device = "nvidia"
    if ([int]($drv -split '\.')[0] -ge 580) { $Auto = "cu130" } else { $Auto = "cu128" }
} elseif ($gpus -match "Intel.*(Arc|Battlemage)") {
    $GpuName = @($gpus -match "Intel")[0]; $GpuInfo = "Intel XPU"; $Auto = "xpu"; $Device = "intel"
} elseif ($gpus -match "AMD|Radeon") {
    $GpuName = @($gpus -match "AMD|Radeon")[0]; $GpuInfo = "not supported on Windows yet, using the CPU"
}
$script:GpuShort = ($GpuName -replace '^NVIDIA ', '' -replace '^GeForce ', '')
$savedFile = Join-Path $Tools "torch-index"
$saved = $null
if (Test-Path $savedFile) { $saved = (Get-Content $savedFile -TotalCount 1).Trim() }
if (-not $TorchIndex) { if ($saved) { $TorchIndex = $saved } else { $TorchIndex = $Auto } }
$FreeGB = [int]((Get-PSDrive ($Dir.Substring(0, 1))).Free / 1GB)

Splash "v$Version $Dot Windows"
Write-Host ""
$rows = @("Folder|$Dir", "GPU|$GpuName", "|$GpuInfo", "PyTorch|$TorchIndex build", "Python|$PythonVersion", "Free space|$FreeGB GB")
if ($Update) { Card "Updating" $Teal $rows } else { Card "Ready to install" $Teal $rows }
$pre = @()
if ($Device -eq "cpu") { $pre += "No supported graphics card found. ComfyUI works on the CPU, but slowly." }
if ($Device -eq "nvidia" -and $TorchIndex -eq "cu128" -and $Auto -eq "cu128") { $pre += "NVIDIA driver older than 580: using CUDA 12.8. A newer driver gets you newer PyTorch." }
if (-not $Update -and $FreeGB -lt $NeedGB) { $pre += "Only $FreeGB GB free. The install needs about $NeedGB GB, plus room for models." }
foreach ($w in $pre) { Say @("  ! $w", $Amber) }

if (-not $Update -and -not $Yes -and -not [Console]::IsInputRedirected) {
    Write-Host ""
    Say @("  Press ", $Ink, "Enter", $Bright, " to install, or close this window to cancel ", $Ink)
    $null = Read-Host
}
$script:Warnings = $pre
$script:T0 = [Diagnostics.Stopwatch]::StartNew()
DashOn

try {
# ------------------------------------------------------------------- tools --
Stage "Tools"
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) {
    $git = Join-Path $Tools "git\cmd\git.exe"
    if (-not (Test-Path $git)) {
        $script:TaskLabel = "Getting a portable Git"; $script:TaskSw = [Diagnostics.Stopwatch]::StartNew(); Render
        $url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip"
        try {
            $rel = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest" -UseBasicParsing
            $asset = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d.]+-64-bit\.zip$' } | Select-Object -First 1
            if ($asset) { $url = $asset.browser_download_url }
        } catch { }
        try {
            $zip = Join-Path $Tools "mingit.zip"
            Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
            Expand-Archive $zip -DestinationPath (Join-Path $Tools "git") -Force
            Remove-Item $zip
        } catch { Fatal "Could not download Git." "Check your internet connection, or install Git from git-scm.com." }
        $script:TaskLabel = ""
    }
    $env:PATH = (Split-Path $git) + ";" + $env:PATH
}
$uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
if (-not $uv) {
    $uv = Join-Path $Tools "uv\uv.exe"
    if (-not (Test-Path $uv)) {
        $script:TaskLabel = "Getting uv"; $script:TaskSw = [Diagnostics.Stopwatch]::StartNew(); Render
        try {
            $zip = Join-Path $Tools "uv.zip"
            Invoke-WebRequest "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" -OutFile $zip -UseBasicParsing
            Expand-Archive $zip -DestinationPath (Join-Path $Tools "uv") -Force
            Remove-Item $zip
        } catch { Fatal "Could not download uv." "Check your internet connection." }
        $script:TaskLabel = ""
    }
}
Ok ("git " + ((& $git --version) -replace 'git version ', '' -replace '\.windows.*', '') + " $Dot uv " + ((& $uv --version) -split ' ')[1])

# ------------------------------------------------------------------ python --
Stage "Python"
$venv = Join-Path $Dir "venv"
$py = Join-Path $venv "Scripts\python.exe"
if (-not (Test-Path $py)) {
    if (-not (Task "Setting up Python $PythonVersion" $uv @("venv", "--python", $PythonVersion, "--seed", $venv))) { Fatal "Could not set up Python." }
}
Ok (& $py --version)
function PipTask($label, [string[]]$pkgs) { Task $label $uv (@("pip", "install", "--python", $py) + $pkgs) }

# Requirements without torch lines, so nothing swaps the GPU build for another one
function ReqTask($label, $req) {
    $tmp = [IO.Path]::GetTempFileName()
    Get-Content $req | Where-Object { $_ -notmatch '^\s*(torch|torchvision|torchaudio)([\s<>=!~;\[]|$)' } | Set-Content $tmp
    $r = PipTask $label @("-r", $tmp)
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $r
}

# ----------------------------------------------------------------- comfyui --
Stage "ComfyUI"
$comfy = Join-Path $Dir "ComfyUI"
if (-not (Test-Path (Join-Path $comfy ".git"))) {
    if (-not (Task "Downloading" $git @("clone", "--progress", "https://github.com/comfyanonymous/ComfyUI", $comfy))) { Fatal "Could not download ComfyUI." "Check your internet connection." }
} elseif ($Update) {
    if (-not (Task "Updating" $git @("-C", $comfy, "pull", "--ff-only", "--progress"))) { Warn "Could not update ComfyUI (local changes?). Kept the current version." }
}
Ok (& $git -C $comfy describe --tags --always)

# ----------------------------------------------------------------- pytorch --
Stage "PyTorch"
$first = -not (Test-Path (Join-Path $venv "Lib\site-packages\torch"))
if ($first) { $label = "Downloading a few GB ($TorchIndex)" } else { $label = "Checking ($TorchIndex)" }
if (-not (PipTask $label @("torch", "torchvision", "torchaudio", "--index-url", "https://download.pytorch.org/whl/$TorchIndex"))) {
    Fatal "Could not install PyTorch." "Try another build: install.bat -TorchIndex cu128"
}
Set-Content $savedFile $TorchIndex
Ok (& $py -c "import torch; print(torch.__version__)" 2>$null)

Stage "ComfyUI packages"
if (-not (ReqTask "ComfyUI requirements" (Join-Path $comfy "requirements.txt"))) { Fatal "Could not install ComfyUI's packages." }
$mreq = Join-Path $comfy "manager_requirements.txt"
if (Test-Path $mreq) { if (-not (ReqTask "ComfyUI-Manager" $mreq)) { Warn "ComfyUI-Manager did not install" } }
Ok "ComfyUI requirements $Dot ComfyUI-Manager"

# ------------------------------------------------------------------- nodes --
Stage "Node packs"
$nodes = Join-Path $Dir "nodes.txt"
$here = Join-Path $ScriptDir "nodes.txt"
if (-not (Test-Path $nodes)) {
    if (Test-Path $here) { Copy-Item $here $nodes }
    else { try { Invoke-WebRequest "$Raw/nodes.txt" -OutFile $nodes -UseBasicParsing } catch { Fatal "Could not download the node list." } }
}
$packs = @()
foreach ($line in Get-Content $nodes) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    $parts = $line -split '\s+'
    $url = $parts[0]
    if ($parts.Count -gt 1) { $name = $parts[1] } else { $name = [IO.Path]::GetFileNameWithoutExtension($url) }
    $target = Join-Path $comfy "custom_nodes\$name"
    if (-not (Test-Path (Join-Path $target ".git"))) {
        if (-not (Task $name $git @("clone", "--progress", "--recursive", $url, $target))) { Warn "Could not download $name"; continue }
    } elseif ($Update) {
        if (-not (Task "Updating $name" $git @("-C", $target, "pull", "--ff-only"))) { Warn "Could not update $name" }
    }
    $req = Join-Path $target "requirements.txt"
    if (Test-Path $req) { if (-not (ReqTask "$name packages" $req)) { Warn "Some packages for $name did not install" } }
    $ipy = Join-Path $target "install.py"
    $doneFlag = Join-Path $target ".installed"
    if ((Test-Path $ipy) -and -not (Test-Path $doneFlag)) {
        Push-Location $target
        if (Task "$name setup" $py @("install.py")) { New-Item $doneFlag -ItemType File | Out-Null }
        Pop-Location
    }
    $packs += $name
}
$null = PipTask "Extras for the AusBoss nodes" @("pymatting>=1.1", "pillow-jxl-plugin")

if ($TorchIndex -ne "cpu") {
    $tv = & $py -c "import torch; print(torch.__version__)" 2>$null
    if ($LASTEXITCODE -ne 0 -or "$tv" -match "\+cpu") {
        if (-not (PipTask "Putting the GPU PyTorch back" @("--reinstall", "torch", "torchvision", "torchaudio", "--index-url", "https://download.pytorch.org/whl/$TorchIndex"))) {
            Warn "PyTorch may be the CPU build now. Run Update ComfyUI.bat."
        }
    }
}
if ($packs.Count) { Ok ($packs -join " ") } else { Ok "none" }

# ------------------------------------------------------------------ finish --
Stage "Finishing"
$src = Join-Path $ScriptDir "install.ps1"
$to = Join-Path $Dir "install.ps1"
if ($src -ne $to) { Copy-Item $src $to -Force }
$extra = Join-Path $Dir "extra_args.txt"
if (-not (Test-Path $extra)) { Set-Content $extra "# Extra ComfyUI startup options, for example: --listen --port 8188" }

Set-Content (Join-Path $Dir "Start ComfyUI.bat") -Encoding ASCII -Value @'
@echo off
title ComfyUI
rem Start ComfyUI. Extra options go in extra_args.txt.
cd /d "%~dp0"
set "ARGS="
for /f "usebackq eol=# delims=" %%a in ("extra_args.txt") do call set "ARGS=%%ARGS%% %%a"
cd ComfyUI
"..\venv\Scripts\python.exe" main.py --enable-manager --windows-standalone-build %ARGS% %*
pause
'@
Set-Content (Join-Path $Dir "Update ComfyUI.bat") -Encoding ASCII -Value @'
@echo off
title Update ComfyUI
rem Update ComfyUI, its packages and every pack in nodes.txt.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Update %*
pause
'@
$bits = "Start ComfyUI.bat $Dot Update ComfyUI.bat"

if (-not $NoShortcut -and -not $Update) {
    try {
        $desk = [Environment]::GetFolderPath("Desktop")
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desk "ComfyUI (AusBoss).lnk"))
        $lnk.TargetPath = Join-Path $Dir "Start ComfyUI.bat"
        $lnk.WorkingDirectory = $Dir
        $lnk.Save()
        $bits += " $Dot desktop shortcut"
    } catch { }
}

$script:TaskLabel = "Checking PyTorch"; $script:TaskSw = [Diagnostics.Stopwatch]::StartNew(); Render
$check = & $py -c "import torch; a = torch.cuda.is_available() or (hasattr(torch, 'xpu') and torch.xpu.is_available()); print(torch.__version__ + ('|yes' if a else '|no'))" 2>$null
$script:TaskLabel = ""
if ($LASTEXITCODE -ne 0 -or -not $check) { Warn "PyTorch did not load. Run Update ComfyUI.bat, and see install.log." }
else {
    $tv, $seen = "$check".Trim() -split "\|"
    if ($seen -eq "yes") { $bits += " $Dot GPU ready" }
    elseif ($Device -ne "cpu") { Warn "PyTorch $tv can't see the GPU. Check the driver, then run Update ComfyUI.bat." }
}
Ok $bits
EndStep
Render
if ($script:Dash) { Start-Sleep -Milliseconds 600 }
} catch {
    Fatal $_.Exception.Message
}

# ----------------------------------------------------------------- summary --
$t = $script:T0.Elapsed
DashOff
Report
Write-Host ""
$rows = @(("Took|{0}m {1}s" -f [int][Math]::Floor($t.TotalMinutes), $t.Seconds), "Start|$Dir\Start ComfyUI.bat", "Open|http://127.0.0.1:8188", "Models|$Dir\ComfyUI\models", "Update|$Dir\Update ComfyUI.bat", "Log|$script:Log")
if ($Update) { Card "ComfyUI is up to date" $Green $rows } else { Card "ComfyUI is ready" $Green $rows }
Write-Host ""

if (-not $Update -and -not $Yes -and -not [Console]::IsInputRedirected) {
    Say @("  Start ComfyUI now? ", $Ink, "[Y/n] ", $Bright)
    $a = Read-Host
    if (-not $a -or $a -match '^[Yy]') { Start-Process (Join-Path $Dir "Start ComfyUI.bat") -WorkingDirectory $Dir }
}
