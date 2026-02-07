-module(test_hb8).
% -module(test_protocol).

%% @doc HyperBEAM AO-Core协议测试模块
%% 
%% 本测试模块验证HyperBEAM系统中AO-Core协议的核心功能，包括：
%% 1. 消息解析与状态管理（counter_test）
%% 2. 设备加载与查询机制（device_test）
%% 3. 直接键访问与计算访问的区分（access_test）
%% 
%% HyperBEAM架构概述：
%% - AO-Core协议是HyperBEAM的核心协议，负责处理去中心化消息的执行
%% - 每个消息都关联一个设备（Device），设备定义了消息中各个键的解析逻辑
%% - 消息解析器（hb_ao模块）负责执行设备函数并返回结果
%% - 存储层（hb_store模块）提供多级存储支持：本地缓存、网关存储、远程节点存储
%% 
%% 存储架构说明：
%% - Local Caching（本地缓存）：最快的存储层，使用内存或文件系统存储常用数据
%% - Gateway Store（网关存储）：通过Arweave网关和GraphQL接口访问远程数据
%% - Remote Node Store（远程节点存储）：从其他AO节点获取数据，支持分布式数据访问
%% - 这些存储层协同工作，实现弹性数据访问策略

-include_lib("eunit/include/eunit.hrl").

