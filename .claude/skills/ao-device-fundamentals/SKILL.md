---
name: ao-device-fundamentals
description: AO HyperBEAM 设备开发基础。包含设备模块结构、确定性执行、ID生成、错误处理等核心概念。开发新设备时首先参考此技能。
---

# AO HyperBEAM Device 基础开发指南

本技能涵盖 AO HyperBEAM 设备开发的核心概念和最佳实践。

## 确定性执行原则

Web3 智能合约/设备的核心要求是**确定性**：相同的输入必须产生相同的输出。

### 必须避免的非确定性操作

```erlang
% ❌ 错误：使用随机数
generate_id() ->
    crypto:strong_rand_bytes(32).

% ❌ 错误：使用系统时间
Timestamp = erlang:system_time(millisecond).

% ❌ 错误：使用进程字典或随机种子
random:uniform(100),
erlang:unique_integer().

% ❌ 错误：读取外部文件或网络
{ok, Content} = file:read_file("/path/to/file"),
{ok, Response} = httpc:request("http://example.com").
```

### 正确做法：使用内容可寻址 ID

```erlang
% ✅ 正确：基于内容生成 ID
generate_id(Data, Opts) ->
    Content = #{
        <<"type">> => <<"entity">>,
        <<"name">> => maps:get(<<"name">>, Data),
        <<"key">> => maps:get(<<"key">>, Data)
    },
    <<"entity_", (hb_util:human_id(hb_path:hashpath(Content, Opts)))/binary>>.
```

**为什么确定性很重要：**
- 所有节点可以独立验证状态转换
- 支持交易重放（replay）
- 不需要信任单个执行者

### AO 中的时间戳处理

```erlang
% ❌ 错误：设备自己生成时间戳
<<"issued_at">> => erlang:system_time(millisecond)

% ✅ 正确：时间戳来自消息元数据
Timestamp = hb_ao:get(<<"timestamp">>, M2, Opts),
<<"timestamp">> => Timestamp

% ✅ 或者：不依赖时间戳，使用其他确定性方式
```

## ID 生成最佳实践

### 使用内容可寻址 ID

在 Web3/AO 环境中，ID 应该基于内容生成，而不是使用随机数：

```erlang
% ✅ 正确：使用内容哈希生成 ID
generate_entity_id(Name, Description, Opts) ->
    Content = #{
        <<"type">> => <<"entity">>,
        <<"name">> => Name,
        <<"description">> => Description
    },
    <<"entity_", (hb_util:human_id(hb_path:hashpath(Content, Opts)))/binary>>.

% ✅ 正确：组合多个字段生成唯一 ID
generate_instance_id(EntityID, Owner, Index, Opts) ->
    Content = #{
        <<"entity_id">> => EntityID,
        <<"owner">> => Owner,
        <<"index">> => Index
    },
    <<"instance_", (hb_util:human_id(hb_path:hashpath(Content, Opts)))/binary>>.
```

**为什么使用内容可寻址 ID：**
- **可验证性**：任何节点都可以验证 ID 对应内容
- **去中心化**：不依赖中央 ID 生成服务
- **唯一性保证**：相同内容产生相同 ID（防碰撞）

## 设备模块结构

所有设备模块必须遵循以下基本结构：

```erlang
-module(dev_your_device_name).
-export([
    info/3,
    your_function/3
]).
-include("include/hb.hrl").
-include_lib("eunit/include/eunit.hrl").
```

## 核心约定

### 模块命名
- 设备模块必须以 `dev_` 前缀开头
- 使用下划线命名法（snake_case）
- 示例：`dev_counter`、`dev_badge`、`dev_processor`

### 导出函数签名
所有导出的设备函数必须接受3个参数：
```erlang
-export([function_name/3]).

function_name(M1, M2, Opts) ->
    {ok, Result}.
```

参数说明：
- `M1`: 消息状态（Message1），包含设备的当前状态
- `M2`: 请求消息（Message2），包含传入的请求数据
- `Opts`: 选项映射，包含运行时配置

### 返回值模式
设备函数应返回以下格式之一：
```erlang
{ok, Result}                    % 成功，返回结果
{ok, #{
    <<"key">> => Value           % 映射格式
}}
{error, Reason}                  % 错误
{error, #{
    <<"status">> => 400,
    <<"error">> => Reason
}}
```

## info 函数规范

设备可以使用两种形式的 `info` 函数：

### 形式1: info/1（无消息参数）
```erlang
info(_) ->
    #{
        <<"default">> => dev_message,
        <<"handlers">> => #{
            <<"info">> => fun info/3,
            <<"compute">> => fun compute/3
        }
    }.
```

