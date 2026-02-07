---
name: ao-device-testing
description: AO HyperBEAM 设备测试。包含 EUnit 测试框架使用、hb_ao:resolve 测试模式、测试环境设置等。测试设备功能时参考此技能。
---

# AO HyperBEAM 设备测试指南

本技能涵盖 AO HyperBEAM 设备测试的核心机制和最佳实践。

## 测试框架

### EUnit 测试
所有设备测试使用 EUnit 测试框架：

```erlang
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
%%% 测试代码放在这里
-endif.
```

## 测试环境设置

### 基本测试设置

```erlang
setup_test_env() ->
    application:ensure_all_started(hb),
    Store = hb_test_utils:test_store(hb_store_fs),
    #{store => [Store]}.
```

**说明**：`hb_store_fs` 的 `write` 操作会自动调用 `filelib:ensure_dir` 确保目录存在，因此不需要手动调用 `hb_store:start`。

## 使用 hb_ao:resolve 进行测试

### 基本测试模式

```erlang
info_test() ->
    application:ensure_all_started(hb),
    {ok, Info} = hb_ao:resolve(
        {as, dev_processor, #{}},
        #{<<"path">> => <<"info">>},
        #{}
    ),
    ?assertEqual(<<"processor">>, maps:get(<<"name">>, Info)).
```

### 传递参数测试
```erlang
encode_json_test() ->
    application:ensure_all_started(hb),
    {ok, Result} = hb_ao:resolve(
        {as, dev_processor, #{}},
        #{
            <<"path">> => <<"encode">>,
            <<"format">> => <<"json">>,
            <<"body">> => #{<<"key">> => <<"value">>}
        },
        #{}
    ),
    ?assertEqual(<<"json">>, maps:get(<<"format">>, Result)).
```

### 带状态的测试
```erlang
name_resolution_test() ->
    Opts = setup_test_env(),
    M1 = #{},

    %% 注册
    {ok, RegResult} = hb_ao:resolve(
        {as, dev_processor, M1},
        #{
            <<"path">> => <<"register_name">>,
            <<"name">> => <<"alice">>,
            <<"value">> => <<"addr123">>
        },
        Opts
    ),
    ?assertEqual(<<"alice">>, maps:get(<<"registered">>, RegResult)),

    %% 查找
    {ok, LookupResult} = hb_ao:resolve(
        {as, dev_processor, RegResult},
        #{<<"path">> => <<"lookup">>, <<"name">> => <<"alice">>},
        Opts
    ),
    ?assertEqual(<<"addr123">>, maps:get(<<"value">>, LookupResult)).
```

## EUnit 断言

### 常用断言
```erlang
?assert(Expression)                    % 断言为真
?assertNot(Expression)                % 断言为假
?assertEqual(Expected, Actual)       % 断言相等
?assertMatch(Pattern, Expression)     % 模式匹配
?assertError(Class, Expression)       % 断言抛出异常
?assertThrow(Value, Expression)        % 断言抛出 throw
?assertExit(Reason, Expression)        % 断言退出
```

### 异常测试
```erlang
error_test() ->
    ?assertError(badarg, erlang:error(badarg)).
```

### 列表断言
```erlang
?assertListsEqual([1,2,3], [1,2,3]).
```

## 测试夹具

### 使用 setup
```erlang
device_test_() ->
    {setup,
        fun() -> application:ensure_all_started(hb) end,
        fun(_) -> ok end,
        fun(_) ->
            {ok, Info} = hb_ao:resolve(
                {as, dev_processor, #{}},
                #{<<"path">> => <<"info">>},
                #{}
            ),
            ?assertEqual(<<"processor">>, maps:get(<<"name">>, Info))
        end
    }.
```

### 并行测试
```erlang
parallel_test_() ->
    {foreach,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_one/1,
            fun test_two/1
        ]
    }.
```

## Mocking 和 Stubbing

### Mock hb_cache
```erlang
mock_cache_test() ->
    meck:new(hb_cache),
    meck:expect(hb_cache, read, fun(_, _) -> {ok, #{<<"data">> => <<"test">>}} end),

    {ok, Result} = dev_my_device:read(#{}, #{<<"target">> => <<"test-id">>}, #{}),
    ?assertEqual(<<"test">>, maps:get(<<"data">>, Result)),

    meck:unload(hb_cache).
```

### Stub 选项
```erlang
test_with_opts() ->
    Store = hb_test_utils:test_store(hb_store_fs),
    Opts = #{
        priv_wallet => ar_wallet:new(),
        store => [Store]
    },
    {ok, Result} = hb_ao:resolve(
        {as, dev_processor, #{}},
        #{<<"path">> => <<"sign">>, <<"body">> => #{<<"data">> => <<"test">>}},
        Opts
    ),
    ?assert(maps:is_key(<<"signed">>, Result)).
```

## 集成测试

### 多步骤测试
```erlang
multi_step_test() ->
    application:ensure_all_started(hb),
    Store = hb_test_utils:test_store(hb_store_fs),
    Opts = #{store => [Store]},

    %% 步骤1: 初始化
    {ok, InitResult} = hb_ao:resolve(
        {as, dev_processor, #{}},
        #{<<"path">> => <<"init">>},
        Opts
    ),
    ?assertEqual(<<"initialized">>, maps:get(<<"status">>, InitResult)),

    %% 步骤2: 处理数据
    {ok, ProcessResult} = hb_ao:resolve(
        {as, dev_processor, InitResult},
        #{<<"path">> => <<"process">>, <<"data">> => <<"test">>},
        Opts
    ),
    ?assertEqual(<<"processed">>, maps:get(<<"status">>, ProcessResult)),

    %% 步骤3: 验证结果
    {ok, VerifyResult} = hb_ao:resolve(
        {as, dev_processor, ProcessResult},
        #{<<"path">> => <<"verify">>},
        Opts
    ),
    ?assertEqual(true, maps:get(<<"valid">>, VerifyResult)).
```

