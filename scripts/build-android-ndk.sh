#!/bin/bash
# ==============================================================================
# Android FFI 库编译脚本 (使用 cargo-ndk)
# ==============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 项目路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_JNI_DIR="$PROJECT_ROOT/app/android/app/src/main/jniLibs"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android FFI 库编译 (cargo-ndk)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 生成 Flutter Rust Bridge 代码
echo -e "${YELLOW}[1/4] 生成 Flutter Rust Bridge 代码...${NC}"
if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
    echo -e "${RED}错误: 未找到 flutter_rust_bridge_codegen${NC}"
    echo ""
    echo "请安装 flutter_rust_bridge_codegen:"
    echo "  cargo install flutter_rust_bridge_codegen"
    echo ""
    exit 1
fi

# 生成 Dart 和 Rust 代码
echo -e "  ${BLUE}生成 Dart 和 Rust 绑定代码...${NC}"
flutter_rust_bridge_codegen generate \
    -r localp2p-ffi::bridge \
    -d app/lib/bridge \
    --rust-root crates/ffi \
    --rust-output crates/ffi/src/frb_generated.rs > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ FRB 代码生成失败${NC}"
    exit 1
fi

# 自动修复生成代码中的路径问题（localp2p_ffi:: -> crate::）
echo -e "  ${BLUE}修复生成代码中的路径引用...${NC}"
# 修复 use 语句中的路径
sed -i 's/use localp2p_ffi::bridge::\*/use crate::bridge::*;/g' crates/ffi/src/frb_generated.rs
# 修复所有函数调用中的路径
sed -i 's/localp2p_ffi::bridge::/crate::bridge::/g' crates/ffi/src/frb_generated.rs
# 修复双分号问题
sed -i 's/;;/;/g' crates/ffi/src/frb_generated.rs

echo -e "${GREEN}✓ FRB 代码生成完成${NC}"
echo ""

# 检查 cargo-ndk 是否安装
echo -e "${YELLOW}[2/4] 检查 cargo-ndk...${NC}"
if ! command -v cargo-ndk &> /dev/null; then
    echo -e "${RED}错误: 未找到 cargo-ndk${NC}"
    echo ""
    echo "请安装 cargo-ndk:"
    echo "  cargo install cargo-ndk"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ cargo-ndk 已安装${NC}"
echo ""

# 检查 ANDROID_NDK_HOME
echo -e "${YELLOW}[2/3] 检查 Android NDK...${NC}"
if [ -z "$ANDROID_NDK_HOME" ]; then
    # 尝试从常见位置查找 NDK
    POSSIBLE_NDK_PATHS=(
        "$HOME/Android/Sdk/ndk"
        "$HOME/.android/ndk"
        "/opt/android-sdk/ndk"
    )

    for ndk_base in "${POSSIBLE_NDK_PATHS[@]}"; do
        if [ -d "$ndk_base" ]; then
            # 查找最新版本的 NDK
            NDK_VERSION=$(ls -t "$ndk_base" | head -n1)
            export ANDROID_NDK_HOME="$ndk_base/$NDK_VERSION"
            break
        fi
    done

    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo -e "${RED}错误: 未找到 Android NDK${NC}"
        echo ""
        echo "请安装 Android NDK 或设置 ANDROID_NDK_HOME 环境变量:"
        echo "  export ANDROID_NDK_HOME=/path/to/your/ndk"
        echo ""
        exit 1
    fi
fi

echo -e "${GREEN}✓ NDK 路径: $ANDROID_NDK_HOME${NC}"
echo ""

# 清理并创建输出目录
echo -e "${YELLOW}[3/4] 清理旧的库文件...${NC}"
if [ -d "$ANDROID_JNI_DIR" ]; then
    rm -rf "$ANDROID_JNI_DIR"
fi
mkdir -p "$ANDROID_JNI_DIR"
echo -e "${GREEN}✓ 清理完成${NC}"
echo ""

# 编译所有架构
echo -e "${YELLOW}[4/4] 编译库文件...${NC}"
echo ""
echo -e "${BLUE}开始编译...${NC}"
echo ""

cd "$PROJECT_ROOT"
# 只编译 localp2p-ffi 包，不编译整个 workspace
cargo ndk --target arm64-v8a --target armeabi-v7a --target x86_64 --target x86 --platform 21 -o "$ANDROID_JNI_DIR" -- build --release -p localp2p-ffi

echo ""
echo -e "${GREEN}✓ 编译完成${NC}"
echo ""

# 显示结果
echo -e "${BLUE}生成的库文件:${NC}"
echo ""

for abi_dir in "$ANDROID_JNI_DIR"/*; do
    if [ -d "$abi_dir" ]; then
        abi_name=$(basename "$abi_dir")
        lib_file="$abi_dir/liblocalp2p_ffi.so"

        if [ -f "$lib_file" ]; then
            size=$(du -h "$lib_file" | cut -f1)
            echo -e "  ${GREEN}✓${NC} $abi_name/liblocalp2p_ffi.so ($size)"
        fi
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  构建完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "库文件已生成到: ${ANDROID_JNI_DIR}"
echo ""
echo -e "现在可以构建 Android APK:"
echo -e "  ${YELLOW}cd app && flutter build apk${NC}"
echo ""
