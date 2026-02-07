-module(test_hb5).
%% @doc HyperBEAM 缓存系统单元测试模块
%%
%% 本模块使用 EUnit 测试框架对 HyperBEAM 缓存系统的核心功能进行全面的单元测试。
%% HyperBEAM 的缓存系统是一个基于内容寻址的分布式存储系统，实现了 AO-Core 协议
%% 的消息和计算结果缓存功能。
%%
%% <h2>HyperBEAM 缓存系统核心概念</h2>
%%
%% <h3>1. 内容寻址存储（Content-Addressed Storage）</h3>
%% HyperBEAM 使用消息内容的加密哈希作为唯一标识符（ID）。这意味着：
%% <ul>
%%   <li>相同内容始终产生相同的 ID，实现自动去重</li>
%%   <li>可以验证存储数据的完整性</li>
%%   <li>支持高效的数据共享和复用</li>
%% </ul>
%%
%% <h3>2. 延迟加载（Lazy Loading）</h3>
%% 嵌套消息数据按需加载，而非一次性加载全部：
%% <ul>
%%   <li>只加载实际使用的数据，节省内存</li>
%%   <li>支持深度嵌套的大型消息结构</li>
%%   <li>通过 hb_cache:ensure_all_loaded/2 强制加载全部</li>
%% </ul>
%%
%% <h3>3. 缓存控制（Cache Control）</h3>
%% 支持 HTTP 风格的缓存指令：
%% <ul>
%%   <li><b>always</b> - 强制缓存结果</li>
%%   <li><b>no-store</b> - 禁止缓存结果</li>
%%   <li><b>only-if-cached</b> - 仅从缓存读取</li>
%%   <li><b>no-cache</b> - 禁用缓存查找</li>
%% </ul>
%%
%% <h3>4. 存储后端</h3>
%% HyperBEAM 支持多种存储后端实现：
%% <ul>
%%   <li><b>hb_store_fs</b> - 本地文件系统存储</li>
%%   <li><b>hb_store_lmdb</b> - LMDB 内存映射数据库</li>
%%   <li><b>hb_store_rocksdb</b> - RocksDB 高性能键值存储</li>
%%   <li><b>hb_store_lru</b> - LRU 策略内存缓存</li>
%% </ul>
%%
%% @see hb_cache - 缓存模块，负责消息的读写和加载
%% @see hb_cache_control - 缓存控制模块，处理缓存指令
%% @see hb_store - 存储抽象层，定义统一存储接口
%% @see hb_message - 消息模块，处理消息签名和验证
%% @see hb_test_utils - 测试工具模块，提供测试辅助函数
%% 运行命令: rebar3 eunit --module=test_hb5
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").
 
%% Run with: rebar3 eunit --module=test_hb5
 
%% ====================================================================
%% 测试用例1：基本读写功能测试
%% ====================================================================
%% @doc 测试缓存系统的基础写入和读取功能
%%
%% 本测试验证：
%% <ul>
%%   <li>消息可以正确写入缓存系统</li>
%%   <li>写入后返回唯一的_content-addressed ID</li>
%%   <li>可以通过该ID从缓存中读取原始消息</li>
%% </ul>
%%
%% <b>测试步骤：</b>
%% <ol>
%%   <li>创建隔离的测试存储环境</li>
%%   <li>重置存储确保干净状态</li>
%%   <li>构建包含测试数据的消息映射</li>
%%   <li>调用 hb_cache:write/2 写入消息</li>
%%   <li>使用返回的ID调用 hb_cache:read/2 读取消息</li>
%%   <li>使用 hb_cache:ensure_all_loaded/2 确保加载所有嵌套数据</li>
%%   <li>验证读取的数据与原始数据一致</li>
%% </ol>
%%
%% @see hb_cache:write/2 - 写入消息到缓存，返回内容寻址ID
%% @see hb_cache:read/2 - 根据ID从缓存读取消息
%% @see hb_cache:ensure_all_loaded/2 - 递归加载所有嵌套数据到内存
basic_write_read_test() ->
    %% 步骤1：创建隔离的测试存储实例
    %% 使用 hb_test_utils:test_store() 创建独立的测试存储环境
    %% 每个测试使用独立的存储目录，避免测试间相互干扰
    Store = hb_test_utils:test_store(),
    %% 步骤2：重置存储到初始空状态
    %% 确保测试从干净的环境开始，清除任何历史数据
    hb_store:reset(Store),
    %% 步骤3：构建包含测试数据的消息映射
    %% 消息使用二进制键名，符合 AO-Core 协议规范
    Opts = #{store => Store},
    
    %% 创建测试消息：包含问候语键值对
    Msg = #{<<"greeting">> => <<"Hello, World!">>},
    %% 步骤4：写入消息到缓存
    %% hb_cache:write/2 返回 {ok, ID} 元组，ID是消息内容的SHA-256哈希
    {ok, ID} = hb_cache:write(Msg, Opts),
    %% 输出调试信息，显示生成的内容寻址ID
    ?debugFmt("Written with ID: ~p", [ID]),
    
    %% 步骤5：从缓存读取消息
    %% read/2 返回 {ok, Read}，其中Read可能包含链接而非完整数据
    {ok, Read} = hb_cache:read(ID, Opts),
    %% 步骤6：确保所有嵌套数据完全加载
    %% 对于简单消息，ensure_all_loaded 会递归解析所有链接
    Loaded = hb_cache:ensure_all_loaded(Read, Opts),
    
    %% 步骤7：验证数据完整性
    %% 断言读取的数据与原始消息完全一致
    ?assertEqual(<<"Hello, World!">>, maps:get(<<"greeting">>, Loaded)),
    ?debugFmt("Basic write/read: OK", []).
 
