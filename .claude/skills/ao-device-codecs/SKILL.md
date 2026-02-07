---
name: ao-device-codecs
description: AO HyperBEAM 编解码器开发。包含 HTTPSig 签名、TABM 结构化编码、JSON 编解码、扁平化转换、ANS-104 格式等。开发数据格式转换设备时参考此技能。
---

# AO HyperBEAM 编解码器开发指南

本技能涵盖 AO HyperBEAM 编解码器开发的核心机制和最佳实践。

## HTTP 签名（HTTPSig）

### RSA-PSS 数字签名

```erlang
Wallet = ar_wallet:new(),
Msg = #{<<"data">> => <<"test">>},

%% 签名消息
{ok, Signed} = your_httpsig_device:commit(
    Msg,
    #{<<"type">> => <<"rsa-pss-sha512">>},
    #{priv_wallet => Wallet}
),

%% 验证签名
true = hb_message:verify(Signed, all, #{}).
```

### HMAC 消息认证码

```erlang
Secret = hb_util:encode(crypto:strong_rand_bytes(64)),
Msg = #{<<"data">> => <<"test">>},

{ok, Signed} = your_httpsig_device:commit(
    Msg,
    #{<<"type">> => <<"hmac-sha256">>, <<"secret">> => Secret},
    #{}
).
```

## 结构化类型编码（TABM）

### 编码为 TABM 格式

TABM 保留 Erlang/Erlang 数据类型信息：

```erlang
Msg = #{
    <<"count">> => 42,
    <<"name">> => <<"test">>,
    <<"module">> => my_handler
},

{ok, TABM} = your_structured_device:from(Msg, #{}, #{}),
true = maps:is_key(<<"ao-types">>, TABM).
```

### 从 TABM 解码

```erlang
{ok, Decoded} = your_structured_device:to(TABM, #{}, #{}),
42 = maps:get(<<"count">>, Decoded).
```

## JSON 编解码

### 编码为 JSON

```erlang
Msg = #{
    <<"name">> => <<"Alice">>,
    <<"age">> => 30,
    <<"items">> => [1, 2, 3]
},

{ok, JSON} = your_json_device:to(Msg, #{}, #{}),
is_binary(JSON).
```

### 从 JSON 解码

```erlang
{ok, Decoded} = your_json_device:from(JSON, #{}, #{}),
<<"Alice">> = maps:get(<<"name">>, Decoded).
```

## 扁平化转换

### 嵌套转扁平

```erlang
Nested = #{
    <<"db">> => #{
        <<"host">> => <<"localhost">>,
        <<"port">> => <<"5432">>
    }
},

{ok, Flat} = your_flat_device:to(Nested, #{}, #{}),
<<"localhost">> = maps:get(<<"db/host">>, Flat).
```

### 扁平转嵌套

```erlang
{ok, Unflat} = your_flat_device:from(Flat, #{}, #{}),
<<"localhost">> = hb_ao:get(<<"db/host">>, Unflat, #{}).
```

## ANS-104 格式

### 消息转换

```erlang
Msg = #{<<"key">> => <<"value">>},

{ok, TX} = your_ans104_device:to(Msg, #{}, #{}),
tx = element(1, TX),

{ok, TABM} = your_ans104_device:from(TX, #{}, #{}).
```

### 序列化与签名

```erlang
Wallet = ar_wallet:new(),
Signed = hb_message:commit(
    Msg,
    #{priv_wallet => Wallet},
    #{<<"commitment-device">> => <<"ans104@1.0">>}
),

{ok, Binary} = your_ans104_device:serialize(TX, #{}, #{}),
is_binary(Binary),

{ok, true} = your_ans104_device:verify(Signed, #{}, #{}).
```

## 完整编解码工作流

```erlang
complete_codec_workflow_test() ->
    %% 1. 创建包含丰富类型的消息
    Msg = #{
        <<"type">> => <<"transfer">>,
        <<"amount">> => 1000,
        <<"recipient">> => <<"alice@example.com">>
    },

    %% 2. 转换为结构化格式（保留类型）
    {ok, Structured} = your_structured_device:from(Msg, #{}, #{}),

    %% 3. 签名消息
    Wallet = ar_wallet:new(),
    {ok, Signed} = your_httpsig_device:commit(
        Structured,
        #{<<"type">> => <<"rsa-pss-sha512">>},
        #{priv_wallet => Wallet}
    ),

    %% 4. 序列化为 JSON（HTTP 传输）
    {ok, Response} = your_json_device:serialize(Signed, #{}, #{}),
    <<"application/json">> = maps:get(<<"content-type">>, Response),

    %% 5. 验证签名
    true = hb_message:verify(Signed, all, #{}).
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
