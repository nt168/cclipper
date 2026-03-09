#!/usr/bin/env bash
# ==============================================================
# Searchfunction.sh
# 功能：
#   1. 解析函数三元素（返回值、函数名、参数列表）
#   2. 在源码工程目录中搜索函数定义（.c）和声明（.h）
#   3. 检测宏定义
#   4. 按源码原目录结构复制到输出目录
# 参数：
#   $1: 函数定义字符串（如 "void fx(type c)" 或 "nt_tcp_recv_ext"）
#   $2: 源码工程目录
#   $3: 输出路径
# 作者：EAO 项目团队
# ==============================================================

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "用法: $0 '函数定义' <源码目录> <输出目录>"
    echo "例如: $0 'static int open_master(void)' /home/nt/project /tmp/fx"
    echo "或者: $0 'nt_tcp_recv_ext' /home/nt/project /tmp/fx"
    exit 1
fi

FUNC_INPUT="$1"
SRC_DIR="$2"
OUT_DIR="$3"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VARIANT_FILE="${SCRIPT_DIR}/FunVariant.cnf"

# 确保输出目录存在
mkdir -p "$OUT_DIR"

# ==============================================================
# get_fun: 解析函数三元素
#   输入: 函数签名字符串
#   输出: 写入 fun/<FUNC_NAME> 文件
#         包含 FUNC_NAME, RET_TYPE, count, PARAM_TYPES, PARAM_PTRS, PARAM_NAMES
# ==============================================================
get_fun() {
    local sig="$1"

    # 标准化：将换行/Tab统一成空格
    sig="$(printf '%s' "$sig" | tr '\n\t' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    # 检查是否有括号（如果没有，可能是宏或简单函数名）
    if [[ ! "$sig" =~ \(.*\) ]]; then
        # 没有括号，可能是宏或简单名称
        local FUNC_NAME="$sig"
        local RET_TYPE="(未知)"
        local count=0
        mkdir -p fun
        local out="fun/${FUNC_NAME}"
        {
            printf 'declare -- FUNC_NAME=%q\n' "$FUNC_NAME"
            printf 'declare -- RET_TYPE=%q\n' "$RET_TYPE"
            printf 'declare -- count=%q\n' "$count"
            declare -a PARAM_TYPES=()
            declare -a PARAM_PTRS=()
            declare -a PARAM_NAMES=()
            declare -p PARAM_TYPES PARAM_PTRS PARAM_NAMES
        } >"$out"
        return 0
    fi

    # 提取括号前和括号内
    local before_paren after_paren param_str
    before_paren="${sig%%(*}"
    after_paren="${sig#*\(}"
    param_str="${after_paren%\)*}"

    # 规范化括号前空白
    local header_norm
    header_norm="$(
        echo "$before_paren" \
        | tr '\t' ' ' \
        | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
    )"

    # 提取函数名和返回值
    local FUNC_NAME RET_TYPE
    FUNC_NAME="${header_norm##* }"
    RET_TYPE="${header_norm% $FUNC_NAME}"

    # 清理参数字符串
    param_str="$(echo "$param_str" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    # 解析参数数组
    local count=0
    declare -a PARAM_TYPES=()
    declare -a PARAM_PTRS=()
    declare -a PARAM_NAMES=()

    if [[ -z "$param_str" || "$param_str" == "void" ]]; then
        count=0
    else
        local -a params
        IFS=',' read -r -a params <<< "$param_str"

        local idx=1 raw p name type_str ptr_str base_type t
        for raw in "${params[@]}"; do
            p="$(echo "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\+/ /g')"
            [[ -z "$p" ]] && continue

            # 提取参数名（最后一个标识符）
            name="$(echo "$p" | grep -o '[A-Za-z_][A-Za-z0-9_]*' | tail -n1 || true)"

            if [[ -z "$name" ]]; then
                type_str="$p"
                name="(未识别)"
            else
                type_str="${p%$name}"
                type_str="$(echo "$type_str" | sed 's/[[:space:]]*$//')"
            fi

            # 智能提取指针：只剥离紧贴参数名的尾部 *...*
            # 例如：char *const *arguments => base_type="char *const", ptr_str="*"
            t="$(echo "$type_str" | sed 's/[[:space:]]\+/ /g; s/[[:space:]]*$//')"
            ptr_str=""
            while :; do
                t="$(echo "$t" | sed 's/[[:space:]]*$//')"
                [[ "$t" == *"*" ]] || break
                ptr_str="${ptr_str}*"
                t="${t%\*}"
            done
            base_type="$(echo "$t" | sed -E 's/[[:space:]]\+/ /g; s/^ //; s/ $//; s/\*[[:space:]]+(const|volatile|restrict)/*\1/g')"

            PARAM_TYPES[$idx]="$base_type"
            PARAM_PTRS[$idx]="$ptr_str"
            PARAM_NAMES[$idx]="$name"
            ((idx++))
        done
        count=$((idx - 1))
    fi

    # 写入文件
    mkdir -p fun
    local out="fun/${FUNC_NAME}"
    {
        printf 'declare -- FUNC_NAME=%q\n' "$FUNC_NAME"
        printf 'declare -- RET_TYPE=%q\n' "$RET_TYPE"
        printf 'declare -- count=%q\n' "$count"
        declare -p PARAM_TYPES PARAM_PTRS PARAM_NAMES
    } >"$out"
}

