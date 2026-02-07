---
name: ao-device-runtime
description: AO HyperBEAM 运行时环境开发。包含 WASM 运行时、Lua 运行时、WASI 系统接口等。开发智能合约执行环境时参考此技能。
---

# AO HyperBEAM 运行时环境开发指南

本技能涵盖 AO HyperBEAM 运行时环境的核心机制和最佳实践。

## WASM 运行时

### 加载并初始化 WASM 模块

```erlang
application:ensure_all_started(hb),
hb:init(),

%% 加载 WASM 镜像（从文件或缓存）
Msg0 = your_wasm_device:cache_wasm_image("path/to/module.wasm"),

%% 初始化实例
{ok, Msg1} = hb_ao:resolve(Msg0, <<"init">>, #{}),

%% 从私有数据获取实例
Priv = hb_private:from_message(Msg1),
{ok, Instance} = hb_ao:resolve(Priv, <<"instance">>, #{}),
is_pid(Instance).
```

### 调用 WASM 函数

```erlang
%% 加载并初始化（复用上面的代码）
{ok, Msg1} = hb_ao:resolve(Msg0, <<"init">>, #{}),

%% 创建计算请求
Msg2 = Msg1#{
    <<"function">> => <<"your_function">>,
    <<"parameters">> => [param1, param2]
},

%% 执行计算
{ok, Result} = hb_ao:resolve(Msg2, <<"compute">>, #{}),

%% 获取结果
{ok, Output} = hb_ao:resolve(Result, <<"results/output">>, #{}).
```

### WASM 快照

创建运行时快照以便后续恢复：

```erlang
{ok, Snapshot} = hb_ao:resolve(Result, <<"snapshot">>, #{}),
true = maps:is_key(<<"body">>, Snapshot).
```

## Lua 运行时

### 初始化 Lua 环境

```erlang
Process = #{
    <<"module">> => #{
        <<"content-type">> => <<"application/lua">>,
        <<"body">> => <<"
            function add(a, b)
                return a + b
            end
        ">>
    }
},

{ok, Initialized} = your_lua_device:init(Process, #{}, #{}),
is_map(Initialized).
```

### 函数发现

运行时可以自动发现 Lua 代码中定义的函数：

```erlang
Process = #{
    <<"module">> => #{
        <<"content-type">> => <<"application/lua">>,
        <<"body">> => <<"
            function test1() return 1 end
            function test2() return 2 end
        ">>
    }
},

{ok, Initialized} = your_lua_device:init(Process, #{}, #{}),
{ok, Functions} = your_lua_device:functions(Initialized, #{}, #{}),

true = lists:member(<<"test1">>, Functions),
true = lists:member(<<"test2">>, Functions).
```

### Lua 数据编码解码

Lua 和 Erlang 数据格式之间的转换：

```erlang
Term = #{<<"key">> => <<"value">>, <<"num">> => 42},

%% 编码为 Lua 格式
Encoded = your_lua_device:encode(Term, #{}),

%% 解码回映射
Decoded = your_lua_device:decode(Encoded, #{}),

Term = Decoded.
```

## WASI 运行时

### 初始化 WASI 环境

WebAssembly System Interface 提供了虚拟文件系统访问：

```erlang
{ok, Msg} = your_wasi_device:init(#{}, #{}, #{}),

%% 获取虚拟文件系统
VFS = hb_ao:get(<<"vfs">>, Msg, #{}),
true = maps:is_key(<<"dev">>, VFS),

%% 获取文件描述符
FDs = hb_ao:get(<<"file-descriptors">>, Msg, #{}),
true = maps:is_key(<<"0">>, FDs),  %% stdin
true = maps:is_key(<<"1">>, FDs),  %% stdout
true = maps:is_key(<<"2">>, FDs).  %% stderr
```

### 标准输出处理

```erlang
%% 初始化 WASI 环境
{ok, Msg0} = your_wasi_device:init(#{}, #{}, #{}),

%% 设置 stdout 内容（通过更新 VFS）
Msg1 = hb_ao:set(Msg0, <<"vfs/dev/stdout">>, <<"Hello, World!">>, #{}),

<<"Hello, World!">> = your_wasi_device:stdout(Msg1).
```

## 完整运行时工作流

```erlang
complete_runtime_workflow_test() ->
    application:ensure_all_started(hb),
    hb:init(),

    %% 1. 加载运行时模块
    Msg0 = your_runtime_device:initialize(),

    %% 2. 初始化运行时
    {ok, Msg1} = hb_ao:resolve(Msg0, <<"init">>, #{}),

    %% 3. 执行计算
    Msg2 = Msg1#{<<"function">> => <<"compute">>, <<"input">> => <<"data">>},
    {ok, Result} = hb_ao:resolve(Msg2, <<"compute">>, #{}),

    %% 4. 获取输出
    {ok, Output} = hb_ao:resolve(Result, <<"output">>, #{}),
    is_binary(Output).
```

## 运行时选择

根据需求选择合适的运行时：

| 运行时 | 适用场景 | 特点 |
|--------|----------|------|
| WASM | 高性能计算、沙箱安全 | 字节码格式，接近原生性能 |
| Lua | 快速脚本、轻量扩展 | 嵌入式，易于集成 |
| WASI | 系统接口访问 | 标准化的系统调用接口 |

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
