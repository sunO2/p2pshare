# ==============================================================================
# Android FFI 库交叉编译脚本 (PowerShell)
# 用于生成 Android 不同 CPU 架构的 .so 库文件
# ==============================================================================

# 错误时停止
$ErrorActionPreference = "Stop"

# 项目路径
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$FfiCrateDir = Join-Path $ProjectRoot "crates\ffi"
$AndroidJniDir = Join-Path $ProjectRoot "app\android\src\main\jniLibs"

# 目标架构
$Targets = @(
    @{ Triple = "aarch64-linux-android"; Abi = "arm64-v8a" },
    @{ Triple = "armv7-linux-androideabi"; Abi = "armeabi-v7a" },
    @{ Triple = "x86_64-linux-android"; Abi = "x86_64" },
    @{ Triple = "i686-linux-android"; Abi = "x86" }
)

# API 级别
$AndroidApiLevel = 21

Write-Host "========================================" -ForegroundColor Blue
Write-Host "  Android FFI 库交叉编译脚本" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# 检查必要的工具
Write-Host "[1/5] 检查编译环境..." -ForegroundColor Yellow
try {
    $null = Get-Command cargo -ErrorAction Stop
    $null = Get-Command rustup -ErrorAction Stop
    Write-Host "✓ 环境检查完成" -ForegroundColor Green
} catch {
    Write-Host "✗ 错误: 未找到 Rust 工具链，请先安装 Rust" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 安装交叉编译工具链
Write-Host "[2/5] 安装交叉编译工具链..." -ForegroundColor Yellow

foreach ($target in $Targets) {
    $triple = $target.Triple
    $installed = rustup target list --installed 2>$null | Select-String -Pattern $triple -Quiet

    if ($installed) {
        Write-Host "  ✓ $triple 已安装" -ForegroundColor Green
    } else {
        Write-Host "  → 安装 $triple..." -ForegroundColor Blue
        rustup target add $triple
    }
}

Write-Host "✓ 工具链安装完成" -ForegroundColor Green
Write-Host ""

# 清理旧的 jniLibs 目录
Write-Host "[3/5] 清理旧的库文件..." -ForegroundColor Yellow
if (Test-Path $AndroidJniDir) {
    Write-Host "  → 删除 $AndroidJniDir" -ForegroundColor Blue
    Remove-Item -Path $AndroidJniDir -Recurse -Force
}
New-Item -ItemType Directory -Path $AndroidJniDir -Force | Out-Null
Write-Host "✓ 清理完成" -ForegroundColor Green
Write-Host ""

# 交叉编译库文件
Write-Host "[4/5] 交叉编译库文件..." -ForegroundColor Yellow

Push-Location $ProjectRoot

foreach ($target in $Targets) {
    $triple = $target.Triple
    $abi = $target.Abi

    Write-Host "  → 编译 $abi ($triple)..." -ForegroundColor Blue

    # 编译
    cargo build --package localp2p-ffi `
        --target $triple `
        --release `
        --lib

    # 复制到 jniLibs 目录
    $targetDir = Join-Path $AndroidJniDir $abi
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    $sourceFile = Join-Path $ProjectRoot "target\$triple\release\liblocalp2p_ffi.so"

    if (Test-Path $sourceFile) {
        Copy-Item -Path $sourceFile -Destination $targetDir -Force
        $size = (Get-Item $sourceFile).Length / 1KB
        Write-Host "    ✓ 已复制到 $abi/ ($([math]::Round($size, 2)) KB)" -ForegroundColor Green
    } else {
        Write-Host "    ✗ 未找到输出文件: $sourceFile" -ForegroundColor Red
    }
}

Pop-Location

Write-Host "✓ 编译完成" -ForegroundColor Green
Write-Host ""

# 显示编译结果
Write-Host "[5/5] 编译结果摘要" -ForegroundColor Yellow
Write-Host ""
Write-Host "生成的库文件:" -ForegroundColor Blue

foreach ($target in $Targets) {
    $abi = $target.Abi
    $libFile = Join-Path $AndroidJniDir "$abi\liblocalp2p_ffi.so"

    if (Test-Path $libFile) {
        $size = (Get-Item $libFile).Length / 1KB
        Write-Host "  ✓ $abi/liblocalp2p_ffi.so ($([math]::Round($size, 2)) KB)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $abi/liblocalp2p_ffi.so (未生成)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host "  构建完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
Write-Host "库文件已生成到: $AndroidJniDir"
Write-Host ""
Write-Host "现在可以构建 Android APK:"
Write-Host "  cd app" -ForegroundColor Yellow
Write-Host "  flutter build apk" -ForegroundColor Yellow
Write-Host ""