%% ====================================================================
%% 测试用例2：嵌套延迟加载功能测试
%% ====================================================================
%% @doc 测试深度嵌套消息结构的延迟加载功能
%%
%% 本测试验证 HyperBEAM 的核心延迟加载机制：
%% <ul>
%%   <li>嵌套消息数据以链接形式存储，节省内存</li>
%%   <li>按需加载实际使用的嵌套数据</li>
%%   <li>导航到嵌套层级时自动加载对应数据</li>
%% </ul>
%%
%% <b>HyperBEAM 数据存储的三层架构：</b>
%% <ol>
%%   <li><b>原始二进制数据</b> - 以内容哈希为路径存储，有效去重</li>
%%   <li><b>Hashpath 图</b> - 存储路径间链接，支持数据共享</li>
%%   <li><b>消息层</b> - 通过 ID 引用消息，支持已提交和未提交消息</li>
%% </ol>
%%
%% <b>测试场景：</b>
%% 创建三级嵌套结构：Level1 -> Level2 -> Level3，验证导航到最深层时
%% 数据能正确加载。这模拟了真实场景中访问大型嵌套消息的某个叶子节点。
%%
%% @see hb_cache:read/2 - 读取返回包含链接的数据
%% @see hb_cache:ensure_all_loaded/2 - 递归加载所有嵌套数据
%% @see hb_message:commit/3 - 将消息转换为 TABM 格式
nested_lazy_loading_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：创建三级深度嵌套的消息结构
    %% 这种嵌套结构模拟真实场景中的复杂消息类型
    %% 最深层(Level3)包含实际的数据值"treasure"
    %% Level3: 最内层消息，包含最终的值数据
    Level3 = #{<<"value">> => <<"treasure">>},
    %% Level2: 第二层消息，嵌套 Level3
    Level2 = #{<<"nested">> => Level3},
    %% Level1: 最外层消息容器，嵌套 Level2
    Level1 = #{<<"data">> => Level2},
    
    %% 步骤3：将嵌套消息写入缓存
    %% 写入时，HyperBEAM 将消息转换为 Type-Annotated Binary Messages (TABMs)
    {ok, ID} = hb_cache:write(Level1, Opts),
    ?debugFmt("Wrote nested structure with ID: ~p", [ID]),
    
    %% 步骤4：读取消息（返回链接形式）
    %% read/2 返回的消息中，嵌套数据以链接形式表示
    %% 链接包含子消息的 ID 和加载选项，但不包含实际数据
    {ok, Read} = hb_cache:read(ID, Opts),
    
    %% 步骤5：完全加载所有嵌套数据
    %% ensure_all_loaded 递归解析所有链接，将嵌套数据完整加载到内存
    Loaded = hb_cache:ensure_all_loaded(Read, Opts),
    
    %% 步骤6：验证嵌套数据访问
    %% 通过逐层导航访问最深层的数据
    %% 验证延迟加载机制正确工作了
    Data = maps:get(<<"data">>, Loaded),
    Nested = maps:get(<<"nested">>, Data),
    Value = maps:get(<<"value">>, Nested),
    
    %% 断言：验证成功获取到最深层的数据"treasure"
    ?assertEqual(<<"treasure">>, Value),
    ?debugFmt("Nested lazy loading: OK", []).
 
