# QuickJS WASM 编译指南：如何将 QuickJS 移植到 AO HyperBEAM

> **文档性质**：技术解释文档
> **适用读者**：想理解 QuickJS WASM 编译过程的开发者
> **最后更新**：2026-02-07

---

## 阅读前必读

### 情况 A：只想运行现有合约

如果你的目的是**运行** JavaScript 智能合约（使用现有的 `aojs.wasm`），**你不需要阅读本文档**！

运行时只需要：
```
~/HyperBEAM/aojs/
├── aojs.wasm              ← 编译好的运行时（直接使用）
├── ao-runtime.js           ← JS 运行时（自动注入）
└── aojs-modules/          ← 你的合约
    └── your-contract.js
```

### 情况 B：想修改/重新编译 QuickJS

如果你需要：
- 修改 QuickJS 源码
- 调整编译参数
- 重新编译 WASM 模块

那么请继续阅读本文档。

---

## 一、背景介绍

### 1.1 为什么选择 QuickJS？

QuickJS 是一个用 C 编写的轻量级 JavaScript 引擎，具有以下特点：

| 特性 | QuickJS | 对比：V8 |
|------|---------|----------|
| **体积** | ~1MB 编译后 | ~10MB+ |
| **启动速度** | 微秒级 | 毫秒级 |
| **设计目标** | 嵌入到其他程序 | 极致性能 |
| **ES 标准** | ES2020-ES2023 几乎完整支持 | 完整支持 |
| **代码复杂度** | 单个 C 文件 + 少量依赖 | 数十万行 C++ |

**核心优势**：QuickJS 的小体积和快启动特性，使其非常适合嵌入到 HyperBEAM 这样的去中心化计算平台中运行 JavaScript 智能合约。

### 1.2 什么是 WASI？

WASI = **WebAssembly System Interface**（WebAssembly 系统接口）

```
┌─────────────────────────────────────────────────────────────┐
│                        操作系统                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Linux/Windows/macOS 提供完整的系统 API              │   │
│  │  (文件、网络、线程、内存管理等)                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ↑
                           │ POSIX / Win32
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      原生应用程序                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  直接调用操作系统 API                                │   │
│  │  pthread_*、fenv.h、malloc_usable_size 等           │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

                    ┌─────────────────────┐
                    │       WASI         │  ←  标准化的 WASM 系统接口
                    └─────────────────────┘
                           ↑
                           │ WASI API（受限）
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                     WASM 应用                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  运行在沙盒中，无法直接访问操作系统                    │   │
│  │  只能通过 WASI 接口访问受控资源                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**关键问题**：QuickJS 原生设计运行在**原生操作系统**上，依赖许多 POSIX 系统调用。WASI 是一个**受限的沙盒环境**，不提供这些系统调用。

---

## 二、核心挑战

将 QuickJS 编译为 WASM 面临以下挑战：

```
┌─────────────────────────────────────────────────────────────┐
│                   QuickJS 原始依赖                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. pthread_* (线程)     ──▶  WASI 没有线程支持           │
│  2. fenv.h (浮点环境)    ──▶  WASI 没有浮点环境 API       │
│  3. malloc_usable_size   ──▶  WASI 没有内存 introspection │
│  4. 随机数/时间          ──▶  需要确定性替代方案           │
│  5. 系统 API             ──▶  受限的 WASI 接口             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   我们的适配工作                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ✅ 提供 stub 函数（空实现，让代码编译通过）                │
│  ✅ 实现确定性运行时（PRNG、时间戳）                        │
│  ✅ 创建 Erlang-WASM 接口层                                 │
│  ✅ 配置编译参数（内存限制、导出函数）                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、适配工作详解

### 3.1 WASI Stub 头文件

**文件**：`wasi_stubs.h`

**目的**：提供 WASI 环境缺失的函数声明，让 QuickJS 代码能够编译通过。

```c
#ifndef WASI_STUBS_H
#define WASI_STUBS_H
#include <stddef.h>

// 1. 浮点数环境 stub
// WASI 没有 <fenv.h>，QuickJS 用它来控制浮点舍入模式
#define FE_DOWNWARD 0x400
#define FE_UPWARD 0x800
#define FE_TOWARDZERO 0xC00

// 提供空实现，舍入模式默认即可
static inline int fesetround(int r) { (void)r; return 0; }
static inline int fegetround(void) { return 0; }

// 2. 内存 introspection stub
// WASI 没有 malloc_usable_size（返回已分配内存的实际大小）
static inline size_t malloc_usable_size(void *p) { (void)p; return 0; }

#endif
```

