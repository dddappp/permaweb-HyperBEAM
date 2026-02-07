-module(test_hb2).  %% 定义测试模块名称为test_hb2，遵循EUnit测试模块命名规范
-include_lib("eunit/include/eunit.hrl").  %% 引入EUnit测试框架的头文件，提供?assert、?assertEqual等宏
-include("include/hb.hrl").  %% 引入HyperBEAM项目的公共头文件，包含常量和宏定义
 
%% ====================================================================
%% 运行说明：使用 rebar3 eunit --module=test_hb2 命令执行此测试模块
%% ====================================================================
 
features_test() ->
    %% 测试功能1：获取所有功能标志
    %% 调用hb_features:all()返回当前节点支持的所有功能标志，以映射形式表示
    Features = hb_features:all(),
    %% 断言验证返回结果是一个映射类型
    ?assert(is_map(Features)),
    %% 使用debug输出打印所有功能标志，便于调试和验证
    ?debugFmt("Features: ~p", [Features]),
    
    %% 测试功能2：检查已知功能标志的存在性
    %% 验证http3功能标志存在于功能映射中
    ?assert(maps:is_key(http3, Features)),
    %% 验证rocksdb功能标志存在于功能映射中
    ?assert(maps:is_key(rocksdb, Features)),
    %% 验证test功能标志存在于功能映射中
    ?assert(maps:is_key(test, Features)),
    %% 功能标志检查通过，输出成功信息
    ?debugFmt("Feature flags: OK", []),
    
    %% 测试功能3：验证enabled/1函数返回布尔值
    %% 检查http3功能的启用状态是否为布尔类型
    ?assert(is_boolean(hb_features:enabled(http3))),
    %% 检查rocksdb功能的启用状态是否为布尔类型
    ?assert(is_boolean(hb_features:enabled(rocksdb))),
    %% 功能检查通过，输出成功信息
    ?debugFmt("Feature checks: OK", []),
    
    %% 测试功能4：验证未知功能的默认行为
    %% 对于不存在的功能，enabled/1应返回false而非抛出异常
    ?assertEqual(false, hb_features:enabled(nonexistent_feature)),
    %% 未知功能处理测试通过，输出成功信息
    ?debugFmt("Unknown feature handling: OK", []).
 
