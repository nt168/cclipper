#!/usr/bin/env bash
# ==============================================================
# detect_dependencies.sh
# 功能：
#   检测源文件中缺失的函数定义，自动生成依赖实现
# 参数：
#   $1: 源文件目录
#   $2: 输出目录
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

detect_missing_symbols() {
    local src_dir="$1"
    local output_dir="$2"
    
    echo "  ==> 检测缺失的符号..."
    
    # 尝试编译，捕获链接错误
    local missing_symbols=$(cd "$output_dir" && make 2>&1 | grep "undefined reference to" | \
        sed "s/.*undefined reference to \`\(.*\)'.*/\1/" | sort -u || true)
    
    if [[ -z "$missing_symbols" ]]; then
        echo "  ✓ 无缺失符号"
        return 0
    fi
    
    echo "  发现缺失符号:"
    echo "$missing_symbols" | while read -r sym; do
        echo "    - $sym"
    done
    
    # 生成依赖实现文件
    generate_dependency_impl "$output_dir" "$missing_symbols"
}

generate_dependency_impl() {
    local output_dir="$1"
    local symbols="$2"
    
    echo "  ==> 从源码提取函数实现..."
    
    # 调用新的提取脚本
    local extract_script="${SCRIPT_DIR:-.}/extract_missing_functions.sh"
    
    if [[ -x "$extract_script" ]]; then
        "$extract_script" "$symbols" "/home/phy/zabbix-3.4.7" "$output_dir"
    else
        echo "  ⚠️  未找到 extract_missing_functions.sh，使用备用方案..."
        generate_fallback_impl "$output_dir" "$symbols"
    fi
}

generate_fallback_impl() {
    local output_dir="$1"
    local symbols="$2"
    
    local deps_file="${output_dir}/src/deps_impl.c"
    
    echo "  ==> 生成依赖实现: src/deps_impl.c"
    
    cat > "$deps_file" <<'EOF'
/*
 * deps_impl.c - 自动生成的依赖函数实现
 * 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
 */

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* 常见依赖函数实现 */

EOF

    # 为每个缺失符号生成实现
    # 先处理 is_prime，确保它在 next_prime 之前定义
    if echo "$symbols" | grep -q "is_prime"; then
        cat >> "$deps_file" <<'EOF'
int is_prime(int n) {
    if (n <= 1) return 0;
    if (n <= 3) return 1;
    if (n % 2 == 0 || n % 3 == 0) return 0;
    for (int i = 5; i * i <= n; i += 6) {
        if (n % i == 0 || n % (i + 2) == 0) return 0;
    }
    return 1;
}

EOF
    fi
    
    while IFS= read -r symbol; do
        [[ -z "$symbol" ]] && continue
        
        case "$symbol" in
            # 内存管理函数
            *mem_malloc_func*)
                cat >> "$deps_file" <<'EOF'
void *zbx_default_mem_malloc_func(void *old, size_t size) {
    (void)old;
    return malloc(size);
}

EOF
                ;;
            *mem_realloc_func*)
                cat >> "$deps_file" <<'EOF'
void *zbx_default_mem_realloc_func(void *old, size_t size) {
    return realloc(old, size);
}

EOF
                ;;
            *mem_free_func*)
                cat >> "$deps_file" <<'EOF'
void zbx_default_mem_free_func(void *ptr) {
    free(ptr);
}

EOF
                ;;
            
            # 哈希和比较函数
            *uint64_hash_func*)
                cat >> "$deps_file" <<'EOF'
typedef uint64_t zbx_uint64_t;
typedef size_t zbx_hash_t;

zbx_hash_t zbx_default_uint64_hash_func(const void *data) {
    zbx_uint64_t value = *(const zbx_uint64_t *)data;
    return (zbx_hash_t)(value % 1000003);
}

EOF
                ;;
            *uint64_compare_func*)
                cat >> "$deps_file" <<'EOF'
typedef uint64_t zbx_uint64_t;

int zbx_default_uint64_compare_func(const void *d1, const void *d2) {
    zbx_uint64_t v1 = *(const zbx_uint64_t *)d1;
    zbx_uint64_t v2 = *(const zbx_uint64_t *)d2;
    return (v1 < v2) ? -1 : (v1 > v2);
}

EOF
                ;;
            
            # 素数计算 - is_prime 已经在上面处理
            is_prime)
                # 已经在上面生成，跳过
                ;;
            next_prime)
                cat >> "$deps_file" <<'EOF'
int next_prime(int n) {
    if (n <= 2) return 2;
    int prime = (n % 2 == 0) ? n + 1 : n;
    while (!is_prime(prime)) {
        prime += 2;
    }
    return prime;
}

EOF
                ;;
            
            # 默认：生成空实现
            *)
                cat >> "$deps_file" <<EOF
/* 未识别的符号: $symbol - 需要手动实现 */
/* void *$symbol(...) { return NULL; } */

EOF
                ;;
        esac
    done <<< "$symbols"
    
    echo "  ✓ deps_impl.c 已生成"
    
    # 更新 Makefile
    update_makefile "$output_dir"
}

update_makefile() {
    local output_dir="$1"
    local makefile="${output_dir}/Makefile"
    
    if [[ ! -f "$makefile" ]]; then
        return
    fi
    
    # 检查是否已经包含 deps_impl.c
    if grep -q "deps_impl.c" "$makefile"; then
        return
    fi
    
    echo "  ==> 更新 Makefile..."
    
    # 在 SRCS 行添加 deps_impl.c
    sed -i 's/^SRCS = /SRCS = src\/deps_impl.c /' "$makefile"
    
    echo "  ✓ Makefile 已更新"
}

# 主函数
if [[ $# -lt 2 ]]; then
    echo "用法: $0 <源码目录> <输出目录>"
    exit 1
fi

SRC_DIR="$1"
OUTPUT_DIR="$2"

detect_missing_symbols "$SRC_DIR" "$OUTPUT_DIR"