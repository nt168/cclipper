# CClipper - C语言函数搜索工具

快速在C语言项目中搜索函数定义、声明和宏定义，并按源码目录结构复制相关文件。

## 功能特性

- ✅ **函数三元素解析**：自动提取返回值、函数名、参数列表
- ✅ **智能搜索**：支持多种函数定义变体（单行、多行、续行等）
- ✅ **宏定义检测**：自动识别 `#define` 宏定义
- ✅ **目录结构保留**：按源码原目录结构复制文件
- ✅ **参数指针解析**：正确处理 `char *const *ptr` 等复杂类型
- ✅ **独立项目生成**：提取函数及其依赖，生成可编译运行的独立项目

## 文件结构

```
cclipper/
├── cclipper.sh                  # 主入口脚本
├── Searchfunction.sh            # 核心搜索脚本
├── extract_function.sh          # 函数提取脚本
├── create_standalone_project.sh # 独立项目生成器
├── analyze_dependencies.sh      # 依赖分析工具
├── configure.sh                 # 系统环境检测（新增）
├── detect_dependencies.sh       # 依赖自动检测（新增）
├── build.sh                     # 自动构建脚本（新增）
├── FunVariant.cnf               # 函数变体配置
├── fun/                         # 解析结果（运行时生成）
└── fsrc/                        # 搜索结果（运行时生成）
```
cclipper/
├── cclipper.sh                  # 主入口脚本
├── Searchfunction.sh            # 核心搜索脚本
├── extract_function.sh          # 函数提取脚本
├── create_standalone_project.sh # 独立项目生成器
├── analyze_dependencies.sh      # 依赖分析工具
├── FunVariant.cnf               # 函数变体配置
├── fun/                         # 解析结果（运行时生成）
└── fsrc/                        # 搜索结果（运行时生成）
```

## 快速开始

### 基本用法

```bash
# 方式1：两个参数（需设置环境变量 CC_SRC_DIR）
export CC_SRC_DIR=/path/to/project
./cclipper.sh "void fx(type c)" /tmp/output

# 方式2：三个参数（推荐）
./cclipper.sh "void fx(type c)" /path/to/project /tmp/output

# 搜索函数名（自动识别宏定义）
./cclipper.sh "nt_tcp_recv" /path/to/project /tmp/output

# 搜索复杂函数
./cclipper.sh "int pty_start(Pty *pty, const char *program)" /path/to/project /tmp/output
```

### 高级用法

```bash
# 启用详细输出
CC_VERBOSE=1 ./cclipper.sh "func_name" /path/to/project /tmp/output

# 直接调用核心脚本
./Searchfunction.sh "func_name" /path/to/project /tmp/output
```

### 独立项目生成（新功能）

生成可独立编译运行的测试项目：

```bash
# 基本用法
./create_standalone_project.sh <返回值> <函数名> <参数列表> <项目路径> <输出路径>

# 或使用完整函数签名（推荐）
./create_standalone_project.sh "函数签名" <项目路径> <输出路径>

# 示例1：提取简单函数
./create_standalone_project.sh "int simple_func(int a, char *b)" /home/project /tmp/standalone

# 示例2：提取静态函数
./create_standalone_project.sh "static void mem_link_chunk(nt_shmem_info_t *info, void *chunk)" /home/project /tmp/standalone

# 示例3：提取无参函数
./create_standalone_project.sh "int open_master(void)" /home/project /tmp/standalone
```

生成的项目结构：

```
standalone/
├── src/
│   ├── main.c          # 测试主程序（自动生成）
│   └── *.c             # 函数定义文件
├── include/
│   ├── config.h        # 平台配置（自动生成）
│   ├── compat.h        # 兼容性头文件（自动生成）
│   └── *.h             # 函数声明头文件
├── Makefile            # 编译脚本（自动生成）
└── README.md           # 项目文档（自动生成）
```

编译运行：

```bash
# 方式1：自动构建（推荐）
cd /tmp/standalone
./build.sh .                    # 自动检测环境、生成依赖、编译、运行

