#!/usr/bin/env bash
# ==============================================================
# analyze_dependencies.sh
# 功能：
#   分析C源文件的依赖项，自动提取所需的头文件
# 参数：
#   $1: 源文件路径
#   $2: 项目根目录
#   $3: 输出目录
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

analyze_and_copy_deps() {
    local source_file="$1"
    local project_root="$2"
    local output_dir="$3"
    local max_depth="${4:-3}"
    
    local visited_files="/tmp/deps_visited_$$"
    echo "" > "$visited_files"
    
    _analyze_deps_recursive "$source_file" "$project_root" "$output_dir" "$max_depth" 0 "$visited_files"
    
    rm -f "$visited_files"
}

_analyze_deps_recursive() {
    local source_file="$1"
    local project_root="$2"
    local output_dir="$3"
    local max_depth="$4"
    local current_depth="$5"
    local visited_files="$6"
    
    # 避免递归过深
    if [[ $current_depth -ge $max_depth ]]; then
        return
    fi
    
    # 检查文件是否存在
    if [[ ! -f "$source_file" ]]; then
        return
    fi
    
    # 避免重复处理
    local file_key=$(realpath "$source_file" 2>/dev/null || echo "$source_file")
    if grep -qF "$file_key" "$visited_files" 2>/dev/null; then
        return
    fi
    echo "$file_key" >> "$visited_files"
    
    # 提取 #include "xxx.h" 形式的头文件
    local includes
    includes=$(grep -n '^#include[[:space:]]*"[^"]*"' "$source_file" 2>/dev/null | \
               sed 's/.*#include[[:space:]]*"\([^"]*\)".*/\1/' || true)
    
    if [[ -z "$includes" ]]; then
        return
    fi
    
    # 创建输出目录
    mkdir -p "${output_dir}/include"
    
    # 处理每个头文件
    while IFS= read -r header; do
        [[ -z "$header" ]] && continue
        
        # 在项目中查找头文件
        local header_path=""
        local header_dir=$(dirname "$header")
        local header_name=$(basename "$header")
        
        # 首先在源文件同目录查找
        if [[ -f "$(dirname "$source_file")/$header" ]]; then
            header_path="$(dirname "$source_file")/$header"
        # 然后在项目根目录查找
        elif [[ -f "${project_root}/${header}" ]]; then
            header_path="${project_root}/${header}"
        # 在 include 目录查找
        elif [[ -f "${project_root}/include/${header_name}" ]]; then
            header_path="${project_root}/include/${header_name}"
        # 使用 find 查找
        else
            header_path=$(find "$project_root" -name "$header_name" -type f 2>/dev/null | head -n1 || true)
        fi
        
        # 如果找到头文件，复制并递归分析
        if [[ -n "$header_path" && -f "$header_path" ]]; then
            local dest_header="${output_dir}/include/${header_name}"
            
            # 复制头文件（如果还未复制）
            if [[ ! -f "$dest_header" ]]; then
                cp "$header_path" "$dest_header"
                echo "  ✓ 提取依赖: include/${header_name}"
                
                # 递归分析该头文件的依赖
                _analyze_deps_recursive "$header_path" "$project_root" "$output_dir" "$max_depth" $((current_depth + 1)) "$visited_files"
            fi
        fi
    done <<< "$includes"
}

# 命令行入口
if [[ $# -lt 3 ]]; then
    cat <<EOF
用法: $0 <源文件> <项目根目录> <输出目录> [最大深度]

功能:
  分析C源文件的依赖项，自动提取所需的头文件

参数:
  源文件      - 要分析的.c或.h文件路径
  项目根目录  - 项目源码根目录
  输出目录    - 依赖文件输出目录
  最大深度    - 递归分析的最大深度（默认3）

示例:
  $0 /tmp/test/src/main.c /home/project /tmp/standalone
  $0 /tmp/test/src/hashmap.c /home/project /tmp/standalone 5

EOF
    exit 1
fi

SOURCE_FILE="$1"
PROJECT_ROOT="$2"
OUTPUT_DIR="$3"
MAX_DEPTH="${4:-3}"

if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "❌ 错误: 源文件不存在: $SOURCE_FILE" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "❌ 错误: 项目根目录不存在: $PROJECT_ROOT" >&2
    exit 1
fi

echo "==> 分析依赖: $(basename "$SOURCE_FILE")"
analyze_and_copy_deps "$SOURCE_FILE" "$PROJECT_ROOT" "$OUTPUT_DIR" "$MAX_DEPTH"
echo "✅ 依赖分析完成"