-module(test_dev1).
%% @doc HyperBEAM设备处理器测试模块
%% 
%% 本模块测试HyperBEAM中核心设备处理器的功能，包括：
%% - 消息基本操作（获取、列出键、设置）
%% - 设备栈（stack@1.0）的两种执行模式：fold和map
%% - 多通道设备（multipass@1.0）的重复执行机制
%% - 去重设备（dedup@1.0）的请求去重功能
%% - 完整的设备流水线组合
%% 
%% HyperBEAM架构说明：
%% - 设备（Device）是AO-Core的核心抽象，代表可执行的计算单元
%% - 消息通过hb_ao:resolve/2,3函数在设备上执行
%% - 设备栈（dev_stack）管理多个子设备的顺序执行
%% - 消息格式：#{<<"device">> => DeviceID, ...其他数据}
%% 
%% 设备处理器：
%% - stack@1.0：设备栈容器，管理子设备执行
%% - multipass@1.0：支持多次通道执行的设备
%% - dedup@1.0：请求去重，防止重复处理

-include_lib("eunit/include/eunit.hrl").
%% 引入EUnit测试框架的头文件，提供断言宏和测试工具

%% 运行方式：rebar3 eunit --module=test_dev1
 
%% @doc 测试用例：消息基本操作
%% 
%% 本测试验证HyperBEAM消息的基本操作功能：
%% 1. 从消息中获取键值
%% 2. 列出消息的所有键
%% 3. 设置消息的新值
%% 
%% hb_ao:resolve/3 函数说明：
%% - 第一个参数是基础消息（Msg）
%% - 第二个参数是请求消息，包含操作指令
%% - 第三个参数是选项映射
%% - 返回{ok, UpdatedMessage}或错误
%% 
%% 消息操作机制：
%% - 获取值：请求消息包含<<"path">>键，值为要获取的键名
%% - 列出键：请求消息包含keys关键字
%% - 设置值：请求消息包含要设置的键值对
message_basics_test() ->
    %% 创建测试消息，包含两个键值对
    %% 消息是HyperBEAM的基本数据单元，格式为映射（Map）
    Msg = #{ <<"name">> => <<"Alice">>, <<"age">> => 30 },
    
    %% 测试1：获取消息中的键值
    %% 调用hb_ao:resolve，指定获取<<"name">>键的值
    %% 返回{ok, Value}，Value是获取的值
    {ok, <<"Alice">>} = hb_ao:resolve(Msg, <<"name">>, #{}),
    %% 输出调试信息，确认获取成功
    ?debugFmt("Get value: OK", []),
    
    %% 测试2：列出消息的所有键
    %% 使用特殊关键字keys请求列出消息的所有键
    %% 返回{ok, KeysList}，KeysList是键名列表
    {ok, Keys} = hb_ao:resolve(Msg, keys, #{}),
    %% 断言验证返回的键数量为2
    ?assertEqual(2, length(Keys)),
    ?debugFmt("List keys: OK", []),
    
    %% 测试3：设置消息的新值
    %% 请求消息包含<<"path">> => <<"set">>表示设置操作
    %% 请求消息同时包含要设置的键值对<<"city">> => <<"Tokyo">>
    %% 返回{ok, UpdatedMsg}，UpdatedMsg是更新后的消息
    {ok, Updated} = hb_ao:resolve(
        Msg,
        #{ <<"path">> => <<"set">>, <<"city">> => <<"Tokyo">> },
        #{}
    ),
    %% 断言验证更新后的消息包含新的city键
    ?assertEqual(<<"Tokyo">>, maps:get(<<"city">>, Updated)),
    ?debugFmt("Set value: OK", []).
 
%% @doc 测试用例：设备栈的折叠模式（Fold Mode）
%% 
%% 本测试验证设备栈在fold模式下的功能：
%% - Fold模式是设备栈的默认执行模式
%% - 子设备按顺序（编号1,2,3...）依次执行
%% - 前一个设备的输出作为下一个设备的输入（状态传递）
%% - 最终结果是累积所有设备处理后的状态
%% 
%% 设备栈配置说明：
%% - <<"device">> => <<"stack@1.0">>：指定使用设备栈处理器
%% - <<"device-stack">>：包含子设备的映射，键为设备编号
%% - <<"result">>：设备间传递的累积状态
%% 
%% 子设备生成：
%% - dev_stack:generate_append_device(Separator) 生成追加设备
%% - 追加设备接收<<"bin">>参数，追加到result末尾
stack_fold_test() ->
    %% 创建追加设备A，使用"+A"作为分隔符
    %% 该设备会将新数据追加到result字段
    AppendA = dev_stack:generate_append_device(<<"+A">>),
    %% 创建追加设备B，使用"+B"作为分隔符
    AppendB = dev_stack:generate_append_device(<<"+B">>),
    
    %% 构建设备栈配置
    Stack = #{
        <<"device">> => <<"stack@1.0">>,
        %% 指定设备类型为stack@1.0
        <<"device-stack">> => #{
            <<"1">> => AppendA,
            %% 设备1：追加"+A"
            <<"2">> => AppendB
            %% 设备2：追加"+B"
        },
        <<"result">> => <<"START">>
        %% 初始状态：result字段初始值
    },
    
    %% 执行设备栈
    %% 请求调用append路径，传入<<"bin">> => <<"!">>
    %% 设备栈会依次调用设备1和设备2
    {ok, Result} = hb_ao:resolve(
        Stack,
        #{ <<"path">> => <<"append">>, <<"bin">> => <<"!">> },
        #{}
    ),
    
    %% 验证执行结果
    %% 预期流程：
    %% 1. 初始result = "START"
    %% 2. 设备1处理：result = "START" + "A" + "!" = "START+A!"
    %% 3. 设备2处理：result = "START+A!" + "B" + "!" = "START+A!+B!"
    ?assertEqual(<<"START+A!+B!">>, maps:get(<<"result">>, Result)),
    %% 输出调试信息
    ?debugFmt("Stack fold: ~s", [maps:get(<<"result">>, Result)]).
 
