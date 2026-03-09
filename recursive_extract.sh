#!/bin/bash
# recursive_extract.sh - 递归提取所有依赖直到编译成功
# 用法: ./recursive_extract.sh <源码根目录> <输出目录>

set -euo pipefail

SRC_ROOT="$1"
OUTPUT_DIR="$2"
MAX_ITERATIONS=20

echo "=========================================="
echo "递归依赖提取工具"
echo "=========================================="
echo

iteration=0
prev_undefined=""

while [[ $iteration -lt $MAX_ITERATIONS ]]; do
    iteration=$((iteration + 1))
    
    echo "==> 第 $iteration 轮提取"
    
    # 尝试编译
    cd "$OUTPUT_DIR"
    
    if make 2>&1 | tee /tmp/build_${iteration}.log; then
        echo
        echo "=========================================="
        echo "✅ 编译成功！"
        echo "=========================================="
        exit 0
    fi
    
    # 检查是否有新的 undefined reference
    if ! grep -q "undefined reference" /tmp/build_${iteration}.log; then
        echo "⚠️  编译失败，但没有发现 undefined reference"
        exit 1
    fi
    
    # 提取所有未定义符号
    undefined=$(grep "undefined reference to" /tmp/build_${iteration}.log | \
                sed "s/.*undefined reference to \`//" | \
                sed "s/'.*//" | sort -u)
    
    # 检查是否有进展
    if [[ "$undefined" == "$prev_undefined" ]]; then
        echo "⚠️  没有新的未定义符号，可能需要手动处理"
        echo "未定义符号:"
        echo "$undefined"
        exit 1
    fi
    
    prev_undefined="$undefined"
    
    echo "发现未定义符号:"
    echo "$undefined" | while read sym; do
        echo "  - $sym"
    done
    echo
    
    # 搜索并复制实现文件
    found_files=()
    for sym in $undefined; do
        # 多种搜索模式
        for pattern in \
            "^[^\/]*${sym}[[:space:]]*\(" \
            "^[^\/]*[[:space:]]${sym}[[:space:]]*\(" \
            "^[^\/]*\*[[:space:]]*${sym}[[:space:]]*\("; do
            
            found=$(grep -r "$pattern" "$SRC_ROOT" --include="*.c" -l 2>/dev/null | head -1 || true)
            
            if [[ -n "$found" ]]; then
                echo "✓ 找到 $sym: $found"
                found_files+=("$found")
                break
            fi
        done
    done
    
    # 复制文件（去重）
    if [[ ${#found_files[@]} -gt 0 ]]; then
        for f in $(echo "${found_files[@]}" | tr ' ' '\n' | sort -u); do
            if [[ ! -f "$OUTPUT_DIR/src/$(basename "$f")" ]]; then
                cp "$f" "$OUTPUT_DIR/src/"
                echo "  复制: $(basename "$f")"
            fi
        done
    else
        echo "⚠️  未找到任何实现文件"
        exit 1
    fi
    
    echo
done

echo "⚠️  达到最大迭代次数 $MAX_ITERATIONS"
exit 1