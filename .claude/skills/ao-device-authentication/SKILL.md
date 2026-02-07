---
name: ao-device-authentication
description: AO HyperBEAM 认证系统开发。包含 HTTP Basic 认证、Cookie 认证、Secret 密钥管理等。开发认证系统时参考此技能。
---

# AO HyperBEAM 认证系统开发指南

本技能涵盖 AO HyperBEAM 认证系统的核心机制和最佳实践。

## Auth Hook

### 模块功能

认证钩子用于在请求处理前后进行身份验证：

```erlang
%% 认证钩子模块的基本接口
{ok, Result} = your_auth_hook_device:request(AuthMsg, #{}, #{}).
```

## HTTP Basic 认证

### 生成认证密钥

```erlang
Credentials = base64:encode(<<"user:password">>),
Req = #{<<"authorization">> => <<"Basic ", Credentials/binary>>},

{ok, Key} = your_http_auth_device:generate(#{}, Req, #{}),
is_binary(Key),
byte_size(Key) > 0.
```

### 缺失认证头处理

```erlang
Result = your_http_auth_device:generate(#{}, #{}, #{}),

{error, #{<<"status">> := 401, <<"www-authenticate">> := <<"Basic">>}} = Result.
```

### 消息签名提交

```erlang
Credentials = base64:encode(<<"user:password">>),
Base = #{<<"data">> => <<"test message">>},
Req = #{<<"authorization">> => <<"Basic ", Credentials/binary>>},

{ok, Signed} = your_http_auth_device:commit(Base, Req, #{}),
true = maps:is_key(<<"commitments">>, Signed).
```

## Cookie 认证

### 消息签名提交

```erlang
Base = #{<<"data">> => <<"test">>},

{ok, Signed} = your_cookie_auth_device:commit(Base, #{}, #{}),
true = maps:is_key(<<"commitments">>, Signed),

Commitments = maps:get(<<"commitments">>, Signed),
1 = map_size(Commitments).
```

### 生成认证密钥

```erlang
{ok, Result} = your_cookie_auth_device:generate(#{}, #{}, #{}),

true = maps:is_key(<<"secret">>, Result),
Secrets = maps:get(<<"secret">>, Result),
is_list(Secrets),
1 = length(Secrets).
```

## Cookie 编解码

### 解析 Cookie 字符串

```erlang
Msg = #{<<"cookie">> => <<"key1=value1; key2=value2">>},

{ok, Cookies} = your_cookie_device:extract(Msg, #{}, #{}),

<<"value1">> = maps:get(<<"key1">>, Cookies),
<<"value2">> = maps:get(<<"key2">>, Cookies).
```

### Cookie 存储

```erlang
Base = #{},
Req = #{
    <<"session">> => <<"abc123">>,
    <<"user">> => <<"john">>
},

{ok, Updated} = your_cookie_device:store(Base, Req, #{}),

{ok, Cookies} = your_cookie_device:extract(Updated, #{}, #{}),
<<"abc123">> = maps:get(<<"session">>, Cookies),
<<"john">> = maps:get(<<"user">>, Cookies).
```

### 获取指定 Cookie

```erlang
Opts = hb_private:opts(#{}),
Base = hb_private:set(#{}, <<"cookie">>, #{
    <<"session">> => <<"abc123">>
}, Opts),

Req = #{<<"key">> => <<"session">>},

{ok, Cookie} = your_cookie_device:get_cookie(Base, Req, #{}),

<<"abc123">> = Cookie.
```

## Secret 密钥管理

### 密钥操作

密钥管理设备提供以下功能：

```erlang
%% 生成新密钥
{ok, Generated} = your_secret_device:generate(#{}, #{}, #{}),

%% 导入密钥
{ok, Imported} = your_secret_device:import(KeyData, #{}, #{}),

%% 列出密钥
{ok, KeyList} = your_secret_device:list(#{}, #{}, #{}),

%% 提交密钥更改
{ok, Committed} = your_secret_device:commit(KeyMsg, #{}, #{}),

%% 导出密钥
{ok, Exported} = your_secret_device:export(KeyID, #{}, #{}).
```

## 完整认证工作流

```erlang
complete_auth_workflow_test() ->
    %% 1. HTTP Basic 认证流程
    Credentials = base64:encode(<<"alice:secret123">>),
    AuthReq = #{<<"authorization">> => <<"Basic ", Credentials/binary>>},

    {ok, Key} = your_http_auth_device:generate(#{}, AuthReq, #{}),
    is_binary(Key),

    %% 2. 使用 HTTP 认证签名消息
    Message = #{<<"action">> => <<"transfer">>, <<"amount">> => 100},
    {ok, SignedHttp} = your_http_auth_device:commit(Message, AuthReq, #{}),
    true = maps:is_key(<<"commitments">>, SignedHttp),

    %% 3. Cookie 认证流程
    {ok, SignedCookie} = your_cookie_auth_device:commit(Message, #{}, #{}),
    true = maps:is_key(<<"commitments">>, SignedCookie),

    %% 4. 提取并重用 Cookie
    {ok, Cookies} = your_cookie_device:extract(SignedCookie, #{}, #{}),
    SecretKeys = [K || <<"secret-", _/binary>> = K <- maps:keys(Cookies)],
    length(SecretKeys) > 0.
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
- [AO Device Codecs](ao-device-codecs): 编解码器开发
