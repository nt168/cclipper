#!/bin/bash
# auto_extract_deps.sh - 自动提取缺失的函数依赖
# 用法: ./auto_extract_deps.sh <目标文件.o> <源码根目录> <输出目录>

set -euo pipefail

OBJ_FILE="$1"
SRC_ROOT="$2"
OUTPUT_DIR="$3"

echo "=========================================="
echo "自动依赖提取工具"
echo "=========================================="
echo "目标文件: $OBJ_FILE"
echo "源码根目录: $SRC_ROOT"
echo "输出目录: $OUTPUT_DIR"
echo

# 获取所有未定义的外部符号
echo "==> 步骤1: 检测未定义符号..."
UNDEFINED=$(nm "$OBJ_FILE" 2>/dev/null | grep ' U ' | awk '{print $2}' || true)

if [[ -z "$UNDEFINED" ]]; then
    echo "✓ 未发现未定义符号"
    exit 0
fi

echo "发现未定义符号:"
echo "$UNDEFINED" | while read sym; do
    echo "  - $sym"
done
echo

# 对每个未定义符号搜索实现
echo "==> 步骤2: 搜索函数实现..."
FOUND_FILES=()

for sym in $UNDEFINED; do
    # 搜索函数定义（多种模式）
    patterns=(
        "^.*[[:space:]]${sym}[[:space:]]*("
        "^.*[[:space:]]\\*?[[:space:]]*${sym}[[:space:]]*("
        "^.*${sym}[[:space:]]*\("
    )
    
    for pattern in "${patterns[@]}"; do
        FOUND=$(grep -r "$pattern" "$SRC_ROOT" --include="*.c" -l 2>/dev/null | head -1 || true)
        
        if [[ -n "$FOUND" ]]; then
            echo "✓ 找到 $sym: $FOUND"
            FOUND_FILES+=("$FOUND")
            break
        else
            echo "✗ 未找到 $sym"
        fi
    done
done

if [[ ${#FOUND_FILES[@]} -eq 0 ]]; then
    echo
    echo "⚠️  未找到任何函数实现"
    exit 1
fi

echo
echo "==> 步骤3: 复制文件到输出目录..."

# 去重
UNIQUE_FILES=($(echo "${FOUND_FILES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

for file in "${UNIQUE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        cp "$file" "$OUTPUT_DIR/src/"
        echo "  ✓ 复制: $(basename "$file")"
    fi
done

echo
echo "=========================================="
echo "✅ 提取完成"
echo "=========================================="
echo "复制了 ${#UNIQUE_FILES[@]} 个文件"
echo "下一步: make clean && make"