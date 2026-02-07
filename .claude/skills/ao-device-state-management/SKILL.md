---
name: ao-device-state-management
description: AO HyperBEAM 设备状态管理。包含缓存读写、状态持久化、私有状态存储、数据加载、消息链传递等机制。管理设备状态时参考此技能。
---

# AO HyperBEAM 设备状态管理指南

本技能涵盖 AO HyperBEAM 设备状态管理的核心机制和最佳实践。

## 核心概念：消息驱动的状态

在 AO 中，**状态不存储在设备本地**，而是通过**消息链**传递。这是 AO 与传统应用的关键区别。

### 消息链工作原理

```
┌─────────────────────────────────────────────────────────────────┐
│                     消息链状态传递                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  初始消息 M1 (空状态)                                            │
│       ↓ 设备操作                                                │
│  load_state(M1) → 从 M1.priv 读取 StateID                      │
│       ↓ hb_cache:read                                         │
│  获取状态内容                                                   │
│       ↓ 设备处理                                                 │
│  save_state(M1, NewState) → 返回 M2 (包含新的 StateID)         │
│       ↓ 设备操作                                                │
│  消息 M2 (包含更新后的 priv.state_id)                            │
│       ↓ ...                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**关键点**：
- 每次操作返回**包含更新后状态的新消息**
- 调用方必须将返回的消息传递给下一次操作
- 状态 ID 存储在消息的 `priv` 部分

### 正确的消息链使用

```erlang
% ❌ 错误：每次都使用原始消息
{ok, Result1} = device:operation1(OriginalMsg, Request, Opts),
{ok, Result2} = device:operation2(OriginalMsg, Request, Opts),  % 错误！

% ✅ 正确：链式传递消息
{ok, Result1} = device:operation1(OriginalMsg, Request, Opts),
{ok, Result2} = device:operation2(Result1, Request, Opts),  % 正确！
{ok, Result3} = device:operation3(Result2, Request, Opts),  % 正确！
```

## 缓存系统架构

### 核心操作

AO 提供内容可寻址存储，相同内容总是返回相同的 ID。

```erlang
% 写入数据，获取内容 ID
{ok, DataID} = hb_cache:write(Data, Opts),

% 通过 ID 读取数据
case hb_cache:read(DataID, Opts) of
    {ok, Data} -> Data;
    not_found -> ...
end,

% 解析延迟加载的数据（link 格式：{link, ID, LinkOpts}）
ResolvedData = hb_cache:ensure_all_loaded(PotentiallyLinkedData, Opts).
```

### 内容可寻址 ID

```erlang
% 使用哈希路径生成确定性 ID
Path = hb_path:hashpath(Content, Opts),
{ok, ID} = hb_cache:write(Path, Opts),

% 以后用相同内容查询，得到相同的 ID
```

## 私有状态管理

### 状态存储模式

有两种常见的状态存储模式：

#### 模式1：Cache + ID 引用

```erlang
-define(STATE_KEY, <<"my-device-state">>).

%% 加载状态
load_state(M1, Opts) ->
    case hb_private:get(?STATE_KEY, M1, not_found, Opts) of
        not_found -> #{};
        StateID ->
            case hb_cache:read(StateID, Opts) of
                {ok, State} -> hb_cache:ensure_all_loaded(State, Opts);
                not_found -> #{}
            end
    end.

