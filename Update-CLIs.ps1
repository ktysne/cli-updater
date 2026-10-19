<#
.SYNOPSIS
    Claude Code CLI、Codex CLI、GitHub CLI のバージョンを確認し、古ければ最新版をインストールする。

.DESCRIPTION
    - Claude Code: ネイティブインストーラ版 (~/.local/bin/claude.exe) を想定し、
      組み込みの `claude update` で更新する。コマンドが見つからない場合は公式
      インストールスクリプトで新規導入する。
    - Codex CLI: npm グローバルパッケージ `@openai/codex` を `npm install -g` で更新する。
    - GitHub CLI: 最新版を GitHub Releases (cli/cli) で確認し、winget (`GitHub.cli`) で更新する。

.NOTES
    Windows PowerShell 5.1 / PowerShell 7 双方で動作。
#>

[CmdletBinding()]
param(
    [switch]$Force  # 最新でも強制再インストール
)

$ErrorActionPreference = 'Stop'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-Info  { param($m) Write-Host "[INFO ] $m" -ForegroundColor White }
function Write-Ok    { param($m) Write-Host "[ OK  ] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Write-Err2  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

# 'a.b.c' 形式のバージョン文字列を [version] に変換。比較不能なら $null。
function ConvertTo-VersionObject {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    try { return [version]$m.Value } catch { return $null }
}

# npm を呼び出し、stdout / stderr / 終了コードを分離して返す。
# $ErrorActionPreference='Stop' のままだと npm が stderr に 1 行書いた時点で
# NativeCommandError となり、npm 自体は成功していても失敗扱いになるため、
# この関数の中だけ 'Continue' に落として自前で終了コードを判定する。
function Invoke-NpmCapture {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw  = & npm @Arguments 2>&1
        $code = $LASTEXITCODE
    } catch {
        return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $prev
    }

    $out = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $err = @($raw | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{
        ExitCode = $code
        StdOut   = ($out -join "`n").Trim()
        StdErr   = ($err -join "`n").Trim()
    }
}

# npm レジストリから最新版を取得する。一時的なネットワーク断を想定して数回リトライし、
# 失敗した場合は npm が出した実際のメッセージを表示する ($null で握り潰さない)。
function Get-NpmLatestVersion {
    param(
        [Parameter(Mandatory)][string]$Package,
        [int]$Retries = 3
    )

    for ($i = 1; $i -le $Retries; $i++) {
        $r = Invoke-NpmCapture @('view', $Package, 'version')
        if ($r.ExitCode -eq 0) {
            $v = ConvertTo-VersionObject $r.StdOut
            if ($v) { return $v }
        }

        # npm は原因 (code ENOTFOUND / E404 など) を stderr の先頭に出す。末尾の
        # "A complete log of this run..." は情報量がないので落とす。
        $lines  = @($r.StdErr -split "`r?`n" | Where-Object { $_ -and ($_ -notmatch 'A complete log of this run') })
        $reason = if ($lines) { ($lines | Select-Object -First 2) -join ' / ' }
                  else        { "npm exit=$($r.ExitCode) / 出力='$($r.StdOut)'" }
        Write-Warn2 ("npm view {0} に失敗 ({1}/{2}) : {3}" -f $Package, $i, $Retries, $reason)

        if ($i -lt $Retries) { Start-Sleep -Seconds (2 * $i) }
    }
    return $null
}

function Resolve-ClaudePath {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:USERPROFILE '.claude\local\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe')
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-ClaudeInstalledVersion {
    param([string]$Path)
    if (-not $Path) { return $null }
    try {
        $out = & $Path --version 2>&1 | Out-String
        return (ConvertTo-VersionObject $out)
    } catch { return $null }
}

function Get-ClaudeLatestVersion {
    # ネイティブビルドの最新バージョンは npm 上のメタデータが最も新鮮。
    return (Get-NpmLatestVersion -Package '@anthropic-ai/claude-code')
}

function Update-ClaudeCli {
    param([string]$Path)
    if ($Path) {
        Write-Info "claude update を実行します..."
        & $Path update
        if ($LASTEXITCODE -ne 0) { throw "claude update が失敗しました (exit=$LASTEXITCODE)" }
    } else {
        Write-Info "Claude Code が未インストールです。公式インストーラで導入します..."
        # Windows 公式インストール手順 (PowerShell): irm でスクリプトを取得して実行
        $script = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' -UseBasicParsing
        Invoke-Expression $script
    }
}

function Get-CodexInstalledVersion {
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    try {
        $out = & codex --version 2>&1 | Out-String
        return (ConvertTo-VersionObject $out)
    } catch { return $null }
}

function Get-CodexLatestVersion {
    return (Get-NpmLatestVersion -Package '@openai/codex')
}

function Remove-NpmCodexLeftovers {
    # npm が @openai スコープ配下に残すステージング用一時ディレクトリ
    # (.codex-XXXX) を掃除する。Windows Defender 等が展開直後の codex.exe を
    # 一時的にロックし、npm 自身の cleanup が EPERM で失敗して残骸が蓄積する
    # ため、ロック解放を待ちながらリトライ削除する。
    $r = Invoke-NpmCapture @('root', '-g')
    if ($r.ExitCode -ne 0) { return }
    $root = ($r.StdOut -split "`n" | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($root)) { return }
    $scope = Join-Path $root.Trim() '@openai'
    if (-not (Test-Path -LiteralPath $scope)) { return }

    $leftovers = @(Get-ChildItem -LiteralPath $scope -Directory -Filter '.codex-*' -Force -ErrorAction SilentlyContinue)
    if ($leftovers.Count -eq 0) { return }

    $removed = @()
    $failed  = @()
    foreach ($dir in $leftovers) {
        $ok = $false
        for ($i = 1; $i -le 5 -and -not $ok; $i++) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                $ok = $true
            } catch {
                Start-Sleep -Milliseconds 700
            }
        }
        if ($ok) { $removed += $dir.Name } else { $failed += $dir.Name }
    }

    if ($removed.Count -gt 0) {
        Write-Info ("npm の一時ステージング残骸を掃除しました ({0} 件)。" -f $removed.Count)
    }
    if ($failed.Count -gt 0) {
        Write-Warn2 ("残存ステージングを削除できませんでした ({0} 件): {1}" -f $failed.Count, ($failed -join ', '))
        # 実行中の codex がバイナリを掴んでいると、短いリトライでは絶対に解放されない。
        # 原因を明示して「codex を閉じてから再実行」に誘導する。
        $running = @(Get-Process -Name 'codex*' -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            Write-Warn2 ("codex 関連プロセスが {0} 個実行中のためロックされています。終了後に再実行すると削除されます。" -f $running.Count)
        } else {
            Write-Warn2 "ウイルス対策ソフトのスキャン等でロックされている可能性があります (次回実行時に再試行されます)。"
        }
    }
}

