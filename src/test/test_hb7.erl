-module(test_hb7).
%% @doc HyperBEAM存储后端测试模块
%% 
%% 本模块测试HyperBEAM的多种存储后端实现及其互操作性，包括：
%% - Gateway存储（hb_store_gateway）：通过Arweave网关访问链上数据
%% - 远程节点存储（hb_store_remote_node）：通过HTTP访问其他HyperBEAM节点
%% - 文件系统存储（hb_store_fs）：本地持久化存储
%% - 内存存储（hb_store_memory）：高性能临时缓存
%% - 多层缓存架构（hb_cache）：统一的缓存抽象层
%% 
%% HyperBEAM采用插件化存储架构，通过统一的存储接口（hb_store行为）
%% 允许节点运营商根据性能、数据可用性等因素灵活选择存储后端。
%% 
%% 存储范围（Scope）概念：
%% - in_memory：内存级别，最快的访问速度
%% - local：本地存储，同节点内的快速访问
%% - remote：远程存储，网络访问，速度较慢
%% - arweave：Arweave区块链存储，最慢但最持久化
%% 
%% 运行方式：rebar3 eunit --module=test_hb7

-include_lib("eunit/include/eunit.hrl").
%% 引入EUnit测试框架的头文件，提供?assertEqual、?debugFmt等测试宏

-include("include/hb.hrl").
%% 引入HyperBEAM项目定义的头文件，包含项目级别的宏定义和类型声明
 
%% Run with: rebar3 eunit --module=test_hb7
%% 使用rebar3命令运行此测试模块的说明注释
 
scope_test() ->
    %% Scope测试：验证不同存储后端的作用域分类
    %% 存储作用域用于决定存储搜索的优先级和策略
    
    %% Gateway存储始终是远程作用域
    %% 因为它需要通过网络访问Arweave网关
    GatewayStore = #{<<"store-module">> => hb_store_gateway},
    ?assertEqual(remote, hb_store_gateway:scope(GatewayStore)),
    %% 验证hb_store_gateway:scope/1函数返回remote
    %% 证明所有网关存储都被归类为远程存储
    ?debugFmt("Gateway store scope: remote", []),
    %% 输出网关存储作用域验证成功的调试信息
    
    %% 远程节点存储也始终是远程作用域
    %% 因为它需要通过HTTP协议访问其他HyperBEAM节点
    RemoteStore = #{
        <<"store-module">> => hb_store_remote_node,
        <<"node">> => <<"http://localhost:8421">>
        %% 配置远程节点的HTTP地址
    },
    ?assertEqual(remote, hb_store_remote_node:scope(RemoteStore)),
    %% 验证hb_store_remote_node:scope/1函数也返回remote
    ?debugFmt("Remote node store scope: remote", []).
    %% 输出远程节点存储作用域验证成功的调试信息
 
gateway_read_test() ->
    %% Gateway读取测试：测试从Arweave网关读取数据
    %% 使用已知的Arweave交易ID进行测试
    
    Store = #{<<"store-module">> => hb_store_gateway},
    %% 创建网关存储配置，指定使用hb_store_gateway模块
    
    %% Known Arweave transaction ID (aos module)
    ID = <<"BOogk_XAI3bvNWnxNxwxmvOfglZt17o4MOVAdPNZ_ew">>,
    %% aos模块的标准Arweave交易ID，用于测试网关读取功能
    %% 这个ID代表aos进程的初始模块代码
    
    try hb_store_gateway:read(Store, ID) of
        {ok, Message} ->
            ?assert(is_map(Message)),
            ?debugFmt("Gateway read success: ~p keys", [maps:size(Message)]),
            ok;
        not_found ->
            ?debugFmt("Gateway read: not_found (ID may not exist)", [])
    catch
        _:_ ->
            ?debugFmt("Gateway read: network unavailable (skipped)", [])
    end.
 
