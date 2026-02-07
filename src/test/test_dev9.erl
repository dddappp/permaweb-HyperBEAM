%%% @doc 数据编码与查询模块测试套件
%%%
%%% 本测试模块验证HyperBEAM中与Arweave数据处理相关的核心模块：
%%% - dev_arweave: Arweave区块链交互模块
%%% - dev_codec_ans104: ANS-104数据格式编解码器
%%% - dev_query: 数据查询引擎
%%% - dev_copycat: 数据复制模块
%%% - dev_manifest: 清单管理模块
%%%
%%% 测试涵盖以下功能领域：
%%% 1. Arweave网络接口函数导出验证
%%% 2. ANS-104格式的消息编解码、序列化、签名与验证
%%% 3. GraphQL查询引擎功能验证
%%% 4. 数据复制与清单管理功能验证
%%% 5. 端到端数据处理工作流验证

-module(test_dev9).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% 运行测试命令: rebar3 eunit --module=test_dev9

%% @doc 测试用例：Arweave模块函数导出验证
%%%
%%% 本测试验证dev_arweave模块是否正确导出所有核心API函数。
%%% dev_arweave模块提供与Arweave区块链网络交互的接口，
%%% 包括交易查询、区块获取、网络状态等关键功能。
%%%
%%% 测试验证的函数：
%%% - tx/3: 交易信息查询与上传
%%% - block/3: 区块信息获取
%%% - current/3: 当前网络状态获取
%%% - status/3: 网络基础信息查询
arweave_exports_test() ->
    %% 确保dev_arweave模块已加载到当前节点
    code:ensure_loaded(dev_arweave),
    %% 验证tx/3函数是否被导出（交易操作API）
    ?assert(erlang:function_exported(dev_arweave, tx, 3)),
    %% 验证block/3函数是否被导出（区块查询API）
    ?assert(erlang:function_exported(dev_arweave, block, 3)),
    %% 验证current/3函数是否被导出（当前状态API）
    ?assert(erlang:function_exported(dev_arweave, current, 3)),
    %% 验证status/3函数是否被导出（状态查询API）
    ?assert(erlang:function_exported(dev_arweave, status, 3)),
    %% 输出测试通过标记
    ?debugFmt("Arweave exports: OK", []).