%% ====================================================================
%% 测试用例3：内容去重功能测试
%% ====================================================================
%% @doc 验证内容寻址存储的自动去重功能
%%
%% 本测试验证 HyperBEAM 的核心特性之一：相同内容产生相同的 ID。
%% 这是通过使用加密哈希函数（SHA-256）对消息内容进行哈希实现的。
%%
%% <b>内容寻址存储的优势：</b>
%% <ul>
%%   <li><b>自动去重</b> - 相同数据只存储一次，节省存储空间</li>
%%   <li><b>数据完整性</b> - 通过 ID 可验证数据未被篡改</li>
%%   <li><b>高效共享</b> - 多个用户可引用相同数据，无需重复存储</li>
%%   <li><b>引用一致性</b> - 相同内容始终可通过同一 ID 访问</li>
%% </ul>
%%
%% <b>应用场景：</b>
%% 当多个用户发送相同的消息或请求时，HyperBEAM 自动识别并复用已存储的数据，
%% 大幅提高存储效率和网络带宽利用率。这在高频重复请求场景下效果尤为显著。
%%
%% @see hb_crypto:sha256/1 - SHA-256 哈希函数，用于生成内容 ID
%% @see hb_cache:write/2 - 写入消息，返回内容寻址 ID
deduplication_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：创建测试消息
    %% 消息包含一个键值对，用于测试去重功能
    Msg = #{<<"x">> => <<"same content">>},
    
    %% 步骤3：第一次写入消息
    %% hb_cache:write/2 计算消息内容的 SHA-256 哈希作为 ID
    {ok, ID1} = hb_cache:write(Msg, Opts),
    %% 步骤4：第二次写入完全相同的消息
    %% 由于内容完全相同，生成的 ID 应该与第一次相同
    {ok, ID2} = hb_cache:write(Msg, Opts),
    
    %% 断言：验证两次写入返回相同的 ID
    %% 这是内容寻址存储的核心保证
    ?assertEqual(ID1, ID2),
    ?debugFmt("Deduplication verified: same ID for same content", []).
 
%% ====================================================================
%% 测试用例4：未找到错误处理测试
%% ====================================================================
%% @doc 验证缓存系统对不存在 ID 的正确处理
%%
%% 本测试验证当请求不存在的消息 ID 时，缓存系统返回正确的错误响应。
%% 这确保了系统能够优雅地处理无效请求，而非抛出异常或返回不确定结果。
%%
%% <b>错误处理策略：</b>
%% <ul>
%%   <li><b>返回 not_found 原子</b> - 表示请求的 ID 不存在于缓存中</li>
%%   <li><b>区分不同错误类型</b> - 支持区分"未找到"与其他错误</li>
%%   <li><b>不影响系统状态</b> - 未找到请求不会修改缓存状态</li>
%% </ul>
%%
%% <b>注意事项：</b>
%% 虚假 ID 可能与有效 ID 格式相同但内容不同。hb_util:human_id/1 用于将
%% 256 位二进制数据转换为人类可读的十六进制字符串，便于调试和测试。
%%
%% @see hb_cache:read/2 - 从缓存读取消息，不存在时返回 not_found
%% @see hb_util:human_id/1 - 将二进制 ID 转换为十六进制字符串
not_found_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：构造一个不存在的 ID
    %% 使用 hb_util:human_id/1 创建格式正确的 256 位二进制 ID
    %% 这个 ID 是有效的 SHA-256 格式，但对应的数据不存在于缓存中
    FakeID = hb_util:human_id(<<1:256>>),
    
    %% 步骤3：尝试读取不存在的 ID
    %% hb_cache:read/2 在 ID 不存在时返回原子 not_found
    Result = hb_cache:read(FakeID, Opts),
    
    %% 断言：验证系统正确返回 not_found
    ?assertEqual(not_found, Result),
    ?debugFmt("Not found handling: OK", []).
 
