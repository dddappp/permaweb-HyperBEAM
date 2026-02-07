---
name: ao-device-extensions
description: AO HyperBEAM 扩展机制开发。包含 Hook 钩子系统、Router 路由器、Meta 信息管理、Relay 中继调用等。开发系统扩展时参考此技能。
---

# AO HyperBEAM 扩展机制开发指南

本技能涵盖 AO HyperBEAM 扩展机制的核心机制和最佳实践。

## Meta 信息管理

### 节点配置信息

```erlang
Node = your_http_server:start_node(#{
    test_config => <<"my_value">>
}),

{ok, Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),

<<"my_value">> = hb_ao:get(<<"test_config">>, Info, #{}).
```

### 构建信息

```erlang
Node = your_http_server:start_node(#{}),

{ok, NodeName} = hb_http:get(Node, <<"/~meta@1.0/build/node">>, #{}),

<<"HyperBEAM">> = NodeName.
```

## Router 路由器

### 路由配置

```erlang
Routes = [
    #{<<"template">> => <<"/api/*">>, <<"node">> => <<"api-server">>},
    #{<<"template">> => <<"*">>, <<"node">> => <<"fallback">>}
],

{ok, _} = your_router_device:route(
    #{<<"path">> => <<"/api/users">>},
    #{routes => Routes}
).
```

## Relay 中继调用

### 调用请求

```erlang
Peer = your_http_server:start_node(#{
    priv_wallet => ar_wallet:new()
}),

{ok, Res} = hb_ao:resolve(
    #{
        <<"device">> => <<"relay@1.0">>,
        <<"method">> => <<"GET">>,
        <<"path">> => <<"/~meta@1.0/build/node">>,
        <<"peer">> => Peer
    },
    <<"call">>,
    #{}
).
```

### 异步调用

```erlang
Peer = your_http_server:start_node(#{
    priv_wallet => ar_wallet:new()
}),

Start = erlang:monotonic_time(millisecond),
{ok, <<"OK">>} = hb_ao:resolve(
    #{
        <<"device">> => <<"relay@1.0">>,
        <<"method">> => <<"GET">>,
        <<"path">> => <<"/~meta@1.0/info">>,
        <<"peer">> => Peer
    },
    <<"cast">>,
    #{}
),
Duration = erlang:monotonic_time(millisecond) - Start,

Duration < 100.
```

## Hook 钩子系统

### 执行钩子

```erlang
Handler1 = #{
    <<"device">> => #{
        <<"test">> => fun(_, Req, _) ->
            {ok, Req#{<<"h1">> => true}}
        end
    }
},
Handler2 = #{
    <<"device">> => #{
        <<"test">> => fun(_, Req, _) ->
            {ok, Req#{<<"h2">> => true}}
        end
    }
},

Opts = #{on => #{<<"test">> => [Handler1, Handler2]}},
{ok, Result} = your_hook_device:on(<<"test">>, #{<<"input">> => true}, Opts),

true = maps:get(<<"h1">>, Result),
true = maps:get(<<"h2">>, Result).
```

### 错误停止

```erlang
Handler1 = #{
    <<"device">> => #{
        <<"test">> => fun(_, Req, _) -> {ok, Req#{<<"h1">> => true}} end
    end
},
Handler2 = #{
    <<"device">> => #{
        <<"test">> => fun(_, _, _) -> {error, <<"Halted">>} end
    end
},
Handler3 = #{
    <<"device">> => #{
        <<"test">> => fun(_, Req, _) -> {ok, Req#{<<"h3">> => true}} end
    end
},

Opts = #{on => #{<<"test">> => [Handler1, Handler2, Handler3]}},
{error, <<"Halted">>} = your_hook_device:on(<<"test">>, #{}, Opts).
```

### 可用钩子类型

| 钩子名 | 触发时机 | 请求/结果说明 |
|--------|----------|---------------|
| `start` | 节点启动 | Req/body: 初始配置 |
| `request` | HTTP 请求接收 | Req/body: 待评估消息序列 |
| `step` | 每条消息评估后 | Req/body: 评估结果 |
| `response` | HTTP 响应发送 | Req/body: 响应消息 |

## 完整基础设施测试

```erlang
complete_infrastructure_test() ->
    %% 1. 启动带钩子的节点
    Parent = self(),
    RequestHook = #{
        <<"device">> => #{
            <<"request">> => fun(_, Req, _) ->
                Parent ! {hook, request},
                {ok, Req}
            end
        }
    },

    Node = your_http_server:start_node(#{
        priv_wallet => ar_wallet:new(),
        on => #{<<"request">> => RequestHook}
    }),

    %% 2. 获取节点信息
    {ok, _Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),

    %% 3. 验证钩子执行
    receive
        {hook, request} -> ok
    after 100 ->
        error(hook_timeout)
    end,

    %% 4. 获取构建信息
    {ok, <<"HyperBEAM">>} = hb_http:get(Node, <<"/~meta@1.0/build/node">>, #{}).
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device Containers](ao-device-containers): 容器设备开发
- [AO Device Testing](ao-device-testing): 测试模式
