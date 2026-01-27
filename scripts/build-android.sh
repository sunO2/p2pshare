#!/bin/bash
# ==============================================================================
# Android FFI 库交叉编译脚本
# 用于生成 Android 不同 CPU 架构的 .so 库文件
# ==============================================================================

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FFI_CRATE_DIR="$PROJECT_ROOT/crates/ffi"
ANDROID_JNI_DIR="$PROJECT_ROOT/app/android/app/src/main/jniLibs"

# 目标架构
TARGETS=(
    "aarch64-linux-android:arm64-v8a"
    "armv7-linux-androideabi:armeabi-v7a"
    "x86_64-linux-android:x86_64"
    "i686-linux-android:x86"
)

# API 级别（Android API 21+ 支持 64位）
ANDROID_API_LEVEL=21

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Android FFI 库交叉编译脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查必要的工具
echo -e "${YELLOW}[1/5] 检查编译环境...${NC}"
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}错误: 未找到 cargo，请先安装 Rust${NC}"
    exit 1
fi

if ! command -v rustup &> /dev/null; then
    echo -e "${RED}错误: 未找到 rustup${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 环境检查完成${NC}"
echo ""

# 安装交叉编译工具链
echo -e "${YELLOW}[2/5] 安装交叉编译工具链...${NC}"

install_target() {
    local target=$1
    if rustup target list --installed | grep -q "$target"; then
        echo -e "  ${GREEN}✓${NC} $target 已安装"
    else
        echo -e "  ${BLUE}→${NC} 安装 $target..."
        rustup target add "$target"
    fi
}

for target_pair in "${TARGETS[@]}"; do
    IFS=':' read -ra PARTS <<< "$target_pair"
    install_target "${PARTS[0]}"
done

echo -e "${GREEN}✓ 工具链安装完成${NC}"
echo ""

# 清理旧的 jniLibs 目录
echo -e "${YELLOW}[3/5] 清理旧的库文件...${NC}"
if [ -d "$ANDROID_JNI_DIR" ]; then
    echo -e "  ${BLUE}→${NC} 删除 $ANDROID_JNI_DIR"
    rm -rf "$ANDROID_JNI_DIR"
fi
mkdir -p "$ANDROID_JNI_DIR"
echo -e "${GREEN}✓ 清理完成${NC}"
echo ""

# 交叉编译库文件
echo -e "${YELLOW}[4/5] 交叉编译库文件...${NC}"

for target_pair in "${TARGETS[@]}"; do
    IFS=':' read -ra PARTS <<< "$target_pair"
    TARGET_TRIPLE="${PARTS[0]}"
    ANDROID_ABI="${PARTS[1]}"

    echo -e "  ${BLUE}→${NC} 编译 $ANDROID_ABI ($TARGET_TRIPLE)..."

    # 设置交叉编译环境变量
    export CARGO_TARGET_${TARGET_TRIPLE//-/_}_LINKER="${TARGET_TRIPLE}-gcc"

    # 编译
    cd "$PROJECT_ROOT"
    cargo build --package localp2p-ffi \
        --target "$TARGET_TRIPLE" \
        --release \
        --lib

    # 获取输出文件名
    if [[ "$TARGET_TRIPLE" == "windows"* ]]; then
        LIB_NAME="localp2p_ffi.dll"
    else
        LIB_NAME="liblocalp2p_ffi.so"
    fi

    # 复制到 jniLibs 目录
    TARGET_DIR="$ANDROID_JNI_DIR/$ANDROID_ABI"
    mkdir -p "$TARGET_DIR"

    SOURCE_FILE="$PROJECT_ROOT/target/$TARGET_TRIPLE/release/$LIB_NAME"
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "$TARGET_DIR/"
        echo -e "    ${GREEN}✓${NC} 已复制到 $ANDROID_ABI/"
    else
        echo -e "    ${RED}✗${NC} 未找到输出文件: $SOURCE_FILE"
    fi
done

echo -e "${GREEN}✓ 编译完成${NC}"
echo ""

# 显示编译结果
echo -e "${YELLOW}[5/5] 编译结果摘要${NC}"
echo ""
echo -e "${BLUE}生成的库文件:${NC}"

for target_pair in "${TARGETS[@]}"; do
    IFS=':' read -ra PARTS <<< "$target_pair"
    ANDROID_ABI="${PARTS[1]}"
    LIB_FILE="$ANDROID_JNI_DIR/$ANDROID_ABI/liblocalp2p_ffi.so"

    if [ -f "$LIB_FILE" ]; then
        SIZE=$(du -h "$LIB_FILE" | cut -f1)
        echo -e "  ${GREEN}✓${NC} $ANDROID_ABI/liblocalp2p_ffi.so ($SIZE)"
    else
        echo -e "  ${RED}✗${NC} $ANDROID_ABI/liblocalp2p_ffi.so (未生成)"
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