%% ====================================================================
%% 测试用例5：缓存控制 always 指令测试
%% ====================================================================
%% @doc 验证 HTTP 风格缓存控制指令 "always" 的功能
%%
%% 本测试验证缓存系统对 "always" 指令的正确响应：
%% <ul>
%%   <li><b>always</b> - 强制缓存结果，后续请求直接从缓存读取</li>
%% </ul>
%%
%% <b>缓存控制指令工作流程：</b>
%% <ol>
%%   <li>首次请求使用 "always" 指令，结果被缓存</li>
%%   <li>后续请求使用 "only-if-cached" 指令</li>
%%   <li>系统从缓存返回结果，无需重新计算</li>
%% </ol>
%%
%% <b>缓存控制优先级：</b>
%% 缓存设置来源优先级（从高到低）：
%% <ol>
%%   <li>节点操作员配置（Opts） - 拥有最终决定权</li>
%%   <li>结果消息（Msg3） - 设备授予的缓存权限</li>
%%   <li>请求消息（Msg2） - 用户的缓存请求</li>
%% </ol>
%%
%% @see hb_cache_control:maybe_store/4 - 根据缓存控制设置决定是否存储
%% @see hb_cache_control:maybe_lookup/3 - 根据缓存设置决定是否从缓存读取
%% @see hb_ao:resolve/3 - 解析消息并返回结果
cache_control_always_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    
    %% 步骤2：准备测试数据
    %% Msg1: 源消息，包含要解析的数据
    Msg1 = #{<<"key">> => <<"cached-value">>},
    %% Msg2: 请求消息，指定要解析的键
    Msg2 = <<"key">>,
    
    %% 步骤3：首次解析，启用 "always" 缓存控制
    %% 使用 cache_control => [<<"always">>] 强制缓存结果
    Opts1 = #{store => Store, cache_control => [<<"always">>]},
    {ok, Res1} = hb_ao:resolve(Msg1, Msg2, Opts1),
    %% 断言：验证首次解析返回正确结果
    ?assertEqual(<<"cached-value">>, Res1),
    ?debugFmt("Resolved and cached with 'always'", []),
    
    %% 步骤4：后续请求使用 "only-if-cached"
    %% 指示系统仅从缓存读取，不进行网络请求或重新计算
    Opts2 = #{store => Store, cache_control => [<<"only-if-cached">>]},
    {ok, Res2} = hb_ao:resolve(Msg1, Msg2, Opts2),
    %% 断言：验证缓存命中，返回相同结果
    ?assertEqual(<<"cached-value">>, Res2),
    ?debugFmt("Cache hit with 'only-if-cached': OK", []).
 
%% ====================================================================
%% 测试用例6：缓存控制 no-store 指令测试
%% ====================================================================
%% @doc 验证 HTTP 风格缓存控制指令 "no-store" 的功能
%%
%% 本测试验证缓存系统对 "no-store" 指令的正确响应：
%% <ul>
%%   <li><b>no-store</b> - 禁止缓存结果，保护敏感数据</li>
%% </ul>
%%
%% <b>no-store 指令的应用场景：</b>
%% <ul>
%%   <li><b>敏感数据</b> - 防止密码、令牌等敏感信息被缓存</li>
%%   <li><b>动态内容</b> - 每次请求需要最新数据的结果</li>
%%   <li><b>隐私保护</b> - 防止缓存中留下用户操作痕迹</li>
%% </ul>
%%
%% <b>测试说明：</b>
%% 本测试直接调用 hb_cache_control:maybe_store/4 函数，该函数根据缓存控制设置
%% 决定是否存储结果。当遇到 "no-store" 指令时，函数返回 not_caching 原子，
%% 表示不进行缓存操作。
%%
%% @see hb_cache_control:maybe_store/4 - 核心缓存控制决策函数
%% @see hb_cache_control:derive_cache_settings/2 - 从消息和配置派生缓存设置
cache_control_no_store_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：准备测试数据
    %% Msg1: 源消息数据
    Msg1 = #{<<"key">> => <<"value">>},
    %% Msg2: 包含 no-store 缓存控制指令的消息
    Msg2 = #{<<"cache-control">> => [<<"no-store">>]},
    %% Msg3: 解析结果消息
    Msg3 = <<"result">>,
    
    %% 步骤3：调用缓存控制决策函数
    %% maybe_store/4 检查缓存控制设置并决定是否缓存
    %% 遇到 no-store 指令时，返回 not_caching 原子
    Result = hb_cache_control:maybe_store(Msg1, Msg2, Msg3, Opts),
    
    %% 断言：验证 no-store 指令被正确遵守
    ?assertEqual(not_caching, Result),
    ?debugFmt("no-store directive respected: OK", []).
 
