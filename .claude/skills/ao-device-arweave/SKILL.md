---
name: ao-device-arweave
description: AO HyperBEAM Arweave 集成开发。包含 Arweave 网络交互、ANS-104 编解码、GraphQL 查询、数据复制、清单管理等。开发 Arweave 集成时参考此技能。
---

# AO HyperBEAM Arweave 集成开发指南

本技能涵盖 AO HyperBEAM 与 Arweave 集成的核心机制和最佳实践。

## Arweave 网络交互

### 核心功能

Arweave 集成设备通常提供以下功能：

```erlang
%% 发送交易到 Arweave 网络
{ok, TxID} = your_arweave_device:tx(TransactionMsg, #{}, Opts),

%% 获取区块信息
{ok, Block} = your_arweave_device:block(BlockHeight, #{}, Opts),

%% 获取当前网络状态
{ok, Current} = your_arweave_device:current(#{}, Opts),

%% 查询交易状态
{ok, Status} = your_arweave_device:status(TxID, #{}, Opts).
```

## ANS-104 格式

### 内容类型

ANS-104 是 Arweave 的标准化数据格式：

```erlang
{ok, ContentType} = your_ans104_device:content_type(#{}),
<<"application/ans104">> = ContentType.
```

### 消息转换

在消息格式和 ANS-104 之间转换：

```erlang
Msg = #{<<"key">> => <<"value">>, <<"data">> => <<"test data">>},

%% 转换为 ANS-104 TX 格式
{ok, TX} = your_ans104_device:to(Msg, #{}, #{}),
is_tuple(TX),
tx = element(1, TX),

%% 从 ANS-104 TX 恢复消息
{ok, TABM} = your_ans104_device:from(TX, #{}, #{}),
is_map(TABM),
<<"value">> = maps:get(<<"key">>, TABM).
```

### 序列化与反序列化

```erlang
Msg = #{<<"test">> => <<"data">>},
{ok, TX} = your_ans104_device:to(Msg, #{}, #{}),

%% 序列化为二进制用于传输
{ok, Binary} = your_ans104_device:serialize(TX, #{}, #{}),
is_binary(Binary),
byte_size(Binary) > 0.

%% 从二进制恢复
{ok, Restored} = your_ans104_device:deserialize(Binary, #{}, #{}),
is_map(Restored).
```

### 签名与验证

```erlang
Wallet = ar_wallet:new(),
Msg = #{<<"key">> => <<"value">>},

%% 签名消息
Signed = hb_message:commit(
    Msg,
    #{priv_wallet => Wallet},
    #{<<"commitment-device">> => <<"ans104@1.0">>}
),

true = maps:is_key(<<"commitments">>, Signed),

%% 验证签名
{ok, true} = your_ans104_device:verify(Signed, #{}, #{}).
```

## 查询引擎

### 查询类型

Arweave 查询设备支持多种查询方式：

```erlang
%% 获取所有匹配的交易
{ok, AllResults} = your_query_device:all(QueryMsg, #{}, Opts),

%% 基础查询
{ok, BaseResults} = your_query_device:base(QueryMsg, #{}, Opts),

%% 精确匹配查询
{ok, ExactResults} = your_query_device:only(QueryMsg, #{}, Opts),

%% GraphQL 查询
{ok, GraphQLResults} = your_query_device:graphql(QueryMsg, #{}, Opts).
```

### 查询配置信息

```erlang
Info = your_query_device:info(#{}),
true = maps:is_key(default, Info),
true = maps:is_key(excludes, Info),

Excludes = maps:get(excludes, Info),
true = lists:member(<<"keys">>, Excludes).
```

### 查询结果检测

```erlang
%% 有结果的情况
JSONWithResults = hb_json:encode(#{
    <<"data">> => #{
        <<"transactions">> => #{
            <<"edges">> => [#{<<"node">> => #{<<"id">> => <<"123">>}}]
        }
    }
}),
{ok, true} = your_query_device:has_results(#{"body" => JSONWithResults}, #{}, #{}),

%% 无结果的情况
JSONEmpty = hb_json:encode(#{
    <<"data">> => #{
        <<"transactions">> => #{<<"edges">> => []}
    }
}),
{ok, false} = your_query_device:has_results(#{"body" => JSONEmpty}, #{}, #{}).
```

## 数据复制

### 复制功能

从 Arweave 复制数据到本地：

```erlang
%% 通过 GraphQL 复制数据
{ok, Result} = your_copycat_device:graphql(QueryMsg, #{}, Opts),

%% 直接从 Arweave 复制
{ok, CopiedData} = your_copycat_device:arweave(TxID, #{}, Opts).
```

## 清单管理

### 清单功能

Arweave 清单（Manifest）提供统一的资源访问接口：

```erlang
%% 获取清单信息
Info = your_manifest_device:info(#{}),
true = maps:is_key(default, Info),
true = maps:is_key(excludes, Info),

%% 索引清单
{ok, Indexed} = your_manifest_device:index(ManifestMsg, #{}, Opts).
```

## 完整数据处理工作流

```erlang
complete_data_workflow_test() ->
    %% 1. 创建消息
    Msg = #{
        <<"type">> => <<"Document">>,
        <<"title">> => <<"Test Document">>,
        <<"data">> => <<"Document content here">>
    },

    %% 2. 使用 ANS-104 格式签名消息
    Wallet = ar_wallet:new(),
    Signed = hb_message:commit(
        Msg,
        #{priv_wallet => Wallet},
        #{<<"commitment-device">> => <<"ans104@1.0">>}
    ),
    true = maps:is_key(<<"commitments">>, Signed),

    %% 3. 转换为 TX 记录
    {ok, TX} = your_ans104_device:to(Signed, #{}, #{}),
    is_tuple(TX),

    %% 4. 序列化传输
    {ok, Binary} = your_ans104_device:serialize(TX, #{}, #{}),
    is_binary(Binary),

    %% 5. 反序列化恢复
    {ok, Restored} = your_ans104_device:deserialize(Binary, #{}, #{}),
    is_map(Restored),

    %% 6. 签名验证
    {ok, true} = your_ans104_device:verify(Signed, #{}, #{}).
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device Codecs](ao-device-codecs): 编解码器开发
- [AO Device State Management](ao-device-state-management): 状态管理