# 方式2：手动构建
cd /tmp/standalone
./configure.sh                  # 检测系统环境，生成 config.h
make                            # 编译项目
make run                        # 运行测试
make clean                      # 清理
```

### 自动构建流程（新增）

完整的自动化构建流程：

```bash
# 一键构建：检测环境 -> 生成依赖 -> 编译 -> 测试
./build.sh /tmp/zbx_test

========================================
自动构建工具
========================================

项目目录: /tmp/zbx_test

==> 步骤1: 系统环境检测...
[INFO] 检测系统环境...
[OK] 操作系统: linux
[OK] 编译器: gcc

==> 步骤2: 准备构建目录...

==> 步骤3: 检测缺失依赖...
[INFO] 尝试编译...
[WARN] 发现缺失依赖
[INFO] 生成依赖实现: src/deps_impl.c
[OK] deps_impl.c 已生成
[OK] Makefile 已更新

==> 步骤4: 验证构建结果...
[OK] 可执行文件: ./test_zbx_test

==> 步骤5: 运行测试...
====================================
测试函数: zbx_hashmap_get
====================================
✅ 测试完成！

✅ 构建完成！
```

## 使用示例

### 示例1：搜索简单函数

```bash
$ ./cclipper.sh "simple_func" /tmp/test_project /tmp/output1

==> 搜索函数: simple_func
==> 源码目录: /tmp/test_project
==> 输出路径: /tmp/output1

✅ 结果已写入: fsrc/simple_func

==> 正在复制相关文件到 /tmp/output1 ...
📂 已复制: include/test_functions.h
📂 已复制: src/test_functions.c

✅ 完成！结果目录：/tmp/output1
```

### 示例2：搜索宏定义

```bash
$ ./cclipper.sh "nt_tcp_recv" /tmp/test_project /tmp/output2

✅ 结果已写入: fsrc/nt_tcp_recv
📂 已复制: include/macros.h
```

### 示例3：提取Zabbix函数并生成独立项目（完整实战）

从Zabbix 3.4.7项目中提取 `zbx_hashmap_get` 函数并生成可运行的独立项目：

```bash
# 步骤1：生成独立项目
$ ./create_standalone_project.sh "int zbx_hashmap_get(zbx_hashmap_t *hm, zbx_uint64_t key)" /home/phy/zabbix-3.4.7 /tmp/zbx_test

==========================================
函数提取工具 - 独立项目生成器
==========================================

函数信息:
  返回值: int
  函数名: zbx_hashmap_get
  参数列表: zbx_hashmap_t *hm, zbx_uint64_t key

✅ 独立项目创建成功！

# 步骤2：进入项目目录并编译
$ cd /tmp/zbx_test
$ make

# 步骤3：运行测试
$ ./test_zbx_hashmap

====================================
测试函数: zbx_hashmap_get
====================================

1. 初始化hashmap...
   ✓ Hashmap初始化成功

2. 插入测试数据...
   ✓ 插入: key=100, value=1000
   ✓ 插入: key=200, value=2000
   ...

3. 测试查询功能...
   ✓ 查询 key=100, 得到 value=1000 ✓
   ✓ 查询 key=200, 得到 value=2000 ✓
   ...

