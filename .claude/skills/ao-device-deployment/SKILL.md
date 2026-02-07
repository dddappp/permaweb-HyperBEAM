---
name: ao-device-deployment
description: AO HyperBEAM 设备部署。包含设备加载、远程设备、模块编译、设备签名验证等。部署设备到 HyperBEAM 时参考此技能。
---

# AO HyperBEAM 设备部署指南

本技能涵盖 AO HyperBEAM 设备部署的核心机制和最佳实践。

## 设备加载机制

### load/2 函数

设备加载是 AO 系统的核心功能，支持三种设备类型：

```erlang
%% 加载设备的通用接口
load(ID, Opts) ->
    case ID of
        % 映射配置：内联设备
        Map when is_map(Map) ->
            {ok, Map};
        % 原子：本地模块
        Atom when is_atom(Atom) ->
            try Atom:module_info(), {ok, Atom}
            catch _:_ -> {error, not_loadable}
            end;
        % 二进制 ID：远程设备
        _ when is_binary(ID) ->
            load_remote(ID, Opts)
    end.
```

## 设备类型

### 本地设备

从模块名称加载（设备模块需要在 BEAM 代码路径中）：

```erlang
{ok, MyDevice} = load(my_device, Opts).
```

### 内联设备

从映射配置直接定义设备行为：

```erlang
DeviceMap = #{
    <<"name">> => <<"my-device">>,
    <<"handler">> => fun my_handler/3
},
{ok, DeviceMap} = load(DeviceMap, Opts).
```

### 远程设备

从消息 ID 加载远程编译的设备（需要启用远程加载）：

```erlang
Opts = #{
    load_remote_devices => true,
    trusted_device_signers => [<<"signer-address">>]
},
{ok, Device} = load(<<"device-id-123">>, Opts).
```

## 远程设备加载

### 启用远程设备

```erlang
Opts = #{
    load_remote_devices => true,
    trusted_device_signers => [Signer1, Signer2]
}.
```

### 签名验证

远程设备必须由可信签名者签名：

```erlang
TrustedSigners = hb_opts:get(trusted_device_signers, [], Opts),
Trusted = lists:any(
    fun(Signer) -> lists:member(Signer, TrustedSigners) end,
    hb_message:signers(Msg, Opts)
).
```

### 内容类型验证

远程设备的内容类型必须为 `application/beam`：

```erlang
case hb_maps:get(<<"content-type">>, Msg, undefined, Opts) of
    <<"application/beam">> ->
        {ok, Device};
    Other ->
        {error, {incompatible_content_type, Other}}
end.
```

## 动态模块加载

### 加载 BEAM 字节码

从消息体动态加载编译好的模块：

```erlang
ModName = hb_util:key_to_atom(<<"dev_my_device">>, new_atoms),
Body = hb_maps:get(<<"body">>, Msg, undefined, Opts),
case erlang:load_module(ModName, Body) of
    {module, ModName} ->
        {ok, ModName};
    {error, Reason} ->
        {error, {device_load_failed, Reason}}
end.
```

### 模块信息检查

验证模块是否可加载：

```erlang
try ModName:module_info() of
    _ -> {ok, ModName}
catch
    _:_ -> {error, not_loadable}
end.
```

## 设备兼容性验证

### 检查设备与当前系统的兼容性

```erlang
verify_device_compatibility(Msg, Opts) ->
    Required = extract_requirements(Msg),
    Failed = check_requirements(Required),
    case Failed of
        [] -> ok;
        _ -> {error, {failed_requirements, Failed}}
    end.
```

### 常见要求

```erlang
-define(REQUIREMENTS, [
    {<<"requires-otp">>, erlang:system_info(otp_release)},
    {<<"requires-wordsize">>, erlang:system_info(wordsize)},
    {<<"requires-64bit">>, erlang:system_info({wordsize, 8})}
]).
```

## 设备预加载

### 配置预加载设备

在应用启动时预加载常用设备：

```erlang
PreloadedDevices = [
    #{
        <<"name">> => <<"processor">>,
        <<"module">> => my_device_module
    },
    #{
        <<"name">> => <<"cache">>,
        <<"module">> => another_device_module
    }
],
Opts = #{preloaded_devices => PreloadedDevices}.
```

### 从预加载加载

通过名称引用预加载的设备：

