#!/usr/bin/env bash
# ==============================================================
# configure.sh
# 功能：
#   检测系统环境，生成平台适配的配置文件
# 输出：
#   config.h - 平台配置头文件
#   Makefile.config - Makefile配置片段
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出函数
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测操作系统
detect_os() {
    local os_type=""
    
    case "$(uname -s)" in
        Linux*)     os_type="linux" ;;
        Darwin*)    os_type="macos" ;;
        CYGWIN*)    os_type="windows" ;;
        MINGW*)     os_type="windows" ;;
        MSYS*)      os_type="windows" ;;
        *)          os_type="unknown" ;;
    esac
    
    echo "$os_type"
}

# 检测编译器
detect_compiler() {
    local compiler="gcc"
    
    if command -v gcc &> /dev/null; then
        compiler="gcc"
    elif command -v clang &> /dev/null; then
        compiler="clang"
    elif command -v cl &> /dev/null; then
        compiler="msvc"
    else
        warning "未找到合适的编译器，默认使用 gcc"
        compiler="gcc"
    fi
    
    echo "$compiler"
}

# 检测头文件
check_header() {
    local header="$1"
    local test_file=$(mktemp)
    
    echo "#include <$header>" > "$test_file"
    echo "int main() { return 0; }" >> "$test_file"
    
    if gcc -fsyntax-only "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        return 0
    else
        rm -f "$test_file"
        return 1
    fi
}

# 检测函数
check_function() {
    local func="$1"
    local test_file=$(mktemp)
    
    cat > "$test_file" <<EOF
#define _GNU_SOURCE
#include <stdio.h>
int main() {
    void *p = (void *)$func;
    return 0;
}
EOF
    
    if gcc "$test_file" -o /dev/null 2>/dev/null; then
        rm -f "$test_file"
        return 0
    else
        rm -f "$test_file"
        return 1
    fi
}

# 检测类型
check_type() {
    local type="$1"
    local test_file=$(mktemp)
    
    cat > "$test_file" <<EOF
#include <stdint.h>
#include <sys/types.h>
int main() {
    ${type} x;
    (void)x;
    return 0;
}
EOF
    
    if gcc "$test_file" -o /dev/null 2>/dev/null; then
        rm -f "$test_file"
        return 0
    else
        rm -f "$test_file"
        return 1
    fi
}

# 生成 config.h
generate_config_h() {
    local output_file="${1:-config.h}"
    local project_name="${2:-standalone}"
    
    info "检测系统环境..."
    
    local os_type=$(detect_os)
    local compiler=$(detect_compiler)
    
    info "操作系统: $os_type"
    info "编译器: $compiler"
    
    # 创建配置文件
    cat > "$output_file" <<EOF
/* config.h - 自动生成的平台配置文件 */
/* 生成时间: $(date '+%Y-%m-%d %H:%M:%S') */
/* 项目名称: $project_name */

#ifndef ${project_name^^}_CONFIG_H
#define ${project_name^^}_CONFIG_H

/* ==================== 平台检测 ==================== */
EOF

    # 根据操作系统生成配置
    case "$os_type" in
        linux)
            cat >> "$output_file" <<EOF
#define PLATFORM_LINUX 1
#define PLATFORM_UNIX 1

/* Linux 特定头文件 */
#define HAVE_UNISTD_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_DLFCN_H 1
#define HAVE_FCNTL_H 1
#define HAVE_POLL_H 1
#define HAVE_EPOLL_H 1

/* 禁用 Windows 特性 */
#undef HAVE_WINSOCK2_H
#undef HAVE_WS2TCPIP_H
#undef HAVE_WINDOWS_H
EOF
            ;;
        macos)
            cat >> "$output_file" <<EOF
#define PLATFORM_MACOS 1
#define PLATFORM_UNIX 1

/* macOS 特定头文件 */
#define HAVE_UNISTD_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_DLFCN_H 1
#define HAVE_FCNTL_H 1
#define HAVE_POLL_H 1

/* 禁用 Windows 特性 */
#undef HAVE_WINSOCK2_H
#undef HAVE_WS2TCPIP_H
#undef HAVE_WINDOWS_H
EOF
            ;;
        windows)
            cat >> "$output_file" <<EOF
#define PLATFORM_WINDOWS 1

/* Windows 特定头文件 */
#define HAVE_WINDOWS_H 1
#define HAVE_WINSOCK2_H 1
#define HAVE_WS2TCPIP_H 1
#define HAVE_IO_H 1
#define HAVE_PROCESS_H 1

/* 禁用 Unix 特性 */
#undef HAVE_UNISTD_H
#undef HAVE_SYS_SOCKET_H
#undef HAVE_EPOLL_H
EOF
            ;;
        *)
            warning "未知平台，使用通用配置"
            cat >> "$output_file" <<EOF
