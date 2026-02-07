%%% @doc test_dev5：HyperBEAM缓存、查找与本地名称服务测试模块
%%%
%%% 本模块测试HyperBEAM的核心存储与查找功能，包括：
%%% - 缓存读写操作——测试hb_cache模块的读写功能
%%% - 消息查找服务——测试dev_lookup对消息ID的解析和获取
%%% - 本地名称注册——测试dev_local_name的命名服务功能
%%% - 名称解析器——测试dev_name的名称解析机制
%%%
%%% 这些组件构成了HyperBEAM的数据访问层：
%%% - 缓存（Cache）提供高速临时数据存储
%%% - 查找（Lookup）支持按ID检索消息
%%% - 名称服务（Local Name）提供易记的名称映射
%%%
%%% 运行方式：rebar3 eunit --module=test_dev5
-module(test_dev5).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% ============================================================
%% 缓存读写测试
%% ============================================================
%% @doc 测试用例：缓存基本读写功能
%%%
%%% 本测试验证缓存系统的核心读写操作：
%%% 1. 创建包含键值对的消息
%%% 2. 将消息写入缓存获取路径标识
%%% 3. 通过路径从缓存读取消息
%%% 4. 验证读取内容与原始数据一致
%%%
%%% 缓存机制说明：
%%% - hb_cache:write/2将消息存入缓存并返回唯一路径标识
%%% - 路径标识可用于后续的消息检索
%%% - 缓存支持内存、文件系统等多种后端存储
cache_write_read_test() ->
    Opts = #{store => hb_test_utils:test_store()},
    %% 创建测试选项配置
    %% 指定使用测试专用的存储后端
    %% test_store提供干净的测试环境，避免污染生产数据

    %% 写入数据
    TestData = #{<<"key">> => <<"value">>},
    %% 创建测试数据映射
    %% 包含单个键值对，用于验证缓存的读写功能

    {ok, Path} = hb_cache:write(TestData, Opts),
    %% 将测试数据写入缓存
    %% hb_cache:write/2参数说明：
    %%   第一个参数：要缓存的消息数据
    %%   第二个参数：缓存选项配置
    %% 返回值：{ok, Path}，Path是缓存数据的唯一路径标识
    %% 路径格式为Base64编码的字符串，可用于后续检索

    %% 读取数据
    Request = #{<<"target">> => Path},
    %% 创建读取请求
    %% 指定要检索的目标路径

    {ok, ReadData} = dev_cache:read(#{}, Request, Opts),
    %% 从缓存读取数据
    %% dev_cache:read/3参数说明：
    %%   第一个参数：消息1（空映射）
    %%   第二个参数：读取请求，包含target字段指定目标路径
    %%   第三个参数：选项配置
    %% 返回值：{ok, ReadData}，ReadData是缓存的消息内容

    ?assert(hb_message:match(TestData, ReadData, only_present, Opts)),
    %% 验证读取数据与原始数据匹配
    %% hb_message:match/4执行消息匹配检查
    %%   第一个参数：期望的原始数据
    %%   第二个参数：实际读取的数据
    %%   第三个参数：匹配模式（only_present要求数据存在即可）
    %%   第四个参数：选项配置
    %% 匹配成功表示缓存读写功能正常

    ?debugFmt("Cache write/read: OK", []).
    %% 输出调试信息，标记测试通过

%% ============================================================
%% 缓存二进制数据测试
%% ============================================================
%% @doc 测试用例：缓存二进制数据读写
%%%
%%% 本测试验证缓存系统对原始二进制数据的支持：
%%% 1. 创建原始二进制数据
%%% 2. 将二进制数据写入缓存
%%% 3. 从缓存读取二进制数据
%%% 4. 验证读取内容与原始数据完全一致
%%%
%%% 二进制数据用途：
%%% - 存储WASM模块字节码
%%% - 存储文件内容或媒体数据
%%% - 存储任意序列化的二进制格式
cache_binary_test() ->
    Opts = #{store => hb_test_utils:test_store()},
    %% 创建测试选项，使用专用测试存储

    %% 写入二进制数据
    BinaryData = <<"raw binary content">>,
    %% 创建测试用的原始二进制数据
    %% 模拟WASM模块、文件内容等二进制资源

    {ok, Path} = hb_cache:write(BinaryData, Opts),
    %% 将二进制数据写入缓存
    %% 二进制数据作为消息体直接存储
    %% 返回唯一路径标识

    %% 读取二进制数据
    {ok, ReadData} = hb_cache:read(Path, Opts),
    %% 从缓存读取二进制数据
    %% hb_cache:read/2参数说明：
    %%   第一个参数：缓存路径标识
    %%   第二个参数：选项配置
    %% 返回值：{ok, ReadData}，ReadData是原始二进制内容

    ?assertEqual(BinaryData, ReadData),
    %% 验证读取的二进制数据与原始数据完全一致
    %% 二进制数据以字节为单位精确比较

    ?debugFmt("Cache binary: OK", []).
    %% 输出调试信息

%% ============================================================
%% 基本查找测试
%% ============================================================
%% @doc 测试用例：消息ID基本查找功能
%%%
%%% 本测试验证查找服务的基本消息检索能力：
%%% 1. 创建测试消息并写入缓存
%%% 2. 获取消息的唯一ID
%%% 3. 使用ID从查找服务检索消息
%%% 4. 验证检索结果与原始消息一致
%%%
%%% 查找服务架构：
%%% - dev_lookup提供统一的消息查询接口
%%%
%%% 消息ID生成：
%%%
%%% 消息写入缓存时自动生成唯一标识符
lookup_basic_test() ->
    %% 写入消息
    Msg = #{<<"test-key">> => <<"test-value">>},
    %% 创建测试消息
    %% 包含单个键值对用于验证查找功能

    {ok, ID} = hb_cache:write(Msg, #{}),
    %% 将消息写入缓存并获取消息ID
    %% 消息ID是基于消息内容计算的哈希值
    %% 确保相同消息具有相同的唯一标识

    %% 查找消息
    {ok, Retrieved} = dev_lookup:read(
        #{},
        #{<<"target">> => ID},
        #{}
    ),
    %% 通过消息ID检索消息
    %% dev_lookup:read/3参数说明：
    %%   第一个参数：消息1（空映射）
    %%   第二个参数：查找请求，指定target为消息ID
    %%   第三个参数：选项配置（空）
    %% 返回值：{ok, Retrieved}，Retrieved是检索到的消息

    ?assert(hb_message:match(Msg, Retrieved)),
    %% 验证检索到的消息与原始消息匹配
    %% 默认匹配模式检查所有字段是否一致

    ?debugFmt("Lookup basic: OK", []).
    %% 输出调试信息

%% ============================================================
%% AOS-2格式查找测试
%% ============================================================
%% @doc 测试用例：AOS-2格式响应查找
%%%
%%% 本测试验证查找服务的格式协商功能：
%%% 1. 创建测试消息并写入缓存
%%% 2. 指定AOS-2格式作为响应类型
%%% 3. 使用AOS-2格式检索消息
%%% 4. 验证响应包含正确的Content-Type和消息体
%%%
%%% AOS-2格式说明：
%%% - application/aos-2是AOS进程的标准消息格式
%%% - 响应包含body和content-type字段
%%% - 适用于AOS进程间的消息交换
lookup_aos2_format_test() ->
    %% 写入消息
    Msg = #{<<"data">> => <<"test-data">>},
    %% 创建测试消息

    {ok, ID} = hb_cache:write(Msg, #{}),
    %% 将消息写入缓存获取ID

    %% 使用AOS-2格式查找
    {ok, Response} = dev_lookup:read(
        #{},
        #{
            <<"target">> => ID,
            <<"accept">> => <<"application/aos-2">>
        },
        #{}
    ),
    %% 使用AOS-2格式检索消息
    %% accept字段指定期望的响应格式
    %% dev_lookup根据请求的格式返回相应结果

    ?assert(maps:is_key(<<"body">>, Response)),
    %% 验证响应包含body字段
    %% AOS-2格式的消息体包含实际消息内容

    ?assertEqual(<<"application/aos-2">>, maps:get(<<"content-type">>, Response)),
    %% 验证响应的Content-Type正确
    %% 确认服务器正确处理了格式协商

    ?debugFmt("Lookup AOS-2: OK", []).
    %% 输出调试信息

%% ============================================================
%% 查找不存在消息测试
%% ============================================================
%% @doc 测试用例：查找不存在消息的错误处理
%%%
%%% 本测试验证查找服务对无效ID的处理：
%%% 1. 使用不存在的消息ID进行查找
%%% 2. 验证返回标准的not_found错误
%%%
%%% 错误处理规范：
%%% - 对于不存在的资源返回404状态码
%%% - 错误格式遵循API错误响应规范
lookup_not_found_test() ->
    {error, not_found} = dev_lookup:read(
        #{},
        #{<<"target">> => <<"nonexistent-id">>},
        #{}
    ),
    %% 尝试查找不存在的消息ID
    %% 预期返回{error, not_found}错误元组
    %% 这验证了错误处理逻辑的正确性

    ?debugFmt("Lookup not found: OK", []).
    %% 输出调试信息

%% ============================================================
%% 本地名称注册测试
%% ============================================================
%% @doc 测试用例：本地名称注册功能
%%%
%%% 本测试验证本地名称服务的注册能力：
%%% 1. 创建新钱包用于身份标识
%%% 2. 准备名称注册请求
%%% 3. 调用名称注册接口
%%% 4. 验证注册成功返回确认消息
%%%
%%% 本地名称用途：
%%% - 为复杂ID提供易记的别名
%%% - 支持进程间引用和路由
%%% - 可用于配置管理和服务发现
local_name_register_test() ->
    Wallet = ar_wallet:new(),
    %% 创建新钱包
    %% 钱包用于身份认证和消息签名
    %% 名称注册需要有效的钱包身份

    Opts = #{priv_wallet => Wallet},
    %% 创建选项配置，包含私钥
    %% 私钥用于对注册操作进行签名

    %% 注册名称
    Req = hb_message:commit(
        #{
            <<"key">> => <<"test-name">>,
            <<"value">> => <<"test-value">>
        },
        Opts
    ),
    %% 提交名称注册请求
    %% hb_message:commit/2对请求进行签名
    %%   第一个参数：注册数据，包含key（名称）和value（值）
    %%   第二个参数：选项配置（包含私钥）
    %% 返回签名后的请求消息

    {ok, <<"Registered.">>} = dev_local_name:register(#{}, Req, Opts),
    %% 执行名称注册
    %% dev_local_name:register/3参数说明：
    %%   第一个参数：消息1（空映射）
    %%   第二个参数：签名后的注册请求
    %%   第三个参数：选项配置
    %% 返回值：{ok, "Registered."}确认注册成功

    ?debugFmt("Local name register: OK", []).
    %% 输出调试信息

%% ============================================================
%% 本地名称查找测试
%% ============================================================
%% @doc 测试用例：本地名称查找功能
%%%
%%% 本测试验证本地名称服务的查询能力：
%%% 1. 配置预定义的名称映射
%%% 2. 使用名称查找对应的值
%%% 3. 验证返回正确的映射结果
%%%
%%% 名称查找应用场景：
%%% - 进程别名解析
%%% - 服务端点发现
%%% - 配置键名映射
local_name_lookup_test() ->
    %% 使用预定义名称配置
    Opts = #{
        local_names => #{
            <<"my-process">> => <<"process-id-123">>
        }
    },
    %% 创建包含预定义名称的选项配置
    %% local_names映射提供名称到值的转换
    %% 此配置模拟本地名称数据库

    %% 查找名称
    LookupReq = #{<<"key">> => <<"my-process">>},
    %% 创建查找请求，指定要查询的名称

    {ok, Value} = dev_local_name:lookup(#{}, LookupReq, Opts),
    %% 执行名称查找
    %% dev_local_name:lookup/3参数说明：
    %%   第一个参数：消息1（空映射）
    %%   第二个参数：查找请求，指定key字段
    %%   第三个参数：包含local_names的配置选项
    %% 返回值：{ok, Value}，Value是对应的实际值

    ?assertEqual(<<"process-id-123">>, Value),
    %% 验证查找结果与预期值一致

    ?debugFmt("Local name lookup: OK", []).
    %% 输出调试信息

%% ============================================================
%% 名称不存在测试
%% ============================================================
%% @doc 测试用例：查找不存在的名称
%%%
%%% 本测试验证名称服务对无效名称的错误处理：
%%% 1. 尝试查询不存在的名称
%%% 2. 验证返回not_found错误
local_name_not_found_test() ->
    {error, not_found} = dev_local_name:lookup(
        #{},
        #{<<"key">> => <<"nonexistent">>},
        #{}
    ),
    %% 尝试查找不存在的名称
    %% 预期返回{error, not_found}错误

    ?debugFmt("Local name not found: OK", []).
    %% 输出调试信息

%% ============================================================
%% 名称解析器测试
%% ============================================================
%% @doc 测试用例：名称解析器信息结构
%%%
%%% 本测试验证名称解析器（dev_name）的信息接口：
%%% 1. 获取解析器的信息结构
%%% 2. 验证包含必要的配置字段
%%%
%%% 名称解析器架构：
%%% - dev_name提供统一的名称解析接口
%%% - 支持配置默认解析器和排除列表
name_resolver_test() ->
    %% 创建模拟解析器
    MockResolver = #{
        <<"device">> => #{
            <<"lookup">> => fun(_, Req, Opts) ->
                Key = hb_ao:get(<<"key">>, Req, Opts),
                %% 从请求中提取key字段
                %% hb_ao:get/3用于安全获取嵌套值

                Names = #{
                    <<"alice">> => <<"alice-id">>,
                    <<"bob">> => <<"bob-id">>
                },
                %% 创建模拟的名称映射
                %% 模拟简单的名称到ID的转换

                case maps:get(Key, Names, not_found) of
                    not_found ->
                        {error, not_found};
                        %% 名称不存在返回错误

                    Value ->
                        {ok, Value}
                        %% 找到则返回对应的值
                end
            end
        }
    },
    %% 创建模拟解析器配置
    %% 包含设备定义和自定义查找函数
    %% 模拟实际名称解析器的行为

    %% 验证信息结构
    Info = dev_name:info(#{}),
    %% 获取名称解析器的信息结构
    %% dev_name:info/1返回解析器的元信息
    %% 参数为空映射表示获取默认信息

    ?assert(maps:is_key(default, Info)),
    %% 验证信息包含default字段
    %% default指定默认使用的解析器

    ?assert(maps:is_key(excludes, Info)),
    %% 验证信息包含excludes字段
    %% excludes列出不支持的操作

    ?debugFmt("Name resolver: OK", []).
    %% 输出调试信息

%% ============================================================
%% 完整存储工作流测试
%% ============================================================
%% @doc 测试用例：完整存储工作流
%%%
%%% 本测试验证HyperBEAM存储系统的完整工作流程：
%%% 1. 写入配置数据到缓存
%%% 2. 通过查找服务检索数据
%%% 3. 注册易记的名称别名
%%% 4. 通过名称查找原始数据
%%%
%%% 此测试模拟典型的数据访问场景：
%%% - 用户存储配置信息
%%% - 系统为数据分配唯一路径
%%% - 开发者注册友好名称便于引用
%%% - 其他模块通过名称快速定位数据
complete_workflow_test() ->
    ?debugFmt("=== Complete Storage Workflow ===", []),
    %% 输出工作流开始标记

    Opts = #{store => hb_test_utils:test_store()},
    %% 创建测试存储选项

    %% 1. 写入数据到缓存
    Data = #{
        <<"type">> => <<"Config">>,
        <<"database">> => <<"postgres://localhost">>,
        <<"port">> => 5432
    },
    %% 创建配置数据示例
    %% 包含数据库连接信息和端口配置

    {ok, DataPath} = hb_cache:write(Data, Opts),
    %% 写入配置到缓存
    %% 返回唯一路径标识DataPath

    ?debugFmt("1. Wrote config to cache: ~s", [DataPath]),
    %% 输出调试信息

    %% 2. 通过查找检索数据
    {ok, Retrieved} = dev_lookup:read(
        #{},
        #{<<"target">> => DataPath},
        Opts
    ),
    %% 使用路径从查找服务检索数据

    ?assert(hb_message:match(Data, Retrieved, only_present, Opts)),
    %% 验证检索结果与原始数据一致

    ?debugFmt("2. Retrieved via lookup", []),
    %% 输出调试信息

    %% 3. 注册名称
    Wallet = ar_wallet:new(),
    RegOpts = Opts#{priv_wallet => Wallet},
    %% 创建带钱包的注册选项

    dev_local_name:direct_register(
        #{<<"key">> => <<"app-config">>, <<"value">> => DataPath},
        RegOpts
    ),
    %% 直接注册名称
    %% 将"app-config"映射到配置数据的路径

    ?debugFmt("3. Registered name 'app-config'", []),
    %% 输出调试信息

    %% 4. 通过名称查找
    {ok, FoundPath} = dev_local_name:lookup(
        #{},
        #{<<"key">> => <<"app-config">>},
        RegOpts
    ),
    %% 使用名称查找对应的路径

    ?assertEqual(DataPath, FoundPath),
    %% 验证找到的路径与原始路径一致

    ?debugFmt("4. Looked up by name", []),
    %% 输出调试信息

    ?debugFmt("=== All tests passed! ===", []).
    %% 输出工作流成功标记
