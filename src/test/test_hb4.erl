%% @doc HyperBEAM 存储抽象层单元测试模块
%% 
%% 本模块使用 EUnit 测试框架对 HyperBEAM 存储抽象层的核心功能进行全面的单元测试。
%% HyperBEAM 的存储系统是一个灵活的多层架构，允许节点运营商根据性能、数据可用性
%% 和其他因素自定义其存储配置。
%% 
%% <h2>HyperBEAM 存储架构概述</h2>
%% 
%% HyperBEAM 的存储抽象层由以下几个核心概念组成：
%% 
%% <h3>1. 存储后端（Storage Backends）</h3>
%% <ul>
%%   <li><b>hb_store_fs</b> - 基于本地文件系统的存储实现</li>
%%   <li><b>hb_store_lmdb</b> - 基于 LMDB 内存映射数据库的存储</li>
%%   <li><b>hb_store_rocksdb</b> - 基于 RocksDB 的高性能 KV 存储</li>
%%   <li><b>hb_store_lru</b> - 基于 LRU 策略的内存缓存，支持持久化</li>
%% </ul>
%% 
%% <h3>2. 统一存储接口（Store Interface）</h3>
%% 所有存储后端都实现 `hb_store` 行为定义的回调函数：
%% <ul>
%%   <li><b>start/1</b> - 初始化存储实例</li>
%%   <li><b>stop/1</b> - 停止存储实例</li>
%%   <li><b>reset/1</b> - 重置存储到初始空状态</li>
%%   <li><b>read/2</b> - 读取指定键的值</li>
%%   <li><b>write/3</b> - 写入键值对</li>
%%   <li><b>make_group/2</b> - 创建组（命名空间/目录）</li>
%%   <li><b>make_link/3</b> - 创建符号链接</li>
%%   <li><b>list/2</b> - 列出组中的键</li>
%%   <li><b>type/2</b> - 获取键的类型（simple 或 composite）</li>
%%   <li><b>resolve/2</b> - 解析链接获取最终目标路径</li>
%% </ul>
%% 
%% <h3>3. 存储链（Store Chains）</h3>
%% 支持配置多个存储后端组成的链，按顺序依次尝试：
%% <ul>
%%   <li>适用于分层存储策略（如本地缓存 + 远程存储）</li>
%%   <li>实现存储的回退（fallback）机制</li>
%%   <li>当第一个存储未命中时，自动查询下一个存储</li>
%% </ul>
%% 
%% <h3>4. 分层数据组织（Groups and Links）</h3>
%% <ul>
%%   <li><b>组（Groups）</b> - 类似文件系统的目录，用于组织相关数据</li>
%%   <li><b>链接（Links）</b> - 符号链接，支持路径重定向和别名</li>
%%   <li>支持递归解析多层链接</li>
%%   <li>支持通过链接访问嵌套组中的数据</li>
%% </ul>
%% 
%% <h2>测试覆盖范围</h2>
%% 本模块测试以下核心功能：
%% <ul>
%%   <li><b>基本读写操作</b> - 验证键值对的写入和读取</li>
%%   <li><b>分层键支持</b> - 验证路径形式的键和组操作</li>
%%   <li><b>符号链接</b> - 验证链接创建和解析</li>
%%   <li><b>存储链回退</b> - 验证多层存储的回退机制</li>
%%   <li><b>LRU 缓存淘汰</b> - 验证缓存容量超限时自动淘汰旧数据</li>
%% </ul>
%% 
%% @see hb_store - 存储抽象层主模块，定义统一接口
%% @see hb_store_fs - 文件系统存储实现
%% @see hb_store_lru - LRU 缓存存储实现
%% @see hb_path - 路径处理工具模块
-module(test_hb4).
%% 包含 EUnit 测试框架的头文件，提供断言宏和环境设置函数
-include_lib("eunit/include/eunit.hrl").
 
%% @spec unique_store(Backend) -> StoreOpts
%% @doc 创建唯一的存储配置用于测试
%% 
%% 此辅助函数生成一个唯一命名的存储配置，避免测试之间的冲突。
%% 每个测试使用唯一的存储名称，确保测试隔离性。
%% 
%% @param Backend 存储模块名称，如 hb_store_fs、hb_store_lru 等
%% @return 存储配置映射，包含 store-module 和 name 键
%% 
%% @example
%% Store = unique_store(hb_store_fs),
%% hb_store:start(Store),
%% hb_store:write(Store, <<"key">>, <<"value">>).
unique_store(Backend) ->
    %% 使用 erlang:unique_integer/1 生成唯一标识符
    %% [positive] 选项确保生成的整数为正数
    Id = integer_to_binary(erlang:unique_integer([positive])),
    %% 构建存储配置映射
    %% <<"store-module">> 指定存储后端模块
    %% <<"name">> 指定存储实例名称，格式为 "cache-TEST/<唯一ID>"
    #{
        <<"store-module">> => Backend,
        <<"name">> => <<"cache-TEST/", Id/binary>>
    }.
 