#define PLATFORM_UNKNOWN 1
EOF
            ;;
    esac
    
    # 检测标准头文件
    info "检测标准头文件..."
    cat >> "$output_file" <<EOF

/* ==================== 标准头文件 ==================== */
EOF
    
    local headers="stdio.h stdlib.h string.h stdarg.h stdint.h stddef.h limits.h errno.h time.h"
    for header in $headers; do
        local header_name=$(echo "$header" | tr '.' '_' | tr '/' '_' | tr 'a-z' 'A-Z')
        if check_header "$header"; then
            echo "#define HAVE_${header_name} 1" >> "$output_file"
            success "$header"
        else
            echo "/* #undef HAVE_${header_name} */" >> "$output_file"
            warning "$header"
        fi
    done
    
    # 检测类型
    info "检测类型定义..."
    cat >> "$output_file" <<EOF

/* ==================== 类型定义 ==================== */
EOF
    
    if check_type "uint64_t"; then
        echo "#define HAVE_UINT64_T 1" >> "$output_file"
        success "uint64_t"
    fi
    
    if check_type "size_t"; then
        echo "#define HAVE_SIZE_T 1" >> "$output_file"
        success "size_t"
    fi
    
    if check_type "ssize_t"; then
        echo "#define HAVE_SSIZE_T 1" >> "$output_file"
        success "ssize_t"
    fi
    
    # 添加编译器信息
    cat >> "$output_file" <<EOF

/* ==================== 编译器信息 ==================== */
EOF
    
    case "$compiler" in
        gcc)
            cat >> "$output_file" <<EOF
#define COMPILER_GCC 1
#define COMPILER_NAME "GCC"
EOF
            ;;
        clang)
            cat >> "$output_file" <<EOF
#define COMPILER_CLANG 1
#define COMPILER_NAME "Clang"
EOF
            ;;
        msvc)
            cat >> "$output_file" <<EOF
#define COMPILER_MSVC 1
#define COMPILER_NAME "MSVC"
EOF
            ;;
    esac
    
    # 结束
    cat >> "$output_file" <<EOF

/* ==================== 其他配置 ==================== */
#define PROJECT_NAME "$project_name"

#endif /* ${project_name^^}_CONFIG_H */
EOF
    
    success "配置文件已生成: $output_file"
}

# 生成 Makefile.config
generate_makefile_config() {
    local output_file="${1:-Makefile.config}"
    local project_name="${2:-standalone}"
    
    info "生成 Makefile 配置..."
    
    local os_type=$(detect_os)
    local compiler=$(detect_compiler)
    
    cat > "$output_file" <<EOF
# Makefile.config - 自动生成的平台配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 项目名称: $project_name

# ==================== 平台配置 ====================
PLATFORM = $os_type
COMPILER = $compiler

EOF
    
    # 根据平台设置
    case "$os_type" in
        linux)
            cat >> "$output_file" <<EOF
# Linux 平台配置
CC = gcc
CFLAGS += -Wall -Wextra -g -D_GNU_SOURCE
LDFLAGS += 
LIBS = -lpthread -ldl -lm

# 平台特定宏
PLATFORM_CFLAGS = -DPLATFORM_LINUX
EOF
            ;;
        macos)
            cat >> "$output_file" <<EOF
# macOS 平台配置
CC = clang
CFLAGS += -Wall -Wextra -g
LDFLAGS += 
LIBS = -lpthread -ldl -lm

# 平台特定宏
PLATFORM_CFLAGS = -DPLATFORM_MACOS
EOF
            ;;
        windows)
            cat >> "$output_file" <<EOF
# Windows 平台配置
CC = gcc
CFLAGS += -Wall -Wextra -g
LDFLAGS += -lws2_32
LIBS = -lws2_32 -lwinmm

# 平台特定宏
PLATFORM_CFLAGS = -DPLATFORM_WINDOWS
EOF
            ;;
        *)
            cat >> "$output_file" <<EOF
# 通用配置
CC = gcc
CFLAGS += -Wall -Wextra -g
LDFLAGS += 
LIBS = 

# 平台特定宏
PLATFORM_CFLAGS = 
EOF
            ;;
    esac
    
    success "Makefile 配置已生成: $output_file"
}