**为什么要这样做**：

| 依赖 | 原始用途 | WASI 问题 | 解决方案 |
|------|----------|-----------|----------|
| `fenv.h` | 控制浮点运算舍入模式 | WASI 不提供此 API | 返回默认值，JS 运算不受影响 |
| `malloc_usable_size` | 调试/优化内存使用 | WASI 不支持 introspection | 返回 0，不影响功能 |

**关键洞察**：这些函数对 QuickJS 执行 JavaScript **不是必须的**，提供 stub 就足够让代码编译和运行。

---

### 3.2 Pthread Stub

**文件**：`ao_runtime.c`（部分）

**目的**：QuickJS 内部使用 pthread 做线程同步，WASI 没有线程支持。

```c
// 定义宏快速生成 stub 函数
#define STUB(ret, name, args) ret name args { return 0; }

// QuickJS 使用的所有 pthread 函数都提供空实现
STUB(int, pthread_mutex_init, (pthread_mutex_t *m, const pthread_mutexattr_t *a))
STUB(int, pthread_mutex_destroy, (pthread_mutex_t *m))
STUB(int, pthread_mutex_lock, (pthread_mutex_t *m))
STUB(int, pthread_mutex_unlock, (pthread_mutex_t *m))
STUB(int, pthread_cond_init, (pthread_cond_t *c, const pthread_condattr_t *a))
STUB(int, pthread_cond_destroy, (pthread_cond_t *c))
STUB(int, pthread_cond_signal, (pthread_cond_t *c))
STUB(int, pthread_cond_broadcast, (pthread_cond_t *c))
STUB(int, pthread_cond_wait, (pthread_cond_t *c, pthread_mutex_t *m))
STUB(int, pthread_cond_timedwait, (pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *t))
```

**为什么要这样做**：

```
问题：QuickJS 的线程相关代码在做什么？

QuickJS 内部有：
- 异步回调机制（虽然单线程）
- 一些用 pthread_mutex 保护的数据结构
- 条件变量用于事件通知

WASI 环境：
- 没有真正的线程
- 单线程执行模型

解决方案：
- 所有 pthread_* 返回 0（成功）
- mutex_* 是空操作
- 条件变量是空操作

结果：
- QuickJS 认为线程操作成功
- 数据保护在单线程环境下不需要
- 代码继续正常执行
```

---

### 3.3 C 接口层

**文件**：`ao_runtime.c`

**目的**：在 QuickJS（C）和 Erlang/WASM 之间建立桥梁。

```c
#include "quickjs.h"

// 全局 QuickJS 运行时实例（每个 WASM 实例一个）
static JSRuntime *rt;
static JSContext *ctx;

// ============================================================
// 初始化函数：WASM 模块加载时自动调用
// ============================================================
int main(void) {
    return qjs_init();
}

// 初始化 QuickJS 运行时
int qjs_init(void) {
    if (rt) return 0;  // 防止重复初始化

    // 创建运行时（管理 JS 对象的内存）
    if (!(rt = JS_NewRuntime())) return -1;

    // 内存限制：防止恶意合约耗尽资源
    JS_SetMemoryLimit(rt, 16*1024*1024);   // 16MB

    // 栈大小限制：防止递归过深
    JS_SetMaxStackSize(rt, 256*1024);      // 256KB

    // 创建上下文（每个上下文是独立的 JS 环境）
    if (!(ctx = JS_NewContext(rt))) return -2;

    return 0;
}

// ============================================================
// 核心接口：执行 JavaScript 代码
// ============================================================
int qjs_eval(const char *code, int len, char *out, int out_size) {
    if (!ctx) return -1;  // 运行时未初始化

    // 执行 JS 代码
    JSValue r = JS_Eval(ctx, code, len, "<eval>", JS_EVAL_TYPE_GLOBAL);

    // 处理异常
    if (JS_IsException(r)) {
        JSValue e = JS_GetException(ctx);
        const char *s = JS_ToCString(ctx, e);
        int n = snprintf(out, out_size, "{\"error\":\"%s\"}", s ? s : "?");
        if (s) JS_FreeCString(ctx, s);
        JS_FreeValue(ctx, e);
        JS_FreeValue(ctx, r);
        return n;
    }

    // 返回结果
    int n = 0;
    if (!JS_IsUndefined(r)) {
        const char *s = JS_ToCString(ctx, r);
        if (s) {
            n = snprintf(out, out_size, "%s", s);
            JS_FreeCString(ctx, s);
        }
    }
    JS_FreeValue(ctx, r);
    return n;
}
```