%% @spec basic_rw_test() -> ok | eunit:test_result()
%% @doc 测试基本读写操作
%% 
%% 本测试验证存储抽象层的基本键值读写功能：
%% <ol>
%%   <li>创建唯一文件存储实例</li>
%%   <li>写入键值对</li>
%%   <li>验证读取返回正确值</li>
%%   <li>验证读取不存在的键返回 not_found</li>
%%   <li>清理测试数据</li>
%% </ol>
%% 
%% 这是存储层最基础的功能测试，确保 write/read 配对操作正常工作。
%% 
%% @see hb_store:write/3
%% @see hb_store:read/2
basic_rw_test() ->
    %% 创建唯一的文件系统存储实例
    Store = unique_store(hb_store_fs),
    %% 调用 hb_store:start/1 初始化存储
    %% 对于文件系统存储，这会确保数据目录存在
    hb_store:start(Store),
    
    %% 定义测试键和值
    Key = <<"test-key">>,
    Value = <<"test-value">>,
    
    %% 断言写入操作成功，返回原子 ok
    ?assertEqual(ok, hb_store:write(Store, Key, Value)),
    %% 断言读取操作返回 {ok, Value} 元组
    ?assertEqual({ok, Value}, hb_store:read(Store, Key)),
    %% 断言读取不存在的键返回原子 not_found
    ?assertEqual(not_found, hb_store:read(Store, <<"missing">>)),
    
    %% 调用 hb_store:reset/1 清理测试数据
    %% 对于文件系统存储，这会删除整个数据目录并重新创建
    hb_store:reset(Store).
 
%% @spec hierarchical_test() -> ok | eunit:test_result()
%% @doc 测试分层键（组）操作
%% 
%% 本测试验证存储层对分层键的支持，类似于文件系统中的目录结构。
%% 
%% 功能验证：
%% <ul>
%%   <li>创建组（目录）</li>
%%   <li>写入嵌套键值对</li>
%%   <li>列出组内容</li>
%%   <li>验证键类型（composite 或 simple）</li>
%% </ul>
%% 
%% 分层键使用列表表示路径，如 [<<"users">>, <<"alice">>] 表示
%% users/alice 这样的嵌套路径。
%% 
%% @see hb_store:make_group/2
%% @see hb_store:type/2
%% @see hb_store:list/2
hierarchical_test() ->
    %% 创建唯一的文件系统存储实例
    Store = unique_store(hb_store_fs),
    hb_store:start(Store),
    
    %% 创建名为 <<"users">> 的组（目录）
    %% 组类型的数据在 type/2 查询时返回 composite
    ok = hb_store:make_group(Store, <<"users">>),
    %% 断言查询 <<"users">> 的类型返回 composite
    ?assertEqual(composite, hb_store:type(Store, <<"users">>)),
    
    %% 写入嵌套项到组中
    %% 路径 [<<"users">>, <<"alice">>] 表示 users/alice
    ok = hb_store:write(Store, [<<"users">>, <<"alice">>], <<"data1">>),
    ok = hb_store:write(Store, [<<"users">>, <<"bob">>], <<"data2">>),
    
    %% 列出组中的内容
    {ok, Items} = hb_store:list(Store, <<"users">>),
    %% 断言组中包含 2 个条目
    ?assertEqual(2, length(Items)),
    %% 断言组中包含 alice 条目
    ?assert(lists:member(<<"alice">>, Items)),
    
    %% 清理测试数据
    hb_store:reset(Store).
 
%% @spec symlink_test() -> ok | eunit:test_result()
%% @doc 测试符号链接功能
%% 
%% 本测试验证存储层的符号链接（symlink）功能：
%% <ul>
%%   <li>创建原始数据项</li>
%%   <li>创建指向原始数据的符号链接</li>
%%   <li>通过链接读取数据</li>
%%   <li>解析链接获取原始路径</li>
%% </ul>
%% 
%% 符号链接机制允许：
%% <ul>
%%   <li>数据别名和重命名</li>
%%   <li>路径重定向</li>
%%   <li>避免数据复制，节省存储空间</li>
%% </ul>
%% 
%% @see hb_store:make_link/3
%% @see hb_store:resolve/2
symlink_test() ->
    %% 创建唯一的文件系统存储实例
    Store = unique_store(hb_store_fs),
    hb_store:start(Store),
    
    %% 创建原始数据项
    ok = hb_store:write(Store, <<"original">>, <<"content">>),
    %% 创建符号链接，从 <<"original">> 到 <<"alias">>
    %% make_link/3 的参数顺序：Existing 是目标，New 是链接名
    ok = hb_store:make_link(Store, <<"original">>, <<"alias">>),
    
    %% 通过链接读取数据，应返回原始内容
    {ok, <<"content">>} = hb_store:read(Store, <<"alias">>),
    
    %% 解析链接获取原始路径
    <<"original">> = hb_store:resolve(Store, <<"alias">>),
    
    %% 清理测试数据
    hb_store:reset(Store).
 
