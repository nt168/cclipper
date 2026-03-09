#!/usr/bin/env bash
# ==============================================================
# cclipper.sh
# 功能：
#   主入口脚本，用于搜索函数定义并复制相关源文件
# 参数：
#   $1: 函数定义字符串（如 "void fx(type c)" 或 "nt_tcp_recv_ext"）
#   $2: 输出路径（如 /tmp/fx）
# 使用：
#   ./cclipper.sh "void fx(type c)" /tmp/fx
#   ./cclipper.sh "nt_tcp_recv_ext" /tmp/fx
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

# 显示帮助信息
show_help() {
    cat <<EOF
用法: $0 <函数定义> <输出路径>
      $0 <函数名> <源码目录> <输出路径>

功能:
  在C语言源码中搜索函数定义、声明和宏定义，并复制相关文件到输出目录。

参数:
  方式1 (两个参数):
    参数1: 函数定义字符串或函数名
            例如: "static void mem_link_chunk(nt_shmem_info_t *info, void *chunk)"
            或者: "nt_tcp_recv_ext"
    参数2: 输出路径
            例如: /tmp/fx

  方式2 (三个参数):
    参数1: 函数定义字符串或函数名
    参数2: 源码工程目录
    参数3: 输出路径

示例:
  # 使用两个参数（需要设置默认源码目录）
  $0 "void fx(type c)" /tmp/fx
  $0 "nt_tcp_recv_ext" /tmp/fx

  # 使用三个参数
  $0 "static int open_master(void)" /home/nt/project /tmp/fx
  $0 "nt_tcp_recv_ext" /home/nt/project /tmp/fx

环境变量:
  CC_SRC_DIR - 默认源码目录（可选）
  CC_VERBOSE - 设置为 1 启用详细输出

EOF
}

# 检查参数数量
if [[ $# -lt 2 ]]; then
    echo "❌ 错误: 参数不足" >&2
    echo
    show_help
    exit 1
fi

# 解析参数
FUNC_INPUT="$1"

if [[ $# -eq 2 ]]; then
    # 两个参数：函数定义 + 输出路径
    if [[ -z "${CC_SRC_DIR:-}" ]]; then
        echo "❌ 错误: 未指定源码目录" >&2
        echo "请使用三种参数形式，或设置环境变量 CC_SRC_DIR" >&2
        echo
        show_help
        exit 1
    fi
    SRC_DIR="$CC_SRC_DIR"
    OUT_DIR="$2"
elif [[ $# -eq 3 ]]; then
    # 三个参数：函数定义 + 源码目录 + 输出路径
    SRC_DIR="$2"
    OUT_DIR="$3"
else
    echo "❌ 错误: 参数过多" >&2
    show_help
    exit 1
fi

# 验证源码目录
if [[ ! -d "$SRC_DIR" ]]; then
    echo "❌ 错误: 源码目录不存在: $SRC_DIR" >&2
    exit 1
fi

# 验证函数输入
if [[ -z "$FUNC_INPUT" ]]; then
    echo "❌ 错误: 函数定义不能为空" >&2
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 检查 Searchfunction.sh 是否存在
SEARCH_SCRIPT="${SCRIPT_DIR}/Searchfunction.sh"
if [[ ! -x "$SEARCH_SCRIPT" ]]; then
    echo "❌ 错误: 未找到 Searchfunction.sh 或无执行权限" >&2
    echo "路径: $SEARCH_SCRIPT" >&2
    exit 1
fi

# 详细输出
if [[ "${CC_VERBOSE:-0}" == "1" ]]; then
    echo "==> 函数定义: $FUNC_INPUT"
    echo "==> 源码目录: $SRC_DIR"
    echo "==> 输出路径: $OUT_DIR"
    echo "==> 搜索脚本: $SEARCH_SCRIPT"
    echo
fi

# 调用 Searchfunction.sh
"$SEARCH_SCRIPT" "$FUNC_INPUT" "$SRC_DIR" "$OUT_DIR"