**关键设计决策**：

| 设计点 | 决策 | 原因 |
|--------|------|------|
| 全局实例 | 单个 `rt` 和 `ctx` | WASM 实例生命周期匹配进程生命周期 |
| 内存限制 | 16MB | 防止单个合约耗尽资源 |
| 栈限制 | 256KB | 防止递归攻击 |
| 结果格式 | JSON 字符串 | 便于 Erlang 端解析 |

---

### 3.4 确定性运行时

**文件**：`ao-runtime.js`

**目的**：保证智能合约的**确定性**——相同的输入必须产生相同的输出。

```javascript
// ============================================================
// 1. 全局状态（每个 WASM 实例私有）
// ============================================================
const _outbox = [];              // 待发送的消息
globalThis.state = {};            // 合约状态
globalThis.msg = {};              // 当前消息
globalThis.env = {};              // 环境变量（区块时间戳等）

// 获取/清空 outbox（供 Erlang 调用）
globalThis._getOutbox = () => JSON.stringify(_outbox);
globalThis._clearOutbox = () => { _outbox.length = 0; };

// ============================================================
// 2. 确定性 PRNG（伪随机数生成器）
// ============================================================

// 初始种子（会被消息哈希覆盖）
let _seed = [1, 2];

// 设置种子函数（由 Erlang 调用，用消息哈希作为种子）
globalThis._setSeed = (s1, s2) => {
    _seed = [s1 >>> 0, s2 >>> 0];
};

// xorshift128+ 算法
const _xorshift = () => {
    let s1 = _seed[0], s2 = _seed[1];
    _seed[0] = s2;
    s1 ^= s1 << 23;
    s1 ^= s1 >>> 17;
    s1 ^= s2;
    s1 ^= s2 >>> 26;
    _seed[1] = s1;
    return ((_seed[0] + _seed[1]) >>> 0) / 4294967296;
};

// 替换 Math.random
Math.random = _xorshift;

// ============================================================
// 3. 确定性时间
// ============================================================

const _OriginalDate = Date;
globalThis.Date = function(...args) {
    if (args.length === 0) {
        // new Date() 使用区块时间戳
        const ts = (env && env.Timestamp) || 0;
        return new _OriginalDate(ts);
    }
    return new _OriginalDate(...args);
};
globalThis.Date.now = () => (env && env.Timestamp) || 0;

// ============================================================
// 4. AO 消息处理框架
// ============================================================

globalThis.Handlers = {
    _h: {},  // 处理器注册表

    add: (name, fn) => { this._h[name] = fn; },
    remove: (name) => { delete this._h[name]; },

    handle: (m) => {
        // 根据 Action 路由到对应处理器
        const h = this._h[m.Action || m.action] || this._h['default'];
        return h ? h(m) : { error: 'No handler: ' + (m.Action || m.action) };
    }
};

// 消息发送
globalThis.ao = {
    send: (m) => {
        if (m && m.Target) {
            _outbox.push(JSON.parse(JSON.stringify(m)));
        }
    }
};
```

**为什么确定性如此重要**？

```
在去中心化系统中，确定性是核心要求：

┌─────────────────────────────────────────────────────────────┐
│                     场景：两个节点                          │
│                                                             │
│  节点 A                         节点 B                       │
│  ─────────                   ─────────                      │
│  收到交易 T                   收到交易 T                     │
│  执行智能合约                 执行智能合约                   │
│  ─────────                   ─────────                      │
│  结果：状态 S_A               结果：状态 S_B                 │
│                                                             │
│  如果 S_A ≠ S_B  →  分叉！共识失败！                        │
└─────────────────────────────────────────────────────────────┘

非确定性来源（必须消除）：
❌ Math.random()           → 每次运行结果不同
❌ Date.now()              → 不同时间运行结果不同
❌ new Date()              → 同上
❌ 真正的随机数             → 同上

确定性替代方案（我们的做法）：
✅ xorshift128+ PRNG      → 相同种子产生相同序列
✅ env.Timestamp          → 区块时间戳是确定的
✅ 消息哈希作为种子       → 相同消息产生相同序列
```

---

### 3.5 编译配置

