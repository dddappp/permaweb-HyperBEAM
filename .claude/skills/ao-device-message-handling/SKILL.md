---
name: ao-device-message-handling
description: AO 设备消息处理。包含消息路由、设备函数调用、参数处理、消息转换等核心机制。开发设备时参考此技能。
---

# AO 设备消息处理指南

本技能涵盖 AO 设备消息处理的核心机制和最佳实践。

## 核心概念

### 消息处理流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     消息处理流程                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  HTTP 请求                                                         │
│       ↓                                                           │
│  解析消息格式 (structured, flat, json 等)                         │
│       ↓                                                           │
│  路由到设备函数 (基于 path 或键名)                                 │
│       ↓                                                           │
│  执行设备函数 (传入 M1, M2, Opts)                                 │
│       ↓                                                           │
│  返回结果 (转换为请求的格式)                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 设备函数签名

### 标准签名

所有设备函数遵循相同的签名：

```erlang
function_name(M1, M2, Opts) ->
    {ok, Result}.
```

**参数说明**：
- `M1`: 设备状态消息，包含设备当前状态
- `M2`: 请求消息，包含客户端传入的数据
- `Opts`: 选项映射，包含运行时配置

**返回值模式**：
```erlang
{ok, Result}                    % 成功
{ok, #{<<"key">> => Value}}    % 成功，返回映射
{error, Reason}                 % 错误
{error, #{<<"status">> => 400, <<"error">> => Reason}}
```

## 消息路由机制

### 路由流程

当收到请求时，系统会：

1. **解析请求**：从请求体中提取 `path` 或目标键
2. **定位设备**：从消息中获取 `device` 键确定设备模块
3. **查找函数**：根据键名查找设备中的导出函数
4. **调用函数**：执行函数并返回结果

### 请求格式

```erlang
% 方式1: 使用 path 键
#{
    <<"path">> => <<"operation_name">>,
    <<"param1">> => Value1,
    <<"param2">> => Value2
}

% 方式2: 直接使用键名
#{
    <<"operation_name">> => true,
    <<"param1">> => Value1
}
```

## 消息获取 API

### 获取键值

```erlang
% 基本获取
Value = some_module:get(<<"key">>, Message, Opts).

% 带默认值
Value = some_module:get(<<"key">>, Message, Default, Opts).
```

### 获取第一个可用值

```erlang
% 从多个来源获取第一个非空值
Value = get_first(
    [
        {PrimaryMessage, <<"key">>},
        {SecondaryMessage, <<"key">>}
    ],
    Default,
    Opts
).
```

## 参数处理

### 必需参数验证

```erlang
operation(_M1, M2, _Opts) ->
    case maps:get(<<"required_param">>, M2, not_found) of
        not_found ->
            {error, #{
                <<"status">> => 400,
                <<"error">> => <<"Missing 'required_param'">>
            }};
        Value ->
            {ok, #{<<"result">> => process(Value)}}
    end.
```

### 可选参数默认值

```erlang
operation(_M1, M2, _Opts) ->
    OptionalParam = maps:get(<<"optional_param">>, M2, <<"default">>),
    Format = maps:get(<<"format">>, M2, <<"json">>),
    {ok, #{<<"format">> => Format, <<"param">> => OptionalParam}}.
```

### 参数截断

设备函数调用时，参数会根据函数元数自动截断：

```erlang
% 如果函数定义为 fun operation/3
% 调用时只传入前3个参数，多余的被忽略
operation(M1, M2, Opts) -> ...
```

## 消息转换

### 格式转换

消息可以在不同格式间转换：

```erlang
% 结构化格式 (嵌套 map)
Structured = convert(RawMsg, <<"structured@1.0">>, Opts).

% 扁平格式 (单层 map)
Flat = convert(Structured, <<"flat@1.0">>, Opts).
```

### 保留键

消息中某些键有特殊含义：

| 键名 | 用途 |
|------|------|
| `<<"get">>` | 获取值 |
| `<<"set">>` | 设置值 |
| `<<"keys">>` | 列出键 |
| `<<"id">>` | 消息 ID |
| `<<"commit">>` | 提交消息 |
| `<<"verify">>` | 验证签名 |

## 消息处理最佳实践

### 1. 参数验证
```erlang
create(_M1, M2, _Opts) ->
    Required = [<<"name">>, <<"data">>],
    case lists:filter(fun(K) -> maps:get(K, M2, not_found) =:= not_found end, Required) of
        [] -> proceed;
        Missing -> {error, #{
            <<"status">> => 400,
            <<"error">> => <<"Missing parameters">>,
            <<"missing">> => Missing
        }}
    end.
```

### 2. 错误信息
```erlang
% 返回有意义的错误
{error, #{
    <<"status">> => 400,
    <<"error">> => <<"Invalid input">>,
    <<"details">> => #{
        <<"field">> => <<"reason">>
    }
}}
```

### 3. 日志记录
```erlang
?event(my_device, {operation, {param, Value}}, Opts).
```

### 4. 返回格式一致性
```erlang
{ok, #{
    <<"status">> => 200,
    <<"data">> => Result
}}
```

## 完整设备示例

```erlang
%%% @doc Example Device - Demonstrates message handling patterns
-module(dev_example).
-export([info/3, process/3, get/3, set/3]).
-include("include/hb.hrl").

%% @doc Device metadata
info(_M1, _M2, _Opts) ->
    {ok, #{
        <<"name">> => <<"example">>,
        <<"version">> => <<"1.0">>,
        <<"endpoints">> => [<<"process">>, <<"get">>, <<"set">>]
    }}.

%% @doc Process data
process(_M1, M2, _Opts) ->
    Input = maps:get(<<"input">>, M2, <<"">>),
    Result = do_processing(Input),
    {ok, #{
        <<"status">> => 200,
        <<"result">> => Result
    }}.

%% @doc Get stored value
get(_M1, M2, _Opts) ->
    Key = maps:get(<<"key">>, M2, not_found),
    case Key of
        not_found ->
            {error, #{<<"status">> => 400, <<"error">> => <<"Missing 'key'">>}};
        _ ->
            {ok, #{<<"status">> => 200, <<"key">> => Key, <<"value">> => <<"stored_value">>}}
    end.

%% @doc Set value
set(_M1, M2, _Opts) ->
    Key = maps:get(<<"key">>, M2, not_found),
    Value = maps:get(<<"value">>, M2, not_found),
    case {Key, Value} of
        {not_found, _} ->
            {error, #{<<"status">> => 400, <<"error">> => <<"Missing 'key'">>}};
        {_, not_found} ->
            {error, #{<<"status">> => 400, <<"error">> => <<"Missing 'value'">>}};
        _ ->
            {ok, #{<<"status">> => 200, <<"key">> => Key, <<"set">> => true}}
    end.

do_processing(Input) ->
    % 处理逻辑
    <<"processed_", Input/binary>>.
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