%% @spec chain_fallback_test() -> ok | eunit:test_result()
%% @doc 测试存储链回退机制
%% 
%% 本测试验证存储链（Store Chains）的回退功能：
%% 当配置多个存储后端时，系统会按顺序尝试每个存储，直到操作成功。
%% 
%% 测试场景：
%% <ul>
%%   <li>创建两个独立的存储实例</li>
%%   <li>仅向第二个存储写入数据</li>
%%   <li>通过存储链读取，应回退到第二个存储</li>
%% </ul>
%% 
%% 存储链的典型应用场景：
%% <ul>
%%   <li>本地缓存 + 远程存储的回退</li>
%%   <li>内存缓存 + 持久化存储</li>
%%   <li>热数据 + 冷数据的分层存储</li>
%% </ul>
%% 
%% @note 存储链是一个列表，按顺序依次尝试
%% @see hb_store:read/2
chain_fallback_test() ->
    %% 创建第一个存储实例（主存储）
    Store1 = unique_store(hb_store_fs),
    %% 创建第二个存储实例（备用存储）
    Store2 = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"cache-TEST/chain-backup">>
    },
    
    %% 初始化两个存储实例
    hb_store:start(Store1),
    hb_store:start(Store2),
    
    %% 仅向 Store2 写入数据
    hb_store:write(Store2, <<"key">>, <<"in-backup">>),
    
    %% 创建存储链 [Store1, Store2]
    %% 读取时先查询 Store1，未找到则回退到 Store2
    Chain = [Store1, Store2],
    %% 断言通过链读取返回 Store2 中的数据
    ?assertEqual({ok, <<"in-backup">>}, hb_store:read(Chain, <<"key">>)),
    
    %% 清理两个存储实例
    hb_store:reset(Store1),
    hb_store:reset(Store2).
 
%% @spec lru_eviction_test() -> ok | eunit:test_result()
%% @doc 测试 LRU 缓存淘汰机制
%% 
%% 本测试验证 hb_store_lru 模块的最近最少使用（LRU）缓存淘汰策略：
%% <ul>
%%   <li>当缓存容量不足时，自动淘汰最旧的数据</li>
%%   <li>被访问的数据会被标记为最近使用</li>
%%   <li>淘汰的数据会持久化到后备存储</li>
%% </ul>
%% 
%% LRU 存储的工作原理：
%% <ul>
%%   <li>使用 ETS 表实现高性能内存缓存</li>
%%   <li>维护访问顺序索引，支持快速淘汰判断</li>
%%   <li>超出容量时，淘汰最早访问的条目</li>
%%   <li>可配置持久化存储，用于数据恢复</li>
%% </ul>
%% 
%% 测试步骤：
%% <ol>
%%   <li>创建持久化存储作为后备</li>
%%   <li>创建 LRU 存储，容量设为 500 字节</li>
%%   <li>写入 200 字节的数据（key1, key2, key3）</li>
%%   <li>由于容量限制，key2 应被淘汰</li>
%%   <li>验证 key1 仍在缓存中（被访问过）</li>
%% </ol>
%% 
%% @see hb_store_lru
%% @see hb_store_lru:start/1
lru_eviction_test() ->
    %% 创建持久化存储配置（后备存储）
    PersistentStore = #{
        <<"store-module">> => hb_store_fs,
        <<"name">> => <<"cache-TEST/lru-persist">>
    },
    %% 创建 LRU 存储配置
    LRUStore = #{
        <<"store-module">> => hb_store_lru,
        <<"name">> => <<"test-evict">>,
        <<"capacity">> => 500,  % 设置很小的容量，仅 500 字节
        <<"persistent-store">> => PersistentStore  %% 指定持久化后备
    },
    
    %% 启动 LRU 存储
    {ok, _} = hb_store_lru:start(LRUStore),
    
    %% 生成 200 字节的随机测试数据
    Data = crypto:strong_rand_bytes(200),
    %% 写入 key1（使用 200 字节，剩余容量 300）
    hb_store_lru:write(LRUStore, <<"key1">>, Data),
    %% 写入 key2（使用 200 字节，剩余容量 100）
    hb_store_lru:write(LRUStore, <<"key2">>, Data),
    %% 读取 key1，将其标记为最近使用
    hb_store_lru:read(LRUStore, <<"key1">>),
    %% 写入 key3（需要 200 字节，但只有 100 容量）
    %% 此时应触发淘汰：淘汰 key2（最久未使用）
    hb_store_lru:write(LRUStore, <<"key3">>, Data),
    
    %% 断言 key1 仍在缓存中
    ?assertEqual({ok, Data}, hb_store_lru:read(LRUStore, <<"key1">>)),
    
    %% 停止 LRU 存储并清理持久化存储
    hb_store_lru:stop(LRUStore),
    hb_store:reset(PersistentStore).