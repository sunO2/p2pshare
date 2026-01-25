#!/bin/bash
# FFI 库跨平台编译脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FFI_DIR="$PROJECT_ROOT/crates/ffi"
OUTPUT_DIR="$FFI_DIR/target"

echo "==================================="
echo "Local P2P FFI 构建脚本"
echo "==================================="
echo ""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
TARGET="${1:-all}"
CLEAN="${2:-false}"

# 清理函数
clean_build() {
    echo -e "${YELLOW}清理构建产物...${NC}"
    cd "$FFI_DIR"
    cargo clean
}

if [ "$CLEAN" = "true" ]; then
    clean_build
fi

# 构建函数
build_target() {
    local target=$1
    local rust_target=$2

    echo -e "${GREEN}构建 $target ($rust_target)...${NC}"

    cd "$FFI_DIR"

    # 添加目标（如果需要）
    if [ "$rust_target" != "" ]; then
        rustup target add "$rust_target" 2>/dev/null || true
    fi

    # 构建
    if [ "$rust_target" != "" ]; then
        cargo build --target "$rust_target" --release
    else
        cargo build --release
    fi

    # 复制库文件到输出目录
    local lib_name=""
    local ext=""
    case "$target" in
        linux|x64*)
            lib_name="liblocalp2p_ffi"
            ext=".so"
            rust_target="${rust_target:-x86_64-unknown-linux-gnu}"
            ;;
        macos|macos-arm64|macos-x64)
            lib_name="liblocalp2p_ffi"
            ext=".dylib"
            ;;
        windows)
            lib_name="localp2p_ffi"
            ext=".dll"
            rust_target="${rust_target:-x86_64-pc-windows-msvc}"
            ;;
        android-arm64)
            lib_name="liblocalp2p_ffi"
            ext=".so"
            rust_target="aarch64-linux-android"
            ;;
        android-armv7)
            lib_name="liblocalp2p_ffi"
            ext=".so"
            rust_target="armv7-linux-androideabi"
            ;;
        android-x64)
            lib_name="liblocalp2p_ffi"
            ext=".so"
            rust_target="x86_64-linux-android"
            ;;
        ios-arm64)
            lib_name="localp2p_ffi"
            ext=".a"
            rust_target="aarch64-apple-ios"
            ;;
        ios-simulator)
            lib_name="localp2p_ffi"
            ext=".a"
            rust_target="aarch64-apple-ios-sim"
            ;;
        *)
            echo -e "${RED}未知目标: $target${NC}"
            return 1
            ;;
    esac

    local src_file="$FFI_DIR/target/$rust_target/release/$lib_name$ext"
    local dst_dir="$OUTPUT_DIR/$target"
    local dst_file="$dst_dir/$lib_name$ext"

    mkdir -p "$dst_dir"
    if [ -f "$src_file" ]; then
        cp "$src_file" "$dst_file"
        echo -e "${GREEN}✓ 已复制到: $dst_file${NC}"
    else
        echo -e "${YELLOW}⚠ 文件不存在: $src_file${NC}"
    fi
}

# 构建所有目标
build_all() {
    echo -e "${GREEN}构建所有平台...${NC}"
    echo ""

    # 检测操作系统
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)
            build_target "linux" "x86_64-unknown-linux-gnu"
            ;;
        Darwin)
            if [ "$ARCH" = "arm64" ]; then
                build_target "macos-arm64" "aarch64-apple-darwin"
            else
                build_target "macos-x64" "x86_64-apple-darwin"
            fi
            # iOS（需要 macOS 和 Xcode）
            if command -v xcrun &> /dev/null; then
                build_target "ios-arm64" "aarch64-apple-ios"
                build_target "ios-simulator" "aarch64-apple-ios-sim"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            build_target "windows" "x86_64-pc-windows-msvc"
            ;;
    esac

    # Android（需要 NDK）
    if command -v cargo-ndk &> /dev/null || [ -d "$ANDROID_NDK_HOME" ]; then
        build_target "android-arm64" "aarch64-linux-android"
        build_target "android-armv7" "armv7-linux-androideabi"
        build_target "android-x64" "x86_64-linux-android"
    fi
}

# 生成 C 头文件
generate_header() {
    echo -e "${GREEN}生成 C 头文件...${NC}"
    cd "$FFI_DIR"
    mkdir -p include
    # 头文件已经手动创建，这里只是确认
    if [ -f "include/localp2p.h" ]; then
        echo -e "${GREEN}✓ C 头文件已存在${NC}"
    fi
}

# 主逻辑
case "$TARGET" in
    all)
        build_all
        ;;
    linux|x64|macos|macos-arm64|macos-x64|windows|android-*)
        build_target "$TARGET" ""
        ;;
    ios-*)
        build_target "$TARGET" ""
        ;;
    clean)
        clean_build
        ;;
    header)
        generate_header
        ;;
    *)
        echo -e "${RED}未知目标: $TARGET${NC}"
        echo ""
        echo "用法: $0 [target] [clean]"
        echo ""
        echo "可用目标:"
        echo "  all           - 构建所有平台（默认）"
        echo "  linux         - Linux x64"
        echo "  macos-arm64   - macOS ARM64"
        echo "  macos-x64     - macOS x64"
        echo "  windows       - Windows x64"
        echo "  android-arm64 - Android ARM64"
        echo "  android-armv7 - Android ARMv7"
        echo "  android-x64   - Android x64"
        echo "  ios-arm64     - iOS ARM64"
        echo "  ios-simulator - iOS 模拟器"
        echo "  clean         - 清理构建产物"
        echo "  header        - 生成 C 头文件"
        echo ""
        echo "示例:"
        echo "  $0 all              # 构建所有平台"
        echo "  $0 linux           # 只构建 Linux"
        echo "  $0 macos-arm64 clean  # 清理并构建 macOS ARM64"
        exit 1
        ;;
esac

# 生成头文件
generate_header

echo ""
echo -e "${GREEN}==================================="
echo "构建完成！"
echo "===================================${NC}"
echo ""
echo "输出目录: $OUTPUT_DIR"
echo ""

# 列出生成的文件
if [ -d "$OUTPUT_DIR" ]; then
    echo "生成的文件:"
    find "$OUTPUT_DIR" -type f \( -name "*.so" -o -name "*.dylib" -o -name "*.dll" -o -name "*.a" \) 2>/dev/null | while read file; do
        size=$(ls -lh "$file" | awk '{print $5}')
        echo "  - $file ($size)"
    done
fi