options_test() ->
    %% 测试功能5：本地选项覆盖全局选项
    %% 创建一个本地选项映射，包含自定义的网关地址
    LocalOpts = #{gateway => <<"https://custom.gateway">>},
    %% 调用hb_opts:get获取网关配置，指定默认值为"default"
    %% 由于本地选项中有gateway键，应返回本地配置的值
    Gateway = hb_opts:get(gateway, <<"default">>, LocalOpts),
    %% 断言验证获取到的网关地址与本地配置一致
    ?assertEqual(<<"https://custom.gateway">>, Gateway),
    %% 本地覆盖功能测试通过，输出成功信息
    ?debugFmt("Local override: OK", []),
    
    %% 测试功能6：默认值的回退机制
    %% 尝试获取一个不存在的键，应返回指定的默认值
    Missing = hb_opts:get(nonexistent_key, <<"fallback">>, #{}),
    %% 断言验证默认值回退机制正常工作
    ?assertEqual(<<"fallback">>, Missing),
    %% 默认值回退测试通过，输出成功信息
    ?debugFmt("Default fallback: OK", []),
    
    %% 测试功能7：全局配置优先模式
    %% 创建一个全局选项映射，设置mode为local_value并指定prefer为global
    GlobalOpts = #{mode => local_value, prefer => global},
    %% 由于prefer设置为global，hb_opts:get应优先返回全局配置
    %% 使用assertNotEqual确保返回值不是本地设置的local_value
    ?assertNotEqual(local_value, hb_opts:get(mode, undefined, GlobalOpts)),
    %% 全局优先模式测试通过，输出成功信息
    ?debugFmt("Prefer global: OK", []).
 
private_state_test() ->
    %% 测试功能8：创建包含私有状态的消息
    %% 创建一个简单的公开数据消息
    Msg = #{<<"data">> => <<"public">>},
    %% 使用hb_private:set函数设置私有状态
    %% 参数：消息体、路径("cache/result")、值(42)、选项映射
    %% 私有状态会存储在消息的"priv"键下，不参与序列化
    MsgWithPriv = hb_private:set(Msg, <<"cache/result">>, 42, #{}),
    %% 断言验证设置私有状态后消息包含"priv"键
    ?assert(maps:is_key(<<"priv">>, MsgWithPriv)),
    %% 设置私有状态功能测试通过，输出成功信息
    ?debugFmt("Set private: OK", []),
    
    %% 测试功能9：获取私有状态值
    %% 使用hb_private:get从私有状态中检索值
    Value = hb_private:get(<<"cache/result">>, MsgWithPriv, #{}),
    %% 断言验证获取到的值与之前设置的值一致
    ?assertEqual(42, Value),
    %% 获取私有状态功能测试通过，输出成功信息
    ?debugFmt("Get private: OK", []),
    
    %% 测试功能10：带默认值的私有状态获取
    %% 尝试获取一个不存在的私有键，指定默认值"default"
    Default = hb_private:get(<<"missing">>, MsgWithPriv, <<"default">>, #{}),
    %% 断言验证默认值正确返回
    ?assertEqual(<<"default">>, Default),
    %% 带默认值获取功能测试通过，输出成功信息
    ?debugFmt("Get with default: OK", []),
    
    %% 测试功能11：从消息中提取私有映射
    %% 使用hb_private:from_message提取消息的私有部分
    Priv = hb_private:from_message(MsgWithPriv),
    %% 断言验证提取结果是一个映射类型
    ?assert(is_map(Priv)),
    %% 提取私有映射功能测试通过，输出成功信息
    ?debugFmt("Extract private: OK", []),
    
    %% 测试功能12：重置私有状态
    %% 使用hb_private:reset移除消息中的所有私有数据
    Cleaned = hb_private:reset(MsgWithPriv),
    %% 断言验证重置后的消息不再包含私有数据
    ?assertEqual(#{}, hb_private:from_message(Cleaned)),
    %% 重置私有状态功能测试通过，输出成功信息
    ?debugFmt("Reset private: OK", []).
 
private_key_check_test() ->
    %% 测试功能13：检测以"priv"开头的私有键
    %% 二进制字符串形式的私有键应该被识别
    ?assert(hb_private:is_private(<<"priv">>)),
    %% "private"完整形式也应该被识别为私有键
    ?assert(hb_private:is_private(<<"private">>)),
    %% 原子形式的私有键同样应该被识别
    ?assert(hb_private:is_private(priv)),
    
    %% 测试功能14：验证非私有键不会被误识别
    %% 普通数据键"data"不应该被识别为私有键
    ?assertNot(hb_private:is_private(<<"data">>)),
    %% 公开数据键"public"不应该被识别为私有键
    ?assertNot(hb_private:is_private(<<"public">>)),
    %% 私有键检测功能测试通过，输出成功信息
    ?debugFmt("Private key detection: OK", []).
 
path_manipulation_test() ->
    %% 测试功能15：获取路径的第一个元素（头部）
    %% 创建一个包含路径的消息，路径为["a", "b", "c"]
    Msg = #{<<"path">> => [<<"a">>, <<"b">>, <<"c">>]},
    %% 使用hb_path:hd从消息中提取路径的第一个元素
    ?assertEqual(<<"a">>, hb_path:hd(Msg, #{})),
    %% 路径头部提取功能测试通过，输出成功信息
    ?debugFmt("Path head: OK", []),
    
    %% 测试功能16：获取路径除头部外的剩余部分（尾部）
    %% 使用hb_path:tl获取去掉第一个元素后的路径
    Tail = hb_path:tl(Msg, #{}),
    %% 断言验证剩余路径为["b", "c"]
    ?assertEqual([<<"b">>, <<"c">>], maps:get(<<"path">>, Tail)),
    %% 路径尾部提取功能测试通过，输出成功信息
    ?debugFmt("Path tail: OK", []),
    
    %% 测试功能17：弹出路径的第一个元素
    %% 使用hb_path:pop_request同时获取头部和剩余路径
    {Head, Rest} = hb_path:pop_request(Msg, #{}),
    %% 断言验证弹出的头部为"a"
    ?assertEqual(<<"a">>, Head),
    %% 断言验证剩余路径为["b", "c"]
    ?assertEqual([<<"b">>, <<"c">>], maps:get(<<"path">>, Rest)),
    %% 路径弹出功能测试通过，输出成功信息
    ?debugFmt("Pop request: OK", []).
 
path_building_test() ->
    %% 测试功能18：向路径头部添加元素（push操作）
    %% 创建包含单元素路径["a"]的消息
    Msg1 = #{<<"path">> => [<<"a">>]},
    %% 使用hb_path:push_request将"b"添加到路径头部
    Msg2 = hb_path:push_request(Msg1, <<"b">>),
    %% 从结果消息中提取更新后的路径
    Path = maps:get(<<"path">>, Msg2),
    %% 断言验证新元素"b"位于路径头部
    ?assertEqual(<<"b">>, hd(Path)),
    %% 路径push功能测试通过，输出成功信息
    ?debugFmt("Push request: OK", []),
    
    %% 测试功能19：向路径尾部添加元素（queue操作）
    %% 创建包含单元素路径["a"]的消息
    Msg3 = #{<<"path">> => [<<"a">>]},
    %% 使用hb_path:queue_request将"b"添加到路径尾部
    Msg4 = hb_path:queue_request(Msg3, <<"b">>),
    %% 从结果消息中提取更新后的路径
    QPath = maps:get(<<"path">>, Msg4),
    %% 断言验证原有元素"a"仍在路径头部
    ?assertEqual(<<"a">>, hd(QPath)),
    %% 断言验证路径完整为["a", "b"]
    ?assertEqual([<<"a">>, <<"b">>], QPath),
    %% 路径queue功能测试通过，输出成功信息
    ?debugFmt("Queue request: OK", []).
 
path_conversion_test() ->
    %% 测试功能20：将路径字符串转换为路径部分列表
    %% 使用hb_path:term_to_path_parts将"/"分隔的字符串转换为列表
    Parts = hb_path:term_to_path_parts(<<"a/b/c">>),
    %% 断言验证转换结果为["a", "b", "c"]
    ?assertEqual([<<"a">>, <<"b">>, <<"c">>], Parts),
    %% 路径字符串转列表功能测试通过，输出成功信息
    ?debugFmt("Path to parts: OK", []),
    
    %% 测试功能21：将路径部分列表转换为路径字符串
    %% 使用hb_path:to_binary将路径列表转换为"/"分隔的字符串
    Binary = hb_path:to_binary([<<"a">>, <<"b">>, <<"c">>]),
    %% 断言验证转换结果为"a/b/c"
    ?assertEqual(<<"a/b/c">>, Binary),
    %% 路径列表转字符串功能测试通过，输出成功信息
    ?debugFmt("Parts to binary: OK", []),
    
    %% 测试功能22：路径规范化
    %% 使用hb_path:normalize确保路径以"/"开头
    Normalized = hb_path:normalize(<<"test">>),
    %% 断言验证规范化后的路径为"/test"
    ?assertEqual(<<"/test">>, Normalized),
    %% 路径规范化功能测试通过，输出成功信息
    ?debugFmt("Path normalize: OK", []).
 
path_matching_test() ->
    %% 测试功能23：大小写不敏感路径匹配
    %% 使用hb_path:matches进行不区分大小写的路径比较
    ?assert(hb_path:matches(<<"Test">>, <<"test">>)),
    ?assert(hb_path:matches(<<"ABC">>, <<"abc">>)),
    %% 验证不匹配的路径返回false
    ?assertNot(hb_path:matches(<<"test">>, <<"other">>)),
    %% 大小写不敏感匹配功能测试通过，输出成功信息
    ?debugFmt("Case-insensitive match: OK", []),
    
    %% 测试功能24：正则表达式路径匹配
    %% 使用hb_path:regex_matches进行正则表达式模式匹配
    ?assert(hb_path:regex_matches(<<"a/b/c">>, <<"a/.*/c">>)),
    ?assert(hb_path:regex_matches(<<"a/anything/c">>, <<"a/.*/c">>)),
    %% 验证不匹配的模式返回false
    ?assertNot(hb_path:regex_matches(<<"a/b/c">>, <<"a/.*/d">>)),
    %% 正则表达式匹配功能测试通过，输出成功信息
    ?debugFmt("Regex match: OK", []).
 
hashpath_test() ->
    %% 测试功能25：单个消息的哈希路径生成
    %% 创建包含数据的消息
    Msg1 = #{<<"data">> => <<"initial">>},
    %% 使用hb_path:hashpath生成单个消息的哈希路径
    %% 单个消息的哈希路径长度为43字节（Base64URL编码的SHA256哈希）
    HP1 = hb_path:hashpath(Msg1, #{}),
    %% 断言验证返回结果是二进制类型
    ?assert(is_binary(HP1)),
    %% 断言验证哈希路径长度为43字节
    ?assertEqual(43, byte_size(HP1)),
    %% 打印生成的哈希路径用于调试
    ?debugFmt("Single hashpath: ~s", [HP1]),
    
    %% 测试功能26：两个消息的链式哈希路径生成
    %% 创建第二个消息
    Msg2 = #{<<"action">> => <<"update">>},
    %% 使用hb_path:hashpath生成链式哈希路径
    %% 链式哈希路径长度为87字节（43 + 1 + 43，包含分隔符）
    HP2 = hb_path:hashpath(Msg1, Msg2, #{}),
    %% 断言验证返回结果是二进制类型
    ?assert(is_binary(HP2)),
    %% 断言验证链式哈希路径长度为87字节
    ?assertEqual(87, byte_size(HP2)),
    %% 链式哈希路径功能测试通过，输出成功信息
    ?debugFmt("Chained hashpath: OK", []).
 
complete_workflow_test() ->
    %% 测试功能27：完整配置工作流程测试
    %% 打印工作流程开始标记
    ?debugFmt("=== Complete Configuration Workflow ===", []),
    
    %% 步骤1：检查可用的功能标志
    %% 调用hb_features:all()获取所有功能标志
    Features = hb_features:all(),
    %% 打印功能标志列表
    ?debugFmt("1. Available features: ~p", [maps:keys(Features)]),
    
    %% 步骤2：创建包含设备信息和路径的消息
    %% 消息包含设备标识符和请求路径
    Msg = #{
        <<"device">> => <<"Process@1.0">>,
        <<"path">> => [<<"init">>, <<"execute">>]
    },
    %% 打印消息创建完成信息
    ?debugFmt("2. Created message with path", []),
    
    %% 步骤3：添加私有状态
    %% 使用hb_private:set设置私有计数器状态
    MsgWithPriv = hb_private:set(Msg, <<"state/counter">>, 0, #{}),
    %% 打印私有状态添加完成信息
    ?debugFmt("3. Added private state", []),
    
    %% 步骤4：处理路径元素
    %% 使用hb_path:pop_request弹出路径的第一个元素
    {Head, Rest} = hb_path:pop_request(MsgWithPriv, #{}),
    %% 断言验证弹出的元素为"init"
    ?assertEqual(<<"init">>, Head),
    %% 打印正在处理的路径元素
    ?debugFmt("4. Processing path element: ~s", [Head]),
    
    %% 步骤5：更新私有状态
    %% 使用hb_private:set更新私有计数器值
    UpdatedMsg = hb_private:set(Rest, <<"state/counter">>, 1, #{}),
    %% 使用hb_private:get获取更新后的计数器值
    Counter = hb_private:get(<<"state/counter">>, UpdatedMsg, #{}),
    %% 断言验证计数器值已更新为1
    ?assertEqual(1, Counter),
    %% 打印更新后的计数器值
    ?debugFmt("5. Updated counter to: ~p", [Counter]),
    
    %% 步骤6：清理私有状态以进行序列化
    %% 使用hb_private:reset移除所有私有数据
    Cleaned = hb_private:reset(UpdatedMsg),
    %% 断言验证清理后的消息不包含私有数据
    ?assertEqual(#{}, hb_private:from_message(Cleaned)),
    %% 打印清理完成信息
    ?debugFmt("6. Cleaned private state for serialization", []),
    
    %% 打印所有测试通过标记
    ?debugFmt("=== All tests passed! ===", []).
