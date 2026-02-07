---
name: ao-device-process-scheduler
description: AO HyperBEAM 进程与调度器开发。包含 AOS 进程计算、消息调度、定时任务（cron）等。开发消息调度系统时参考此技能。
---

# AO HyperBEAM 进程与调度器开发指南

本技能涵盖 AO HyperBEAM 进程管理和任务调度的核心机制和最佳实践。

## AOS 进程计算

### 初始化进程环境

```erlang
dev_process:init().
```

### 创建测试进程

```erlang
Process = dev_process:test_aos_process().
```

### 调度计算任务

```erlang
%% 调度多个 Lua 计算任务
dev_process:schedule_aos_call(Process, <<"X = 10">>),
dev_process:schedule_aos_call(Process, <<"X = X * 2">>),
dev_process:schedule_aos_call(Process, <<"return X">>).
```

### 执行计算槽位

```erlang
%% 按槽位顺序执行
{ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 0}, #{}),
{ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 1}, #{}),
{ok, State2} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 2}, #{}),

<<"20">> = hb_ao:get(<<"results/data">>, State2, #{}).
```

### 获取当前状态（now）

```erlang
dev_process:schedule_aos_call(Process, <<"return 'hello'">>),
{ok, Result} = hb_ao:resolve(Process, <<"now/results/data">>, #{}),
<<"hello">> = Result.
```

### 干运行（dryrun）

```erlang
{ok, DryResult} = hb_ao:resolve(
    Process,
    #{
        <<"path">> => <<"compute">>,
        <<"method">> => <<"POST">>,
        <<"dryrun">> => #{<<"data">> => <<"return 99">>}
    },
    #{}
),
is_map(DryResult).
```

## 调度器

### 启动调度器

```erlang
dev_scheduler:start().
```

### 创建并调度进程

```erlang
Opts = #{
    priv_wallet => hb:wallet(),
    store => hb_opts:get(store)
},

Process = dev_scheduler:test_process(),
SignedProcess = hb_message:commit(Process, Opts),

{ok, Assignment} = dev_scheduler:schedule(
    #{},
    #{<<"method">> => <<"POST">>, <<"body">> => SignedProcess},
    Opts
),

true = maps:is_key(<<"slot">>, Assignment).
```

### 调度器状态

```erlang
{ok, Status} = dev_scheduler:status(#{}, #{}, #{}),
true = maps:is_key(<<"address">>, Status),
true = maps:is_key(<<"processes">>, Status).
```

## 定时任务（Cron）

### 一次性任务

```erlang
{ok, TaskID} = dev_cron:once(
    #{},
    #{<<"cron-path">> => <<"/test/path">>},
    #{}
),

is_binary(TaskID),

%% 停止任务
{ok, _} = dev_cron:stop(#{}, #{<<"task">> => TaskID}, #{}).
```

### 周期性任务

```erlang
{ok, TaskID} = dev_cron:every(
    #{},
    #{
        <<"cron-path">> => <<"/test/heartbeat">>,
        <<"interval">> => <<"500-milliseconds">>
    },
    #{}
),

is_binary(TaskID),
timer:sleep(100),

%% 停止任务
{ok, _} = dev_cron:stop(#{}, #{<<"task">> => TaskID}, #{}).
```

### 间隔格式

| 格式 | 说明 | 示例 |
|------|------|------|
| `N-milliseconds` | 毫秒 | `<<"500-milliseconds">>` |
| `N-seconds` | 秒 | `<<"30-seconds">>` |
| `N-minutes` | 分钟 | `<<"5-minutes">>` |
| `N-hours` | 小时 | `<<"1-hours">>` |

## 完整进程工作流

```erlang
complete_workflow_test() ->
    %% 1. 初始化
    dev_process:init(),
    Process = dev_process:test_aos_process(),

    %% 2. 调度计算任务
    dev_process:schedule_aos_call(Process, <<"Counter = 1">>),
    dev_process:schedule_aos_call(Process, <<"Counter = Counter + 1">>),
    dev_process:schedule_aos_call(Process, <<"return Counter">>),

    %% 3. 按顺序执行各槽位
    {ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 0}, #{}),
    {ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 1}, #{}),
    {ok, State} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 2}, #{}),

    %% 4. 验证结果
    Result = hb_ao:get(<<"results/data">>, State, #{}),
    <<"2">> = Result.
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
- [AO Device Deployment](ao-device-deployment): 部署和加载
