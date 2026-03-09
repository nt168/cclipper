#!/usr/bin/env bash
# ==============================================================
# build.sh
# 功能：
#   完整构建流程：configure -> make
# 参数：
#   $1: 项目目录（包含源文件的项目根目录）
#   $2: 输出目录（可选，默认为当前目录下的build/）
# 使用：
#   ./build.sh /tmp/zbx_test
#   ./build.sh /tmp/zbx_test /tmp/zbx_test_build
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 参数处理
if [[ $# -lt 1 ]]; then
    cat <<EOF
用法: $0 <项目目录> [输出目录]

功能:
  完整构建流程，包括：
  1. 系统环境检测 (configure)
  2. 依赖分析
  3. 编译 (make)
  4. 运行测试 (可选)

参数:
  项目目录  - 包含 Makefile 的项目根目录
  输出目录  - 构建输出目录（可选，默认：项目目录/build/）

示例:
  $0 /tmp/zbx_test
  $0 /tmp/zbx_test /tmp/zbx_test_build

流程:
  1. 检测系统环境，生成 config.h 和 compat.h
  2. 分析缺失依赖，生成 deps_impl.c
  3. 编译项目
  4. 运行测试程序

EOF
    exit 1
fi

PROJECT_DIR="$1"
BUILD_DIR="${2:-${PROJECT_DIR}/build}"

# 验证项目目录
if [[ ! -d "$PROJECT_DIR" ]]; then
    error "项目目录不存在: $PROJECT_DIR"
    exit 1
fi

if [[ ! -f "${PROJECT_DIR}/Makefile" ]]; then
    error "未找到 Makefile: ${PROJECT_DIR}/Makefile"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "自动构建工具"
echo "========================================"
echo
echo "项目目录: $PROJECT_DIR"
echo "构建目录: $BUILD_DIR"
echo

# 第一步：系统环境检测
echo "==> 步骤1: 系统环境检测..."
CONFIGURE_SCRIPT="${SCRIPT_DIR}/configure.sh"

if [[ ! -x "$CONFIGURE_SCRIPT" ]]; then
    error "未找到 configure.sh"
    exit 1
fi

mkdir -p "${PROJECT_DIR}/include"
"$CONFIGURE_SCRIPT" -o "${PROJECT_DIR}/include" -p "$(basename "$PROJECT_DIR")"

# 第二步：复制项目到构建目录
echo
echo "==> 步骤2: 准备构建目录..."

if [[ "$BUILD_DIR" != "$PROJECT_DIR" ]]; then
    # 清理旧的构建目录
    rm -rf "$BUILD_DIR"
    mkdir -p "$(dirname "$BUILD_DIR")"
    
    # 复制项目文件（排除build目录本身）
    mkdir -p "$BUILD_DIR"
    (cd "$PROJECT_DIR" && find . -maxdepth 1 ! -name '.' ! -name 'build' -exec cp -r {} "$BUILD_DIR/" \;)
    
    success "已复制到构建目录"
else
    success "使用项目目录作为构建目录"
fi

# 第三步：自动检测并生成依赖
echo
echo "==> 步骤3: 检测缺失依赖..."

DETECT_DEPS="${SCRIPT_DIR}/detect_dependencies.sh"

if [[ ! -x "$DETECT_DEPS" ]]; then
    error "未找到 detect_dependencies.sh"
    exit 1
fi

# 尝试第一次编译
cd "$BUILD_DIR"
make clean 2>/dev/null || true

info "尝试编译..."
if make 2>&1 | tee /tmp/build.log | grep -q "undefined reference"; then
    warning "发现缺失依赖"
    
    # 分析缺失的符号
    "$DETECT_DEPS" "${BUILD_DIR}/src" "$BUILD_DIR"
    
    # 重新编译
    echo
    info "重新编译..."
    make clean 2>/dev/null || true
    
    if make 2>&1 | tee /tmp/build2.log | grep -q "undefined reference"; then
        warning "仍有缺失依赖，尝试第二次生成..."
        
        # 第二次检测
        "$DETECT_DEPS" "${BUILD_DIR}/src" "$BUILD_DIR"
        make clean 2>/dev/null || true
        
        if make 2>&1 | tee /tmp/build3.log | grep -q "undefined reference"; then
            error "自动依赖生成失败，请手动补充"
            echo
            echo "缺失的符号:"
            grep "undefined reference to" /tmp/build3.log | sed "s/.*undefined reference to \`\(.*\)'.*/  - \1/" | sort -u
            echo
            echo "请手动编辑 ${BUILD_DIR}/src/deps_impl.c 添加实现"
            exit 1
        fi
    fi
fi

success "编译成功"

# 第四步：检查可执行文件
echo
echo "==> 步骤4: 验证构建结果..."

EXECUTABLE=$(find "$BUILD_DIR" -maxdepth 1 -type f -executable -name "test_*" | head -n1 || true)

if [[ -z "$EXECUTABLE" ]]; then
    warning "未找到可执行文件"
else
    success "可执行文件: $EXECUTABLE"
    
    # 第五步：运行测试
    echo
    echo "==> 步骤5: 运行测试..."
    echo "----------------------------------------"
    "$EXECUTABLE"
    echo "----------------------------------------"
fi

# 完成
echo
echo "========================================"
echo "✅ 构建完成！"
echo "========================================"
echo
echo "构建目录: $BUILD_DIR"
if [[ -n "$EXECUTABLE" ]]; then
    echo "可执行文件: $EXECUTABLE"
    echo
    echo "运行命令: $EXECUTABLE"
fi
echo