✅ 测试完成！
====================================
```

生成的项目结构：

```
/tmp/zbx_test/
├── include/
│   ├── common.h        # 自动提取的依赖头文件
│   ├── config.h        # 配置文件
│   ├── sysinc.h        # 系统头文件
│   ├── zbxalgo.h       # 函数声明
│   ├── zbx_compat.h    # 兼容性头文件
│   └── ...
├── src/
│   ├── hashmap.c       # 函数定义
│   ├── main.c          # 测试主程序（自动生成）
│   └── zbx_deps.c      # 依赖函数实现（手动补充）
├── Makefile            # 编译脚本
├── README.md           # 项目文档
└── test_zbx_hashmap    # 可执行文件
```

## 输出文件说明

### fun/<函数名>

存储函数解析信息，格式：

```bash
declare -- FUNC_NAME=pty_start
declare -- RET_TYPE=int
declare -- count=9
declare -a PARAM_TYPES=([1]="Pty" [2]="const char" [3]="char *const" ...)
declare -a PARAM_PTRS=([1]="*" [2]="*" [3]="*" ...)
declare -a PARAM_NAMES=([1]="pty" [2]="program" [3]="arguments" ...)
```

### fsrc/<函数名>

存储搜索结果，格式：

```
pty_start 声明: include/Pty.h
pty_start 定义: src/Pty.c
pty_start 函数体：
int pty_start(Pty *pty, const char *program, ...) {
    ...
}
```

## 参数解析规则

### 指针解析

正确处理复杂指针类型：

```c
char *const *arguments  →  类型: char *const  指针: *  名称: arguments
const char *ptr         →  类型: const char   指针: *  名称: ptr
int **matrix            →  类型: int          指针: ** 名称: matrix
```

### 函数变体支持

支持以下函数定义格式：

```c
// 单行
int func(int a) { }

// 多行返回值
static int
func(int a) { }

// 多行参数
int func(
    int a,
    char *b
) { }

// 带续行符
int func(int a, \
         char *b) { }
```

## 配置文件

### FunVariant.cnf

配置函数定义的匹配模式，可根据项目需要自定义。

## 环境变量

- `CC_SRC_DIR`：默认源码目录
- `CC_VERBOSE`：设置为 `1` 启用详细输出

## 依赖

- Bash 4.0+
- Perl 5.x
- grep, awk, sed

## 常见问题

**Q: 找不到函数定义？**
A: 检查源码目录路径是否正确，确认函数名拼写无误。

**Q: 参数类型解析错误？**
A: 复杂类型（如函数指针）可能需要手动调整解析结果。

**Q: 宏定义未识别？**
A: 确保宏定义格式为 `#define MACRO_NAME ...`

**Q: 独立项目编译失败？**
A: 可能需要手动补充以下内容：
   - 依赖函数实现（如 `zbx_deps.c`）
   - 兼容性头文件（如 `zbx_compat.h`）
   - 平台特定的配置（如 `config.h`）
   - 缺失的系统头文件包含

**Q: 如何处理跨平台问题？**
A: 
   - 修改 `config.h` 以适配目标平台
   - 添加平台兼容性宏定义
   - 使用条件编译处理平台差异

## 独立项目生成说明

### 自动生成的内容

1. **源文件**：提取的函数定义（`.c` 文件）
2. **头文件**：函数声明及依赖（`.h` 文件）
3. **main.c**：测试主程序框架
4. **Makefile**：编译脚本
5. **README.md**：项目文档

### 可能需要手动补充的内容

1. **依赖函数实现**：
   - 内存管理函数
   - 工具函数
   - 平台适配函数

2. **兼容性处理**：
   - 跨平台宏定义
   - 类型定义
   - 系统头文件包含

3. **测试数据**：
   - 完善 `main.c` 中的测试逻辑
   - 准备测试用例数据

### 编译流程

```bash
# 1. 生成独立项目
./create_standalone_project.sh "函数签名" 项目路径 输出路径

# 2. 进入项目目录
cd 输出路径

# 3. 尝试编译
make

# 4. 根据错误提示补充缺失依赖
#    - 创建 zbx_deps.c 等依赖文件
#    - 修改头文件包含

# 5. 重新编译直到成功
make clean && make

# 6. 运行测试
make run
```

## 项目亮点

- ✅ **智能依赖提取**：自动分析并提取依赖的头文件
- ✅ **完整测试框架**：生成可运行的测试程序
- ✅ **跨项目适用**：已在Zabbix 3.4.7等真实项目中验证
- ✅ **易于扩展**：清晰的代码结构，便于添加新功能

## 许可证

MIT License

## 作者

EAO 项目团队