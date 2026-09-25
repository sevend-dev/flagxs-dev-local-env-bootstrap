#Requires -Version 5.1
#
# flagxs 開発環境構築のブートストラップスクリプト（Windows 側）。
# WSL と Ubuntu、開発に必須な Windows のツールをインストールする。
#
# 実行コマンドを含む手順は社内の開発ドキュメントに記載している。
# 実行後は Ubuntu 側で install.sh を実行すること。
#
# 再実行しても安全である。インストール済みのもの・作成済みのものはスキップする。
#
$ErrorActionPreference = 'Stop'

$UbuntuDistribution = 'Ubuntu-26.04'

# winget でインストールする開発に必須なツール
$WingetPackages = @(
    @{ Id = 'Docker.DockerDesktop'; Name = 'Docker Desktop' }
    @{ Id = 'Microsoft.VisualStudioCode'; Name = 'Visual Studio Code' }
    @{ Id = 'JetBrains.Toolbox'; Name = 'JetBrains Toolbox' }
    @{ Id = 'Fork.Fork'; Name = 'Fork' }
    @{ Id = 'DBeaver.DBeaver.Community'; Name = 'DBeaver' }
    @{ Id = 'JGraph.Draw'; Name = 'draw.io' }
)

function Write-Log {
    param([string]$Message)
    Write-Host '==> ' -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Test-Prerequisites {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'PowerShell を管理者として実行してから、もう一度実行してください。'
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget が見つかりません。Microsoft Store から「アプリ インストーラー」をインストールしてください。'
    }
}

# WSL 本体。有効化の直後は再起動が必要になることがあるため、その場合は $false を返して止める
function Install-Wsl {
    wsl.exe --status *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'WSL は既にインストール済みのためスキップします'
        Write-Log 'WSL を更新します'
        # 出力を Out-Host に流す。流さないと関数の戻り値に混ざり、$true / $false の判定が壊れる
        wsl.exe --update | Out-Host
        return $true
    }

    Write-Log 'WSL をインストールします'
    wsl.exe --install --no-distribution | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'WSL のインストールに失敗しました。'
    }

    wsl.exe --status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Log 'WSL を有効にするには PC の再起動が必要です。再起動後に、もう一度このスクリプトを実行してください。'
        return $false
    }
    return $true
}

# WSL が使うメモリの上限。既定のままだと開発中に不足しやすいため、物理メモリの半分を割り当てる。
# 既にファイルがあれば、個人の設定とみなして触らない
function New-WslConfig {
    $path = Join-Path $env:USERPROFILE '.wslconfig'
    if (Test-Path $path) {
        Write-Log "$path は既にあるため触りません"
        return
    }

    $totalGb = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $wslGb = [math]::Max([math]::Floor($totalGb / 2), 8)
    if ($totalGb -lt 32) {
        Write-Log "注意: 物理メモリが ${totalGb}GB です。開発には 32GB 以上を推奨します。"
    }

    $content = @"
[wsl2]
memory=${wslGb}GB
swap=${wslGb}GB

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@
    # BOM 付きの UTF-8 だと WSL が読めないため、ASCII で書く（内容は ASCII のみ）
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::ASCII)
    Write-Log "$path を作成しました（memory=${wslGb}GB）"
}

# winget install が「既にインストール済み」のときに返す終了コード。失敗ではないので成功として扱う
#   0x8A15002B: アップグレードの対象が無い / 0x8A150061: 既にインストール済み
$WingetAlreadyInstalledExitCodes = @(-1978335189, -1978335135)

function Test-WingetInstalled {
    param([string]$Id)
    winget list --id $Id --exact --accept-source-agreements *> $null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackages {
    foreach ($package in $WingetPackages) {
        if (Test-WingetInstalled $package.Id) {
            Write-Log "$($package.Name) は既にインストール済みのためスキップします"
            continue
        }
        Write-Log "$($package.Name) をインストールします"
        winget install --id $package.Id --exact --silent --accept-package-agreements --accept-source-agreements
        if ($WingetAlreadyInstalledExitCodes -contains $LASTEXITCODE) {
            Write-Log "$($package.Name) は既にインストール済みでした"
            continue
        }
        if ($LASTEXITCODE -ne 0) {
            throw "$($package.Name) のインストールに失敗しました。もう一度このスクリプトを実行してください。"
        }
    }
}

function Test-UbuntuInstalled {
    # wsl.exe -l の出力は UTF-16 のため、ヌル文字を除いてから比較する
    $distributions = (wsl.exe --list --quiet) -replace "`0", '' | ForEach-Object { $_.Trim() }
    return ($distributions -contains $UbuntuDistribution)
}

# ユーザーの作成は初回起動時の対話になるため、インストールだけ行い、起動は案内に回す。
# 初回起動までは一覧に出ないことがあるので、既定のディストリビューションにするのは一覧に出たときだけ
function Install-Ubuntu {
    if (Test-UbuntuInstalled) {
        Write-Log "$UbuntuDistribution は既にインストール済みのためスキップします"
    } else {
        Write-Log "$UbuntuDistribution をインストールします"
        wsl.exe --install $UbuntuDistribution --no-launch
        if ($LASTEXITCODE -ne 0) {
            throw "$UbuntuDistribution のインストールに失敗しました。"
        }
    }

    if (Test-UbuntuInstalled) {
        wsl.exe --set-default $UbuntuDistribution
    }
}

function Main {
    Test-Prerequisites
    if (-not (Install-Wsl)) {
        return
    }
    New-WslConfig
    Install-WingetPackages
    Install-Ubuntu
    Write-Log '社内の開発ドキュメントの手順に従って、Ubuntu 側の続きを進めてください'
}

# irm | iex で実行されるため、exit を使うと PowerShell のウィンドウごと閉じてしまう。
# エラーは throw で上げてここで表示し、ウィンドウは開いたままにする
try {
    Main
} catch {
    Write-Host 'Error: ' -ForegroundColor Red -NoNewline
    Write-Host $_.Exception.Message
}