**文件**：`Makefile`

**目的**：配置编译参数，生成可在 WASI 环境中运行的 WASM。

```makefile
# ============================================================
// 工具链配置
// ============================================================
WASI_SDK_VERSION = 24.0
WASI_SDK = $(HOME)/wasi-sdk-$(WASI_SDK_VERSION)-x86_64-linux
SYSROOT = $(WASI_SDK)/share/wasi-sysroot
CC = $(WASI_SDK)/bin/clang  # 使用 WASI 版本的 clang

QJS_VERSION = 2024-01-13
QJS = $(HOME)/quickjs-$(QJS_VERSION)

# ============================================================
// 编译器 flags
// ============================================================
CFLAGS = \
    --sysroot=$(SYSROOT) \           # WASI 系统根目录
    --target=wasm32-wasi \            # 编译为 WASM 目标
    -O1 \                             # 优化级别（平衡大小和速度）
    -DCONFIG_VERSION=\"$(QJS_VERSION)\" \
    -D_WASI_EMULATED_SIGNAL \         # 模拟信号处理
    -D_WASI_EMULATED_PROCESS_CLOCKS \ # 模拟进程时钟
    -DCONFIG_BIGNUM \                 # 启用大数支持
    -include wasi_stubs.h \           # 包含 stub 头文件

# ============================================================
// 链接器 flags（关键！）
// ============================================================
LDFLAGS = \
    --sysroot=$(SYSROOT) \
    --target=wasm32-wasi \
    -Wl,-z,stack-size=1048576 \       # 栈大小 1MB
    -Wl,--initial-memory=16777216 \    # 初始内存 16MB
    -Wl,--max-memory=67108864 \        # 最大内存 64MB（沙盒限制）
    -Wl,--export=malloc \              # 导出 malloc（内存分配）
    -Wl,--export=free \                # 导出 free（内存释放）
    -Wl,--export=qjs_init \            # 导出初始化函数
    -Wl,--export=qjs_eval \            # 导出求值函数
    -lwasi-emulated-signal \           # 模拟信号库
    -lwasi-emulated-process-clocks     # 模拟时钟库
```

**关键配置解释**：

| 配置项 | 值 | 原因 |
|--------|-----|------|
| `--target=wasm32-wasi` | - | 指定 WASI 目标平台 |
| `-O1` | 优化级别 | 平衡大小和速度 |
| `--max-memory=67108864` | 64MB | WASM 沙盒限制 |
| `-Wl,--export=qjs_eval` | - | Erlang 需要调用此函数 |
| `-include wasi_stubs.h` | - | 提供缺失的函数声明 |

---

### 3.6 关键：WASM 函数导出机制

**核心问题**：C 函数编译为 WASM 后，外部代码怎么调用它？

#### 3.6.1 什么是函数导出？

在原生 C 程序中，函数默认可以被链接器访问。但在 WASM 中，**默认情况下外部无法调用内部函数**！

```
┌─────────────────────────────────────────────────────────────┐
│  问题：WASM 模块的边界                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────┐                                    │
│  │    WASM 模块        │                                    │
│  │                     │                                    │
│  │  int qjs_eval() {   │  ← 默认：外部看不到这个函数！     │
│  │    ...              │                                    │
│  │  }                  │                                    │
│  │                     │                                    │
│  │  int main() {      │                                    │
│  │    ...              │                                    │
│  │  }                  │                                    │
│  └─────────────────────┘                                    │
│                                                             │
│  必须显式导出，才能被外部调用！                              │
└─────────────────────────────────────────────────────────────┘
```

#### 3.6.2 如何导出函数？

通过链接器选项 `-Wl,--export=函数名`：

```makefile
LDFLAGS = \
    ...
    -Wl,--export=qjs_eval \     ← 导出 qjs_eval 函数
    -Wl,--export=qjs_init \     ← 导出 qjs_init 函数
    -Wl,--export=malloc \       ← 导出内存分配函数
    -Wl,--export=free \         ← 导出内存释放函数
    ...
```

**效果**：编译后，WASM 模块的导出表中会包含这些函数。