gateway_invalid_id_test() ->
    %% 无效ID测试：验证网关存储正确拒绝无效格式的ID
    %% 无效ID不需要进行网络调用，直接返回not_found
    
    Store = #{<<"store-module">> => hb_store_gateway},
    %% 创建网关存储配置
    
    %% Short key - not a valid ID (should return not_found without network call)
    %% 短键不是有效的43字节Arweave交易ID
    %% hb_store_gateway:read函数会检查ID长度，不符合则直接返回not_found
    ?assertEqual(not_found, hb_store_gateway:read(Store, <<"shortkey">>)),
    ?debugFmt("Invalid ID rejected: OK", []).

    %% Note: Testing non-existent valid-format IDs requires network access
    %% and is covered by gateway_read_test when network is available.

remote_node_basic_test() ->
    %% 远程节点基本测试：测试通过HTTP访问远程节点的存储
    %% 这是HyperBEAM分布式存储的核心功能
    
    %% Setup local store for testing
    %% 创建本地文件系统存储作为测试数据源
    LocalStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-remote-basic">>
        %% 使用hb_store_fs模块，name参数指定存储目录名称
    },
    hb_store:reset(LocalStore),
    %% 重置本地存储，确保测试从干净状态开始
    ?debugFmt("Local store reset: OK", []),
    %% 输出本地存储重置成功的调试信息
    
    %% Create test message
    TestData = #{<<"test-key">> => <<"test-value-", (integer_to_binary(rand:uniform(10000)))/binary>>},
    %% 创建测试数据映射，包含随机生成的值
    %% integer_to_binary将随机数转换为二进制
    ID = hb_message:id(TestData),
    %% 计算测试消息的唯一ID，基于消息内容的SHA256哈希
    ?debugFmt("Test message ID: ~s", [hb_util:encode(ID)]),
    %% 输出消息ID的Base64url编码，便于调试
    
    %% Write to local store
    {ok, ID} = hb_cache:write(TestData, #{store => LocalStore}),
    %% 使用hb_cache:write将测试数据写入本地存储
    %% 返回{ok, ID}表示写入成功
    ?debugFmt("Wrote message to local store", []),
    %% 输出消息写入本地存储成功的调试信息
    
    %% Start HTTP server
    %% 启动HTTP服务器，使本地存储可通过网络访问
    Node = hb_http_server:start_node(#{store => LocalStore}),
    %% 使用hb_http_server:start_node启动节点
    %% 参数指定使用的存储后端为LocalStore
    ?debugFmt("Started HTTP server at: ~s", [Node]),
    %% 输出HTTP服务器启动信息和访问地址
    
    %% Configure remote store
    %% 配置远程存储，指向刚启动的HTTP服务器
    RemoteStore = #{
        <<"store-module">> => hb_store_remote_node,
        <<"node">> => Node
        %% 指定使用hb_store_remote_node模块和远程节点地址
    },
    
    %% Read via remote store
    %% 通过远程存储读取数据
    {ok, Retrieved} = hb_store_remote_node:read(RemoteStore, ID),
    %% 调用远程节点的/~cache@1.0/read端点获取数据
    Loaded = hb_cache:ensure_all_loaded(Retrieved),
    %% 确保所有链接的数据都被加载到缓存中
    ?assert(is_map(Loaded)),
    %% 验证返回结果是映射类型
    ?debugFmt("Remote read success", []),
    %% 输出远程读取成功的调试信息
    
    %% Verify content matches
    %% 验证读取的数据内容与原始数据一致
    ?assertEqual(maps:get(<<"test-key">>, TestData), maps:get(<<"test-key">>, Loaded)),
    %% 比较两个映射中的test-key字段值
    ?debugFmt("Content verified: OK", []).
    %% 输出内容验证成功的调试信息
 
remote_node_not_found_test() ->
    %% 远程节点未找到测试：验证远程存储正确处理不存在的键
    
    LocalStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-remote-notfound">>
    },
    %% 创建本地存储配置
    hb_store:reset(LocalStore),
    %% 重置本地存储
    
    Node = hb_http_server:start_node(#{store => LocalStore}),
    %% 启动HTTP服务器
    RemoteStore = #{
        <<"store-module">> => hb_store_remote_node,
        <<"node">> => Node
    },
    %% 配置远程存储
    
    %% Non-existent key
    %% 尝试读取不存在的键
    ?assertEqual(not_found, hb_store_remote_node:read(RemoteStore, <<"nonexistent">>)),
    %% 验证远程存储对不存在的键返回not_found
    ?debugFmt("Remote not_found: OK", []).
    %% 输出未找到情况处理正确的调试信息
 