%% @doc 测试用例：设备栈的映射模式（Map Mode）
%% 
%% 本测试验证设备栈在map模式下的功能：
%% - Map模式下所有子设备并行执行（逻辑上）
%% - 每个设备的输出存储在独立的命名空间（设备编号作为键）
%% - 不会像fold模式那样累积状态
%% - 适用于需要对同一输入执行多个独立操作的场景
%% 
%% Map模式配置：
%% - 在请求消息中设置<<"mode">> => <<"Map">>
%% - 或者在设备栈消息中设置<<"mode">> => <<"Map">>
%% - 请求消息中的mode优先级高于设备栈配置的mode
%% 
%% 结果访问：
%% - 使用"设备编号/result"路径访问各设备的结果
%% - 例如"1/result"访问设备1的结果
stack_map_test() ->
    %% 创建两个追加设备
    AppendA = dev_stack:generate_append_device(<<"+A">>),
    AppendB = dev_stack:generate_append_device(<<"+B">>),
    
    %% 构建设备栈配置
    Stack = #{
        <<"device">> => <<"stack@1.0">>,
        <<"device-stack">> => #{
            <<"1">> => AppendA,
            <<"2">> => AppendB
        },
        <<"result">> => <<"START">>
    },
    
    %% 执行设备栈，使用Map模式
    %% mode设置为<<"Map">>指定使用map模式
    {ok, Result} = hb_ao:resolve(
        Stack,
        #{ <<"path">> => <<"append">>, <<"mode">> => <<"Map">>, <<"bin">> => <<"!">> },
        #{}
    ),
    
    %% 验证设备1的结果：独立执行，只追加一次
    %% "START" + "A" + "!" = "START+A!"
    ?assertEqual(<<"START+A!">>, hb_ao:get(<<"1/result">>, Result, #{})),
    %% 验证设备2的结果：独立执行，只追加一次
    %% "START" + "B" + "!" = "START+B!"
    ?assertEqual(<<"START+B!">>, hb_ao:get(<<"2/result">>, Result, #{})),
    ?debugFmt("Stack map: OK", []).
 
%% @doc 测试用例：多通道设备（Multipass）功能
%% 
%% 本测试验证multipass@1.0设备的多通道执行机制：
%% - Multipass设备可以触发多次执行通道（pass）
%% - 当设备返回{pass, _}时，系统会重新执行整个处理流程
%% - 通常用于需要迭代处理直到满足条件的场景
%% 
%% multipass@1.0 配置：
%% - <<"passes">>：指定总共需要执行的通道数
%% - <<"pass">>：当前执行的通道号（从1开始）
%% - 当通道号小于passes时，返回{pass, _}触发下一次执行
%% - 当通道号等于passes时，返回{ok, _}完成执行
%% 
%% 执行流程示例（passes=2）：
%% 1. 第一次调用：pass=1 < passes=2，返回{pass, _}触发重执行
%% 2. 第二次调用：pass=2 = passes=2，返回{ok, _}完成执行
multipass_test() ->
    %% 创建multipass设备消息
    %% device指定使用multipass@1.0处理器
    Msg1 = #{
        <<"device">> => <<"multipass@1.0">>,
        <<"passes">> => 2,
        %% 指定总共需要2次通道
        <<"pass">> => 1
        %% 当前通道号=1
    },
    
    %% 第一次调用compute
    %% multipass设备检测到pass(1) < passes(2)
    %% 返回{pass, _}表示需要重新执行
    {pass, _} = hb_ao:resolve(Msg1, <<"compute">>, #{}),
    ?debugFmt("Pass 1: triggered repass", []),
    
    %% 创建第二次调用的消息
    %% 将pass改为2
    Msg2 = Msg1#{ <<"pass">> => 2 },
    
    %% 第二次调用compute
    %% multipass设备检测到pass(2) == passes(2)
    %% 返回{ok, _}表示执行完成
    {ok, _} = hb_ao:resolve(Msg2, <<"compute">>, #{}),
    ?debugFmt("Pass 2: complete", []).
 
%% @doc 测试用例：去重设备（Deduplication）功能
%% 
%% 本测试验证dedup@1.0设备的请求去重功能：
%% - 去重设备检测重复的请求（基于dedup-subject）
%% - 相同的请求只会执行一次，后续请求被跳过
%% - 适用于防止重复处理相同数据
%% 
%% 去重机制：
%% - <<"dedup-subject">>：指定用于去重判断的字段
%% - 对于相同subject的请求，dedup设备只处理第一个
%% - 后续相同subject的请求会跳过dedup之后的所有设备
%% 
%% 应用场景：
%% - 防止重复写入数据库
%% - 避免重复发送网络请求
%% - 确保幂等性（Idempotency）
dedup_test() ->
    %% 构建设备栈，包含去重设备和追加设备
    Stack = #{
        <<"device">> => <<"stack@1.0">>,
        <<"dedup-subject">> => <<"request">>,
        %% 指定使用"request"字段值作为去重判断依据
        <<"device-stack">> => #{
            <<"1">> => <<"dedup@1.0">>,
            %% 设备1：去重设备
            <<"2">> => dev_stack:generate_append_device(<<"+PROCESSED">>)
            %% 设备2：追加设备（去重后执行）
        },
        <<"result">> => <<"INIT">>
    },
    
    %% 创建请求消息
    Request = #{ <<"path">> => <<"append">>, <<"bin">> => <<"!">> },
    
    %% 第一次调用：处理请求
    %% dedup检测到新的subject，允许后续处理
    {ok, Msg2} = hb_ao:resolve(Stack, Request, #{}),
    %% 验证结果：追加了"+PROCESSED!"
    ?assertEqual(<<"INIT+PROCESSED!">>, maps:get(<<"result">>, Msg2)),
    ?debugFmt("First call: processed", []),
    
    %% 第二次调用：相同的请求
    %% dedup检测到相同的subject，跳过后续处理
    {ok, Msg3} = hb_ao:resolve(Msg2, Request, #{}),
    %% 验证结果：没有再次追加，保持不变
    ?assertEqual(<<"INIT+PROCESSED!">>, maps:get(<<"result">>, Msg3)),
    ?debugFmt("Second call: deduplicated", []).
 
%% @doc 测试用例：完整的设备流水线
%% 
%% 本测试验证多个设备的组合使用：
%% 1. 去重设备（dedup@1.0）：防止重复处理
%% 2. 验证设备（generate_append_device）：追加"-validated"
%% 3. 转换设备（generate_append_device）：追加"-transformed"
%% 
%% 流水线工作流程：
%% - 请求首先经过去重检查
%% - 通过去重后依次经过验证和转换设备
%% - 每个设备追加自己的标记到结果
%% 
%% 实际应用场景：
%% - 数据处理管道：验证 → 转换 → 存储
%% - Web请求处理：认证 → 授权 → 业务逻辑
%% - 消息处理：解析 → 验证 → 路由
complete_pipeline_test() ->
    ?debugFmt("=== Complete Pipeline Test ===", []),
    
    %% 构建一个处理流水线：验证 → 转换 → 存储
    Pipeline = #{
        <<"device">> => <<"stack@1.0">>,
        <<"device-stack">> => #{
            <<"1">> => <<"dedup@1.0">>,
            %% 第一阶段：去重检查
            <<"2">> => dev_stack:generate_append_device(<<"-validated">>),
            %% 第二阶段：验证，追加"-validated"
            <<"3">> => dev_stack:generate_append_device(<<"-transformed">>)
            %% 第三阶段：转换，追加"-transformed"
        },
        <<"dedup-subject">> => <<"request">>,
        <<"result">> => <<"input">>
    },
    
    %% 执行流水线
    %% bin设置为空字符串，不添加额外分隔符
    {ok, Result} = hb_ao:resolve(
        Pipeline,
        #{ <<"path">> => <<"append">>, <<"bin">> => <<"">> },
        #{}
    ),
    
    %% 预期结果：input-validated-transformed
    Expected = <<"input-validated-transformed">>,
    ?assertEqual(Expected, maps:get(<<"result">>, Result)),
    ?debugFmt("Pipeline result: ~s", [maps:get(<<"result">>, Result)]),
    ?debugFmt("=== All tests passed! ===", []).