%% @doc 测试用例：计数器状态管理功能
%% 
%% 本测试验证AO-Core协议的基本状态管理能力：
%% - 使用消息作为状态容器，消息中的键值对即为状态数据
%% - 通过hb_ao:resolve/3函数解析消息中的键值
%% - 通过"set"操作修改消息状态，实现状态转换
%% - 支持链式操作，多个操作按顺序执行
%% 
%% 测试流程：
%% 1. 初始化状态消息，包含count和name两个键
%% 2. 读取count键的初始值（应为0）
%% 3. 使用set操作将count修改为1
%% 4. 验证count值已更新为1
%% 5. 链式执行多个set操作，最终值应为最后一次设置的值
%% 
%% 注意：在AO-Core中，状态变更通过返回新消息实现，而不是原地修改
counter_test() ->
    %% 初始化状态消息
    %% 消息是AO-Core中的基本数据单元，每个消息包含一组键值对
    %% 这里创建一个包含计数器状态的消息，count为计数值，name为名称
    State = #{
        <<"count">> => 0,
        <<"name">> => <<"My Counter">>
    },
    
    %% 使用hb_ao:resolve/3解析count键的值
    %% hb_ao:resolve是AO-Core的核心函数，负责执行设备函数并返回结果
    %% 第一个参数是基础消息（Base Message），包含状态数据
    %% 第二个参数是请求消息（Request Message），指定要解析的路径(path)
    %% 第三个参数是选项映射，控制解析行为（如缓存、远程设备加载等）
    %% 路径以"/"开头表示直接读取消息中的键值，否则作为设备函数调用
    {ok, 0} = hb_ao:resolve(
        State, 
        #{<<"path">> => <<"/count">>}, 
        #{}
    ),
    
    %% 使用"set"操作修改消息状态
    %% "set"是dev_message设备的内置函数，用于创建新的消息副本
    %% 请求消息中指定要设置的键值对（<<"count">> => 1）
    %% hb_ao:resolve返回{ok, NewMessage}，其中NewMessage是更新后的消息
    %% 注意：AO-Core采用不可变数据模式，不修改原消息，而是返回新消息
    {ok, State2} = hb_ao:resolve(
        State,
        #{<<"path">> => <<"set">>, <<"count">> => 1},
        #{}
    ),
    
    %% 验证状态更新
    %% 再次解析count键，验证值已更新为1
    {ok, 1} = hb_ao:resolve(
        State2,
        #{<<"path">> => <<"/count">>},
        #{}
    ),
    
    %% 使用hb_ao:resolve_many/2执行链式操作
    %% 该函数按顺序执行一系列消息解析，将前一个操作的结果作为下一个操作的输入
    %% 这模拟了多个操作连续执行的场景
    %% 最终结果中count应为20（最后一次set操作的值）
    {ok, Final} = hb_ao:resolve_many([
        State,
        #{<<"path">> => <<"set">>, <<"count">> => 10},
        #{<<"path">> => <<"set">>, <<"count">> => 20}
    ], #{}),
    
    %% 使用hb_ao:get/2直接获取消息中的键值
    %% 这是一个便捷函数，用于从消息中提取键值，无需通过设备解析
    %% 注意：此函数直接读取消息映射，与hb_ao:resolve的设备解析机制不同
    20 = hb_ao:get(<<"count">>, Final).

%% @doc 测试用例：设备加载与查询功能
%% 
%% 本测试验证HyperBEAM设备系统的核心功能：
%% - 设备是AO-Core协议的核心概念，定义了消息键的解析逻辑
%% - 每个设备是一个Erlang模块或映射，包含一组处理函数
%% - 设备可以通过ID（Arweave交易ID）或模块名加载
%% - 设备可以指定info函数返回设备的元数据（导出列表、处理器等）
%% 
%% 设备类型：
%% - 模块设备：Erlang模块，直接调用模块函数
%% - 映射设备：Erlang映射，键可以是函数或字面量
%% - 远程设备：通过Arweave ID加载的设备模块
%% 
%% 设备解析流程：
%% 1. 从消息中获取device键的值（设备ID）
%% 2. 使用hb_ao_device:load/2加载设备模块
%% 3. 使用hb_ao_device:info/3获取设备信息
%% 4. 检查键是否被设备导出（is_exported）
device_test() ->
    %% 验证默认设备是dev_message
    %% 默认设备用于处理消息的基本功能（get、set、keys等）
    %% 当消息没有指定device键时，使用默认设备
    %% dev_message是AO-Core内置的基础设备，提供标准消息操作
    ?assertEqual(dev_message, hb_ao_device:default()),
    
    %% 使用hb_ao_device:load/2加载设备
    %% 如果设备是模块名，直接返回模块原子
    %% 如果设备是映射，返回该映射本身
    %% 如果设备是Arweave ID，根据配置尝试从网络加载
    {ok, Mod} = hb_ao_device:load(dev_message, #{}),
    ?assertEqual(dev_message, Mod),
    
    %% 获取设备信息
    %% hb_ao_device:info/3返回设备的元数据映射
    %% 设备信息可能包含：
    %% - exports: 设备导出的键列表
    %% - excludes: 设备不处理的键列表
    %% - handler: 全局处理函数
    %% - default: 默认处理函数
    %% - default_mod: 默认设备模块
    Info = hb_ao_device:info(dev_message, #{}, #{}),
    ?assert(is_map(Info)),
    
    %% 验证键是否被设备导出
    %% hb_ao_device:is_exported/4检查指定键是否属于设备的导出函数
    %% 导出函数是设备愿意处理的键，非导出函数不会被设备调用
    %% 创建一个测试消息，包含data键
    Msg = #{<<"data">> => <<"test">>},
    ?assertEqual(true, hb_ao_device:is_exported(
        Msg, dev_message, <<"get">>, #{}
    )).

%% @doc 测试用例：直接键访问与计算访问的区分
%% 
%% 本测试验证设备访问模式的区分机制：
%% - 直接键访问（Direct Key Access）：直接从消息映射中读取键值，不执行设备函数
%% - 计算访问（Computed Access）：执行设备函数获取结果，可能涉及复杂计算
%% 
%% 区分依据：
%% - 如果键在消息中存在字面量值，且不在设备的导出函数列表中，则为直接访问
%% - 如果键是设备的导出函数（如get、set等），则为计算访问
%% 
%% 性能考量：
%% - 直接键访问通常更快，因为无需执行设备函数
%% - 对于频繁访问的数据，直接访问模式可以提高性能
%% 
%% 应用场景：
%% - 配置数据、元数据等静态数据适合直接访问
%% - 计算密集型操作、需要状态变更的操作适合计算访问
access_test() ->
    %% 创建基础消息
    %% 指定使用message@1.0设备，包含data键的字面量值
    Base = #{
        <<"device">> => <<"message@1.0">>,
        <<"data">> => <<"value">>
    },
    
    %% 验证"data"键是直接键访问
    %% "data"是消息中的字面量键，不在dev_message的导出函数列表中
    %% 因此is_direct_key_access返回true，表示可以直接读取
    ?assertEqual(true, hb_ao_device:is_direct_key_access(
        Base, 
        #{<<"path">> => <<"data">>}, 
        #{}
    )),
    
    %% 验证"get"键是计算访问（不是直接键访问）
    %% "get"是dev_message设备的导出函数，用于获取消息中的键值
    %% 调用get函数会执行设备逻辑，因此不是直接键访问
    ?assertEqual(false, hb_ao_device:is_direct_key_access(
        Base,
        #{<<"path">> => <<"get">>},  %% 'get' is a function
        #{}
    )).