```
┌─────────────────────────────────────────────────────────────┐
│  WASM 模块导出表 (Export Table)                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  "qjs_eval"  →  函数指针 (0x1234)    ← Erlang 可以调用！  │
│  "qjs_init"  →  函数指针 (0x1238)    ← Erlang 可以调用！  │
│  "malloc"    →  函数指针 (0x1240)    ← Erlang 可以调用！  │
│  "free"      →  函数指针 (0x1244)    ← Erlang 可以调用！  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 3.6.3 Erlang 如何调用 WASM 函数？

看 `dev_aojs.erl` 中的调用链：

```erlang
%% dev_aojs.erl
eval_js(Instance, Code, _Opts) ->
    %% 步骤 1: 写入 JS 代码到 WASM 内存
    {ok, CodePtr} = hb_beamr_io:write_string(Instance, Code),

    %% 步骤 2: 分配结果缓冲区
    {ok, ResultPtr} = hb_beamr_io:malloc(Instance, ?RESULT_BUF_SIZE),

    %% 步骤 3: 调用 WASM 中的 qjs_eval 函数
    %%           ↓ WASM 实例     ↓ 函数名     ↓ 参数
    Result = hb_beamr:call(Instance, "qjs_eval",
        [CodePtr, CodeLen, ResultPtr, ?RESULT_BUF_SIZE]),
    ...
```

关键函数是 `hb_beamr:call/3`，它是一个 **NIF**（Native Implemented Function）：

```
┌─────────────────────────────────────────────────────────────────┐
│  Erlang 调用 WASM 函数的完整流程                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Erlang 代码                                                 │
│     hb_beamr:call(Instance, "qjs_eval", [...])                  │
│           ↓                                                     │
│  2. hb_beamr NIF (C 语言实现)                                   │
│     - 获取 WASM 实例                                             │
│     - 查找导出表："qjs_eval" → 0x1234                           │
│     - 调用 WASM 函数                                             │
│           ↓                                                     │
│  3. WASM 运行时 (wasmtime/wasmer)                                │
│     - 执行 qjs_eval 代码                                         │
│     - 结果写入 ResultPtr 指向的内存                               │
│           ↓                                                     │
│  4. hb_beamr_io:read()                                           │
│     - 从 WASM 内存读取结果                                        │
│           ↓                                                     │
│  5. 返回给 Erlang                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.6.4 验证导出函数

可以使用 `wasm-objdump` 查看 WASM 模块的导出表：

```bash
# 查看导出表
wasm-objdump -x aojs.wasm | grep Export

# 预期输出：
# Export: qjs_init   func 0
# Export: qjs_eval   func 1
# Export: malloc     func 2
# Export: free       func 3
```

#### 3.6.5 总结：关键配置

| 配置 | 作用 | 为什么需要 |
|------|------|-----------|
| `-Wl,--export=qjs_eval` | 导出 qjs_eval | Erlang 调用 JS 执行 |
| `-Wl,--export=qjs_init` | 导出 qjs_init | 初始化 QuickJS |
| `-Wl,--export=malloc` | 导出 malloc | 内存分配 |
| `-Wl,--export=free` | 导出 free | 内存释放 |

**关键洞察**：**不导出的函数，外部调不到！** 这是一个重要的安全特性——WASM 模块可以隐藏内部实现，只暴露必要的接口。

---

## 四、完整架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        编译阶段                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   QuickJS C 源码              我们的适配层              WASI SDK     │
│   ┌─────────────┐            ┌─────────────┐         ┌──────────┐  │
│   │ quickjs.c   │            │ wasi_stubs.h│          │ clang     │  │
│   │ cutils.c    │            │ ao_runtime.c│          │ wasi-libc │  │
│   │ libbf.c     │     +      │ ao-runtime.js│         │          │  │
│   │ libunicode  │            └─────────────┘         └──────────┘  │
│   └─────────────┘                       ↓                         │
│                         ┌─────────────────────────────┐          │
│                         │   make (编译为 WASM)        │          │
│                         └─────────────────────────────┘          │
│                                     ↓                             │
│                           ┌─────────────────┐                    │
│                           │   aojs.wasm     │  (~1MB)           │
│                           │   (最终产物)     │                    │
│                           └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        运行阶段                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Erlang/OTP                      HyperBEAM              WASM Runtime│
│   ┌─────────────┐                ┌─────────────┐       ┌─────────┐ │
│   │ dev_aojs.erl│ ◀───────────▶ │ hb_beamr.erl│ ◀──▶ │ qjs_eval│ │
│   │ (设备逻辑)   │   IPC 调用     │ (接口封装)   │       │         │ │
│   └─────────────┘                └─────────────┘       │  JS    │ │
│                                                          │ Runtime│ │
│   JavaScript 合约                ┌─────────────┐          │  +     │ │
│   ┌─────────────┐                │ dev_stack   │          │ State  │ │
│   │ counter.js  │               │ (设备栈)    │          │        │ │
│   │ token.js    │               └─────────────┘          └─────────┘ │
│   └─────────────┘                                                   │
│                                                                     │
│   消息流程：                                                         │
│   1. Erlang 接收 HTTP 请求                                           │
│   2. 加载 JS 合约到 WASM                                             │
│   3. WASM 执行 JS 代码（确定性）                                      │
│   4. 结果返回给 Erlang                                               │
│   5. 状态通过快照持久化                                              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 五、运行流程详解