function Update-CodexCli {
    Write-Info "npm install -g @openai/codex@latest を実行します..."
    # `npm warn cleanup ... EPERM` は Windows で AV 等が新規 exe を一時ロックする
    # ために出るだけで、インストール自体は成功する。ログレベルを error に絞って
    # 警告ノイズを抑制する (成功判定は下の LASTEXITCODE とバージョン再確認で担保)。
    $r = Invoke-NpmCapture @('install', '-g', '@openai/codex@latest', '--loglevel=error')
    if ($r.StdOut) { Write-Host $r.StdOut }
    if ($r.ExitCode -ne 0) {
        if ($r.StdErr) { Write-Host $r.StdErr }
        throw "npm install が失敗しました (exit=$($r.ExitCode))"
    }
    # npm が消し損ねたステージング残骸を掃除する。
    Remove-NpmCodexLeftovers
}

# winget での新規導入直後は、このプロセスの PATH に導入先が入っていないため、MSI が記録する InstallDir も探す。
function Resolve-GhPath {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($key in 'HKLM:\SOFTWARE\GitHub\CLI', 'HKCU:\SOFTWARE\GitHub\CLI') {
        $dir = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).InstallDir
        if ($dir) {
            $exe = Join-Path $dir 'gh.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    }
    return $null
}

function Get-GhInstalledVersion {
    $path = Resolve-GhPath
    if (-not $path) { return $null }
    try {
        # 1 行目が "gh version 2.x.y (yyyy-mm-dd)"。日付は x.y.z 形式に一致しないので誤検出しない。
        $out = & $path --version 2>&1 | Out-String
        return (ConvertTo-VersionObject $out)
    } catch { return $null }
}

# GitHub CLI は npm で配布されていないため、GitHub Releases の latest から取得する。
function Get-GhLatestVersion {
    param([int]$Retries = 3)

    # Windows PowerShell 5.1 の既定では TLS 1.2 が無効で api.github.com に接続できないため。
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'cli-updater'; 'Accept' = 'application/vnd.github+json' }

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -Headers $headers -UseBasicParsing
            $v = ConvertTo-VersionObject $rel.tag_name
            if ($v) { return $v }
            $reason = "tag_name を解釈できません ('$($rel.tag_name)')"
        } catch {
            $reason = $_.Exception.Message
        }
        Write-Warn2 ("GitHub Releases (cli/cli) の取得に失敗 ({0}/{1}) : {2}" -f $i, $Retries, $reason)
        if ($i -lt $Retries) { Start-Sleep -Seconds (2 * $i) }
    }
    return $null
}

