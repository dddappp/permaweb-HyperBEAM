-module(test_hb3).  %% 定义测试模块名称为test_hb3，用于测试HyperBEAM的消息、链接、映射和单例功能
-include_lib("eunit/include/eunit.hrl").  %% 引入EUnit测试框架的头文件，提供?assert、?assertEqual等断言宏
 
%% ====================================================================
%% 消息测试部分 - 验证消息签名、验证和ID生成功能
%% ====================================================================
 
message_sign_verify_test() ->
    %% 测试功能1：消息签名和验证
    %% 使用ar_wallet:new()创建一个新的RSA钱包，用于消息签名
    Wallet = ar_wallet:new(),
    %% 创建一个包含测试数据的消息映射
    Msg = #{<<"data">> => <<"test">>},
    
    %% 步骤1：使用私钥对消息进行签名
    %% 调用hb_message:commit将消息转换为TABM格式并使用私钥Wallet进行签名
    %% 函数返回包含签名承诺(commitments)的消息
    Signed = hb_message:commit(Msg, #{priv_wallet => Wallet}),
    %% 断言验证签名后的消息包含"commitments"键
    ?assert(maps:is_key(<<"commitments">>, Signed)),
    
    %% 步骤2：验证签名的有效性
    %% 调用hb_message:verify使用'all'策略验证所有签名者的签名
    %% 第二个参数'all'表示需要验证所有承诺签名
    ?assert(hb_message:verify(Signed, all, #{})),
    
    %% 步骤3：篡改检测测试
    %% 创建一个篡改后的消息副本，修改原始数据
    Tampered = Signed#{<<"data">> => <<"modified">>},
    %% 断言验证篡改后的消息签名验证失败
    ?assertNot(hb_message:verify(Tampered, all, #{})).
 
message_id_test() ->
    %% 测试功能2：消息ID生成机制
    %% 创建一个测试消息，包含键值对
    Msg = #{<<"key">> => <<"value">>},
    
    %% 测试1：验证ID生成的确定性
    %% 同一消息两次调用id()应生成相同的ID
    ID1 = hb_message:id(Msg),
    ID2 = hb_message:id(Msg),
    %% 断言验证两个ID相等
    ?assertEqual(ID1, ID2),
    
    %% 测试2：签名消息与未签名消息的ID差异
    %% 创建新钱包并签名消息
    Wallet = ar_wallet:new(),
    Signed = hb_message:commit(Msg, #{priv_wallet => Wallet}),
    %% 使用'signed'策略生成签名消息的ID（包含所有签名信息）
    SignedID = hb_message:id(Signed, signed, #{}),
    %% 使用'unsigned'策略生成未签名消息的ID（不包含签名信息）
    UnsignedID = hb_message:id(Signed, unsigned, #{}),
    %% 断言验证签名和未签名的ID不同
    ?assertNotEqual(SignedID, UnsignedID).
 
%% ====================================================================
%% 链接测试部分 - 验证链接规范化、检测和往返处理功能
%% ====================================================================
 
link_normalize_test() ->
    %% 测试功能3：消息链接规范化
    %% 创建包含嵌套结构的消息
    Msg = #{
        <<"data">> => <<"value">>,
        <<"nested">> => #{<<"deep">> => <<"structure">>}
    },
    
    %% 使用hb_link:normalize将嵌套子消息转换为缓存链接
    %% 'offload'模式会将子消息写入缓存并返回链接
    Normalized = hb_link:normalize(Msg, offload, #{}),
    %% 断言验证规范化后的消息包含"nested+link"键
    ?assert(maps:is_key(<<"nested+link">>, Normalized)),
    %% 断言验证原始的"nested"键已被移除（被替换为链接）
    ?assertNot(maps:is_key(<<"nested">>, Normalized)).
 
link_key_detection_test() ->
    %% 测试功能4：链接键识别
    %% 验证以"+link"结尾的键被正确识别为链接键
    ?assert(hb_link:is_link_key(<<"data+link">>)),
    %% 验证普通键不会被误识别为链接键
    ?assertNot(hb_link:is_link_key(<<"data">>)),
    %% 验证链接规范符可以被正确移除
    ?assertEqual(<<"data">>, hb_link:remove_link_specifier(<<"data+link">>)).
 
link_roundtrip_test() ->
    %% 测试功能5：链接往返处理
    %% 创建包含嵌套结构的原始消息
    Original = #{
        <<"header">> => <<"value">>,
        <<"body">> => #{<<"content">> => <<"data">>}
    },
    
    %% 步骤1：规范化 - 将嵌套结构转换为链接
    Normalized = hb_link:normalize(Original, offload, #{}),
    %% 步骤2：解码 - 将"+link"后缀的键还原为原始键名
    Decoded = hb_link:decode_all_links(Normalized),
    %% 步骤3：加载 - 递归加载所有链接指向的数据
    Loaded = hb_cache:ensure_all_loaded(Decoded, #{}),
    %% 断言验证往返处理后的结果与原始消息一致
    ?assertEqual(Original, Loaded).
 
%% ====================================================================
%% 映射测试部分 - 验证映射中的链接自动解析功能
%% ====================================================================
 
maps_link_resolution_test() ->
    %% 测试功能6：映射中的链接自动解析
    %% 创建测试数据并写入缓存
    Data = <<"cached data">>,
    {ok, ID} = hb_cache:write(Data, #{}),
    %% 创建包含链接的映射，{link, ID, #{}}表示指向缓存数据的链接
    Map = #{<<"key">> => {link, ID, #{}}},
    
    %% 使用hb_maps:get获取键值，会自动解析链接
    Value = hb_maps:get(<<"key">>, Map),
    %% 断言验证获取到的值与原始数据一致
    ?assertEqual(Data, Value).
 
maps_typed_link_test() ->
    %% 测试功能7：带类型的链接解析
    %% 创建字符串数据"42"并写入缓存
    {ok, ID} = hb_cache:write(<<"42">>, #{}),
    %% 创建带类型声明的链接映射，指定type为integer
    Map = #{<<"count">> => {link, ID, #{<<"type">> => integer}}},
    
    %% 获取值时hb_maps会根据类型声明自动转换
    Value = hb_maps:get(<<"count">>, Map),
    %% 断言验证获取到的值为整数42而非字符串
    ?assertEqual(42, Value).
 
%% ====================================================================
%% 单例测试部分 - 验证HTTP API请求到消息的解析功能
%% ====================================================================
 
singleton_simple_path_test() ->
    %% 测试功能8：简单路径解析
    %% 解析路径"/a/b/c"为三个消息
    Msgs = hb_singleton:from(#{<<"path">> => <<"/a/b/c">>}, #{}),
    %% 断言验证返回4个消息（1个基础消息+3个路径段消息）
    ?assertEqual(4, length(Msgs)),
    
    %% 解构消息列表：[基础消息, 消息1, 消息2, 消息3]
    [_Base, Msg1, Msg2, Msg3] = Msgs,
    %% 断言验证每个消息的路径段
    ?assertEqual(<<"a">>, maps:get(<<"path">>, Msg1)),
    ?assertEqual(<<"b">>, maps:get(<<"path">>, Msg2)),
    ?assertEqual(<<"c">>, maps:get(<<"path">>, Msg3)).
 
singleton_inline_params_test() ->
    %% 测试功能9：内联参数解析
    %% 解析带有查询参数的路径"/action&key=value&flag"
    Msgs = hb_singleton:from(#{<<"path">> => <<"/action&key=value&flag">>}, #{}),
    
    %% 解构消息列表：[基础消息, 动作消息]
    [_Base, Msg] = Msgs,
    %% 断言验证参数"key"被解析为字符串值"value"
    ?assertEqual(<<"value">>, maps:get(<<"key">>, Msg)),
    %% 断言验证布尔参数"flag"被解析为true
    ?assertEqual(true, maps:get(<<"flag">>, Msg)).
 
singleton_scoped_keys_test() ->
    %% 测试功能10：作用域键解析
    %% 创建带有全局键和作用域键的请求
    Req = #{
        <<"path">> => <<"/a/b">>,
        <<"global">> => <<"g">>,
        <<"1.first">> => <<"f">>
    },
    
    %% 解析请求，生成两个消息
    [_Base, Msg1, Msg2] = hb_singleton:from(Req, #{}),
    
    %% 测试1：验证全局键在所有消息中存在
    ?assertEqual(<<"g">>, maps:get(<<"global">>, Msg1)),
    ?assertEqual(<<"g">>, maps:get(<<"global">>, Msg2)),
    
    %% 测试2：验证作用域键"N.Key"只存在于第N个消息
    ?assertEqual(<<"f">>, maps:get(<<"first">>, Msg1)),
    ?assertEqual(error, maps:find(<<"first">>, Msg2)).
 
singleton_roundtrip_test() ->
    %% 测试功能11：单例往返转换
    %% 创建原始消息列表
    Original = [
        #{},
        #{<<"path">> => <<"a">>},
        #{<<"path">> => <<"b">>, <<"key">> => <<"value">>}
    ],
    
    %% 步骤1：将AO-Core消息列表转换为TABM格式
    TABM = hb_singleton:to(Original),
    %% 步骤2：从TABM格式恢复为消息列表
    Recovered = hb_singleton:from(TABM, #{}),
    
    %% 断言验证往返转换后消息数量一致
    ?assertEqual(length(Original), length(Recovered)).