### 5.1 设备栈初始化

```
POST /~aojs@1.0/init

┌─────────────────────────────────────────────────────────────────┐
│  消息流：init                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  HTTP 请求                                                       │
│      ↓                                                          │
│  dev_stack @1.0（设备栈）                                        │
│      ├─ dev_wasm @1.0                                           │
│      │   ├─ 加载 aojs.wasm 到 WASM 实例                         │
│      │   ├─ 调用 qjs_init() 初始化 QuickJS                      │
│      │   └─ 保存实例到 priv["instance"]                        │
│      │                                                          │
│      └─ dev_aojs @1.0（我们的设备）                              │
│          ├─ 检查 priv["aojs/initialized"]                        │
│          ├─ 注入 ao-runtime.js（Handlers、ao.send）             │
│          └─ 设置 priv["aojs/ready"] = true                      │
│                                                                 │
│  返回：包含 WASM 实例引用的消息 M1                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 消息处理

```
POST /~aojs@1.0/compute
Body: { "Action": "Increment", "From": "user123" }

┌─────────────────────────────────────────────────────────────────┐
│  消息流：compute                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 解析消息，构建 JS 对象                                         │
│     {                                                              │
│       Id: "...",                                                  │
│       From: "user123",                                            │
│       Action: "Increment",                                        │
│       Tags: {...},                                                │
│       Block-Height: 12345                                        │
│     }                                                             │
│                                                                 │
│  2. 构建执行代码                                                  │
│     _clearOutbox();                                              │
│     globalThis.msg = {...};  // 消息 JSON                        │
│     globalThis.env = {...};  // 环境（Process ID 等）            │
│     JSON.stringify(Handlers.handle(msg));                         │
│                                                                 │
│  3. 调用 WASM 执行                                                 │
│     hb_beamr:call(instance, "qjs_eval", [codePtr, ...])          │
│                                                                 │
│  4. 获取结果和 outbox                                              │
│     results = JSON.parse(result);                                 │
│     outbox = JSON.parse(_getOutbox());                            │
│                                                                 │
│  5. 返回结果                                                       │
│     {                                                              │
│       results: { data: {...}, outbox: [...] },                    │
│       ...                                                         │
│     }                                                             │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 状态持久化

```
┌─────────────────────────────────────────────────────────────────┐
│  快照流程（snapshot/normalize）                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  snapshot (保存状态)：                                           │
│  ──────────────────                                            │
│  1. 调用 hb_beamr:serialize(WASM实例)                          │
│     - 读取 WASM 内存映像                                         │
│     - 返回二进制快照数据                                         │
│                                                                 │
│  2. 快照存储在消息中                                              │
│     M2 = M1#{ <<"snapshot">> => BinarySnapshot }               │
│                                                                 │
│  3. cache-control: store 标记持久化                             │
│     - 快照写入缓存                                               │
│                                                                 │
│                                                                 │
│  normalize (恢复状态)：                                         │
│  ──────────────────                                            │
│  1. 从消息中获取快照                                              │
│     Snapshot = M1[<<"snapshot">>]                              │
│                                                                 │
│  2. 调用 hb_beamr:deserialize(WASM实例, Snapshot)                │
│     - 写入 WASM 内存映像                                         │
│     - QuickJS 状态完全恢复                                       │
│                                                                 │
│  3. 清除快照标记                                                 │
│     M2 = maps:remove(<<"snapshot">>, M1)                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 六、JavaScript 模块示例

### 6.1 Counter 模块

**文件**：`aojs/aojs-modules/counter.js`

```javascript
// 初始化状态（首次加载时）
state.count = state.count || 0;

// 注册处理器
Handlers.add('Increment', () => {
    state.count += 1;           // 修改状态
    return { count: state.count };  // 返回结果
});