### 错误场景测试
```erlang
error_handling_test() ->
    %% 测试缺失参数
    {ok, ErrorResult} = hb_ao:resolve(
        {as, dev_processor, #{}},
        #{<<"path">> => <<"register_name">>},
        #{}
    ),
    ?assertEqual(400, maps:get(<<"status">>, ErrorResult)),
    ?assertEqual(<<"Missing 'name'">>, maps:get(<<"error">>, ErrorResult)),

    %% 测试无效数据
    {ok, InvalidResult} = hb_ao:resolve(
        {as, dev_processor, #{}},
        #{
            <<"path">> => <<"encode">>,
            <<"format">> => <<"invalid">>,
            <<"body">> => #{<<"key">> => <<"value">>}
        },
        #{}
    ),
    ?assertEqual(400, maps:get(<<"status">>, InvalidResult)).
```

## Dummy 设备测试

### 简单测试设备

```erlang
-module(dev_dummy).
-export([echo/3]).

echo(_M1, M2, _Opts) ->
    {ok, M2}.
```

### 创建测试设备
```erlang
-module(dev_test_device).
-export([test_func/3]).

test_func(_M1, M2, _Opts) ->
    {ok, #{<<"test">> => maps:get(<<"input">>, M2, <<"default">>)}}.
```

## 性能测试

### 计时测试
```erlang
timing_test() ->
    {ok, Result} = timer:tc(
        fun() ->
            lists:map(
                fun(I) ->
                    hb_ao:resolve(
                        {as, dev_processor, #{}},
                        #{<<"path">> => <<"encode">>, <<"body">> => #{<<"i">> => I}},
                        #{}
                    )
                end,
                lists:seq(1, 100)
            )
        end
    ),
    {Time, _} = Result,
    ?assert(Time < 5000000).  % 5秒内完成
```

## 测试覆盖率

### 覆盖率配置
在 `rebar.config` 中添加：

```erlang
{cover_enabled, true}.
{cover_export_enabled, true}.
```

### 运行覆盖率
```bash
rebar3 ct --cover
rebar3 cover --verbose
```

## 测试最佳实践

1. **每个功能一个测试**: 每个导出的函数应有对应的测试
2. **测试正常和异常路径**: 测试成功和错误情况
3. **使用有意义的断言**: 使用具体的断言而非泛泛的检查
4. **隔离测试**: 确保测试之间不相互依赖
5. **记录测试数据**: 使用清晰的数据设置和清理

## 状态链式调用测试

### 关键原则：每次操作必须传递更新后的消息

在测试需要状态的设备时，每次操作必须将结果消息传递给下一次操作：

```erlang
% 错误：每次都使用原始消息，状态不会更新
{ok, Result1} = dev_badge:create_badge(...),
{ok, Result2} = dev_badge:issue(Result1, ...),  % 使用 Result1 正确
{ok, Result3} = dev_badge:issue(Result1, ...),  % 错误！应该用 Result2
{error, _} = dev_badge:issue(Result1, ...),     % 错误！应该用 Result3

% 正确：链式传递消息
{ok, Result1} = dev_badge:create_badge(...),
{ok, Result2} = dev_badge:issue(Result1, ...),
{ok, Result3} = dev_badge:issue(Result2, ...),
{error, _} = dev_badge:issue(Result3, ...).
```

## 常见测试陷阱

### 陷阱1：重复函数定义
Erlang 不允许同一模块中有重复的函数定义。编译时会报错：
```
function issue/3 already defined
```
**解决**：删除重复的函数定义。

### 陷阱2：签名验证在测试环境中不可用
`hb_message:signers/2` 在没有完整消息签名基础设施的测试环境中返回空列表，导致签名者显示为 `"anonymous"`。
**解决**：
- 对于测试，使用 `hb_private:set` 直接设置状态
- 不要依赖签名验证进行单元测试

### 陷阱3：测试变量未使用警告
```erlang
{ok, _Result2} = dev_badge:issue(...),  % 警告：未使用变量
{ok, _Result3} = dev_badge:issue(...),
```
**解决**：使用实际变量名来追踪状态流：
```erlang
{ok, Result2} = dev_badge:issue(...),
{ok, Result3} = dev_badge:issue(...),
```

### 陷阱4：使用错误的参数调用 get_state
`get_state/2` 需要 4 个参数（Key, Msg, Default, Opts）：
```erlang
% 错误
State = hb_private:get(<<"state">>, M1),  % 编译错误

% 正确
State = hb_private:get(<<"state">>, M1, not_found, Opts)
```

## 运行测试

### 运行所有测试
```bash
rebar3 eunit
```

### 运行特定模块测试
```bash
rebar3 eunit --module=dev_processor
```

### 运行特定测试
```bash
rebar3 eunit --module=dev_processor --group=name_resolution_test
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Deployment](ao-device-deployment): 部署和加载