%% 保存状态 - 关键！
save_state(M1, State, Opts) ->
    {ok, StateID} = hb_cache:write(State, Opts),
    UpdatedMsg = hb_private:set(M1, #{?STATE_KEY => StateID}, Opts),
    % 标记消息持久化 - 状态才能跨调用保留！
    UpdatedMsg#{<<"cache-control">> => [<<"store">>]}.
```

#### 模式2：直接存储

```erlang
%% 直接在 priv 中存储状态
load_state(M1, Opts) ->
    hb_private:get(<<"state">>, M1, #{}, Opts).

save_state(M1, State, Opts) ->
    UpdatedMsg = hb_private:set(M1, #{<<"state">> => State}, Opts),
    UpdatedMsg#{<<"cache-control">> => [<<"store">>]}.
```

### cache-control: store 的作用

```erlang
save_state(M1, State, Opts) ->
    {ok, StateID} = hb_cache:write(State, Opts),
    UpdatedMsg = hb_private:set(M1, #{<<"state">> => StateID}, Opts),

    % 告诉 AO 调度器：
    %   - 将这条消息写入持久化存储
    %   - 下次可以从存储恢复这个消息
    %   - 消息中的 priv 数据会被保留
    UpdatedMsg#{<<"cache-control">> => [<<"store">>]}.
```

**没有 `cache-control: store` 的后果**：
- 状态只在当前消息链中有效
- 调度器重启后状态丢失
- 无法跨会话恢复状态

## HTTP 请求到消息链的转换

当用户使用 curl 调用设备时，AO 调度器会自动组装消息链：

```
用户请求                           AO 调度器
─────────                          ────────
curl POST /process                 收到请求
  - Process-ID: xxx                查找进程状态
  - Body: {...}                    ↓
                                   读取最近的 assignments
                                   ↓
  新消息 M_new              ←  Assignment_N−1 (上一个状态)
        ↓                           ↑
  调度器组装消息链                  │
        ↓                           │
  M_combined = {                   │
      <<"process">> => Assignment_N−1,  % 恢复上一个状态
      <<"message">> => M_new,       % 新请求
      <<"slot">> => N               % 槽位号
  }                                ↑
        ↓                           │
  设备函数调用                      │
  load_state(M_combined) ←──────┘
      ↓
  hb_private:get 找到 StateID (在 Assignment_N−1 的 priv 中)
```

**关键理解**：即使客户端没有显式传入"上一个消息"ID，AO 调度器会自动通过 Process-ID 查找并恢复上一个状态。

## priv_store 机制

### 隔离存储

Priv 数据与公共数据分开存储：

```erlang
%% hb_private.erl 中的 opts/1 函数
opts(Opts) ->
    PrivStore = ...,      % 单独的 priv store
    BaseStore = ...,      % 公共 store
    NormStore = PrivStore ++ BaseStore,
    Opts#{
        hashpath => ignore,
        cache_control => [<<"no-cache">>, <<"no-store">>],
        store => NormStore
    }.
```

### 关键理解：priv 数据的处理机制

通过分析 AO 源码发现：

```erlang
%% hb_cache.erl 中的 do_write_message
do_write_message(Msg, Store, Opts) when is_map(Msg) ->
    maps:map(
        fun(Key, Value) ->
            write_key(UncommittedID, Key, MsgHashpathAlg, Value, Store, Opts)
        end,
        maps:without([<<"priv">>], Msg)  % priv 被排除，不写入公共存储！
    ),
    ...
```

**priv 数据的处理方式**：
- **不会**自动写入公共存储（通过 `maps:without([<<"priv">>], Msg)` 排除）
- **必须**通过 `cache-control: store` 和 `additional-hashpaths` 机制显式持久化
- **可以**使用单独的 priv_store 进行隔离存储（通过 `hb_private:opts/1` 配置）
- **注意**：priv 数据不会自动在 HTTP 请求间传递，需要通过消息链显式传递

## 快照机制

快照用于保存设备状态的某个时间点：

```erlang
%% 快照函数示例
snapshot(RawMsg1, _Msg2, Opts) ->
    Msg1 = ensure_process_key(RawMsg1, Opts),
    {ok, SnapshotMsg} = run_as(
        <<"execution">>,
        Msg1,
        #{<<"path">> => <<"snapshot">>, <<"mode">> => <<"Map">>},
        Opts#{
            cache_control => [<<"no-cache">>, <<"no-store">>],
            hashpath => ignore
        }
    ),
    ProcID = hb_message:id(Msg1, all, Opts),
    Slot = hb_ao:get(<<"at-slot">>, {as, <<"message@1.0">>, Msg1}, Opts),
    {ok,
        hb_private:set(
            SnapshotMsg#{ <<"cache-control">> => [<<"store">>] },
            #{ <<"priv/additional-hashpaths">> =>
                [hb_path:to_binary([ProcID, <<"snapshot">>, Slot])]
            },
            Opts
        )
    }.
```

## 状态持久化完整示例

```erlang
-module(dev_counter).
-export([info/3, increment/3, value/3]).
-include("include/hb.hrl").

-define(STATE_KEY, <<"counter-state-id">>).

info(_M1, _M2, _Opts) ->
    {ok, #{<<"name">> => <<"counter">>, <<"version">> => <<"1.0">>}}.

increment(M1, _M2, Opts) ->
    State = load_state(M1, Opts),
    CurrentValue = maps:get(<<"value">>, State, 0),
    NewValue = CurrentValue + 1,
    NewState = State#{<<"value">> => NewValue},
    M1Updated = save_state(M1, NewState, Opts),
    {ok, M1Updated#{<<"value">> => NewValue}}.

value(M1, _M2, Opts) ->
    State = load_state(M1, Opts),
    #{<<"value">> => maps:get(<<"value">>, State, 0)}.

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
    UpdatedMsg#{<<"cache-control">> => [<<"store">>]}.
```

## 常见错误模式

### 错误1：get_map 按类型过滤

```erlang
% ❌ 错误：只返回 map 类型的值
get_map(Map, Key, Default) ->
    case maps:get(Key, Map, not_found) of
        not_found -> Default;
        Val when is_map(Val) -> Val;  % 列表等类型会返回 Default！
        _ -> Default
    end.

% ✅ 正确：返回任何非 not_found 的值
get_map(Map, Key, Default) ->
    case maps:get(Key, Map, not_found) of
        not_found -> Default;
        Val -> Val  % 返回实际值
    end.
```

### 错误2：忘记 cache-control: store

```erlang
% ❌ 错误：状态不会持久化
save_state(M1, State, Opts) ->
    {ok, StateID} = hb_cache:write(State, Opts),
    hb_private:set(M1, #{?STATE_KEY => StateID}, Opts).

% ✅ 正确：状态会持久化
save_state(M1, State, Opts) ->
    {ok, StateID} = hb_cache:write(State, Opts),
    UpdatedMsg = hb_private:set(M1, #{?STATE_KEY => StateID}, Opts),
    UpdatedMsg#{<<"cache-control">> => [<<"store">>]}.
```

### 错误3：直接访问 priv

```erlang
% ❌ 错误：应该使用 hb_private 模块
State = maps:get(<<"priv">>, M1, #{}),
StateID = maps:get(?STATE_KEY, State, not_found),

% ✅ 正确：使用 hb_private:get
StateID = hb_private:get(?STATE_KEY, M1, not_found, Opts).
```

## 辅助函数模式

### get_map - 获取可能不存在或不同类型的值

```erlang
%% 获取 map 中的值，不存在返回默认值
get_map(Map, Key, Default) ->
    case maps:get(Key, Map, not_found) of
        not_found -> Default;
        Val -> Val
    end.
```

### 状态更新 - 多字段

```erlang
update_state(M1, Updates, Opts) ->
    State = load_state(M1, Opts),
    NewState = maps:merge(State, Updates),
    save_state(M1, NewState, Opts).
```

### 列表操作

```erlang
add_to_list(M1, ListKey, Item, Opts) ->
    State = load_state(M1, Opts),
    List = get_map(State, ListKey, []),
    NewState = State#{ListKey => [Item | List]},
    save_state(M1, NewState, Opts).

remove_from_list(M1, ListKey, Item, Opts) ->
    State = load_state(M1, Opts),
    List = get_map(State, ListKey, []),
    NewState = State#{ListKey => lists:delete(Item, List)},
    save_state(M1, NewState, Opts).
```

## 最佳实践清单

| 做法 | 说明 |
|------|------|
| ✅ 链式传递消息 | 每次操作返回更新后的消息 |
| ✅ 添加 cache-control: store | 让状态持久化 |
| ✅ 使用 hb_private:get/set | 通过模块访问 priv 数据 |
| ✅ 调用 ensure_all_loaded | 解析延迟加载的链接 |
| ✅ 返回值传递给下次调用 | 保持状态连续性 |

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device Testing](ao-device-testing): 测试模式
- [AO Device Deployment](ao-device-deployment): 部署和加载