Handlers.add('Decrement', () => {
    state.count -= 1;
    return { count: state.count };
});

Handlers.add('GetCount', () => ({
    count: state.count
}));

Handlers.add('Reset', () => {
    state.count = 0;
    return { count: 0 };
});
```

**执行流程**：

```
1. POST /~aojs@1.0/compute (Action=Increment)
   ↓
2. dev_aojs 加载 counter.js
   ↓
3. 调用 Handlers.handle({Action: "Increment"})
   ↓
4. QuickJS 执行：
   - state.count 从 0 变为 1
   - 返回 {count: 1}
   ↓
5. dev_aojs 调用 snapshot 保存状态
   ↓
6. 下次请求时 normalize 恢复状态
   ↓
7. state.count 仍然是 1
```

### 6.2 Token 模块

**文件**：`aojs/aojs-modules/token.js`

```javascript
// 状态初始化
state.balances = state.balances || {};
state.name = state.name || 'TestToken';
state.ticker = state.ticker || 'TST';
state.totalSupply = state.totalSupply || 0;

// 处理器：铸造代币
Handlers.add('Mint', (msg) => {
    const qty = parseInt(msg.Tags.Quantity || '0');
    const recipient = msg.From;

    // 更新状态
    state.balances[recipient] = (state.balances[recipient] || 0) + qty;
    state.totalSupply += qty;

    return { success: true, balance: state.balances[recipient] };
});

// 处理器：转账
Handlers.add('Transfer', (msg) => {
    const from = msg.From;
    const to = msg.Tags.Recipient;
    const qty = parseInt(msg.Tags.Quantity || '0');

    // 余额检查
    const fromBalance = state.balances[from] || 0;
    if (fromBalance < qty) {
        return { error: 'Insufficient balance' };
    }

    // 更新状态
    state.balances[from] = fromBalance - qty;
    state.balances[to] = (state.balances[to] || 0) + qty;

    // 发送通知消息
    ao.send({
        Target: to,
        Action: 'Credit-Notice',
        Quantity: String(qty),
        Sender: from
    });

    return { success: true };
});
```

---

## 七、总结

### 7.1 适配工作清单

| 步骤 | 工作内容 | 文件 | 目的 |
|------|----------|------|------|
| 1 | 下载 QuickJS 源码 | - | 获取 C 源码 |
| 2 | 安装 WASI SDK | - | 获取 WASM 编译器 |
| 3 | 创建 stub 头文件 | `wasi_stubs.h` | 提供缺失函数 |
| 4 | 创建 C 接口层 | `ao_runtime.c` | Erlang-WASM 桥接 |
| 5 | 创建确定性运行时 | `ao-runtime.js` | 保证确定性 |
| 6 | 配置 Makefile | `Makefile` | 编译参数 |
| 7 | 编译 WASM | `make` | 生成最终产物 |
| 8 | 编写 JS 模块 | `counter.js`, `token.js` | 测试合约 |

### 7.2 核心设计原则

| 原则 | 实现 | 原因 |
|------|------|------|
| **确定性** | PRNG + 区块时间戳 | 去中心化共识要求 |
| **沙盒安全** | 内存/栈限制 | 防止资源耗尽 |
| **接口清晰** | qjs_init/qjs_eval | 简化 Erlang 调用 |
| **状态持久化** | serialize/deserialize | 支持进程恢复 |

### 7.3 文件清单

```
aojs/
├── aojs.wasm              ← 最终产物（约 1MB）
└── aojs-modules/
    ├── counter.js         ← 示例：计数器合约
    └── token.js           ← 示例：代币合约

~/quickjs-2024-01-13/     ← QuickJS 源码
├── quickjs.c
├── cutils.c
├── libbf.c
├── libunicode.c
└── ...

~/wasi-sdk-24.0/          ← WASI SDK
└── bin/
    └── clang             ← WASM 编译器