function Update-GhCli {
    param([bool]$IsInstalled)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget が見つかりません。App Installer を導入するか、https://cli.github.com/ から手動で更新してください。"
    }

    $common = @('--id', 'GitHub.cli', '--exact', '--silent', '--disable-interactivity',
                '--accept-source-agreements', '--accept-package-agreements')
    # winget upgrade は同じバージョンを入れ直せないため、未導入時と -Force 時は install を使う。
    $verb = if ($IsInstalled -and -not $Force.IsPresent) { 'upgrade' } else { 'install' }
    $extra = @(if ($Force.IsPresent) { '--force' })

    Write-Info "winget $verb --id GitHub.cli を実行します (管理者権限の確認が表示されることがあります)..."
    & winget $verb @common @extra
    $code = $LASTEXITCODE

    # winget の終了コード: 0x8A15002B = 適用できる更新がない, 0x8A150014 = 該当パッケージが見つからない
    $UPDATE_NOT_APPLICABLE = -1978335189
    $NO_APPLICATIONS_FOUND = -1978335212
    switch ($code) {
        0 { return }
        $UPDATE_NOT_APPLICABLE {
            throw "winget のカタログに最新版がまだ反映されていません。時間をおいて再実行してください。"
        }
        $NO_APPLICATIONS_FOUND {
            throw "gh は winget 以外 (scoop, choco, 手動配置など) で導入されているため更新できません。導入に使った方法で更新してください。"
        }
        default { throw ("winget {0} が失敗しました (exit=0x{1:X8})" -f $verb, $code) }
    }
}

function Invoke-CliCheck {
    param(
        [string]$Name,
        [scriptblock]$GetInstalled,
        [scriptblock]$GetLatest,
        [scriptblock]$DoUpdate
    )

    Write-Section "$Name"
    $installed = & $GetInstalled
    $latest    = & $GetLatest

    if ($null -eq $installed) { Write-Warn2 "$Name はインストールされていません。" }
    else                      { Write-Info  "現在のバージョン : $installed" }

    if ($null -eq $latest) {
        Write-Err2 "$Name の最新バージョンを取得できませんでした (ネットワーク/npm を確認)。"
        return [pscustomobject]@{ Name=$Name; Installed=$installed; Latest=$null; Action='skipped' }
    }
    Write-Info "最新バージョン   : $latest"

    $needsUpdate = ($null -eq $installed) -or ($installed -lt $latest) -or $Force.IsPresent
    if (-not $needsUpdate) {
        Write-Ok "$Name は最新です。更新は不要です。"
        return [pscustomobject]@{ Name=$Name; Installed=$installed; Latest=$latest; Action='up-to-date' }
    }

    try {
        # 更新コマンドの出力を戻り値の結果オブジェクトに混ぜないため、画面へ流す。
        & $DoUpdate | Out-Host
    } catch {
        Write-Err2 "$Name の更新中にエラー: $($_.Exception.Message)"
        return [pscustomobject]@{ Name=$Name; Installed=$installed; Latest=$latest; Action='failed' }
    }

    # 更新後の検証
    $after = & $GetInstalled
    if ($after -and $after -ge $latest) {
        Write-Ok "$Name を $after に更新しました。"
        return [pscustomobject]@{ Name=$Name; Installed=$after; Latest=$latest; Action='updated' }
    } else {
        Write-Warn2 "$Name の更新後バージョン確認に失敗 (after=$after / latest=$latest)。"
        return [pscustomobject]@{ Name=$Name; Installed=$after; Latest=$latest; Action='verification-failed' }
    }
}

# --- 前提: npm が必要 -----------------------------------------------------
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Err2 "npm が見つかりません。Node.js をインストールしてから再実行してください。"
    exit 1
}

Write-Section "CLI 更新チェック開始"
Write-Info ("実行ユーザー : {0}" -f $env:USERNAME)
Write-Info ("実行ホスト   : {0}" -f $env:COMPUTERNAME)
Write-Info ("日時         : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

$results = @()

# Claude Code
$claudePath = Resolve-ClaudePath
if ($claudePath) { Write-Info "Claude Code パス : $claudePath" }
$results += Invoke-CliCheck `
    -Name 'Claude Code CLI' `
    -GetInstalled { Get-ClaudeInstalledVersion -Path $claudePath } `
    -GetLatest    { Get-ClaudeLatestVersion } `
    -DoUpdate     { Update-ClaudeCli -Path $claudePath }

# Codex
$results += Invoke-CliCheck `
    -Name 'Codex CLI' `
    -GetInstalled { Get-CodexInstalledVersion } `
    -GetLatest    { Get-CodexLatestVersion } `
    -DoUpdate     { Update-CodexCli }

# GitHub CLI
$results += Invoke-CliCheck `
    -Name 'GitHub CLI' `
    -GetInstalled { Get-GhInstalledVersion } `
    -GetLatest    { Get-GhLatestVersion } `
    -DoUpdate     { Update-GhCli -IsInstalled ($null -ne (Get-GhInstalledVersion)) }

Write-Section "結果サマリ"
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# 失敗があれば非ゼロで終了 (skipped = 最新版を取得できず更新判定不能。成功ではない)
$hasFailure = $results | Where-Object { $_.Action -in @('failed','verification-failed','skipped') }
if ($hasFailure) { exit 2 }
exit 0