%% @doc 测试用例：ANS-104内容类型验证
%%%
%%% ANS-104是Arweave的标准数据打包格式，用于将多个数据项
%%% 组合成单个可传输的交易。本测试验证编解码器是否正确
%%% 返回ANS-104格式的内容类型标识。
%%%
%%% 内容类型在HTTP请求的Content-Type头中使用，用于标识
%%% 请求体的数据格式。ANS-104格式的内容类型为
%%% "application/ans104"。
ans104_content_type_test() ->
    %% 调用content_type/1函数获取ANS-104内容类型
    {ok, ContentType} = dev_codec_ans104:content_type(#{}),
    %% 断言返回的内容类型为标准的ANS-104标识
    ?assertEqual(<<"application/ans104">>, ContentType),
    %% 输出调试信息显示获取的内容类型
    ?debugFmt("ANS-104 content type: ~s", [ContentType]).

%% @doc 测试用例：ANS-104格式消息转换测试
%%%
%%% 本测试验证ANS-104编解码器的基本转换功能：
%%% - to/3: 将消息映射转换为Arweave TX记录格式
%%% - from/3: 将TX记录转换回消息映射格式
%%%
%%% 此测试确保数据在两种格式之间能够无损转换，
%%% 这是数据持久化和传输的基础能力。
ans104_to_from_test() ->
    %% 创建测试用的消息映射，包含键值对数据
    Msg = #{
        <<"key">> => <<"value">>,
        <<"data">> => <<"test data">>
    },
    %% 将消息映射转换为TX记录格式
    {ok, TX} = dev_codec_ans104:to(Msg, #{}, #{}),
    %% 断言转换结果是元组类型
    ?assert(is_tuple(TX)),
    %% 断言元组的第一元素是tx原子，表示有效的TX记录
    ?assertEqual(tx, element(1, TX)),
    
    %% 将TX记录转换回消息映射格式
    {ok, TABM} = dev_codec_ans104:from(TX, #{}, #{}),
    %% 断言转换结果是映射类型
    ?assert(is_map(TABM)),
    %% 断言原始数据中的键值对被正确保留
    ?assertEqual(<<"value">>, maps:get(<<"key">>, TABM)),
    ?debugFmt("ANS-104 to/from: OK", []).

%% @doc 测试用例：ANS-104序列化功能测试
%%%
%%% 序列化是将内存中的数据结构转换为二进制字节流的过程。
%%% 对于Arweave交易，需要将TX记录序列化为网络传输格式。
%%%
%%% 序列化后的二进制数据可以：
%%% - 通过HTTP POST发送到Arweave节点
%%% - 存储到本地缓存供后续使用
%%% - 作为数据签名的一部分参与签名计算
ans104_serialize_test() ->
    %% 创建测试消息映射
    Msg = #{<<"test">> => <<"data">>},
    %% 将消息转换为TX记录
    {ok, TX} = dev_codec_ans104:to(Msg, #{}, #{}),
    %% 将TX记录序列化为二进制格式
    {ok, Binary} = dev_codec_ans104:serialize(TX, #{}, #{}),
    %% 断言序列化结果是有效的二进制类型
    ?assert(is_binary(Binary)),
    %% 断言序列化后的字节大小大于0
    ?assert(byte_size(Binary) > 0),
    %% 输出序列化结果的字节大小
    ?debugFmt("ANS-104 serialize: ~p bytes", [byte_size(Binary)]).

%% @doc 测试用例：ANS-104签名与验证测试
%%%
%%% 本测试验证ANS-104格式消息的完整签名流程：
%%% 1. 使用私钥对消息进行签名
%%% 2. 验证签名的有效性
%%%
%%% 签名机制确保：
%%% - 消息的真实性和完整性
%%% - 发送者的身份认证
%%% - 消息不可否认性
ans104_sign_verify_test() ->
    %% 创建新的测试钱包（包含公私钥对）
    Wallet = ar_wallet:new(),
    %% 创建待签名的消息
    Msg = #{<<"key">> => <<"value">>},
    
    %% 使用hb_message:commit对消息进行签名
    %% - 传入消息内容
    %% - 配置选项：指定私钥钱包
    %% - 设备配置：指定使用ANS-104格式进行签名
    Signed = hb_message:commit(
        Msg,
        #{priv_wallet => Wallet},
        #{<<"commitment-device">> => <<"ans104@1.0">>}
    ),
    
    %% 断言签名结果包含commitments字段（签名承诺）
    ?assert(maps:is_key(<<"commitments">>, Signed)),
    %% 调用verify/3验证签名有效性
    {ok, true} = dev_codec_ans104:verify(Signed, #{}, #{}),
    ?debugFmt("ANS-104 sign/verify: OK", []).

%% @doc 测试用例：查询模块函数导出验证
%%%
%%% dev_query模块提供HyperBEAM的查询引擎功能，
%%% 支持多种查询模式和返回格式。
%%%
%%% 测试验证的查询模式：
%%% - all/3: 匹配请求消息中的所有键
%%% - base/3: 匹配基础消息中的所有键
%%% - only/3: 只匹配指定的键
%%% - graphql/3: GraphQL风格查询
query_exports_test() ->
    %% 确保dev_query模块已加载
    code:ensure_loaded(dev_query),
    %% 验证all/3函数是否导出
    ?assert(erlang:function_exported(dev_query, all, 3)),
    %% 验证base/3函数是否导出
    ?assert(erlang:function_exported(dev_query, base, 3)),
    %% 验证only/3函数是否导出
    ?assert(erlang:function_exported(dev_query, only, 3)),
    %% 验证graphql/3函数是否导出
    ?assert(erlang:function_exported(dev_query, graphql, 3)),
    ?debugFmt("Query exports: OK", []).

%% @doc 测试用例：查询引擎配置信息验证
%%%
%%% dev_query:info/1返回查询引擎的配置信息，包括：
%%% - default: 默认的查询处理函数
%%% - excludes: 在查询时默认排除的键列表
%%%
%%% 排除列表防止查询系统内部使用的元数据键
%%% 干扰正常的业务数据查询。
query_info_test() ->
    %% 获取查询引擎配置信息
    Info = dev_query:info(#{}),
    %% 断言配置包含default键
    ?assert(maps:is_key(default, Info)),
    %% 断言配置包含excludes键（排除列表）
    ?assert(maps:is_key(excludes, Info)),
    %% 获取排除列表
    Excludes = maps:get(excludes, Info),
    %% 断言"keys"键被包含在排除列表中
    ?assert(lists:member(<<"keys">>, Excludes)),
    ?debugFmt("Query info: OK", []).

%% @doc 测试用例：查询结果检测功能测试
%%%
%%% has_results/3用于判断GraphQL查询响应是否包含交易结果。
%%% 这是网关客户端配置中的重要功能，用于确定节点返回的
%%% 响应是否应被视为有效数据。
%%%
%%% 检测逻辑：
%%% - 解析GraphQL响应JSON
%%% - 检查transactions.edges数组是否非空
%%% - 返回布尔值表示是否有结果
query_has_results_test() ->
    %% 测试场景1：查询结果非空
    %% 构造包含交易结果的GraphQL响应JSON
    JSONWithResults = hb_json:encode(#{
        <<"data">> => #{
            <<"transactions">> => #{
                <<"edges">> => [#{<<"node">> => #{<<"id">> => <<"123">>}}]
            }
        }
    }),
    %% 断言检测函数正确识别有结果的情况
    {ok, true} = dev_query:has_results(#{<<"body">> => JSONWithResults}, #{}, #{}),
    
    %% 测试场景2：查询结果为空
    %% 构造空结果的GraphQL响应JSON
    JSONEmpty = hb_json:encode(#{
        <<"data">> => #{
            <<"transactions">> => #{<<"edges">> => []}
        }
    }),
    %% 断言检测函数正确识别无结果的情况
    {ok, false} = dev_query:has_results(#{<<"body">> => JSONEmpty}, #{}, #{}),
    ?debugFmt("Query has_results: OK", []).

%% @doc 测试用例：Copycat模块函数导出验证
%%%
%%% dev_copycat模块提供数据复制功能，支持：
%%% - graphql/3: 通过GraphQL接口复制数据
%%% - arweave/3: 从Arweave网络复制数据
%%%
%%% 数据复制是HyperBEAM分布式架构中的关键功能，
%%% 确保数据在多个节点间的一致性和可用性。
copycat_exports_test() ->
    %% 确保dev_copycat模块已加载
    code:ensure_loaded(dev_copycat),
    %% 验证graphql/3函数是否导出
    ?assert(erlang:function_exported(dev_copycat, graphql, 3)),
    %% 验证arweave/3函数是否导出
    ?assert(erlang:function_exported(dev_copycat, arweave, 3)),
    ?debugFmt("Copycat exports: OK", []).

%% @doc 测试用例：Manifest模块函数导出验证
%%%
%%% dev_manifest模块提供清单管理功能，用于：
%%% - info/0: 获取清单配置信息
%%% - index/3: 创建数据索引
%%%
%%% 清单功能帮助管理复杂的数据集合，
%%% 提供数据的逻辑组织和快速访问能力。
manifest_exports_test() ->
    %% 确保dev_manifest模块已加载
    code:ensure_loaded(dev_manifest),
    %% 验证info/0函数是否导出（无参数版本）
    ?assert(erlang:function_exported(dev_manifest, info, 0)),
    %% 验证index/3函数是否导出
    ?assert(erlang:function_exported(dev_manifest, index, 3)),
    ?debugFmt("Manifest exports: OK", []).

%% @doc 测试用例：Manifest配置信息验证
%%%
%%% dev_manifest:info/0返回清单模块的配置信息，
%%% 包括默认处理函数和排除列表配置。
manifest_info_test() ->
    %% 获取清单模块配置信息
    Info = dev_manifest:info(),
    %% 断言配置包含default键
    ?assert(maps:is_key(default, Info)),
    %% 断言配置包含excludes键
    ?assert(maps:is_key(excludes, Info)),
    %% 断言default值是有效的函数
    ?assert(is_function(maps:get(default, Info))),
    ?debugFmt("Manifest info: OK", []).

%% @doc 测试用例：完整数据处理工作流
%%%
%%% 本测试验证HyperBEAM数据处理系统的端到端工作流程：
%%% 1. 创建符合ANS-104格式的消息
%%% 2. 使用私钥对消息进行签名
%%% 3. 将消息转换为TX记录格式
%%% 4. 序列化TX记录为二进制
%%% 5. 反序列化二进制恢复原始数据
%%% 6. 验证签名有效性
%%%
%%% 此测试模拟典型的数据发布场景：
%%% - 用户创建业务消息
%%% - 系统对消息进行签名确保完整性
%%% - 将签名消息打包为Arweave交易格式
%%% - 通过网络传输到Arweave区块链
complete_data_workflow_test() ->
    %% 输出工作流开始标记
    ?debugFmt("=== Complete Data Workflow ===", []),
    
    %% 步骤1：创建ANS-104格式消息
    %% 创建新的测试钱包用于消息签名
    Wallet = ar_wallet:new(),
    %% 创建包含文档元数据的测试消息
    Msg = #{
        <<"type">> => <<"Document">>,
        <<"title">> => <<"Test Document">>,
        <<"data">> => <<"Document content here">>
    },
    
    %% 步骤2：使用ANS-104格式签名消息
    %% 调用hb_message:commit进行消息签名
    %% 传入消息、钱包配置和设备配置
    Signed = hb_message:commit(
        Msg,
        #{priv_wallet => Wallet},
        #{<<"commitment-device">> => <<"ans104@1.0">>}
    ),
    %% 断言签名结果包含承诺信息
    ?assert(maps:is_key(<<"commitments">>, Signed)),
    %% 输出签名完成标记
    ?debugFmt("1. Message signed with ANS-104", []),
    
    %% 步骤3：转换为TX记录
    %% 将签名消息转换为Arweave交易记录格式
    {ok, TX} = dev_codec_ans104:to(Signed, #{}, #{}),
    %% 断言转换结果是有效的TX记录元组
    ?assert(is_tuple(TX)),
    %% 输出转换完成标记
    ?debugFmt("2. Converted to TX record", []),
    
    %% 步骤4：序列化传输
    %% 将TX记录序列化为网络传输用的二进制格式
    {ok, Binary} = dev_codec_ans104:serialize(TX, #{}, #{}),
    %% 断言序列化结果是有效的二进制
    ?assert(is_binary(Binary)),
    %% 输出序列化大小信息
    ?debugFmt("3. Serialized: ~p bytes", [byte_size(Binary)]),
    
    %% 步骤5：反序列化恢复
    %% 将二进制数据反序列化为消息映射
    {ok, Restored} = dev_codec_ans104:deserialize(Binary, #{}, #{}),
    %% 断言恢复结果是有效的映射
    ?assert(is_map(Restored)),
    %% 输出反序列化完成标记
    ?debugFmt("4. Deserialized successfully", []),
    
    %% 步骤6：签名验证
    %% 验证原始消息签名的有效性
    {ok, true} = dev_codec_ans104:verify(Signed, #{}, #{}),
    %% 输出验证完成标记
    ?debugFmt("5. Signature verified", []),
    
    %% 输出工作流全部完成标记
    ?debugFmt("=== All tests passed! ===", []).