```

---

## 八、附加分析：env 注入机制验证

> **分析日期**：2026-02-07
> **分析目的**：验证 `ao-runtime.js` 中 `env.Timestamp` 的注入机制

### 8.1 问题提出

在分析 `ao-runtime.js` 时，发现代码使用了 `env.Timestamp`：

```javascript
globalThis.Date = function(...args) {
    if (args.length === 0) {
        const ts = (env && env.Timestamp) || 0;  ← env 从哪来？
        return new _OriginalDate(ts);
    }
    return new _OriginalDate(...args);
};
```

**关键问题**：`env` 对象是如何被注入到 JavaScript 运行时中的？

### 8.2 代码验证

**验证过程**：

1. 搜索 `ao-runtime.js` 中的 `env` 用法
2. 检查 `dev_aojs.erl` 中的注入逻辑
3. 对比 `build_env_json` 函数实际输出

**代码证据**（src/dev_aojs.erl:145-149）：

```erlang
%% JavaScript 代码通过字符串拼接注入
JsCode = iolist_to_binary([
    <<"_clearOutbox();globalThis.msg=">>, MsgJson,
    <<";globalThis.env=">>, EnvJson,  ← 直接拼接 JSON
    <<";JSON.stringify(Handlers.handle(msg))">>
]),
```

**build_env_json 函数**（src/dev_aojs.erl:176-181）：

```erlang
build_env_json(Process, Opts) ->
    ProcId = hb_maps:get(<<"id">>, Process, <<>>, Opts),
    EnvMap = #{
        <<"Process">> => #{<<"Id">> => ProcId}  ← 只有 Process.Id
    },
    hb_json:encode(EnvMap).
```

### 8.3 关键发现

| 检查项 | 预期 | 实际 | 状态 |
|--------|------|------|------|
| `env` 注入方式 | ✅ JS 代码拼接 | ✅ 已验证 | 一致 |
| `env.Process.Id` | ✅ 存在 | ✅ 存在 | 一致 |
| `env.Timestamp` | ❌ 预期存在 | ❌ **不存在** | **不一致** |

**结论**：`build_env_json` 函数**没有**包含 `Timestamp` 字段！

### 8.4 问题分析

**代码现状**：

```
ao-runtime.js 期望的 env：
{
    "Process": { "Id": "..." },
    "Timestamp": 1234567890    ← 期望有这个字段
}

dev_aojs.erl 实际生成的 env：
{
    "Process": { "Id": "..." }  ← 缺少 Timestamp！
}
```

**可能的原因**：

1. **功能未完成**：`Timestamp` 功能还在开发中
2. **设计变更**：决定不使用 `Timestamp`，但未更新文档
3. **测试环境问题**：测试中没有使用 `env.Timestamp`

### 8.5 对确定性的影响

**当前状态**：

| 时间来源 | 状态 | 影响 |
|----------|------|------|
| `Date.now()` | 指向 `env.Timestamp` | ⚠️ 但 `env.Timestamp` 不存在 |
| 降级值 | `0` | ✅ 有默认值 |

**实际行为**：

```javascript
// 当前实际执行（因为 env.Timestamp 不存在）
globalThis.Date.now = () => (env && env.Timestamp) || 0;
// 始终返回 0！
```

**这可能是一个问题**：合约可能期望获取区块时间戳，但当前始终返回 0。

### 8.6 修复建议

如果需要启用 `env.Timestamp` 功能，`build_env_json` 应该修改为：

```erlang
build_env_json(Process, Opts) ->
    ProcId = hb_maps:get(<<"id">>, Process, <<>>, Opts),
    Timestamp = hb_maps:get(<<"timestamp">>, Process, 0, Opts),
    EnvMap = #{
        <<"Process">> => #{<<"Id">> => ProcId},
        <<"Timestamp">> => Timestamp
    },
    hb_json:encode(EnvMap).
```

### 8.7 验证结论

| 验证项 | 结论 |
|--------|------|
| `env` 注入机制 | ✅ 通过 JS 代码字符串拼接验证 |
| `env.Process.Id` | ✅ 正确工作 |
| `env.Timestamp` | ❌ 未实现，与文档不一致 |
| 确定性影响 | ⚠️ `Date.now()` 始终返回 0 |

### 8.8 总结

**本次分析发现的问题**：

| 问题 | 严重程度 | 建议 |
|------|----------|------|
| `env.Timestamp` 未实现 | 中 | 补充实现或更新文档 |
| 文档与代码不一致 | 低 | 同步更新 `ao-runtime.js` 文档 |

**后续行动**（可选）：

- [ ] 确认是否需要 `Timestamp` 功能
- [ ] 如需要，修改 `build_env_json` 添加 `Timestamp`
- [ ] 如不需要，从 `ao-runtime.js` 移除 `env.Timestamp` 相关代码

---

**文档版本**：1.1
**更新说明**：新增第八章"附加分析"，验证 env 注入机制
**分析日期**：2026-02-07
**作者**：AI Assistant
