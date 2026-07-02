<#
.SYNOPSIS
    Claude Code CLI と Codex CLI のバージョンを確認し、古ければ最新版をインストールする。

.DESCRIPTION
    - Claude Code: ネイティブインストーラ版 (~/.local/bin/claude.exe) を想定し、
      組み込みの `claude update` で更新する。コマンドが見つからない場合は公式
      インストールスクリプトで新規導入する。
    - Codex CLI: npm グローバルパッケージ `@openai/codex` を `npm install -g` で更新する。

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
    try {
        $latest = & npm view '@anthropic-ai/claude-code' version 2>$null
        return (ConvertTo-VersionObject $latest)
    } catch { return $null }
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
    try {
        $latest = & npm view '@openai/codex' version 2>$null
        return (ConvertTo-VersionObject $latest)
    } catch { return $null }
}

function Remove-NpmCodexLeftovers {
    # npm が @openai スコープ配下に残すステージング用一時ディレクトリ
    # (.codex-XXXX) を掃除する。Windows Defender 等が展開直後の codex.exe を
    # 一時的にロックし、npm 自身の cleanup が EPERM で失敗して残骸が蓄積する
    # ため、ロック解放を待ちながらリトライ削除する。
    $root = try { (& npm root -g 2>$null | Select-Object -First 1) } catch { $null }
    if ([string]::IsNullOrWhiteSpace($root)) { return }
    $scope = Join-Path $root.Trim() '@openai'
    if (-not (Test-Path -LiteralPath $scope)) { return }

    $leftovers = @(Get-ChildItem -LiteralPath $scope -Directory -Filter '.codex-*' -Force -ErrorAction SilentlyContinue)
    if ($leftovers.Count -eq 0) { return }

    foreach ($dir in $leftovers) {
        $removed = $false
        for ($i = 1; $i -le 5 -and -not $removed; $i++) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                $removed = $true
            } catch {
                Start-Sleep -Milliseconds 700
            }
        }
        if (-not $removed) {
            Write-Warn2 ("残存ステージングを削除できませんでした (次回実行時に再試行されます): {0}" -f $dir.Name)
        }
    }
    Write-Info "npm の一時ステージング残骸を掃除しました。"
}

function Update-CodexCli {
    Write-Info "npm install -g @openai/codex@latest を実行します..."
    # `npm warn cleanup ... EPERM` は Windows で AV 等が新規 exe を一時ロックする
    # ために出るだけで、インストール自体は成功する。ログレベルを error に絞って
    # 警告ノイズを抑制する (成功判定は下の LASTEXITCODE とバージョン再確認で担保)。
    & npm install -g '@openai/codex@latest' --loglevel=error
    if ($LASTEXITCODE -ne 0) { throw "npm install が失敗しました (exit=$LASTEXITCODE)" }
    # npm が消し損ねたステージング残骸を掃除する。
    Remove-NpmCodexLeftovers
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
        & $DoUpdate
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

Write-Section "結果サマリ"
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# 失敗があれば非ゼロで終了
$hasFailure = $results | Where-Object { $_.Action -in @('failed','verification-failed') }
if ($hasFailure) { exit 2 }
exit 0