# ==============================================================
# search_fun: 在工程目录中搜索函数定义、声明和宏定义
#   输入: fun/<FUNC_NAME> 文件路径, 工程目录
#   输出: 写入 fsrc/<FUNC_NAME> 文件
# ==============================================================
search_fun() {
    local funfile="$1"
    local proj="$2"

    if [[ ! -f "$funfile" ]]; then
        echo "错误: funfile 不存在: $funfile" >&2
        return 1
    fi
    if [[ ! -d "$proj" ]]; then
        echo "错误: project 路径不存在: $proj" >&2
        return 1
    fi

    # 读取函数信息
    # shellcheck disable=SC1090
    source "$funfile"

    : "${FUNC_NAME:?FUNC_NAME 未定义}"

    local def_file=""
    local def_body=""
    local -a decl_files=()
    local is_macro=0
    local macro_def=""

    # 先检查是否是宏定义（使用更简单的方法）
    while IFS= read -r -d '' f; do
        # 检查文件中是否有 #define FUNC_NAME
        if grep -q "^[[:space:]]*#[[:space:]]*define[[:space:]]\+${FUNC_NAME}\b" "$f" 2>/dev/null; then
            is_macro=1
            def_file="$f"
            
            # 提取宏定义内容（包括多行宏）
            macro_def=$(awk "
                /^[[:space:]]*#[[:space:]]*define[[:space:]]+${FUNC_NAME}[([:space:]]/ {
                    found = 1
                    line = \$0
                    # 检查是否有续行符
                    while (line ~ /\\\\\$/) {
                        print line
                        getline line
                    }
                    print line
                    exit
                }
            " "$f")
            break
        fi
    done < <(find "$proj" -type f \( -name '*.h' -o -name '*.c' \) -print0)

    # 如果不是宏，搜索函数定义
    if [[ $is_macro -eq 0 ]]; then
        while IFS= read -r -d '' f; do
            local out
            out="$(perl -0777 -e '
                use strict; use warnings;
                my ($fn, $path) = @ARGV;
                local $/; my $orig = <STDIN>;
                my $s = $orig;

                # 用空格替换注释/字符串
                $s =~ s{/\*.*?\*/}{ " " x length($&) }gse;
                $s =~ s{//[^\n]*}{ " " x length($&) }gse;
                $s =~ s{"(?:\\.|[^"\\])*"}{ " " x length($&) }gse;
                $s =~ s{'\''(?:\\.|[^'\''\\])*'\''}{ " " x length($&) }gse;

                my $len = length($s);

                while ($s =~ /(?<![\w\.>])\Q$fn\E\s*\(/g) {
                    my $m_end = pos($s);
                    my $paren = $m_end - 1;

                    # 找到匹配的 ")"
                    my $d = 1;
                    my $i = $paren + 1;
                    while ($i < $len) {
                        my $c = substr($s,$i,1);
                        if ($c eq "(") { $d++; }
                        elsif ($c eq ")") { $d--; last if $d==0; }
                        $i++;
                    }
                    next if $d != 0;
                    my $rparen = $i;

                    # 跳过空白/宏/attribute(...)
                    my $k = $rparen + 1;
                    while ($k < $len) {
                        if (substr($s,$k) =~ /\A\s/) { $k++; next; }
                        if (substr($s,$k) =~ /\A([A-Za-z_]\w*)/ ) {
                            my $id = $1;
                            $k += length($id);
                            while ($k < $len && substr($s,$k,1) =~ /\s/) { $k++; }
                            if ($k < $len && substr($s,$k,1) eq "(") {
                                my $dd=1; my $j=$k+1;
                                while ($j < $len) {
                                    my $cc=substr($s,$j,1);
                                    if ($cc eq "(") { $dd++; }
                                    elsif ($cc eq ")") { $dd--; last if $dd==0; }
                                    $j++;
                                }
                                last if $dd!=0;
                                $k = $j+1;
                                next;
                            }
                            next;
                        }
                        last;
                    }

                    # 定义：下一个关键字符是 "{"
                    while ($k < $len && substr($s,$k,1) =~ /\s/) { $k++; }
                    next if $k >= $len;
                    next unless substr($s,$k,1) eq "{";

                    my $brace = $k;

                    # 计算snippet起点：包含可能在上一行的返回值
                    my $st = rindex($orig, "\n", $-[0]);
                    $st = ($st < 0) ? 0 : $st + 1;
                    for (1..3) {
                        last if $st == 0;
                        my $pn = rindex($orig, "\n", $st-2);
                        last if $pn < 0;
                        my $line = substr($orig, $pn+1, $st-$pn-1);
                        last if $line =~ /[;{}]/;
                        if ($line =~ /^\s*(?:[A-Za-z_]\w*|\*|\s)+\s*$/) {
                            $st = $pn + 1;
                        } else {
                            last;
                        }
                    }

                    # 找匹配的 "}"
                    my $bd=1; my $q=$brace+1;
                    while ($q < $len) {
                        my $cc = substr($s,$q,1);
                        if ($cc eq "{") { $bd++; }
                        elsif ($cc eq "}") { $bd--; last if $bd==0; }
                        $q++;
                    }
                    next if $bd != 0;
                    my $end = $q;

                    my $snippet = substr($orig, $st, $end-$st+1);
                    print $snippet;
                    exit 0;
                }
                exit 1;
            ' "$FUNC_NAME" "$f" <"$f" 2>/dev/null)" || true

            if [[ -n "$out" ]]; then
                def_file="$f"
                def_body="$out"
                break
            fi
        done < <(find "$proj" -type f -name '*.c' -print0)

        # 搜索函数声明（.h 文件）
        while IFS= read -r -d '' f; do
            if perl -0777 -e '
                use strict; use warnings;
                my ($fn)=@ARGV; local $/; my $s=<STDIN>;

                $s =~ s{/\*.*?\*/}{ " " x length($&) }gse;
                $s =~ s{//[^\n]*}{ " " x length($&) }gse;
                $s =~ s{"(?:\\.|[^"\\])*"}{ " " x length($&) }gse;
                $s =~ s{'\''(?:\\.|[^'\''\\])*'\''}{ " " x length($&) }gse;

                my $len = length($s);
                while ($s =~ /(?<![\w\.>])\Q$fn\E\s*\(/g) {
                    my $m_end = pos($s);
                    my $paren = $m_end - 1;
                    my $d=1; my $i=$paren+1;
                    while ($i<$len) {
                        my $c=substr($s,$i,1);
                        if ($c eq "(") { $d++; }
                        elsif ($c eq ")") { $d--; last if $d==0; }
                        $i++;
                    }
                    next if $d!=0;
                    my $k=$i+1;
                    while ($k<$len && substr($s,$k,1)=~ /\s/) { $k++; }
                    # 跳过宏/attribute(...)
                    while ($k<$len) {
                        if (substr($s,$k,1)=~ /\s/) { $k++; next; }
                        last if substr($s,$k,1) eq ";" || substr($s,$k,1) eq "{";
                        if (substr($s,$k) =~ /\A([A-Za-z_]\w*)/ ) {
                            my $id=$1; $k += length($id);
                            while ($k<$len && substr($s,$k,1)=~ /\s/) { $k++; }
                            if ($k<$len && substr($s,$k,1) eq "(") {
                                my $dd=1; my $j=$k+1;
                                while ($j<$len) {
                                    my $cc=substr($s,$j,1);
                                    if ($cc eq "(") { $dd++; }
                                    elsif ($cc eq ")") { $dd--; last if $dd==0; }
                                    $j++;
                                }
                                last if $dd!=0;
                                $k=$j+1;
                                next;
                            }
                            next;
                        }
                        last;
                    }
                    while ($k<$len && substr($s,$k,1)=~ /\s/) { $k++; }
                    if ($k<$len && substr($s,$k,1) eq ";") { exit 0; }
                }
                exit 1;
            ' "$FUNC_NAME" <"$f" 2>/dev/null; then
                decl_files+=("$f")
            fi
        done < <(find "$proj" -type f -name '*.h' -print0)
    fi

    # 输出结果
    mkdir -p fsrc
    local out="fsrc/${FUNC_NAME}"

    {
        if [[ $is_macro -eq 1 ]]; then
            echo "[$FUNC_NAME 是宏定义]"
            if [[ -n "$def_file" ]]; then
                local rel="${def_file#"$proj"/}"
                [[ "$rel" == "$def_file" ]] && rel="$def_file"
                echo "$FUNC_NAME 宏定义位置: $rel"
                echo "$FUNC_NAME 宏定义内容："
                printf "%s\n" "$macro_def"
            fi
        else
            if ((${#decl_files[@]})); then
                for f in "${decl_files[@]}"; do
                    local rel="${f#"$proj"/}"
                    [[ "$rel" == "$f" ]] && rel="$f"
                    echo "$FUNC_NAME 声明: $rel"
                done
            else
                echo "$FUNC_NAME 声明: (未找到)"
            fi

            if [[ -n "$def_file" ]]; then
                local rel="${def_file#"$proj"/}"
                [[ "$rel" == "$def_file" ]] && rel="$def_file"
                echo "$FUNC_NAME 定义: $rel"
                echo "$FUNC_NAME 函数体："
                printf "%s\n" "$def_body"
            else
                echo "$FUNC_NAME 定义: (未找到)"
                echo "$FUNC_NAME 函数体："
                echo "(未找到)"
            fi
        fi
    } >"$out"

    echo "✅ 结果已写入: $out"
}

# ==============================================================
# copy_with_structure: 按源码目录结构复制文件
# ==============================================================
copy_with_structure() {
    local src_file="$1"
    local src_root="$2"
    local dst_root="$3"

    rel_path=$(realpath --relative-to="$src_root" "$src_file" 2>/dev/null || echo "${src_file#$src_root/}")
    dst_path="$dst_root/$rel_path"

    mkdir -p "$(dirname "$dst_path")"
    cp "$src_file" "$dst_path"
    echo "📂 已复制: $rel_path"
}

# ==============================================================
# 主流程
# ==============================================================
echo "==> 搜索函数: $FUNC_INPUT"
echo "==> 源码目录: $SRC_DIR"
echo "==> 输出路径: $OUT_DIR"
echo

# 解析函数
get_fun "$FUNC_INPUT"

# 找到刚生成的 fun 文件
funfile="$(ls -1t fun/* 2>/dev/null | head -n1 || true)"
if [[ -z "$funfile" ]]; then
    echo "❌ 错误: 未生成 fun/<函数名> 文件" >&2
    exit 2
fi

# 搜索函数定义和声明
search_fun "$funfile" "$SRC_DIR"

# 读取搜索结果并复制文件
# shellcheck disable=SC1090
source "$funfile"
result_file="fsrc/${FUNC_NAME}"

if [[ ! -f "$result_file" ]]; then
    echo "❌ 错误: 未找到搜索结果文件" >&2
    exit 3
fi

echo
echo "==> 正在复制相关文件到 $OUT_DIR ..."

# 解析结果文件，提取文件路径并复制
while IFS= read -r line; do
    if [[ "$line" =~ (声明|定义|宏定义位置):[[:space:]]*(.+)$ ]]; then
        file_path="${BASH_REMATCH[2]}"
        # 去除可能的 "project/" 前缀
        file_path="${file_path#project/}"

        # 如果不是 "(未找到)"，且文件存在
        if [[ "$file_path" != "(未找到)" ]]; then
            full_path="$SRC_DIR/$file_path"
            if [[ -f "$full_path" ]]; then
                copy_with_structure "$full_path" "$SRC_DIR" "$OUT_DIR"
            fi
        fi
    fi
done < "$result_file"

echo
echo "✅ 完成！结果目录：$OUT_DIR"
echo "✅ 解析信息：fun/$FUNC_NAME"
echo "✅ 搜索结果：fsrc/$FUNC_NAME"