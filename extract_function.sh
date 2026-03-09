#!/usr/bin/env bash
# ==============================================================
# extract_function.sh
# 功能：
#   根据函数信息（返回值、函数名、参数列表）提取函数定义、声明和宏定义
# 参数：
#   $1: 返回值类型（如 "static int"）
#   $2: 函数名（如 "mem_link_chunk"）
#   $3: 参数列表（如 "nt_shmem_info_t *info, void *chunk"）
#   $4: 项目路径
#   $5: 结果路径
# 使用：
#   ./extract_function.sh "static void" "mem_link_chunk" "nt_shmem_info_t *info, void *chunk" /home/project /tmp/result
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

# 显示帮助
show_help() {
    cat <<EOF
用法: $0 <返回值> <函数名> <参数列表> <项目路径> <结果路径>

功能:
  根据提供的函数信息，在项目中搜索并提取函数定义、声明和宏定义。

参数:
  返回值      - 函数返回类型，如: "static int", "void", "const char *"
  函数名      - 函数名称，如: "mem_link_chunk", "nt_tcp_recv"
  参数列表    - 函数参数，如: "int a, char *b", "void"
  项目路径    - 源码项目目录
  结果路径    - 输出结果目录

示例:
  # 提取简单函数
  $0 "int" "simple_func" "int a, char *b" /home/project /tmp/result

  # 提取静态函数
  $0 "static void" "mem_link_chunk" "nt_shmem_info_t *info, void *chunk" /home/project /tmp/result

  # 提取无参函数
  $0 "int" "open_master" "void" /home/project /tmp/result

  # 提取复杂参数函数
  $0 "int" "pty_start" "Pty *pty, const char *program, char *const *arguments" /home/project /tmp/result

EOF
}

# 检查参数数量
if [[ $# -lt 5 ]]; then
    echo "❌ 错误: 参数不足" >&2
    echo
    show_help
    exit 1
fi

RET_TYPE="$1"
FUNC_NAME="$2"
PARAM_LIST="$3"
PROJECT_PATH="$4"
RESULT_PATH="$5"

# 验证参数
if [[ -z "$FUNC_NAME" ]]; then
    echo "❌ 错误: 函数名不能为空" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "❌ 错误: 项目路径不存在: $PROJECT_PATH" >&2
    exit 1
fi

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> 函数信息"
echo "    返回值: $RET_TYPE"
echo "    函数名: $FUNC_NAME"
echo "    参数列表: $PARAM_LIST"
echo "    项目路径: $PROJECT_PATH"
echo "    结果路径: $RESULT_PATH"
echo

# 构建函数签名
if [[ -z "$PARAM_LIST" ]]; then
    FUNC_SIG="${RET_TYPE} ${FUNC_NAME}(void)"
else
    FUNC_SIG="${RET_TYPE} ${FUNC_NAME}(${PARAM_LIST})"
fi

echo "==> 构建函数签名: $FUNC_SIG"
echo

# 调用 Searchfunction.sh
SEARCH_SCRIPT="${SCRIPT_DIR}/Searchfunction.sh"
if [[ ! -x "$SEARCH_SCRIPT" ]]; then
    echo "❌ 错误: 未找到 Searchfunction.sh 或无执行权限" >&2
    exit 1
fi

"$SEARCH_SCRIPT" "$FUNC_SIG" "$PROJECT_PATH" "$RESULT_PATH"