# 生成兼容性头文件
generate_compat_h() {
    local output_file="${1:-compat.h}"
    local project_name="${2:-standalone}"
    
    info "生成兼容性头文件..."
    
    cat > "$output_file" <<EOF
/* compat.h - 跨平台兼容性头文件 */
/* 生成时间: $(date '+%Y-%m-%d %H:%M:%S') */

#ifndef ${project_name^^}_COMPAT_H
#define ${project_name^^}_COMPAT_H

/* 包含配置文件 */
#include "config.h"

/* ==================== 标准头文件 ==================== */
#ifdef HAVE_STDIO_H
#include <stdio.h>
#endif

#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif

#ifdef HAVE_STRING_H
#include <string.h>
#endif

#ifdef HAVE_STDARG_H
#include <stdarg.h>
#endif

#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif

#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif

#ifdef HAVE_LIMITS_H
#include <limits.h>
#endif

/* ==================== 平台特定头文件 ==================== */
#ifdef PLATFORM_LINUX
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <time.h>
#endif

#ifdef PLATFORM_MACOS
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <time.h>
#endif

#ifdef PLATFORM_WINDOWS
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <io.h>
#include <process.h>
#include <errno.h>
#include <time.h>

/* Windows 下缺少的函数 */
#define snprintf _snprintf
#define vsnprintf _vsnprintf
#define strcasecmp _stricmp
#define strncasecmp _strnicmp
#define close closesocket
#define unlink _unlink
#define fileno _fileno
#define isatty _isatty
#define access _access
#define getpid _getpid
#define mkdir(a, b) _mkdir(a)

/* Windows socket 初始化 */
static inline int ws_startup(void) {
    WSADATA wsaData;
    return WSAStartup(MAKEWORD(2, 2), &wsaData);
}

static inline void ws_cleanup(void) {
    WSACleanup();
}
#endif

/* ==================== 类型定义 ==================== */
#ifndef HAVE_UINT64_T
typedef unsigned long long uint64_t;
#endif

#ifndef HAVE_SIZE_T
typedef unsigned long size_t;
#endif

#ifndef HAVE_SSIZE_T
typedef long ssize_t;
#endif

/* 固定大小类型 */
typedef uint64_t zbx_uint64_t;
typedef int64_t zbx_int64_t;
typedef uint32_t zbx_uint32_t;
typedef int32_t zbx_int32_t;
typedef uint16_t zbx_uint16_t;
typedef int16_t zbx_int16_t;
typedef uint8_t zbx_uint8_t;
typedef int8_t zbx_int8_t;

/* ==================== 平台适配宏 ==================== */
#ifdef PLATFORM_WINDOWS
#define PATH_SEP '\\'
#define PATH_SEP_STR "\\"
#else
#define PATH_SEP '/'
#define PATH_SEP_STR "/"
#endif

/* 导出/导入宏 */
#ifdef PLATFORM_WINDOWS
    #ifdef BUILDING_DLL
        #define DLL_EXPORT __declspec(dllexport)
    #else
        #define DLL_EXPORT __declspec(dllimport)
    #endif
#else
    #define DLL_EXPORT __attribute__((visibility("default")))
#endif

/* 线程局部存储 */
#ifdef PLATFORM_WINDOWS
    #define THREAD_LOCAL __declspec(thread)
#else
    #define THREAD_LOCAL __thread
#endif

/* 函数属性 */
#ifdef COMPILER_GCC
    #define UNUSED __attribute__((unused))
    #define NORETURN __attribute__((noreturn))
    #define PACKED __attribute__((packed))
    #define ALIGNED(x) __attribute__((aligned(x)))
#else
    #define UNUSED
    #define NORETURN
    #define PACKED
    #define ALIGNED(x)
#endif

#endif /* ${project_name^^}_COMPAT_H */
EOF
    
    success "兼容性头文件已生成: $output_file"
}

# 主函数
main() {
    local output_dir="."
    local project_name="standalone"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -p|--project)
                project_name="$2"
                shift 2
                ;;
            -h|--help)
                cat <<EOF
用法: $0 [选项]

选项:
  -o, --output DIR      输出目录（默认：当前目录）
  -p, --project NAME    项目名称（默认：standalone）
  -h, --help           显示帮助信息

功能:
  检测系统环境，生成平台适配的配置文件

生成的文件:
  config.h          - 平台配置头文件
  Makefile.config   - Makefile配置片段
  compat.h          - 跨平台兼容性头文件

示例:
  $0
  $0 -o /tmp/project -p myapp
  $0 --output ./include --project zbx_test

EOF
                exit 0
                ;;
            *)
                error "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    echo "========================================"
    echo "系统环境检测工具"
    echo "========================================"
    echo
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 生成配置文件
    generate_config_h "$output_dir/config.h" "$project_name"
    generate_makefile_config "$output_dir/Makefile.config" "$project_name"
    generate_compat_h "$output_dir/compat.h" "$project_name"
    
    echo
    echo "========================================"
    echo "✅ 配置完成！"
    echo "========================================"
    echo
    echo "生成的文件:"
    echo "  - $output_dir/config.h"
    echo "  - $output_dir/Makefile.config"
    echo "  - $output_dir/compat.h"
    echo
}

# 执行主函数
main "$@"