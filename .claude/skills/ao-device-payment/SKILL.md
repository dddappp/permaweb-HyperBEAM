---
name: ao-device-payment
description: AO HyperBEAM 支付系统开发。包含 P4 支付协议、Simple Pay 定价、FAFF 免费访问控制等。开发计费系统时参考此技能。
---

# AO HyperBEAM 支付系统开发指南

本技能涵盖 AO HyperBEAM 支付和计费系统的核心机制和最佳实践。

## P4 支付协议

### 模块导出验证

```erlang
code:ensure_loaded(dev_p4),

true = erlang:function_exported(dev_p4, request, 3),
true = erlang:function_exported(dev_p4, response, 3),
true = erlang:function_exported(dev_p4, balance, 3).
```

## Simple Pay 定价

### 操作员免费访问

```erlang
Wallet = ar_wallet:new(),
Address = hb_util:human_id(ar_wallet:to_address(Wallet)),

NodeMsg = #{
    operator => Address,
    simple_pay_price => 10
},

Req = hb_message:commit(
    #{<<"path">> => <<"/test">>},
    #{priv_wallet => Wallet}
),

{ok, Price} = dev_simple_pay:estimate(
    #{},
    #{<<"request">> => Req},
    NodeMsg
),

0 = Price.
```

### 非操作员通用定价

```erlang
ClientWallet = ar_wallet:new(),
OperatorWallet = ar_wallet:new(),
OperatorAddress = hb_util:human_id(ar_wallet:to_address(OperatorWallet)),

NodeMsg = #{
    operator => OperatorAddress,
    simple_pay_price => 10
},

Req = hb_message:commit(
    #{<<"path">> => <<"/test">>},
    #{priv_wallet => ClientWallet}
),

{ok, Price} = dev_simple_pay:estimate(
    #{},
    #{<<"request">> => Req},
    NodeMsg
),

Price > 0.
```

### 余额查询

```erlang
ClientWallet = ar_wallet:new(),
ClientAddress = hb_util:human_id(ar_wallet:to_address(ClientWallet)),

NodeMsg = #{
    simple_pay_ledger => #{ClientAddress => 500}
},

Req = hb_message:commit(
    #{<<"path">> => <<"/balance">>},
    #{priv_wallet => ClientWallet}
),

{ok, Balance} = dev_simple_pay:balance(#{}, Req, NodeMsg),

500 = Balance.
```

### 新用户默认余额

```erlang
NewWallet = ar_wallet:new(),

NodeMsg = #{
    simple_pay_ledger => #{}
},

Req = hb_message:commit(
    #{<<"path">> => <<"/balance">>},
    #{priv_wallet => NewWallet}
),

{ok, Balance} = dev_simple_pay:balance(#{}, Req, NodeMsg),

0 = Balance.
```

## FAFF 访问控制

### 白名单允许访问

```erlang
Wallet = ar_wallet:new(),
Address = hb_util:human_id(ar_wallet:to_address(Wallet)),

Req = hb_message:commit(
    #{<<"action">> => <<"test">>},
    #{priv_wallet => Wallet}
),

Msg = #{<<"request">> => Req},

NodeMsg = #{faff_allow_list => [Address]},

{ok, Price} = dev_faff:estimate(unused, Msg, NodeMsg),

0 = Price.
```

### 白名单外用户被阻止

```erlang
Wallet = ar_wallet:new(),

Req = hb_message:commit(
    #{<<"action">> => <<"test">>},
    #{priv_wallet => Wallet}
),

Msg = #{<<"request">> => Req},

NodeMsg = #{faff_allow_list => []},

{ok, Price} = dev_faff:estimate(unused, Msg, NodeMsg),

<<"infinity">> = Price.
```

### FAFF 计费

```erlang
Req = #{<<"action">> => <<"test">>},
NodeMsg = #{},

{ok, Result} = dev_faff:charge(unused, Req, NodeMsg),

true = Result.
```

## 完整支付工作流

```erlang
complete_payment_workflow_test() ->
    %% 设置
    OperatorWallet = ar_wallet:new(),
    OperatorAddress = hb_util:human_id(ar_wallet:to_address(OperatorWallet)),
    ClientWallet = ar_wallet:new(),
    ClientAddress = hb_util:human_id(ar_wallet:to_address(ClientWallet)),

    NodeMsg = #{
        operator => OperatorAddress,
        simple_pay_price => 10,
        simple_pay_ledger => #{ClientAddress => 100}
    },

    %% 1. 检查初始余额
    BalanceReq = hb_message:commit(#{}, #{priv_wallet => ClientWallet}),
    {ok, Balance1} = dev_simple_pay:balance(#{}, BalanceReq, NodeMsg),
    100 = Balance1,

    %% 2. 估计请求价格
    Req = hb_message:commit(
        #{<<"path">> => <<"/compute">>},
        #{priv_wallet => ClientWallet}
    ),
    {ok, Price} = dev_simple_pay:estimate(
        #{},
        #{<<"request">> => Req},
        NodeMsg
    ),
    Price > 0,

    %% 3. 操作员免费访问
    OperatorReq = hb_message:commit(
        #{<<"path">> => <<"/compute">>},
        #{priv_wallet => OperatorWallet}
    ),
    {ok, OperatorPrice} = dev_simple_pay:estimate(
        #{},
        #{<<"request">> => OperatorReq},
        NodeMsg
    ),
    0 = OperatorPrice.
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