local_caching_test() ->
    %% 本地缓存测试：测试远程存储的自动本地缓存功能
    %% 当从远程节点读取数据时，可以自动缓存到本地存储
    
    %% Setup stores
    %% 创建两个存储：一个用于源数据，一个用于缓存
    LocalStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-caching-remote">>
        %% 源数据存储，存储在test-caching-remote目录
    },
    CacheStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-caching-local">>
        %% 缓存存储，存储在test-caching-local目录
    },
    hb_store:reset(LocalStore),
    hb_store:reset(CacheStore),
    %% 重置两个存储
    ?debugFmt("Stores reset: OK", []),
    %% 输出存储重置成功的调试信息
    
    %% Create and store test data
    TestData = #{<<"cached-key">> => <<"cached-value">>},
    %% 创建测试数据
    ID = hb_message:id(TestData),
    %% 计算消息ID
    {ok, ID} = hb_cache:write(TestData, #{store => LocalStore}),
    %% 将测试数据写入源存储
    ?debugFmt("Test data written", []),
    %% 输出测试数据写入的调试信息
    
    %% Start server and configure remote store with caching
    %% 启动HTTP服务器并配置远程存储启用本地缓存
    Node = hb_http_server:start_node(#{store => LocalStore}),
    %% 启动服务器，源数据存储为LocalStore
    RemoteStoreWithCache = #{
        <<"store-module">> => hb_store_remote_node,
        <<"node">> => Node,
        <<"local-store">> => CacheStore
        %% 配置local-store参数启用本地缓存
    },
    
    %% First read - fetches from remote, caches locally
    %% 首次读取：从远程获取数据并自动缓存到本地
    {ok, Msg1} = hb_store_remote_node:read(RemoteStoreWithCache, ID),
    %% 读取请求会从远程节点获取数据
    %% hb_store_remote_node:maybe_cache函数会将数据写入CacheStore
    ?debugFmt("First read (from remote): OK", []),
    %% 输出首次读取的调试信息
    
    %% Verify data was cached locally
    %% 验证数据已被缓存到本地存储
    {ok, CachedMsg} = hb_cache:read(ID, #{store => CacheStore}),
    %% 从本地缓存存储读取数据
    LoadedCached = hb_cache:ensure_all_loaded(CachedMsg),
    %% 确保缓存数据完全加载
    ?assertEqual(<<"cached-value">>, maps:get(<<"cached-key">>, LoadedCached)),
    %% 验证缓存的数据内容正确
    ?debugFmt("Data cached locally: OK", []).
    %% 输出本地缓存验证成功的调试信息
 
maybe_cache_test() ->
    %% 手动缓存测试：测试maybe_cache函数的直接调用
    %% maybe_cache允许手动将数据写入本地缓存
    
    LocalStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-maybe-cache">>
    },
    %% 创建本地存储配置
    hb_store:reset(LocalStore),
    %% 重置存储
    
    StoreOpts = #{<<"local-store">> => LocalStore},
    %% 创建存储选项，指定本地缓存存储
    Data = #{<<"manual-cache-key">> => <<"manual-cache-value">>},
    %% 创建要缓存的数据
    ID = hb_message:id(Data),
    %% 计算数据的唯一ID
    
    %% Manually cache data
    %% 手动缓存数据
    Result = hb_store_remote_node:maybe_cache(StoreOpts, Data),
    %% 直接调用maybe_cache函数，将数据写入本地缓存
    ?assertEqual(ok, Result),
    %% 验证缓存操作返回成功
    ?debugFmt("maybe_cache succeeded", []),
    %% 输出缓存操作成功的调试信息
    
    %% Verify data was cached
    %% 验证数据已被成功缓存
    {ok, Cached} = hb_cache:read(ID, #{store => LocalStore}),
    %% 从本地存储读取缓存的数据
    LoadedCached = hb_cache:ensure_all_loaded(Cached),
    %% 确保数据完全加载
    ?assertEqual(<<"manual-cache-value">>, maps:get(<<"manual-cache-key">>, LoadedCached)),
    %% 验证缓存的数据内容正确
    ?debugFmt("Manual cache verified: OK", []).
    %% 输出手动缓存验证成功的调试信息
 
maybe_cache_with_links_test() ->
    %% 带链接的缓存测试：测试maybe_cache函数的链接功能
    %% 缓存数据时，可以同时创建指向该数据的链接
    
    LocalStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-cache-links">>
    },
    %% 创建本地存储配置
    hb_store:reset(LocalStore),
    %% 重置存储
    
    StoreOpts = #{<<"local-store">> => LocalStore},
    %% 创建存储选项
    Data = #{<<"linked-data">> => <<"linked-value">>},
    %% 创建测试数据
    ID = hb_message:id(Data),
    %% 计算数据ID
    Links = [<<"link1">>, <<"link2">>, ID],
    %% 创建链接列表，包含多个别名
    %% link1和link2是自定义链接名，ID是数据本身的路径
    
    %% Cache with links
    %% 带链接地缓存数据
    Result = hb_store_remote_node:maybe_cache(StoreOpts, Data, Links),
    %% 调用maybe_cache函数，传入链接列表
    %% 函数会创建从各链接到实际数据ID的映射
    ?assertEqual(ok, Result),
    %% 验证操作返回成功
    ?debugFmt("maybe_cache with links succeeded", []),
    %% 输出带链接缓存成功的调试信息
    
    %% Verify data is readable by ID
    %% 验证可以通过ID读取缓存的数据
    {ok, Cached} = hb_cache:read(ID, #{store => LocalStore}),
    %% 通过数据ID读取缓存
    ?assert(is_map(Cached)),
    %% 验证返回结果是映射类型
    ?debugFmt("Cache with links verified: OK", []).
    %% 输出带链接缓存验证成功的调试信息
 
multi_tier_storage_test() ->
    %% 多层存储测试：测试多层存储的按顺序查找功能
    %% HyperBEAM支持配置多个存储后端，按顺序查找直到找到数据
    
    ?debugFmt("=== Multi-Tier Storage Test ===", []),
    %% 输出测试开始标记
    
    %% Setup three tiers
    %% 创建多层存储配置（这里演示两层：内存和文件系统）
    MemoryStore = #{<<"store-module">> => hb_store_memory},
    %% 内存存储，最快但重启后丢失
    FsStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-multi-tier">>
        %% 文件系统存储，持久化但较慢
    },
    hb_store:reset(FsStore),
    %% 重置文件系统存储
    
    %% Write to filesystem tier
    %% 向文件系统层写入测试数据
    TestData = #{<<"tier-key">> => <<"tier-value">>},
    %% 创建测试数据
    ID = hb_message:id(TestData),
    %% 计算消息ID
    {ok, ID} = hb_cache:write(TestData, #{store => FsStore}),
    %% 将数据写入文件系统存储
    ?debugFmt("1. Wrote to filesystem tier", []),
    %% 输出写入完成的调试信息
    
    %% Read through multi-tier
    %% 通过多层存储读取（会依次尝试每个存储）
    Stores = [MemoryStore, FsStore],
    %% 定义存储列表，hb_cache会按顺序尝试
    {ok, Retrieved} = hb_cache:read(ID, #{store => Stores}),
    %% 调用read时指定多个存储
    %% 如果MemoryStore中没有数据，会继续查找FsStore
    Loaded = hb_cache:ensure_all_loaded(Retrieved),
    %% 确保数据完全加载
    ?assertEqual(<<"tier-value">>, maps:get(<<"tier-key">>, Loaded)),
    %% 验证读取的数据内容正确
    ?debugFmt("2. Multi-tier read: OK", []),
    %% 输出多层读取成功的调试信息
    
    %% Not found case
    %% 测试多层存储中数据不存在的情况
    NotFoundResult = hb_cache:read(<<"nonexistent-id">>, #{store => Stores}),
    %% 尝试读取不存在的ID
    ?assertEqual(not_found, NotFoundResult),
    %% 验证返回not_found
    ?debugFmt("3. Multi-tier not_found: OK", []),
    %% 输出多层存储未找到情况处理的调试信息
    
    ?debugFmt("=== Multi-Tier Storage Test Complete ===", []).
    %% 输出测试完成标记
 
complete_workflow_test() ->
    %% 完整工作流测试：集成测试完整的远程存储工作流程
    %% 从创建数据、启动节点、配置远程存储、读取到缓存验证
    
    ?debugFmt("=== Complete Remote Storage Workflow ===", []),
    %% 输出工作流测试开始标记
    
    %% 1. Setup infrastructure
    %% 第一步：设置基础设施
    LocalStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-workflow-source">>
        %% 创建源数据存储
    },
    CacheStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"test-workflow-cache">>
        %% 创建缓存存储
    },
    hb_store:reset(LocalStore),
    hb_store:reset(CacheStore),
    %% 重置两个存储
    ?debugFmt("1. Infrastructure setup complete", []),
    %% 输出基础设施设置完成的调试信息
    
    %% 2. Create original data
    %% 第二步：创建原始数据
    OriginalData = #{
        <<"type">> => <<"test-message">>,
        <<"content">> => <<"Hello from remote storage!">>,
        <<"timestamp">> => erlang:system_time(millisecond)
        %% 创建包含类型、内容和时间戳的消息
    },
    ID = hb_message:id(OriginalData),
    %% 计算消息的唯一ID
    {ok, ID} = hb_cache:write(OriginalData, #{store => LocalStore}),
    %% 将原始数据写入源存储
    ?debugFmt("2. Original data stored, ID: ~s", [hb_util:encode(ID)]),
    %% 输出数据存储完成和ID的调试信息
    
    %% 3. Start remote node
    %% 第三步：启动远程节点
    Node = hb_http_server:start_node(#{store => LocalStore}),
    %% 使用源存储启动HTTP服务器
    %% 外部可以通过HTTP访问这个节点来读取数据
    ?debugFmt("3. Remote node started at: ~s", [Node]),
    %% 输出节点启动和访问地址的调试信息
    
    %% 4. Configure remote store with caching
    %% 第四步：配置带本地缓存的远程存储
    RemoteStore = #{
        <<"store-module">> => hb_store_remote_node,
        <<"node">> => Node,
        <<"local-store">> => CacheStore
        %% 配置远程节点存储，并指定本地缓存
    },
    ?debugFmt("4. Remote store configured with local cache", []),
    %% 输出远程存储配置完成的调试信息
    
    %% 5. Read via remote (triggers caching)
    %% 第五步：通过远程存储读取（触发自动缓存）
    {ok, RemoteMsg} = hb_store_remote_node:read(RemoteStore, ID),
    %% 从远程节点读取数据
    %% 读取过程中会调用maybe_cache将数据写入CacheStore
    LoadedRemote = hb_cache:ensure_all_loaded(RemoteMsg),
    %% 确保数据完全加载
    ?assertEqual(<<"Hello from remote storage!">>, maps:get(<<"content">>, LoadedRemote)),
    %% 验证远程读取的数据内容正确
    ?debugFmt("5. Remote read successful", []),
    %% 输出远程读取成功的调试信息
    
    %% 6. Verify local cache
    %% 第六步：验证本地缓存
    {ok, CachedMsg} = hb_cache:read(ID, #{store => CacheStore}),
    %% 从本地缓存存储读取数据
    LoadedCached = hb_cache:ensure_all_loaded(CachedMsg),
    %% 确保数据完全加载
    ?assertEqual(<<"Hello from remote storage!">>, maps:get(<<"content">>, LoadedCached)),
    %% 验证本地缓存的数据内容与远程读取的一致
    ?debugFmt("6. Local cache verified", []),
    %% 输出本地缓存验证成功的调试信息
    
    %% 7. Verify scope
    %% 第七步：验证远程存储的作用域
    ?assertEqual(remote, hb_store_remote_node:scope(RemoteStore)),
    %% 验证远程节点存储的作用域是remote
    ?debugFmt("7. Scope is remote: OK", []),
    %% 输出作用域验证成功的调试信息
    
    ?debugFmt("=== Complete Workflow Test Passed! ===", []).
    %% 输出完整工作流测试通过的总结信息
