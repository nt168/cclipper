#!/usr/bin/env bash
# extract_missing_functions.sh - 从源码中提取缺失的函数实现
# 用法: $0 <未定义符号列表> <源码根目录> <输出目录>

set -euo pipefail

SYMBOLS="$1"
SRC_ROOT="$2"
OUTPUT_DIR="$3"

echo "  ==> 搜索函数实现..."

# 将符号列表转为数组
IFS=$'\n' read -d '' -ra SYMBOL_ARRAY <<< "$SYMBOLS" || true

FOUND_FILES=()
NEEDS_STUB=()  # 需要生成简化实现的函数

for symbol in "${SYMBOL_ARRAY[@]}"; do
    [[ -z "$symbol" ]] && continue
    
    echo "  搜索: $symbol"
    
    # 优先级1: 精确匹配函数定义（推荐）
    # 优先级2: 宽松匹配（可能误匹配）
    
    found=""
    found_file=""
    
    # 第一轮：精确匹配函数定义（排除纯调用）
    precise_patterns=(
        # 标准函数定义：返回类型 函数名(参数)
        "^[a-zA-Z_][a-zA-Z0-9_ \t]*[[:space:]]+[*[:space:]]*${symbol}[[:space:]]*[(][^)]*[)]"
        # void 特殊处理
        "^void[[:space:]]+[*[:space:]]*${symbol}[[:space:]]*[(]"
        # static 函数定义
        "^static[[:space:]].*[[:space:]]${symbol}[[:space:]]*[(]"
    )
    
    for pattern in "${precise_patterns[@]}"; do
        # 在源码中搜索函数定义
        matches=$(grep -r "$pattern" "$SRC_ROOT" --include="*.c" -l 2>/dev/null || true)
        
        if [[ -n "$matches" ]]; then
            # 如果找到多个文件，选择最佳的
            # 优先级：algodefs.c > hashset.c > 其他
            best_file=""
            for file in $matches; do
                basename_file=$(basename "$file")
                
                # 优先选择 algodefs.c（通常包含基础函数）
                if [[ "$basename_file" == "algodefs.c" ]]; then
                    best_file="$file"
                    break
                fi
                
                # 其次选择当前文件名
                if [[ -z "$best_file" ]]; then
                    best_file="$file"
                fi
            done
            
            if [[ -n "$best_file" ]]; then
                found="$best_file"
                found_file=$(basename "$best_file")
                echo "    ✓ 找到定义: $found"
                break
            fi
        fi
    done
    
    # 第二轮：如果精确匹配失败，使用宽松匹配
    if [[ -z "$found" ]]; then
        loose_pattern="${symbol}[[:space:]]*[(]"
        matches=$(grep -r "$loose_pattern" "$SRC_ROOT" --include="*.c" -l 2>/dev/null | head -3 || true)
        
        if [[ -n "$matches" ]]; then
            # 过滤掉明显不合适的文件（如 template_*.c, db*.c, log.c, mutex.c 等）
            for file in $matches; do
                basename_file=$(basename "$file")
                
                # 跳过会引入过多依赖的文件
                if [[ "$basename_file" =~ ^(template_|db|trapper|proxy|log\.c|mutex|locks|ipc|misc\.c) ]]; then
                    echo "    ⚠ 跳过复杂依赖文件: $basename_file"
                    continue
                fi
                
                # 检查文件是否已在输出目录
                if [[ ! -f "${OUTPUT_DIR}/src/${basename_file}" ]]; then
                    found="$file"
                    found_file="$basename_file"
                    echo "    ✓ 找到: $found"
                    break
                else
                    echo "    ✓ 已存在: $basename_file"
                    found="exists"
                    break
                fi
            done
        fi
    fi
    
    if [[ -z "$found" ]]; then
        echo "    ✗ 未找到: $symbol (将生成简化实现)"
        NEEDS_STUB+=("$symbol")
    elif [[ "$found" != "exists" && -f "$found" ]]; then
        FOUND_FILES+=("$found")
    fi
done

# 去重并复制文件
if [[ ${#FOUND_FILES[@]} -gt 0 ]]; then
    echo
    echo "  ==> 复制文件..."
    
    UNIQUE_FILES=($(printf '%s\n' "${FOUND_FILES[@]}" | sort -u))
    
    for file in "${UNIQUE_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "${OUTPUT_DIR}/src/"
            echo "    ✓ 复制: $(basename "$file")"
        fi
    done
fi

# 生成简化实现的函数
if [[ ${#NEEDS_STUB[@]} -gt 0 ]]; then
    echo
    echo "  ==> 生成简化实现..."
    
    STUB_FILE="${OUTPUT_DIR}/src/stub_impl.c"
    
    cat > "$STUB_FILE" << 'EOF'
/*
 * stub_impl.c - 简化函数实现
 * 自动生成于: $(date '+%Y-%m-%d %H:%M:%S')
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

EOF

    for symbol in "${NEEDS_STUB[@]}"; do
        case "$symbol" in
            *__zbx_zabbix_log|*zabbix_log)
                cat >> "$STUB_FILE" << 'EOF'
void __zbx_zabbix_log(int level, const char *fmt, ...)
{
    // 简化实现，避免引入复杂的日志系统
    (void)level;
    (void)fmt;
}

EOF
                echo "    ✓ 生成: $symbol (简化日志函数)"
                ;;
            *zbx_malloc2)
                cat >> "$STUB_FILE" << 'EOF'
void *zbx_malloc2(const char *filename, int line, void *old, size_t size)
{
    if (old != NULL) {
        fprintf(stderr, "[file:%s,line:%d] zbx_malloc: allocating already allocated memory.\n",
                filename, line);
        exit(EXIT_FAILURE);
    }
    return malloc(size > 0 ? size : 1);
}

EOF
                echo "    ✓ 生成: $symbol (简化内存分配)"
                ;;
            *zbx_realloc2)
                cat >> "$STUB_FILE" << 'EOF'
void *zbx_realloc2(const char *filename, int line, void *old, size_t size)
{
    void *ptr = realloc(old, size > 0 ? size : 1);
    if (ptr == NULL && size > 0) {
        fprintf(stderr, "[file:%s,line:%d] zbx_realloc: out of memory.\n", filename, line);
        exit(EXIT_FAILURE);
    }
    return ptr;
}

EOF
                echo "    ✓ 生成: $symbol (简化内存重分配)"
                ;;
            *)
                cat >> "$STUB_FILE" << EOF
/* 未识别的符号: $symbol - 需要手动实现 */

EOF
                echo "    ⚠ 未识别: $symbol"
                ;;
        esac
    done
    
    echo "    ✓ 生成文件: $STUB_FILE"
fi