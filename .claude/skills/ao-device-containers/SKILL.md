---
name: ao-device-containers
description: AO HyperBEAM 容器设备开发。包含设备栈（stack@1.0）、多通道（multipass@1.0）、去重（dedup@1.0）等容器设备。开发复合设备时参考此技能。
---

# AO HyperBEAM 容器设备开发指南

本技能涵盖 AO HyperBEAM 容器设备的核心机制和最佳实践。

## 设备栈（stack@1.0）

### 概述

设备栈是管理多个子设备顺序执行的容器设备，支持两种执行模式：
- **Fold 模式（默认）**: 按顺序依次执行子设备，状态累积传递
- **Map 模式**: 所有子设备并行执行，结果存储在独立命名空间

### Fold 模式示例

```erlang
AppendA = your_stack_device:generate_append_device(<<"+A">>),
AppendB = your_stack_device:generate_append_device(<<"+B">>),

Stack = #{
    <<"device">> => <<"stack@1.0">>,
    <<"device-stack">> => #{
        <<"1">> => AppendA,
        <<"2">> => AppendB
    },
    <<"result">> => <<"START">>
},

{ok, Result} = hb_ao:resolve(
    Stack,
    #{ <<"path">> => <<"append">>, <<"bin">> => <<"!">> },
    #{}
),

<<"START+A!+B!">> = maps:get(<<"result">>, Result).
```

### Map 模式示例

```erlang
{ok, Result} = hb_ao:resolve(
    Stack,
    #{ <<"path">> => <<"append">>, <<"mode">> => <<"Map">>, <<"bin">> => <<"!">> },
    #{}
),

<<"START+A!">> = hb_ao:get(<<"1/result">>, Result, #{}),
<<"START+B!">> = hb_ao:get(<<"2/result">>, Result, #{}).
```

### 设备栈配置键

| 键名 | 说明 | 示例 |
|------|------|------|
| `device` | 设备类型 | `<<"stack@1.0">>` |
| `device-stack` | 子设备映射 | `#{<<"1">> => Device}` |
| `result` | 初始状态 | `<<"START">>` |
| `mode` | 执行模式 | `<<"Fold">>` 或 `<<"Map">>` |
| `Stack-Pass` | 通道号 | `1` |
| `Error-Strategy` | 错误处理策略 | `<<"halt">>` |
| `Allow-Multipass` | 是否允许多通道 | `true` |

## 多通道设备（multipass@1.0）

### 概述

多通道设备支持迭代执行，适用于需要重复处理直到满足条件的场景。

### 基本用法

```erlang
Msg = #{
    <<"device">> => <<"multipass@1.0">>,
    <<"passes">> => 2,
    <<"pass">> => 1
},

%% 第一次调用：返回 {pass, _} 触发重执行
{pass, _} = hb_ao:resolve(Msg, <<"compute">>, #{}),

%% 第二次调用：返回 {ok, _} 完成执行
Msg2 = Msg#{ <<"pass">> => 2 },
{ok, _} = hb_ao:resolve(Msg2, <<"compute">>, #{}).
```

### 执行流程

```
pass < passes: 返回 {pass, _} 触发下一次执行
pass = passes: 返回 {ok, _} 完成执行
```

## 去重设备（dedup@1.0）

### 概述

去重设备检测重复请求，相同请求只处理一次，后续请求被跳过。

### 基本用法

```erlang
Stack = #{
    <<"device">> => <<"stack@1.0">>,
    <<"dedup-subject">> => <<"request">>,
    <<"device-stack">> => #{
        <<"1">> => <<"dedup@1.0">>,
        <<"2">> => your_stack_device:generate_append_device(<<"+PROCESSED">>)
    },
    <<"result">> => <<"INIT">>
},

Request = #{ <<"path">> => <<"append">>, <<"bin">> => <<"!">> },

%% 第一次调用：处理请求
{ok, Msg2} = hb_ao:resolve(Stack, Request, #{}),
<<"INIT+PROCESSED!">> = maps:get(<<"result">>, Msg2),

%% 第二次调用：相同的请求被去重
{ok, Msg3} = hb_ao:resolve(Msg2, Request, #{}),
<<"INIT+PROCESSED!">> = maps:get(<<"result">>, Msg3).
```

### 去重机制

- `dedup-subject`: 指定用于去重判断的字段
- 相同 subject 的请求只处理第一个
- 后续请求跳过 dedup 之后的所有设备

## 完整流水线示例

```erlang
complete_pipeline_test() ->
    Pipeline = #{
        <<"device">> => <<"stack@1.0">>,
        <<"device-stack">> => #{
            <<"1">> => <<"dedup@1.0">>,
            <<"2">> => your_stack_device:generate_append_device(<<"-validated">>),
            <<"3">> => your_stack_device:generate_append_device(<<"-transformed">>)
        },
        <<"dedup-subject">> => <<"request">>,
        <<"result">> => <<"input">>
    },

    {ok, Result} = hb_ao:resolve(
        Pipeline,
        #{ <<"path">> => <<"append">>, <<"bin">> => <<"">> },
        #{}
    ),

    <<"input-validated-transformed">> = maps:get(<<"result">>, Result).
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
