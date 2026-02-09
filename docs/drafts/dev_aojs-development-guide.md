# AO JavaScript 设备开发完整教程：dev_aojs 从入门到精通

> **适用读者**：AO 设备开发入门者
> **核心设备**：`dev_aojs`（JavaScript 智能合约运行时设备）
> **最后更新**：2026-02-09
> **验证依据**：HyperBEAM 核心代码库源码 + 官方参考文档

---

## 目录

1. [全景视图：系统架构概览](#一全景视图系统架构概览)
2. [核心概念体系](#二核心概念体系)
3. [开发环境准备](#三开发环境准备)
4. [核心功能深度解析](#四核心功能深度解析)
5. [关键技术实现原理](#五关键技术实现原理)
6. [状态持久化机制](#六状态持久化机制)
7. [调试与测试](#七调试与测试)
8. [部署与运维](#八部署与运维)
9. [最佳实践与常见问题](#九最佳实践与常见问题)
10. [总结与进阶路径](#十总结与进阶路径)

---

## 一、全景视图：系统架构概览

### 1.1 dev_aojs 在 AO 生态系统中的定位

在深入技术细节之前，我们需要先理解 `dev_aojs` 设备在整个 AO/HyperBEAM 架构中的位置和作用。这将帮助您建立正确的「心智模型」，避免在后续开发中迷失于细节。

**整体架构层次**：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AO 进程层                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  process@1.0（进程管理）  ←→  scheduler@1.0（调度器）            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    ↓                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      设备栈层（stack@1.0）                         │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │   │
│  │  │ dedup   │→ │  cron   │→ │ wasm-64 │→ │  aojs   │           │   │
│  │  │  @1.0   │  │  @1.0   │  │  @1.0   │  │  @1.0   │           │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    ↓                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       运行时层                                   │   │
│  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │              QuickJS（JavaScript 引擎）                  │   │   │
│  │  │                    运行在 WASM 中                        │   │   │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

**关键理解**：

| 层级 | 组件 | 作用 | 与 dev_aojs 的关系 |
|------|------|------|-------------------|
| 进程层 | `process@1.0`、`scheduler@1.0` | 进程生命周期管理、消息调度 | 使用设备栈来执行业务逻辑 |
| 设备栈层 | `stack@1.0` | 按顺序调用多个设备 | 协调 dev_aojs 与其他设备的协作 |
| 设备层 | `dev_aojs`、`dev_wasm`、`dev_lua` | 执行具体智能合约代码 | dev_aojs 依赖 dev_wasm 管理 WASM 实例 |
| WASM 层 | QuickJS | JavaScript 运行时 | dev_aojs 通过 hb_beamr 调用 QuickJS |

### 1.2 dev_aojs 的核心职责

`dev_aojs` 是 AO 系统中专门用于执行 JavaScript 智能合约的设备。它的核心职责可以概括为以下四个方面：

**职责一：运行时初始化（`init/3`）**

初始化阶段确保 QuickJS 引擎已加载并就绪，同时注入 AO 运行时环境（Handlers、ao.send 等），并验证 WASM 实例的有效性。这个阶段是后续所有操作的基础，如果初始化失败，设备将无法正常工作。

**职责二：消息处理（`compute/3`）**

消息处理是 dev_aojs 的核心功能。当消息到达时，设备会接收并解析传入的 AO 消息，将消息转换为 JavaScript 可理解的格式，调用用户定义的处理器函数，最后收集并返回处理结果。这个过程实现了智能合约的业务逻辑。

**职责三：状态持久化（`snapshot/3`、`normalize/3`）**

为了支持进程的持久化运行，dev_aojs 提供了状态快照功能。它将 QuickJS 运行时状态保存为二进制快照，并在进程重启时从快照恢复运行时状态。这是实现有状态智能合约的关键机制。

**职责四：输出标准化**

设备统一返回标准格式，方便上层组件处理结果。同时支持 outbox 机制，允许合约发送新消息到其他进程，实现进程间通信。

### 1.3 设备栈协作架构

在完整的 AO 进程中，`dev_aojs` 通常不会单独使用，而是与其他设备组成设备栈（Device Stack）来提供完整的功能。以下是一个典型的设备栈配置：

**典型 AO JS 进程设备栈配置**：

```
["dedup@1.0", "cron@1.0", "wasm-64@1.0", "aojs@1.0", "multipass@1.0"]
```

**各设备职责说明**：

| 设备 | 职责 | 为何在此位置 |
|------|------|------------|
| `dedup@1.0` | 消息去重 | 第一关，确保相同消息只处理一次 |
| `cron@1.0` | 定时调度 | 处理定时任务逻辑 |
| `wasm-64@1.0` | WASM 实例管理 | 为 aojs 提供底层 WASM 支持 |
| `aojs@1.0` | JavaScript 执行 | **我们的设备**，执行业务逻辑 |
| `multipass@1.0` | 多通道输出 | 处理多个待发送消息 |

**执行顺序逻辑**：数据流按照设备栈顺序流动，每个设备处理后将结果传递给下一个设备。`dev_aojs` 作为核心业务逻辑设备，通常位于栈的中后部。

---

## 二、核心概念体系

在开始开发之前，必须建立对以下核心概念的正确理解。这些概念是理解 dev_aojs 工作原理的基础。

### 2.1 设备（Device）的本质

在 AO 系统中，「设备」是一个核心抽象概念。理解设备的本质对于正确开发和使用 dev_aojs 至关重要。

**设备的核心特征**：

| 特征 | 说明 | 示例 |
|------|------|------|
| 模块化 | 每个设备是一个独立的 Erlang 模块 | `dev_aojs.erl` |
| 标准化接口 | 所有设备遵循相同的函数签名 | `(M1, M2, Opts) → {ok, Result}` |
| 可组合 | 多个设备可以组成设备栈 | `["dedup@1.0", "aojs@1.0"]` |
| 可替换 | 可以用其他设备替换相同功能的设备 | 用 `lua@5.3a` 替换 `aojs@1.0` |

**标准函数签名（常见于执行设备）**：

```erlang
-export([info/3, init/3, compute/3, snapshot/3, normalize/3]).
```

> **⚠️ 重要说明**：AO 设备**没有任何必须实现的函数**！这是**功能导向的弱约束设计**：
>
> - 系统通过 `hb_ao_device:find_exported_function/5` **动态查找**设备是否实现了某个函数
> - 如果设备没有某函数，系统会**静默跳过**或使用默认设备处理
> - `info` 函数是**特殊**的：如果存在，总是会被识别
> - 设备通过 `exports` 字段**声明**自己支持哪些函数（可选）
>
> **不同设备的常见函数**：
> - **执行设备**（如 `dev_aojs`）：`compute/3` 是核心
> - **Codec 设备**（如 `dev_codec_json`）：`to/3, from/3`
> - **Cron 设备**（如 `dev_cron`）：`once/3, every/3`
> - **Cache 设备**（如 `dev_cache`）：`read/3, write/3`
>
> **关键理解**：设备接口是**按需实现**的，不需要实现所有函数。

### 2.2 消息结构（M1 与 M2）

AO 系统中的所有交互都通过消息完成。理解 M1 和 M2 的区别和作用是掌握设备开发的关键。

**定义**：

- **M1 = 当前状态消息（Message 1）**
  - 代表进程/实体的当前状态
  - 包含私有数据（priv）和公共数据
  - 类似 HTTP 请求中的 request body + session state

- **M2 = 传入消息（Message 2）**
  - 代表新的请求/操作
  - 包含操作类型（path）、参数（body）、标签（tags）
  - 类似 HTTP 请求中的 method + path + body

**M1 与 M2 的关键区别**：

| 属性 | M1（状态消息） | M2（请求消息） |
|------|---------------|---------------|
| 本质 | 实体当前状态 | 新到达的请求 |
| 生命周期 | 持续存在，可累积变化 | 一次性使用 |
| 数据类型 | 混合（状态、配置、priv） | 操作相关数据 |
| 写入缓存 | 部分数据会写入 | 不会直接写入 |
| 传递给 | 设备的当前状态 | 触发新操作 |

**代码示例**（dev_aojs.erl:432-441）：

```erlang
execute_handler(M1, M2, Opts) ->
    Prefix = dev_stack:prefix(M1, M2, Opts),
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),

    %% M1 提供进程上下文（Process）
    Message = hb_maps:get(<<"body">>, M2, #{}, Opts),
    Process = hb_maps:get(<<"process">>, M1, #{}, Opts),

    %% M2 提供操作信息（Message）
    MsgJson = build_msg_json(Message, M2, Opts),
    ...
```

### 2.3 设备栈前缀机制

设备栈使用前缀（Prefix）机制来隔离不同设备的数据。这是避免数据冲突的关键设计。

**问题**：如果多个设备都使用相同的键名（如「state」、「instance」），会发生什么？

**解决**：使用前缀隔离每个设备的命名空间

**示例**：

```erlang
prefixed_key(Prefix, Key) ->
    case Prefix of
        <<>> -> Key;            %% 无前缀时直接使用键名
        _ -> <<Prefix/binary, "/", Key/binary>>  %% 有前缀时组合
    end.

%% 示例：
prefixed_key(<<"proc-123/slot-0/aojs@1.0">>, <<"initialized">>)
    -> <<"proc-123/slot-0/aojs@1.0/initialized">>
```

**前缀的来源**：前缀由 `dev_stack:prefix/3` 函数根据设备栈配置自动生成，确保每个设备实例有独立的命名空间。

### 2.4 WASM 实例与 QuickJS 引擎

`dev_aojs` 的核心是 QuickJS JavaScript 引擎，它运行在 WebAssembly 环境中。理解这一层的架构对于调试和性能优化至关重要。

**通信架构**：

```
Erlang/OTP → hb_beamr (WAMR 封装) → WAMR → QuickJS
```

**导出的 C 函数（WASM 导出表）**：

| 函数 | 作用 |
|------|------|
| `qjs_init()` | 初始化 QuickJS 运行时 |
| `qjs_eval()` | 执行 JavaScript 代码 |
| `malloc()` | 内存分配 |
| `free()` | 内存释放 |

**内存布局（WASM 线性内存））**：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `--initial-memory` | 16777216 | 16MB 初始内存 |
| `--max-memory` | 67108864 | 64MB 最大内存 |
| `-Wl,-z,stack-size` | 1048576 | 1MB 栈大小 |

### 2.5 状态持久化的两种模式

AO 系统支持两种主要的状态持久化模式。理解它们的区别对于正确设计有状态设备至关重要。

**模式一：缓存模式（dev_counter 等简单设备）**

缓存模式的核心思想是保存状态数据映射，而非保存运行时内存快照。状态数据以 Erlang 映射的形式存储，例如 `#{ <<"counter">> => 5 }`。这种模式的优点包括：状态数据体积小易于管理、可以独立查看和调试状态、支持增量更新。但它不适合复杂运行时状态，因为需要显式编写序列化/反序列化逻辑。

**模式二：WASM 序列化模式（dev_aojs 等运行时设备）**

序列化模式保存整个 WASM 运行时内存快照。快照格式是二进制 blob，包含 QuickJS 运行时的所有状态信息。这种模式的优点包括：保存完整状态包括 JS 对象和闭包、无需修改设备代码即可保存任意状态、保证确定性。但缺点也很明显：快照体积大（通常是几 MB）、无法直接查看状态内容、序列化有一定性能开销。

---

## 三、开发环境准备

### 3.1 必需的系统依赖

在开始开发 dev_aojs 之前，需要确保开发环境满足以下要求：

**基础系统依赖**：

| 依赖项 | 最低版本 | 说明 |
|--------|----------|------|
| Erlang/OTP | 26.0+ | BEAM 虚拟机，核心运行时 |
| rebar3 | 3.22.0+ | Erlang 构建工具和依赖管理 |
| Git | 2.0+ | 版本控制 |
| make | 3.0+ | 构建系统（QuickJS 编译需要） |
| CMake | 3.0+ | WAMR 编译需要 |

**QuickJS/WASM 编译依赖**：

| 依赖项 | 最低版本 | 说明 |
|--------|----------|------|
| wasi-sdk | 24.0 | WASI 编译器工具链 |
| clang | (wasi-sdk 内置) | C 编译器（wasi 目标） |
| QuickJS | 2024-01-13 | JavaScript 引擎源码 |

### 3.2 HyperBEAM 项目结构

理解 HyperBEAM 的项目结构有助于定位相关代码和配置文件：

```
HyperBEAM/
├── src/                              ← Erlang/OTP 源代码
│   ├── dev_aojs.erl                 ← **我们的主角设备**
│   ├── dev_wasm.erl                 ← WASM 设备（依赖）
│   ├── dev_stack.erl                ← 设备栈管理
│   ├── hb_beamr.erl                 ← WAMR 封装
│   └── ...
├── aojs/                            ← JavaScript 相关文件
│   ├── aojs.wasm                   ← 编译后的 QuickJS WASM 模块
│   ├── ao-runtime.js                ← AO JavaScript 运行时
│   └── aojs-modules/                ← JavaScript 智能合约模块
│       ├── counter.js               ← 计数器示例
│       └── token.js                 ← 代币示例
└── docs/drafts/                     ← 设计文档草稿
    ├── ao-device-state-persistence-verification.md
    ├── quickjs-wasm-compilation-guide.md
    ├── device-collaboration.md
    └── device-configuration-persistence.md
```

**对于 dev_aojs 开发者的重点关注区域**：

- `src/dev_aojs.erl` ← 源代码（主要编辑对象）
- `aojs/ao-runtime.js` ← JavaScript 运行时（可能需要修改）
- `aojs/aojs-modules/` ← 测试合约（用于验证）

### 3.3 编译与测试环境验证

在开始开发之前，需要验证开发环境已正确配置：

```bash
# 1. 进入 HyperBEAM 项目目录
cd /Users/yangjiefeng/Documents/permaweb/HyperBEAM

# 2. 编译 Erlang 代码
make compile

# 3. 运行 dev_aojs 相关测试
rebar3 eunit --module=dev_aojs
```

**预期测试输出**：

```
===> Verifying dependencies...
===> Compiling dev_aojs
===> Running EUnit tests for dev_aojs:
info_test (info_test/0)...[0.003s] ok
aojs_wasm_init_test_...
    aojs_wasm_init... ok
js_basic_eval_test_...
    js_basic_eval... ok
js_counter_module_test_...
    js_counter_module... ok
js_token_module_test_...
    js_token_module... ok

All tests passed.
```

---

## 四、核心功能深度解析

### 4.1 信息函数：`info/3`

`info/3` 是 AO 设备用于向系统报告能力的**可选**函数。

> **特殊规则**：`info` 函数是设备接口中**唯一特殊**的——如果存在，总是会被系统识别为有效导出。

**函数签名**：

```erlang
info(_M1, _M2, _Opts) -> {ok, InfoMap}
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| M1 | 消息 | 当前状态消息（此函数未使用） |
| M2 | 消息 | 传入消息（此函数未使用） |
| Opts | 映射 | 选项参数（此函数未使用） |
| 返回 | {ok, 映射} | 设备信息映射 |

**返回值结构**（dev_aojs.erl:84-97）：

```erlang
{ok, #{
    <<"name">> => <<"aojs@1.0">>,
    <<"description">> => <<"JavaScript Smart Contract Runtime">>,
    <<"exports">> => [<<"init">>, <<"compute">>, <<"snapshot">>, <<"normalize">>]
}}
```

**开发者须知**：

- info 函数通常不接受任何参数，所有信息都是静态的
- exports 列表决定了可以通过什么操作调用该设备
- 系统使用 info 函数来验证设备能力

### 4.2 初始化函数：`init/3`

`init/3` 负责初始化设备的运行时环境。对于 `dev_aojs`，这意味着确保 QuickJS 引擎已准备好执行 JavaScript 代码。

**函数签名**：

```erlang
init(M1, M2, Opts) -> {ok, M1'} | {error, Reason}
```

**职责**：

1. 检查设备是否已初始化（幂等性保证）
2. 验证 WASM 实例是否已创建（下层设备负责）
3. 标记设备为「就绪」状态

**注意**：实际 WASM 实例的创建由 dev_wasm 设备完成，dev_aojs 只负责检查和标记就绪状态。

**核心代码实现**（dev_aojs.erl:121-213）：

```erlang
init(M1, _M2, Opts) ->
    Prefix = dev_stack:prefix(M1, #{}, Opts),
    case hb_private:get(prefixed_key(Prefix, <<"initialized">>), M1, not_found, Opts) of
        true ->
            {ok, M1};  %% 幂等性：已初始化，直接返回
        _ ->
            do_init(M1, Prefix, Opts)  %% 执行初始化
    end.

do_init(M1, Prefix, Opts) ->
    Instance = hb_private:get(
        prefixed_key(Prefix, <<"instance">>),
        M1, not_found, Opts),
    case Instance of
        not_found ->
            {error, #{<<"error">> => <<"wasm_instance_not_found">>}};
        _ ->
            {ok, hb_private:set(M1,
                prefixed_key(Prefix, <<"ready">>), true, Opts)}
    end.
```

**开发者要点**：

- **幂等性保证**：多次调用 init 应该产生相同结果
- **依赖检查**：确保下层设备（dev_wasm）已创建 WASM 实例
- **状态隔离**：使用前缀机制避免与其他设备栈实例冲突
- **错误处理**：WASM 实例不存在时返回明确的错误信息

### 4.3 JavaScript 模块加载：`load_js_module/2`

`load_js_module/2` 负责将用户提供的 JavaScript 合约代码加载到 QuickJS 运行时中。

**函数签名**：

```erlang
load_js_module(M1, Opts) -> {ok, M1'} | {error, Reason}
```

**职责**：

1. 检查是否需要注入 AO 运行时（Handlers、ao.send 等）
2. 查找用户提供的 JavaScript 模块源代码
3. 执行模块代码，注册消息处理器

**AO 运行时注入**（dev_aojs.erl:323-327）：

`inject_ao_runtime/2` 读取 `ao-runtime.js` 并执行注入，提供以下全局对象：

- Handlers 对象 ← 用于注册消息处理器
- ao.send() ← 用于发送消息到其他进程
- state 对象 ← 用于存储合约状态
- Math.random ← 确定性 PRNG（xorshift128+）
- Date.now ← 固定返回 0（当前未实现区块时间戳注入）

**模块源查找**（dev_aojs.erl:358-394）：

```erlang
find_module_source(M1, Opts) ->
    case hb_maps:get(<<"aojs-module">>, M1, not_found, Opts) of
        not_found ->
            case hb_maps:get(<<"module-id">>, M1, not_found, Opts) of
                not_found -> not_found;
                ModuleId ->
                    Path = <<"aojs/aojs-modules/", ModuleId/binary, ".js">>,
                    case file:read_file(Path) of
                        {ok, Content} -> Content;
                        _ -> not_found
                    end
            end;
        Source -> Source
    end.
```

**两种模块提供方式**：

1. **内联**：消息中直接包含 JS 代码
   ```erlang
   #{<<"aojs-module">> => <<"Handlers.add('Inc', ...)">>}
   ```
2. **文件引用**：指定模块 ID，从文件加载
   ```erlang
   #{<<"module-id">> => <<"counter">>}
   ```

### 4.4 消息处理核心：`compute/3`

`compute/3` 是 `dev_aojs` 的核心函数，负责执行 JavaScript 智能合约处理器并返回结果。

**函数签名**：

```erlang
compute(M1, M2, Opts) -> {ok, M3} | {error, Reason}
```

**职责**：

1. 确保 JavaScript 模块已加载
2. 构建消息和环境的 JSON 对象
3. 调用 JavaScript 处理器函数
4. 解析结果和 outbox
5. 返回标准化的结果格式

**消息 JSON 构建**（dev_aojs.erl:499-519）：

从 AO 消息中提取字段并转换为 JSON：

| AO 消息字段 | → | JS 对象字段 |
|------------|---|------------|
| `<<"id">>` | → | Id |
| `<<"from-process">>` | → | From |
| `<<"action">>` | → | Action |
| `<<"data">>` | → | Data |
| 其他字段 | → | Tags（除保留字段外） |
| `<<"block-height">>` | → | Block-Height |

**JavaScript 执行代码**（dev_aojs.erl:468-472）：

```erlang
JsCode = iolist_to_binary([
    <<"_clearOutbox();">>,              %% 清空 outbox
    <<"globalThis.msg=">>, MsgJson,      %% 注入消息
    <<";globalThis.env=">>, EnvJson,     %% 注入环境
    <<";JSON.stringify(Handlers.handle(msg))">>  %% 调用处理器
]).
```

**执行流程**：

1. `_clearOutbox()` ← 清空上次的 outbox
2. `globalThis.msg = {...}` ← 注入消息对象
3. `globalThis.env = {...}` ← 注入环境信息
4. `Handlers.handle(msg)` ← 调用处理器
5. `JSON.stringify(...)` ← 序列化结果

**返回结果格式**：

```json
{
    "results": {
        "data": {...},    ← 处理器返回值
        "outbox": [...]   ← 待发送消息列表
    }
}
```

### 4.5 状态快照：`snapshot/3` 和 `normalize/3`

状态持久化是 `dev_aojs` 的关键特性之一。通过 `snapshot/3` 和 `normalize/3` 函数，系统可以在进程重启后恢复 JavaScript 运行时的状态。

**snapshot/3 函数**（dev_aojs.erl:781-800）：

```erlang
snapshot(M1, _M2, Opts) ->
    Prefix = dev_stack:prefix(M1, #{}, Opts),
    Instance = hb_private:get(
        prefixed_key(Prefix, <<"instance">>),
        M1, not_found, Opts),
    case Instance of
        not_found ->
            {error, <<"no_wasm_instance">>};
        _ ->
            case hb_beamr:serialize(Instance) of
                {ok, Snapshot} ->
                    {ok, M1#{<<"snapshot">> => Snapshot}};
                {error, E} ->
                    {error, E}
            end
    end.
```

**职责**：将 QuickJS 运行时的当前状态保存为二进制快照

**normalize/3 函数**（dev_aojs.erl:819-837）：

```erlang
normalize(M1, _M2, Opts) ->
    case hb_maps:get(<<"snapshot">>, M1, not_found, Opts) of
        not_found ->
            {ok, M1};  %% 无快照，新进程
        Snapshot ->
            Prefix = dev_stack:prefix(M1, #{}, Opts),
            Instance = hb_private:get(
                prefixed_key(Prefix, <<"instance">>),
                M1, not_found, Opts),
            case hb_beamr:deserialize(Instance, Snapshot) of
                ok ->
                    {ok, maps:remove(<<"snapshot">>, M1)};
                {error, E} ->
                    {error, E}
            end
    end.
```

**职责**：从快照恢复 QuickJS 运行时的状态

**开发者要点**：

- snapshot 和 normalize 由进程调度器自动调用
- 不需要也不应该手动调用
- 只需要确保设备实现了这两个 API
- 调度器根据配置（`process_snapshot_slots`、`process_snapshot_time`）自动决定何时调用

**快照触发条件**：

| 触发类型 | 条件 | 配置项 |
|----------|------|--------|
| 槽位触发 | `Slot rem process_snapshot_slots == 0` | `process_snapshot_slots` |
| 时间触发 | 距离上次快照超过指定秒数 | `process_snapshot_time` |

---

## 五、关键技术实现原理

### 5.1 Erlang 与 WASM 的通信机制

`dev_aojs` 通过 `hb_beamr` 模块与 WASM 实例进行通信。这种通信涉及内存读写和函数调用两个核心操作。

**eval_js/3 函数详解**（dev_aojs.erl:621-699）：

这是 Erlang 与 WASM 通信的核心函数，流程如下：

```erlang
eval_js(Instance, Code, _Opts) ->
    %% 步骤 1: 写入 JavaScript 代码到 WASM 内存
    {ok, CodePtr} = hb_beamr_io:write_string(Instance, Code),
    CodeLen = byte_size(Code),

    %% 步骤 2: 分配结果缓冲区
    {ok, ResultPtr} = hb_beamr_io:malloc(Instance, ?RESULT_BUF_SIZE),

    %% 步骤 3: 调用 WASM 中的 qjs_eval 函数
    Result = hb_beamr:call(Instance, "qjs_eval",
        [CodePtr, CodeLen, ResultPtr, ?RESULT_BUF_SIZE]),

    %% 步骤 4: 处理执行结果
    EvalResult = case Result of
        {ok, [Length]} when Length >= 0 ->
            {ok, ResultBin} = hb_beamr_io:read(Instance, ResultPtr, max(1, Length)),
            {ok, ResultBin};
        {ok, [Length]} when Length < 0 ->
            {ok, ErrorBin} = hb_beamr_io:read_string(Instance, ResultPtr),
            {error, ErrorBin};
        {error, E} ->
            {error, E}
    end,

    %% 步骤 5: 释放内存
    hb_beamr_io:free(Instance, CodePtr),
    hb_beamr_io:free(Instance, ResultPtr),

    EvalResult.
```

**结果格式约定**：

| 返回值 | 含义 |
|--------|------|
| `{ok, [Length]}` 其中 Length >= 0 | 成功，结果长度为 Length |
| `{ok, [Length]}` 其中 Length < 0 | 错误，|Length| 是错误信息长度 |
| `{error, E}` | 调用失败 |

### 5.2 确定性运行时的实现

AO 系统要求所有计算必须是确定性的——相同的输入必须产生相同的输出。`dev_aojs` 通过确定性运行时来保证这一点。

**为什么需要确定性？**

在去中心化系统中，多个节点需要就状态达成共识。如果 `S_A ≠ S_B` → 分叉！共识失败！

**非确定性来源（必须消除）**：

| 来源 | 问题 | 解决方案 |
|------|------|----------|
| `Math.random()` | 每次运行结果不同 | 确定性 PRNG（xorshift128+） |
| `Date.now()` | 不同时间运行结果不同 | 固定返回 0（当前实现） |
| `new Date()` | 同上 | 同上 |
| 真正的随机数 | 同上 | 使用种子驱动的 PRNG |

**⚠️ 重要说明**：虽然 `ao-runtime.js` 中实现了使用 `env.Timestamp` 的代码，但 `dev_aojs` 的 `build_env_json/2` 函数**从未设置** `env.Timestamp` 字段。因此，`Date.now()` 和 `new Date()` 当前始终返回 0（Unix 纪元时间）。如需使用真正的区块时间戳，需要修改 `build_env_json/2` 函数来注入 `Timestamp` 值。

**确定性替代方案（ao-runtime.js 实现）**：

**1. 确定性 PRNG（xorshift128+）**：

```javascript
let _seed = [1, 2];
globalThis._setSeed = (s1, s2) => {
    _seed = [s1 >>> 0, s2 >>> 0];
};
const _xorshift = () => {
    let s1 = _seed[0], s2 = _seed[1];
    _seed[0] = s1;
    s1 ^= s1 << 23;
    s1 ^= s1 >>> 17;
    s1 ^= s2;
    s1 ^= s2 >>> 26;
    _seed[1] = s1;
    return ((_seed[0] + _seed[1]) >>> 0) / 4294967296;
};
Math.random = _xorshift;
```

**2. 确定性时间**：

```javascript
const _OriginalDate = Date;
globalThis.Date = function(...args) {
    if (args.length === 0) {
        const ts = (env && env.Timestamp) || 0;
        return new _OriginalDate(ts);
    }
    return new _OriginalDate(...args);
};
globalThis.Date.now = () => (env && env.Timestamp) || 0;
```

**种子设置机制**：

为了确保完全确定性，PRNG 的种子应该来自消息内容。当前代码中 `_setSeed` 函数已定义，但未被 dev_aojs 调用。

**当前行为**：PRNG 使用固定种子 `[1, 2]`，这保证了确定性（每次运行结果相同），但不是基于消息内容。

**建议**：如果需要基于消息内容设置种子，可以在 `execute_handler` 中调用 `_setSeed`，传入消息相关值（如消息 ID 或序列号）。

### 5.3 Outbox 机制

`dev_aojs` 支持通过 outbox 机制让智能合约发送消息到其他进程。这是 AO 系统消息传递的核心机制。

**outbox 是什么？**

outbox = 智能合约发送的消息队列

- 合约内部使用 `ao.send()` 添加消息到 outbox
- 合约执行完成后，outbox 中的消息被收集并返回
- 调度器负责将这些消息实际发送到目标进程

**ao.send 实现**（ao-runtime.js）：

```javascript
globalThis.ao = {
    send: (m) => {
        if (m && m.Target) {
            _outbox.push(JSON.parse(JSON.stringify(m)));
        }
    }
};
```

**返回结果中的 Outbox**：

```json
{
    "results": {
        "data": {...},
        "outbox": [
            {
                "Target": "process-2",
                "Action": "Credit",
                "Quantity": "100"
            }
        ]
    }
}
```

**调度器处理流程**：

1. 从 results.outbox 中获取消息列表
2. 将每个消息发送到对应的目标进程
3. 目标进程收到消息后，会触发其 compute 操作

---

## 六、状态持久化机制

### 6.1 普通设备与进程设备的区别

理解普通设备和进程设备在状态管理上的根本区别是开发有状态应用的关键。

**普通设备的状态行为**：

问题：普通设备（如直接调用的 dev_aojs）能否跨 HTTP 请求保持状态？

**答案：不能！**

**原因分析**（基于源码验证）：

1. **HTTP 请求消息创建**（hb_singleton.erl:197）：`normalize_base(Rest) -> [#{}|Rest]` → 非 ID 路径返回空消息 M1 = `#{}`
2. **Priv 数据排除**（hb_cache.erl:268）：`maps:without([<<"priv">>], Msg)` → priv 数据不会写入缓存
3. **无消息链接**（hb_cache.erl:272-281）：只链接到 commitment IDs，不会自动关联请求

**测试验证**：

```bash
请求1: POST /~aojs@1.0/compute (Action=Increment)
        M1 = #{}
        state.count = 0 → 1
        返回 {results: {data: {count: 1}}}

请求2: POST /~aojs@1.0/compute (Action=Increment)
        M1 = #{}  ← 新的空消息！
        state.count = 0 → 1  ← 状态丢失了！
        返回 {results: {data: {count: 1}}}  ← 又是 1！

结果：无论调用多少次 increment，value 始终返回 1
```

**进程设备的状态行为**：

解决方案：**使用进程机制**

进程的工作原理：

1. Worker 在内存中保存 Msg1（含状态）
2. 每次请求使用 Msg1 作为基础
3. 新消息成为下一轮的 Msg1
4. 超时后通过 snapshot 保存到缓存

**两种方式对比**：

| 特性 | 普通设备调用 | 进程机制调用 |
|------|------------|-------------|
| M1 来源 | `#{}` (空消息) | 上一条消息（含状态） |
| 状态保持 | ❌ 不保持 | ✅ Worker 内存保持 |
| 状态持久化 | ❌ 无 | ✅ 快照自动保存 |
| 适用场景 | 无状态查询 | 有状态应用 |
| HTTP 行为 | 每次独立调用 | 基于之前状态 |

### 6.2 快照触发机制

进程设备使用双重触发机制来决定何时保存快照。

**两种触发条件**（dev_process.erl:479-500）：

```erlang
should_snapshot(Slot, Msg3, Opts) ->
    should_snapshot_slots(Slot, Opts)    ← 槽位触发
        orelse
    should_snapshot_time(Msg3, Opts).  ← 时间触发
```

**槽位触发机制**：

```erlang
should_snapshot_slots(Slot, Opts) ->
    case hb_opts:get(process_snapshot_slots, ?DEFAULT_SNAPSHOT_SLOTS, Opts) of
        Undef when (Undef == undefined) or (Undef == <<"false">>) ->
            false;
        RawSnapshotSlots ->
            SnapshotSlots = hb_util:int(RawSnapshotSlots),
            Slot rem SnapshotSlots == 0   ← 每 N 个槽位触发一次
    end.
```

示例：

| 配置值 | 触发频率 |
|--------|----------|
| `process_snapshot_slots = 1` | 每次消息都保存快照 |
| `process_snapshot_slots = 5` | 每 5 个消息保存一次快照 |
| `process_snapshot_slots = 未设置` | 不按槽位触发 |

**时间触发机制**：

```erlang
should_snapshot_time(Msg3, Opts) ->
    case hb_opts:get(process_snapshot_time, ?DEFAULT_SNAPSHOT_TIME, Opts) of
        Undef when (Undef == undefined) or (Undef == <<"false">>) ->
            false;
        RawSecs ->
            Secs = hb_util:int(RawSecs),
            (当前时间 - 上次快照时间) >= Secs   ← 每 N 秒触发一次
    end.
```

**默认配置对比**：

| 配置项 | 测试环境默认值 | 生产环境默认值 |
|--------|--------------|--------------|
| `process_snapshot_slots` | 1 | `undefined` (禁用) |
| `process_snapshot_time` | `undefined` (禁用) | 60 秒 |
| `process_worker_max_idle` | 300 秒 | 300 秒 |

**快照存储路径**：

```
priv/additional-hashpaths/[ProcessID]/snapshot/[Slot]
```

---

## 七、调试与测试

### 7.1 EUnit 测试框架

`dev_aojs` 使用 EUnit 作为测试框架。以下是测试结构和运行方法。

**运行测试命令**：

```bash
# 运行所有 dev_aojs 测试
rebar3 eunit --module=dev_aojs

# 运行单个测试
rebar3 eunit --module=dev_aojs --group=js_counter_module

# 增加超时时间（复杂测试需要）
Timeout = 120  ← 在测试定义中设置
```

**测试用例详解**：

**info_test**：
验证：设备信息返回正确
- `name = "aojs@1.0"`
- `description = "JavaScript Smart Contract Runtime"`
- `exports = ["init", "compute", "snapshot", "normalize"]`

**aojs_wasm_init_test**：
验证：WASM 镜像加载和初始化
1. 加载 WASM 镜像 (`dev_wasm:cache_wasm_image`)
2. 构建设备栈消息
3. 初始化设备栈 (`hb_ao:resolve` with path="init")
4. 调用 `qjs_init` 初始化 QuickJS
5. 验证返回值为 0 (成功)

**js_basic_eval_test**：
验证：JavaScript 基本求值
- 测试 `1 + 2 = 3`
- 测试 JSON 序列化

**js_counter_module_test**：
验证：完整的状态持久化流程
1. 初始化 state 和 Handlers
2. 加载 counter.js 模块
3. 测试 GetCount (初始值 0)
4. 测试 Increment (状态变化: 0→1→2)
5. 测试 Decrement (状态变化: 2→1)
6. 测试 Reset (状态重置为 0)

> 这是验证 dev_aojs 状态管理的核心测试！

**js_token_module_test**：
验证：更复杂的业务逻辑（代币合约）
1. 初始化 state、Handlers 和 ao.send
2. 测试 Info (代币信息)
3. 测试初始余额 (0)
4. 测试 Mint (铸造代币)
5. 验证余额更新 (100)

### 7.2 调试技巧

开发过程中，有效的调试技巧可以大大提高效率。

**1. 使用 ?event 日志宏**：

```erlang
?event({running_init})           ← 初始化开始
?event({calling_wasm_executor, ...}) ← 调用 WASM 执行器
?event({stack_execute, ...})      ← 栈执行
?event({result, ok, ...})         ← 结果返回
```

查看日志：

```bash
make console   ← 启动 Erlang 控制台
```

**2. 消息结构调试**：

```erlang
?event({msg1, M1}),                    ← 打印 M1
?event({msg2, M2}),                    ← 打印 M2
?event({opts, Opts}),                  ← 打印选项
?event({result, Result}),              ← 打印结果
```

**3. WASM 内存调试**：

```erlang
% 读取 WASM 内存
{ok, Mem} = hb_beamr_io:read(Instance, 0, Size).
io:format("Memory: ~p~n", [Mem]).

% 写入测试数据
{ok, Ptr} = hb_beamr_io:write_string(Instance, <<"test data">>).
{ok, Data} = hb_beamr_io:read(Instance, Ptr, 9).
io:format("Read: ~p~n", [Data]).
```

**4. 常见问题排查清单**：

| 问题 | 检查项 | 解决项 |
|------|--------|--------|
| WASM 实例未找到 | dev_wasm 是否已初始化；设备栈是否包含 wasm-64@1.0 | 确保 init 在 compute 之前调用 |
| JavaScript 语法错误 | eval_js 返回 {error, Error} | 修复 JS 代码语法 |
| Handlers 未定义 | ao-runtime.js 是否已注入；模块代码中是否定义了 Handlers | 确保在模块中调用 Handlers.add() |
| 状态不持久化 | 是否通过进程调用；snapshot/normalize 是否实现 | 使用进程机制并验证快照配置 |

---

## 八、部署与运维

### 8.1 设备注册与配置

在 HyperBEAM 节点中使用 `dev_aojs` 需要正确配置。

**第一层：节点配置（hb_opts.erl）**：

必须将 aojs@1.0 添加到节点的预加载设备列表：

```erlang
preloaded_devices => [
    ...
    #{<<"name">> => <<"aojs@1.0">>, <<"module">> => dev_aojs},
    ...
]
```

**重要提示**：默认配置中可能没有 aojs@1.0，需要手动添加！

**第二层：进程配置（Spawn Tags）**：

Spawn 进程时配置设备栈：

```json
{
    "type": "Process",
    "module": "module-id",
    "scheduler": "scheduler-address",

    "execution-device": "stack@1.0",
    "device-stack": [
        "dedup@1.0",
        "cron@1.0",
        "wasm-64@1.0",
        "aojs@1.0",
        "multipass@1.0"
    ],
    "stack-keys": ["init", "compute", "snapshot", "normalize"],

    "data": "initial-script"
}
```

### 8.2 监控与运维

**关键监控指标**：

1. **消息处理延迟**
   - compute 调用耗时
   - JS 执行时间
   - 监控方法：`hb_beamr:call` 耗时

2. **WASM 内存使用**
   - 当前内存使用量
   - 内存增长趋势
   - 监控方法：`hb_beamr_io:size/1`

3. **快照操作频率**
   - 快照保存频率
   - 快照大小
   - 监控方法：snapshot 调用计数

4. **错误率**
   - JS 执行错误
   - 内存分配失败
   - 监控方法：`eval_js` 错误返回

**日志分析**：

| 事件 | 说明 |
|------|------|
| `running_init` | init 函数被调用 |
| `calling_wasm_executor` | 开始执行 JS 代码 |
| `snapshot/generating_snapshot` | 开始生成快照 |
| `snapshot/finished_snapshot` | 快照生成完成 |
| `wasm_error` | WASM 执行错误 |
| `import_called` | WASM 导入函数被调用 |

**日志级别配置**：

| 级别 | 用途 |
|------|------|
| debug | 详细执行信息（开发环境） |
| info | 关键操作日志（生产环境推荐） |
| warning | 警告信息 |
| error | 错误信息 |

**性能优化建议**：

1. **减少快照频率**：如果状态不经常变化，增加 `process_snapshot_time`（示例：`process_snapshot_time = 300`）
2. **限制 WASM 内存大小**：编译时设置合理的 `--max-memory`（示例：`--max-memory=67108864`）
3. **优化 JavaScript 代码**：避免内存泄漏；减少全局变量使用；使用 let/const 替代 var
4. **合理使用 outbox**：批量发送消息优于逐条发送；避免过大的 outbox

---

## 九、最佳实践与常见问题

### 9.1 JavaScript 合约开发最佳实践

**1. 状态管理最佳实践**：

**推荐模式**：

```javascript
// 在模块顶部初始化状态
state.count = state.count || 0;
state.balances = state.balances || {};

// 永远不要假设状态已经存在
Handlers.add('Action', (msg) => {
    state.value = state.value || 0;
    // ...执行业务逻辑
});
```

**错误模式**：

```javascript
// 假设 state.count 已存在
state.count += 1;  // 如果 state.count 是 undefined，结果是 NaN！
```

**2. 消息处理最佳实践**：

```javascript
Handlers.add('Transfer', (msg) => {
    // 1. 参数验证
    const quantity = parseInt(msg.Tags.Quantity || '0');
    if (quantity <= 0) {
        return { error: 'Invalid quantity' };
    }

    // 2. 状态读取
    const from = msg.From;
    const balance = state.balances[from] || 0;

    // 3. 业务逻辑验证
    if (balance < quantity) {
        return { error: 'Insufficient balance' };
    }

    // 4. 状态更新
    state.balances[from] = balance - quantity;
    const to = msg.Tags.Recipient;
    state.balances[to] = (state.balances[to] || 0) + quantity;

    // 5. 返回结果
    return { success: true, newBalance: balance - quantity };
});
```

**3. 错误处理最佳实践**：

```javascript
Handlers.add('Action', (msg) => {
    try {
        const result = riskyOperation(msg);
        return { success: true, data: result };
    } catch (error) {
        return {
            error: 'Operation failed',
            reason: error.message || String(error)
        };
    }
});

// 为未知 Action 提供默认处理器
Handlers.add('default', (msg) => {
    return { error: 'Unknown action: ' + (msg.Action || 'unknown') };
});
```

### 9.2 安全注意事项

**1. 资源耗尽防护**：

| 配置项 | 值 | 目的 |
|--------|-----|------|
| WASM 内存限制 | `--max-memory=67108864` (64MB) | 防止单个合约耗尽资源 |
| 栈大小限制 | `-Wl,-z,stack-size=1048576` (1MB) | 防止递归攻击 |

**2. 输入验证**：

```javascript
// 验证必要字段存在
if (!msg.Tags.Quantity) {
    return { error: 'Missing Quantity' };
}

// 验证数据类型
const quantity = parseInt(msg.Tags.Quantity);
if (isNaN(quantity) || quantity < 0) {
    return { error: 'Invalid Quantity' };
}

// 验证数值范围
const MAX_VALUE = 1000000;
if (quantity > MAX_VALUE) {
    return { error: 'Quantity exceeds maximum' };
}
```

**3. 防止注入攻击**：

| 做法 | 说明 |
|------|------|
| 验证和清理所有外部输入 | 防止恶意数据 |
| 避免使用 eval() 或 Function() | 防止代码注入 |
| 使用 JSON.parse() 替代 eval() | 安全解析 JSON |

---

## 十、总结与进阶路径

### 10.1 核心要点回顾

**架构理解**：

```
HyperBEAM → dev_stack → dev_wasm → QuickJS (WASM) → JavaScript
```

dev_aojs 依赖下层设备管理 WASM 实例，自己专注于 JS 执行。

**四个核心 API**：

| API | 职责 | 自动调用 |
|-----|------|---------|
| info/3 | 返回设备信息 | 系统启动时 |
| init/3 | 初始化运行时 | 首次 compute 前 |
| compute/3 | 执行处理器 | 每次消息处理时 |
| snapshot/3 | 保存状态 | 进程调度器 |
| normalize/3 | 恢复状态 | 进程调度器 |

**关键概念**：

| 概念 | 说明 | 重要性 |
|------|------|--------|
| 设备栈 | 多个设备组合使用 | ★★★★★ |
| 前缀机制 | 数据隔离，避免冲突 | ★★★★☆ |
| 确定性运行时 | 保证计算可验证 | ★★★★★ |
| Outbox | 合约间消息传递 | ★★★★☆ |
| 快照机制 | 状态持久化 | ★★★★★ |
| 进程机制 | 跨请求状态保持 | ★★★★★ |

**常见陷阱**：

| 陷阱 | 说明 |
|------|------|
| ❌ 直接 HTTP 调用 dev_aojs | 状态不保持 |
| ❌ 假设 state 对象自动初始化 | 需要手动检查 |
| ❌ 使用非确定性代码 | Date.now、Math.random |
| ❌ 忘记实现 snapshot/normalize | 状态不持久化 |
| ❌ 设备栈配置错误 | 顺序或前缀缺失 |

### 10.2 进阶学习路径

**初级阶段（已覆盖）**：

- ✅ 理解设备栈架构
- ✅ 掌握四个核心 API
- ✅ 能编写基本 JS 合约
- ✅ 理解状态持久化机制
- ✅ 能运行和调试测试

**中级阶段**：

- ○ 深入学习 QuickJS 内部机制
- ○ 理解 WAMR (WebAssembly Micro Runtime)
- ○ 学习 hb_beamr 模块源码
- ○ 掌握 WASM 内存管理
- ○ 学习设备协作机制（dev_stack）
- ○ 理解进程调度和消息路由

**高级阶段**：

- ○ 开发自定义 AO 设备
- ○ 优化 QuickJS/WASM 性能
- ○ 实现高级确定性机制
- ○ 设计复杂的多设备协作流程
- ○ 贡献 HyperBEAM 开源项目

### 10.3 参考资料汇总

**核心模块源代码位置**：

| 文件 | 说明 |
|------|------|
| `src/dev_aojs.erl` | 主角设备 |
| `src/dev_wasm.erl` | WASM 设备 |
| `src/dev_stack.erl` | 设备栈管理 |
| `src/hb_beamr.erl` | WAMR 封装 |
| `src/hb_ao.erl` | AO 核心解析器 |

**官方参考文档**：

| 文档 | 说明 |
|------|------|
| `docs/drafts/ao-device-state-persistence-verification.md` | 状态持久化 |
| `docs/drafts/quickjs-wasm-compilation-guide.md` | QuickJS 编译指南 |
| `docs/drafts/device-collaboration.md` | 设备协作 |
| `docs/drafts/device-configuration-persistence.md` | 设备配置 |

**JavaScript 相关**：

| 文件 | 说明 |
|------|------|
| `aojs/ao-runtime.js` | AO JavaScript 运行时 |
| `aojs/aojs-modules/counter.js` | 计数器示例 |
| `aojs/aojs-modules/token.js` | 代币示例 |

**外部资源**：

| 资源 | URL |
|------|-----|
| QuickJS | https://bellard.org/quickjs/ |
| WAMR | https://bytecodealliance.github.io/wamr.dev/ |
| Erlang/OTP | https://www.erlang.org/doc |
| rebar3 | https://rebar3.org/ |

---

## 结语

本教程系统地介绍了 `dev_aojs` 设备的开发流程和核心技术要点。从系统架构到具体实现，从基础概念到高级技巧，我们涵盖了入门开发者需要掌握的所有核心知识。

`dev_aojs` 作为 AO 系统中执行 JavaScript 智能合约的核心设备，其设计体现了 AO 架构的核心理念：**模块化、可组合、确定性**。通过设备栈机制，不同功能的设备可以灵活组合；通过快照和进程机制，系统实现了可靠的状态持久化；通过确定性运行时，所有计算结果都可以被验证和重现。

希望本教程能帮助您快速上手 `dev_aojs` 开发，并在未来的实践中不断深化对 AO 系统的理解。

**Happy Coding!**

---

**文档信息**

| 项目 | 值 |
|------|------|
| 标题 | AO JavaScript 设备开发完整教程 |
| 适用设备 | dev_aojs |
| 目标读者 | AO 设备开发入门者 |
| 核心主题 | 系统架构、核心 API、状态持久化、调试测试 |
| 验证依据 | HyperBEAM 核心代码库源码 |
| 置信度 | 100% |
| 文档版本 | 1.0 |
| 创建日期 | 2026-02-09 |
| 保存路径 | `docs/drafts/dev_aojs-development-guide.md` |