%% ====================================================================
%% 测试用例7：列出消息键测试
%% ====================================================================
%% @doc 验证缓存系统列出消息键的功能
%%
%% 本测试验证 hb_cache:list/2 函数能够正确返回消息的所有顶层键。
%% 这在需要了解消息结构或进行消息遍历时非常有用。
%%
%% <b>hb_cache:list/2 功能说明：</b>
%% <ul>
%%   <li>返回消息的所有直接子键</li>
%%   <li>不递归遍历嵌套结构</li>
%%   <li>返回键名为二进制列表</li>
%% </ul>
%%
%% <b>使用场景：</b>
%% <ul>
%%   <li><b>消息探索</b> - 了解消息包含哪些字段</li>
%%   <li><b>数据处理</b> - 动态处理消息的各个字段</li>
%%   <li><b>调试检查</b> - 验证消息结构是否符合预期</li>
%% </ul>
%%
%% @see hb_cache:list/2 - 列出消息的顶层键
%% @see hb_cache:list_numbered/2 - 列出编号键并排序
list_keys_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：创建包含多个键的消息
    %% 消息包含三个键：alpha、beta、gamma
    Msg = #{<<"alpha">> => <<"1">>, <<"beta">> => <<"2">>, <<"gamma">> => <<"3">>},
    %% 步骤3：写入消息到缓存
    {ok, ID} = hb_cache:write(Msg, Opts),
    
    %% 步骤4：列出消息的所有键
    %% hb_cache:list/2 返回消息的所有直接子键
    Keys = hb_cache:list(ID, Opts),
    %% 步骤5：对键进行排序以确保一致性
    %% 因为映射的键顺序可能不确定
    SortedKeys = lists:sort(Keys),
    
    %% 断言：验证返回了所有预期的键
    ?assertEqual([<<"alpha">>, <<"beta">>, <<"gamma">>], SortedKeys),
    ?debugFmt("List keys: OK", []).
 
%% ====================================================================
%% 测试用例8：列出编号键测试
%% ====================================================================
%% @doc 验证缓存系统列出并排序编号键的功能
%%
%% 本测试验证 hb_cache:list_numbered/2 函数能够正确返回消息中所有可解析为
%% 整数的键，并将其转换为排序后的整数列表。
%%
%% <b>hb_cache:list_numbered/2 功能说明：</b>
%% <ul>
%%   <li>筛选键名可解析为整数的键</li>
%%   <li>将二进制键名转换为整数</li>
%%   <li>返回排序后的整数列表</li>
%% </ul>
%%
%% <b>应用场景：</b>
%% <ul>
%%   <li><b>有序数据访问</b> - 处理列表、数组等有序数据结构</li>
%%   <li><b>分页处理</b> - 按编号分页访问消息片段</li>
%%   <li><b>序列验证</b> - 验证消息是否包含连续的编号键</li>
%% </ul>
%%
%% <b>与 hb_cache:list/2 的区别：</b>
%% list/2 返回原始二进制键名，list_numbered/2 额外进行整数转换和排序。
%% 对于处理类似数组的消息结构，list_numbered/2 更加方便。
%%
%% @see hb_cache:list/2 - 列出原始键名
%% @see hb_cache:list_numbered/2 - 列出并排序编号键
%% @see hb_util:number/1 - 将二进制转换为数字
list_numbered_test() ->
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：创建包含非连续编号键的消息
    %% 键名为 "1"、"2"、"5"、"10"，表示四个数据片段
    Msg = #{
        <<"1">> => <<"first">>,
        <<"2">> => <<"second">>,
        <<"5">> => <<"fifth">>,
        <<"10">> => <<"tenth">>
    },
    %% 步骤3：写入消息到缓存
    {ok, ID} = hb_cache:write(Msg, Opts),
    
    %% 步骤4：列出并排序编号键
    %% hb_cache:list_numbered/2 将键名转换为整数并排序
    Numbers = hb_cache:list_numbered(ID, Opts),
    
    %% 断言：验证返回了正确排序的整数列表
    ?assertEqual([1, 2, 5, 10], lists:sort(Numbers)),
    ?debugFmt("List numbered: OK", []).
 