### 形式2: info/3（带消息参数）
```erlang
info(_M1, _M2, _Opts) ->
    {ok, #{
        <<"name">> => <<"device-name">>,
        <<"version">> => <<"1.0">>,
        <<"description">> => <<"Description of the device">>,
        <<"endpoints">> => [
            <<"endpoint1">>,
            <<"endpoint2">>
        ]
    }}.
```

### 常用的 info 配置键

| 键名 | 说明 | 示例 |
|------|------|------|
| `name` | 设备名称 | `<<"counter">>` |
| `version` | 版本号 | `<<"1.0">>` |
| `description` | 描述 | `<<"Counter Device">>` |
| `endpoints` | 可用端点列表 | `[<<"increment">>]` |
| `handlers` | 处理器映射 | `#{<<"key">> => fun h/3}` |
| `exports` | 导出函数列表 | `[<<"op1">>, <<"op2">>]` |

## 函数导出控制

设备可以通过 `exports` 列表控制哪些函数可以被外部调用：

```erlang
info(_M1, _M2, _Opts) ->
    {ok, #{
        <<"name">> => <<"processor">>,
        <<"exports">> => [
            <<"encode">>,
            <<"decode">>,
            <<"sign">>
        ]
    }}.
```

## 错误处理模式

### 标准错误响应
```erlang
function_name(_M1, M2, _Opts) ->
    case maps:get(<<"required_key">>, M2, not_found) of
        not_found ->
            {error, #{
                <<"status">> => 400,
                <<"error">> => <<"Missing 'required_key'">>
            }};
        Value ->
            {ok, #{<<"result">> => Value}}
    end.
```

### 错误传播
```erlang
function_name(_M1, M2, Opts) ->
    case some_operation(M2, Opts) of
        {ok, Result} ->
            {ok, Result};
        {error, Reason} ->
            {error, Reason};
        error ->
            {error, <<"Operation failed">>}
    end.
```

## 事件日志

使用 `?event` 宏进行日志记录：

```erlang
?event(your_device, {operation, {key, Value}}, Opts).
```

## 完整设备示例

```erlang
%%% @doc Counter Device - 演示确定性执行和状态管理
-module(dev_counter).
-export([info/3, increment/3, value/3]).
-include("include/hb.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(STATE_KEY, <<"counter-state-id">>).

info(_M1, _M2, _Opts) ->
    {ok, #{
        <<"name">> => <<"counter">>,
        <<"version">> => <<"1.0">>,
        <<"description">> => <<"Counter with deterministic state">>,
        <<"endpoints">> => [<<"increment">>, <<"value">>]
    }}.

increment(M1, _M2, Opts) ->
    State = load_state(M1, Opts),
    CurrentValue = maps:get(<<"value">>, State, 0),
    NewValue = CurrentValue + 1,
    NewState = State#{<<"value">> => NewValue},
    M1Updated = save_state(M1, NewState, Opts),
    {ok, M1Updated#{<<"value">> => NewValue}}.

value(M1, _M2, Opts) ->
    State = load_state(M1, Opts),
    CurrentValue = maps:get(<<"value">>, State, 0),
    {ok, CurrentValue}.

%% 私有辅助函数
load_state(M1, Opts) ->
    case hb_private:get(?STATE_KEY, M1, not_found, Opts) of
        not_found -> #{};
        StateID ->
            case hb_cache:read(StateID, Opts) of
                {ok, State} -> hb_cache:ensure_all_loaded(State, Opts);
                not_found -> #{}
            end
    end.

save_state(M1, State, Opts) ->
    {ok, StateID} = hb_cache:write(State, Opts),
    UpdatedMsg = hb_private:set(M1, #{?STATE_KEY => StateID}, Opts),
    % 标记持久化 - 关键！
    UpdatedMsg#{<<"cache-control">> => [<<"store">>]}.

%% 测试
-ifdef(TEST).

counter_test() ->
    Opts = setup_test_env(),

    % 创建初始消息
    M1 = #{<<"device">> => <<"counter@1.0">>},

    % 链式调用 - 每次传递更新后的消息
    {ok, R1} = dev_counter:increment(M1, #{}, Opts),
    {ok, R2} = dev_counter:increment(R1, #{}, Opts),
    {ok, R3} = dev_counter:increment(R2, #{}, Opts),

    % 验证计数器值为 3
    ?assertEqual(3, maps:get(<<"value">>, R3)).

setup_test_env() ->
    application:ensure_all_started(hb),
    Store = hb_test_utils:test_store(hb_store_fs),
    #{store => [Store]}.

-endif.
```

## 开发步骤

1. 创建设备模块文件
2. 实现 `info/3` 函数描述设备
3. 实现业务功能函数（遵循 3 参数约定）
4. 添加 `load_state/save_state` 辅助函数
5. 添加 EUnit 测试
6. 确保确定性执行（无随机数、无系统时间）

## 相关技能

- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device Testing](ao-device-testing): 测试模式
- [AO Device Deployment](ao-device-deployment): 部署和加载
