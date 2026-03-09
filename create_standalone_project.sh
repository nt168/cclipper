#!/usr/bin/env bash
# ==============================================================
# create_standalone_project.sh
# 功能：
#   提取函数及其依赖，生成独立可编译项目
# 参数：
#   $1: 返回值类型
#   $2: 函数名
#   $3: 参数列表
#   $4: 项目路径
#   $5: 输出路径
# 输出：
#   独立项目结构，包含 Makefile、main.c、源文件、头文件等
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

show_help() {
    cat <<EOF
用法: 
  方式1: $0 <返回值> <函数名> <参数列表> <项目路径> <输出路径>
  方式2: $0 "函数签名" <项目路径> <输出路径>

示例:
  # 方式1: 分开参数
  $0 "int" "simple_func" "int a, char *b" /home/project /tmp/standalone
  $0 "static void" "mem_link_chunk" "nt_shmem_info_t *info, void *chunk" /home/project /tmp/standalone

  # 方式2: 完整函数签名（推荐）
  $0 "int simple_func(int a, char *b)" /home/project /tmp/standalone
  $0 "int zbx_hashmap_get(zbx_hashmap_t *hm, zbx_uint64_t key)" /home/project /tmp/standalone

EOF
    exit 1
}

# 解析参数
if [[ $# -eq 3 ]]; then
    # 方式2: 完整函数签名
    FUNC_SIG="$1"
    PROJECT_PATH="$2"
    OUTPUT_PATH="$3"
    
    # 解析函数签名
    if [[ ! "$FUNC_SIG" =~ \(.*\) ]]; then
        echo "❌ 错误: 函数签名格式不正确，应包含括号" >&2
        show_help
    fi
    
    # 提取括号前部分（返回值 + 函数名）
    BEFORE_PAREN="${FUNC_SIG%%(*}"
    BEFORE_PAREN=$(echo "$BEFORE_PAREN" | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')
    
    # 提取函数名（最后一个词）
    FUNC_NAME="${BEFORE_PAREN##* }"
    
    # 提取返回值（去掉函数名）
    RET_TYPE="${BEFORE_PAREN% $FUNC_NAME}"
    
    # 提取参数列表
    AFTER_PAREN="${FUNC_SIG#*\(}"
    PARAM_LIST="${AFTER_PAREN%\)}"
    PARAM_LIST=$(echo "$PARAM_LIST" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    
    # 如果参数列表为空，设置为 void
    if [[ -z "$PARAM_LIST" ]]; then
        PARAM_LIST="void"
    fi
    
elif [[ $# -eq 5 ]]; then
    # 方式1: 分开参数
    RET_TYPE="$1"
    FUNC_NAME="$2"
    PARAM_LIST="$3"
    PROJECT_PATH="$4"
    OUTPUT_PATH="$5"
else
    echo "❌ 错误: 参数数量不正确" >&2
    show_help
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR=$(mktemp -d)

echo "=========================================="
echo "函数提取工具 - 独立项目生成器"
echo "=========================================="
echo
echo "函数信息:"
echo "  返回值: $RET_TYPE"
echo "  函数名: $FUNC_NAME"
echo "  参数列表: $PARAM_LIST"
echo "  项目路径: $PROJECT_PATH"
echo "  输出路径: $OUTPUT_PATH"
echo

# 第一步：使用 extract_function.sh 搜索函数
EXTRACT_SCRIPT="${SCRIPT_DIR}/extract_function.sh"
if [[ ! -x "$EXTRACT_SCRIPT" ]]; then
    echo "❌ 错误: 未找到 extract_function.sh" >&2
    exit 1
fi

echo "==> 步骤1: 搜索函数定义..."
"$EXTRACT_SCRIPT" "$RET_TYPE" "$FUNC_NAME" "$PARAM_LIST" "$PROJECT_PATH" "$TEMP_DIR"

# 检查搜索结果（Searchfunction.sh 在当前目录创建 fun/ 和 fsrc/）
RESULT_FILE="fsrc/${FUNC_NAME}"
if [[ ! -f "$RESULT_FILE" ]]; then
    echo "❌ 错误: 未找到函数搜索结果" >&2
    exit 1
fi

echo
echo "==> 步骤2: 分析函数依赖..."

# 读取函数定义和声明
DEF_FILE=""
DECL_FILE=""
FUNC_BODY=""

while IFS= read -r line; do
    if [[ "$line" =~ ${FUNC_NAME}[[:space:]]+(声明|定义):[[:space:]]*(.+)$ ]]; then
        type="${BASH_REMATCH[1]}"
        file="${BASH_REMATCH[2]}"
        if [[ "$type" == "声明" && "$file" != "(未找到)" ]]; then
            DECL_FILE="$file"
        elif [[ "$type" == "定义" && "$file" != "(未找到)" ]]; then
            DEF_FILE="$file"
        fi
    fi
done < "$RESULT_FILE"

# 提取函数体
FUNC_BODY=$(sed -n "/${FUNC_NAME} 函数体：/,/${FUNC_NAME} .*：/p" "$RESULT_FILE" | sed '1d;$d')

if [[ -z "$FUNC_BODY" ]]; then
    FUNC_BODY=$(sed -n "/${FUNC_NAME} 函数体：/,\$p" "$RESULT_FILE" | sed '1d')
fi

echo "  定义文件: ${DEF_FILE:-未找到}"
echo "  声明文件: ${DECL_FILE:-未找到}"

# 第三步：创建独立项目结构
echo
echo "==> 步骤3: 创建独立项目..."

mkdir -p "$OUTPUT_PATH"/{src,include}

# 创建lib目录并添加说明
mkdir -p "$OUTPUT_PATH/lib"
cat > "${OUTPUT_PATH}/lib/README.md" <<'EOF'
# Library Directory

This directory is reserved for external libraries.

Usage:
- Place static libraries (*.a) here
- Place shared libraries (*.so) here
- Update Makefile to link them

Example Makefile:
  LDFLAGS += -L./lib
  LIBS += -lmylib
EOF

# 复制源文件和头文件
if [[ -n "$DEF_FILE" ]]; then
    DEF_FULL="${PROJECT_PATH}/${DEF_FILE}"
    if [[ -f "$DEF_FULL" ]]; then
        cp "$DEF_FULL" "${OUTPUT_PATH}/src/"
        echo "  ✓ 复制源文件: src/$(basename "$DEF_FILE")"
    fi
fi

if [[ -n "$DECL_FILE" ]]; then
    DECL_FULL="${PROJECT_PATH}/${DECL_FILE}"
    if [[ -f "$DECL_FULL" ]]; then
        cp "$DECL_FULL" "${OUTPUT_PATH}/include/"
        echo "  ✓ 复制头文件: include/$(basename "$DECL_FILE")"
    fi
fi

# 分析并提取依赖头文件
ANALYZE_DEPS="${SCRIPT_DIR}/analyze_dependencies.sh"
if [[ -x "$ANALYZE_DEPS" ]]; then
    echo
    echo "  ==> 分析源文件依赖..."
    
    # 分析源文件依赖
    if [[ -n "$DEF_FILE" && -f "${OUTPUT_PATH}/src/$(basename "$DEF_FILE")" ]]; then
        "$ANALYZE_DEPS" "${OUTPUT_PATH}/src/$(basename "$DEF_FILE")" "$PROJECT_PATH" "$OUTPUT_PATH" 5
    fi
    
    # 分析头文件依赖
    if [[ -n "$DECL_FILE" && -f "${OUTPUT_PATH}/include/$(basename "$DECL_FILE")" ]]; then
        "$ANALYZE_DEPS" "${OUTPUT_PATH}/include/$(basename "$DECL_FILE")" "$PROJECT_PATH" "$OUTPUT_PATH" 5
    fi
fi

# 第四步：系统环境检测
echo
echo "==> 步骤4: 检测系统环境..."

CONFIGURE_SCRIPT="${SCRIPT_DIR}/configure.sh"
if [[ -x "$CONFIGURE_SCRIPT" ]]; then
    "$CONFIGURE_SCRIPT" -o "${OUTPUT_PATH}/include" -p "${FUNC_NAME}_test"
else
    warning "未找到 configure.sh，跳过系统环境检测"
fi

# 第五步：分析依赖类型
echo
echo "==> 步骤4: 分析依赖类型..."

# 解析参数列表提取类型
DEPEND_TYPES=()

if [[ -n "$PARAM_LIST" && "$PARAM_LIST" != "void" ]]; then
    IFS=',' read -ra PARAMS <<< "$PARAM_LIST"
    for param in "${PARAMS[@]}"; do
        param=$(echo "$param" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # 提取类型（去掉参数名）
        type=$(echo "$param" | sed 's/[[:space:]]*\*[[:space:]]*/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/ [A-Za-z_][A-Za-z0-9_]*$//' | sed 's/[[:space:]]*$//')
        if [[ -n "$type" ]]; then
            DEPEND_TYPES+=("$type")
        fi
    done
fi

# 添加返回值类型
if [[ -n "$RET_TYPE" && "$RET_TYPE" != "void" ]]; then
    RET_CLEAN=$(echo "$RET_TYPE" | sed 's/static[[:space:]]*//;s/inline[[:space:]]*//;s/[[:space:]]*$//')
    DEPEND_TYPES+=("$RET_CLEAN")
fi

echo "  依赖类型: ${DEPEND_TYPES[*]:-无}"

# 第五步：生成 main.c
echo
echo "==> 步骤5: 生成测试文件 main.c..."

MAIN_C="${OUTPUT_PATH}/src/main.c"

cat > "$MAIN_C" <<EOF
/*
 * main.c - 测试函数 ${FUNC_NAME}
 * 自动生成于: $(date '+%Y-%m-%d %H:%M:%S')
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 包含函数声明头文件 */
EOF

if [[ -n "$DECL_FILE" ]]; then
    echo "#include \"$(basename "$DECL_FILE")\"" >> "$MAIN_C"
fi

cat >> "$MAIN_C" <<EOF

/* 函数定义（如果未在头文件中） */
EOF

# 如果是静态函数，需要包含函数体
if [[ "$RET_TYPE" =~ static ]]; then
    echo "$FUNC_BODY" >> "$MAIN_C"
fi

cat >> "$MAIN_C" <<EOF

int main(void)
{
    printf("====================================\n");
    printf("测试函数: ${FUNC_NAME}\n");
    printf("====================================\n\n");

    /* 声明和初始化测试变量 */
EOF

# 根据参数生成变量声明和初始化
if [[ -n "$PARAM_LIST" && "$PARAM_LIST" != "void" ]]; then
    IFS=',' read -ra PARAMS <<< "$PARAM_LIST"
    for param in "${PARAMS[@]}"; do
        param=$(echo "$param" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        param_name=$(echo "$param" | grep -o '[A-Za-z_][A-Za-z0-9_]*$' || true)
        if [[ -n "$param_name" ]]; then
            # 提取类型（去掉参数名）
            param_type=$(echo "$param" | sed "s/[[:space:]]*${param_name}[[:space:]]*$//" | sed 's/[[:space:]]*$//')
            
            # 检查是否是指针类型
            is_pointer=0
            if [[ "$param_type" == *"*" ]]; then
                is_pointer=1
                # 去掉指针符号
                param_type=$(echo "$param_type" | sed 's/[[:space:]]*\*[[:space:]]*//g')
            fi
            
            # 生成变量声明
            if [[ $is_pointer -eq 1 ]]; then
                cat >> "$MAIN_C" <<EOF
    ${param_type} ${param_name}_data;
    memset(&${param_name}_data, 0, sizeof(${param_name}_data));
    ${param_type} *${param_name} = &${param_name}_data;
EOF
            else
                cat >> "$MAIN_C" <<EOF
    ${param_type} ${param_name};
    memset(&${param_name}, 0, sizeof(${param_name}));
EOF
            fi
        fi
    done
fi

cat >> "$MAIN_C" <<EOF

    printf("调用函数 ${FUNC_NAME}...\n");
EOF

# 处理返回值
RET_CLEAN=$(echo "$RET_TYPE" | sed 's/static[[:space:]]*//;s/inline[[:space:]]*//;s/[[:space:]]*$//')
if [[ "$RET_CLEAN" != "void" ]]; then
    cat >> "$MAIN_C" <<EOF

    ${RET_CLEAN} result = ${FUNC_NAME}(
EOF

    # 生成参数列表
    if [[ -n "$PARAM_LIST" && "$PARAM_LIST" != "void" ]]; then
        IFS=',' read -ra PARAMS <<< "$PARAM_LIST"
        param_names=()
        for param in "${PARAMS[@]}"; do
            param=$(echo "$param" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            param_name=$(echo "$param" | grep -o '[A-Za-z_][A-Za-z0-9_]*$' || true)
            if [[ -n "$param_name" ]]; then
                param_names+=("$param_name")
            fi
        done
        if [[ ${#param_names[@]} -gt 0 ]]; then
            param_str=$(IFS=', '; echo "${param_names[*]}")
            echo "        ${param_str}" >> "$MAIN_C"
        fi
    else
        echo "        void" >> "$MAIN_C"
    fi

    cat >> "$MAIN_C" <<EOF
    );

    printf("函数返回值: %d\n", (int)result);  /* TODO: 根据返回类型调整格式化 */
EOF
else
    cat >> "$MAIN_C" <<EOF

    ${FUNC_NAME}(
EOF
    if [[ -n "$PARAM_LIST" && "$PARAM_LIST" != "void" ]]; then
        IFS=',' read -ra PARAMS <<< "$PARAM_LIST"
        param_names=()
        for param in "${PARAMS[@]}"; do
            param=$(echo "$param" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            param_name=$(echo "$param" | grep -o '[A-Za-z_][A-Za-z0-9_]*$' || true)
            if [[ -n "$param_name" ]]; then
                param_names+=("$param_name")
            fi
        done
        if [[ ${#param_names[@]} -gt 0 ]]; then
            param_str=$(IFS=', '; echo "${param_names[*]}")
            echo "        ${param_str}" >> "$MAIN_C"
        fi
    else
        echo "        void" >> "$MAIN_C"
    fi
    echo "    );" >> "$MAIN_C"
fi

cat >> "$MAIN_C" <<EOF

    printf("\n测试完成!\n");
    return 0;
}
EOF

echo "  ✓ 生成 src/main.c"

# 第六步：生成 Makefile
echo
echo "==> 步骤6: 生成 Makefile..."

MAKEFILE="${OUTPUT_PATH}/Makefile"

cat > "$MAKEFILE" <<'EOF'
# Makefile - 自动生成的独立项目
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

CC = gcc
CFLAGS = -Wall -Wextra -g -I./include
LDFLAGS =

# 源文件
SRCS = $(wildcard src/*.c)
OBJS = $(SRCS:.c=.o)

# 目标文件
TARGET = test_$(notdir $(CURDIR))

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(OBJS) $(TARGET)
	rm -rf *.dSYM

# 依赖关系
EOF

# 添加头文件依赖
if [[ -n "$DECL_FILE" ]]; then
    echo "src/main.o: include/$(basename "$DECL_FILE")" >> "$MAKEFILE"
fi

echo "  ✓ 生成 Makefile"

# 第七步：生成 README
echo
echo "==> 步骤7: 生成项目文档..."

README="${OUTPUT_PATH}/README.md"

cat > "$README" <<EOF
# 独立项目 - ${FUNC_NAME}

自动生成于: $(date '+%Y-%m-%d %H:%M:%S')

## 项目信息

- **函数名**: ${FUNC_NAME}
- **返回值**: ${RET_TYPE}
- **参数列表**: ${PARAM_LIST:-void}

## 项目结构

\`\`\`
$(basename "$OUTPUT_PATH")/
├── src/
│   ├── main.c          # 测试主程序
$(if [[ -n "$DEF_FILE" ]]; then echo "│   └── $(basename "$DEF_FILE")          # 函数定义"; fi)
├── include/
$(if [[ -n "$DECL_FILE" ]]; then echo "│   └── $(basename "$DECL_FILE")          # 函数声明"; fi)
├── Makefile            # 编译脚本
└── README.md           # 本文档
\`\`\`

## 编译和运行

\`\`\`bash
# 编译
make

# 运行
make run
# 或
./test_*

# 清理
make clean
\`\`\`

## 依赖说明

EOF

if [[ ${#DEPEND_TYPES[@]} -gt 0 ]]; then
    echo "本函数依赖以下类型：" >> "$README"
    for type in "${DEPEND_TYPES[@]}"; do
        echo "- \`$type\`" >> "$README"
    done
else
    echo "本函数无特殊类型依赖。" >> "$README"
fi

cat >> "$README" <<EOF

## TODO

1. 完善 \`src/main.c\` 中的测试数据初始化
2. 根据需要添加缺失的类型定义和依赖库
3. 如果函数依赖其他函数，需要一并提取

## 注意事项

- 静态函数已被复制到 main.c 中
- 可能需要手动调整头文件包含路径
- 可能需要添加自定义类型定义

EOF

echo "  ✓ 生成 README.md"

# 第八步：递归提取所有依赖函数
echo
echo "==> 步骤8: 递归提取所有依赖函数..."

MAX_ITERATIONS=20
iteration=0
prev_missing=""

while [[ $iteration -lt $MAX_ITERATIONS ]]; do
    iteration=$((iteration + 1))
    
    echo "  ==> 第 $iteration 轮编译..."
    
    # 尝试编译
    cd "$OUTPUT_PATH"
    if make 2>&1 | tee /tmp/build_round_${iteration}.log; then
        echo
        echo "  ✅ 编译成功！"
        break
    fi
    
    # 检查是否有 undefined reference 错误
    if ! grep -q "undefined reference" /tmp/build_round_${iteration}.log; then
        echo "  ⚠️  编译失败但无 undefined reference，停止"
        break
    fi
    
    # 提取未定义符号
    missing=$(grep "undefined reference to" /tmp/build_round_${iteration}.log | \
              sed "s/.*undefined reference to \`//" | sed "s/'.*//" | sort -u)
    
    # 检查是否有进展
    if [[ "$missing" == "$prev_missing" ]]; then
        echo "  ⚠️  没有新的缺失符号，可能需要手动处理"
        echo "  缺失符号:"
        echo "$missing"
        break
    fi
    
    prev_missing="$missing"
    
    echo "  发现未定义符号:"
    echo "$missing"
    echo
    
    # 使用新脚本从源码提取函数实现
    EXTRACT_SCRIPT="${SCRIPT_DIR}/extract_missing_functions.sh"
    if [[ -x "$EXTRACT_SCRIPT" ]]; then
        "$EXTRACT_SCRIPT" "$missing" "$PROJECT_PATH" "$OUTPUT_PATH"
    else
        echo "  ⚠️  未找到 extract_missing_functions.sh"
        break
    fi
    
    cd - > /dev/null
done

if [[ $iteration -ge $MAX_ITERATIONS ]]; then
    echo "  ⚠️  达到最大迭代次数 $MAX_ITERATIONS"
fi

# 清理临时文件
rm -rf "$TEMP_DIR"

echo
echo "=========================================="
echo "✅ 独立项目创建成功！"
echo "=========================================="
echo
echo "项目路径: $OUTPUT_PATH"
echo
echo "下一步操作："
echo "  1. cd $OUTPUT_PATH"
echo "  2. make"
echo "  3. make run"
echo
echo "注意: 可能需要手动完善测试代码和依赖项"
echo