%% ====================================================================
%% 测试用例9：完整工作流程测试
%% ====================================================================
%% @doc 综合验证缓存系统所有核心功能的集成测试
%%
%% 本测试用例整合了前面所有测试的功能点，模拟完整的缓存操作工作流程：
%% <ol>
%%   <li>创建嵌套数据结构</li>
%%   <li>写入缓存获取内容寻址 ID</li>
%%   <li>从缓存读取数据（延迟加载）</li>
%%   <li>完全加载所有嵌套数据</li>
%%   <li>验证数据结构和内容正确性</li>
%%   <li>验证内容寻址去重功能</li>
%% </ol>
%%
%% <b>测试覆盖的功能：</b>
%% <ul>
%%   <li><b>内容寻址存储</b> - 相同内容产生相同 ID</li>
%%   <li><b>延迟加载</b> - 按需加载嵌套数据</li>
%%   <li><b>完整加载</b> - 递归加载所有嵌套数据</li>
%%   <li><b>数据导航</b> - 通过键路径访问嵌套值</li>
%%   <li><b>去重验证</b> - 验证内容寻址一致性</li>
%% </ul>
%%
%% <b>HyperBEAM 缓存系统架构优势：</b>
%% <ul>
%%   <li><b>存储效率</b> - 内容去重减少冗余存储</li>
%%   <li><b>内存效率</b> - 延迟加载避免不必要的数据加载</li>
%%   <li><b>数据一致性</b> - 内容寻址保证数据完整性</li>
%%   <li><b>灵活访问</b> - 支持多种数据访问模式</li>
%% </ul>
complete_workflow_test() ->
    %% 输出测试开始标记
    ?debugFmt("=== Complete Caching Workflow Test ===", []),
    
    %% 步骤1：创建测试存储环境
    Store = hb_test_utils:test_store(),
    hb_store:reset(Store),
    Opts = #{store => Store},
    
    %% 步骤2：创建嵌套数据结构
    %% 模拟真实场景中的复杂消息结构
    %% Inner: 最内层消息，包含秘密值
    Inner = #{<<"secret">> => <<"hidden treasure">>},
    %% Outer: 外层容器消息，嵌套 Inner 和标签
    Outer = #{<<"container">> => Inner, <<"label">> => <<"box">>},
    ?debugFmt("1. Created nested data structure", []),
    
    %% 步骤3：写入缓存
    %% hb_cache:write/2 返回消息的唯一内容寻址 ID
    {ok, ID} = hb_cache:write(Outer, Opts),
    ?debugFmt("2. Cached with ID: ~p", [ID]),
    
    %% 步骤4：从缓存读取（延迟加载）
    %% read/2 返回可能包含链接的数据结构
    {ok, Read} = hb_cache:read(ID, Opts),
    ?debugFmt("3. Read from cache (with links)", []),
    
    %% 步骤5：完全加载所有嵌套数据
    %% ensure_all_loaded/2 递归解析所有链接
    Loaded = hb_cache:ensure_all_loaded(Read, Opts),
    ?debugFmt("4. Fully loaded all nested data", []),
    
    %% 步骤6：验证数据结构
    %% 通过键路径导航访问嵌套数据
    %% 验证最外层标签
    Label = maps:get(<<"label">>, Loaded),
    ?assertEqual(<<"box">>, Label),
    
    %% 访问嵌套容器中的秘密值
    Container = maps:get(<<"container">>, Loaded),
    Secret = maps:get(<<"secret">>, Container),
    ?assertEqual(<<"hidden treasure">>, Secret),
    ?debugFmt("5. Verified nested structure", []),
    
    %% 步骤7：验证内容寻址去重
    %% 写入相同内容应返回相同的 ID
    {ok, ID2} = hb_cache:write(Outer, Opts),
    ?assertEqual(ID, ID2),
    ?debugFmt("6. Verified content-addressed deduplication", []),
    
    %% 测试完成输出
    ?debugFmt("=== All caching tests passed! ===", []).