```erlang
load(ID, Opts) when is_binary(ID) ->
    NormKey = hb_ao:normalize_key(ID),
    case lists:search(
        fun (#{ <<"name">> := Name }) -> Name =:= NormKey end,
        hb_opts:get(preloaded_devices, [], Opts)
    ) of
        {value, #{ <<"module">> := Mod }} -> load(Mod, Opts);
        false -> {error, {module_not_admissable, NormKey}}
    end.
```

## 设备打包

### BEAM 编译

```bash
rebar3 compile
```

### 生成设备消息

将编译好的模块打包成消息格式：

```erlang
{ok, DeviceMsg} = hb_message:create(#{
    <<"content-type">> => <<"application/beam">>,
    <<"module-name">> => <<"dev_my_device">>,
    <<"body">> => DeviceBody
}, Opts).
```

### 签名设备

使用私钥签名设备消息：

```erlang
SignedMsg = hb_message:commit(DeviceMsg, #{priv_wallet => Wallet}).
```

## 设备注册

### 默认设备

设置默认设备（用于未指定设备时的回退）：

```erlang
default_device() ->
    my_default_device.
```

### 自定义默认设备

在配置中指定默认设备：

```erlang
DefaultDevice = my_device_module,
Opts = #{default_device => DefaultDevice}.
```

## 设备版本管理

### 版本检查

在设备 info 中声明版本要求：

```erlang
info(_M1, _M2, _Opts) ->
    {ok, #{
        <<"name">> => <<"my-device">>,
        <<"version">> => <<"1.0.0">>,
        <<"requires">> => #{
            <<"hyperbeam">> => <<">=1.0.0">>
        }
    }}.
```

### 兼容性检查

```erlang
check_version(DeviceVersion, Required) ->
    case parse_version(DeviceVersion) of
        {ok, V} when V >= Required -> ok;
        _ -> {error, {incompatible_version, DeviceVersion}}
    end.
```

## 部署最佳实践

### 1. 设备签名

始终签名远程设备以确保安全性：

```erlang
SignedDevice = hb_message:commit(DeviceMsg, #{
    priv_wallet => Wallet,
    signers => [Wallet]
}).
```

### 2. 设置可信签名者

```erlang
Opts = #{
    trusted_device_signers => [
        <<"wallet-address-1">>,
        <<"wallet-address-2">>
    ]
}.
```

### 3. 启用远程加载

```erlang
Opts = #{
    load_remote_devices => true
}.
```

### 4. 验证兼容性

```erlang
Opts = #{
    device_compatibility => [
        {<<"otp">>, erlang:system_info(otp_release)}
    ]
}.
```

## 常见部署错误

### 远程设备禁用

```erlang
{error, remote_devices_disabled} ->
    %% 解决: 在 Opts 中设置 load_remote_devices => true
```

### 签名者不可信

```erlang
{error, device_signer_not_trusted} ->
    %% 解决: 将签名者添加到 trusted_device_signers 列表
```

### 不兼容的内容类型

```erlang
{error, {incompatible_content_type, Other}} ->
    %% 解决: 使用 <<"application/beam">> 内容类型
```

### 设备加载失败

```erlang
{error, {device_load_failed, Reason}} ->
    %% 解决: 检查 Reason 详情并修复
```

## 设备监控

### 加载事件日志

```erlang
?event(device_load, {requested_load, {id, ID}}, Opts),
?event(device_load, {loading_from_cache, {id, ID}}, Opts),
?event(device_load, {verifying_device_trust, {id, ID}}, Opts).
```

### 加载统计

```erlang
Stats = #{
    loaded_count => length(Loaded),
    failed_count => length(Failed),
    load_times => LoadTimes
}.
```

## 部署步骤

### 步骤1: 编译设备

```bash
rebar3 compile
```

### 步骤2: 生成设备消息

```erlang
{ok, DeviceMsg} = create_device_message(my_device_module, Opts).
```

### 步骤3: 签名设备

```erlang
SignedMsg = hb_message:commit(DeviceMsg, #{priv_wallet => Wallet}).
```

### 步骤4: 写入缓存

```erlang
{ok, DeviceID} = hb_cache:write(SignedMsg, Opts).
```

### 步骤5: 验证加载

```erlang
{ok, Device} = load(DeviceID, Opts#{
    load_remote_devices => true,
    trusted_device_signers => [Wallet]
}).
```

## 相关技能

- [AO Device Fundamentals](ao-device-fundamentals): 基础开发概念
- [AO Device Message Handling](ao-device-message-handling): 消息处理
- [AO Device State Management](ao-device-state-management): 状态管理
- [AO Device Testing](ao-device-testing): 测试模式
