-module(test_hb9).
%% @doc HyperBEAM HTTP服务器测试模块
%% 
%% 本模块测试HyperBEAM的HTTP服务器核心功能，包括：
%% - 服务器启动与配置（start_test）
%% - 节点URL格式验证（node_url_test）
%% - 节点可访问性测试（node_accessible_test）
%% - 自定义选项配置（custom_opts_test）
%% - 配置更新机制（config_update_test）
%% - 配置历史追踪（history_test）
%% - 启动钩子执行（hook_test）
%% - 服务器重启行为（restart_test）
%% 
%% HyperBEAM架构说明：
%% - HTTP服务器（hb_http_server模块）是HyperBEAM的核心组件之一
%% - 它将AO-Core协议与HTTP协议连接起来，使节点可通过网络访问
%% - 每个节点有一个唯一的URL，格式为http://localhost:{port}/
%% - 节点支持自定义配置选项，通过Opts消息进行传递
%% - 节点启动时可以执行钩子函数（hook），用于初始化或修改配置

-include_lib("eunit/include/eunit.hrl").
%% 引入EUnit测试框架的头文件，提供?assertEqual、?assert、?debugFmt等测试宏

-include("include/hb.hrl").
%% 引入HyperBEAM项目定义的头文件，包含项目级别的宏定义和类型声明

%% Test basic server startup
%% @doc 测试用例：基本服务器启动功能
%% 
%% 本测试验证HTTP服务器能否成功启动：
%% 1. 创建包含随机端口和私钥的配置
%% 2. 调用hb_http_server:start/1启动服务器
%% 3. 验证返回的Pid是有效的进程标识符
%% 
%% 技术细节：
%% - 端口号在10000-20000范围内随机生成，避免端口冲突
%% - 使用ar_wallet:new()创建测试钱包，用于签名和身份验证
%% - hb_http_server:start/1返回{ok, Pid}或错误
start_test() ->
    Config = #{
        port => 10000 + rand:uniform(10000),
        %% 随机生成端口号，范围10000-20000
        %% 避免使用低端口（<1024）和常见端口，减少冲突风险
        priv_wallet => ar_wallet:new()
        %% 创建新的Arweave钱包实例
        %% 钱包用于HTTP请求的签名验证和身份标识
    },
    {ok, Pid} = hb_http_server:start(Config),
    %% 调用hb_http_server:start/1启动HTTP服务器
    %% Config包含服务器的所有配置选项
    %% 返回{ok, Pid}表示服务器成功启动，Pid是监听进程的进程标识符
    ?assert(is_pid(Pid)).
    %% 验证返回的Pid确实是进程标识符类型
    %% EUnit的?assert宏用于布尔值断言，为真则测试通过

%% Test node URL format
%% @doc 测试用例：节点URL格式验证
%% 
%% 本测试验证启动的节点URL格式是否符合规范：
%% 1. 调用hb_http_server:start_node/0启动默认节点
%% 2. 验证返回结果是二进制类型
%% 3. 验证URL包含"http://localhost:"前缀
%% 4. 验证URL以"/"结尾
%% 
%% URL格式规范：
%% - 协议：http://（支持HTTP/2）
%% - 主机：localhost（本地回环地址）
%% - 端口：动态分配
%% - 路径：必须以"/"结尾
node_url_test() ->
    Node = hb_http_server:start_node(),
    %% 启动一个默认配置的HTTP服务器节点
    %% 不传入参数时使用默认配置
    %% 返回节点的访问URL，如<<"http://localhost:12345/">>
    ?assert(is_binary(Node)),
    %% 验证Node是二进制类型
    %% URL在HyperBEAM中使用二进制字符串表示
    ?assert(binary:match(Node, <<"http://localhost:">>) =/= nomatch),
    %% 验证URL包含正确的协议和主机前缀
    %% binary:match/2在二进制中查找子串，找到返回位置，找不到返回nomatch
    %% URL should end with /
    ?assertEqual(<<"/">>, binary:part(Node, byte_size(Node) - 1, 1)).
    %% 验证URL以斜杠"/"结尾
    %% binary:part/3从二进制中提取子串
    %% 参数：二进制、起始位置、长度
    %% byte_size(Node) - 1是最后一个字符的位置

%% Test node accessibility
%% @doc 测试用例：节点可访问性测试
%% 
%% 本测试验证启动的节点能否正确响应HTTP请求：
%% 1. 启动带有默认配置的节点
%% 2. 向/~meta@1.0/info端点发送GET请求
%% 3. 验证返回结果是映射类型
%% 
%% 端点说明：
%% - /~meta@1.0/info：返回节点的元信息
%% - 元信息包含节点配置、状态、已加载模块等
%% - 这是测试节点是否正常工作的基本方法
node_accessible_test() ->
    Node = hb_http_server:start_node(#{}),
    %% 启动节点，传入空映射使用默认配置
    %% 显式传入#{}表示使用默认选项，不添加额外配置
    {ok, Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    %% 使用hb_http:get/3向节点发送GET请求
    %% 参数：节点URL、路径、选项映射
    %% 返回{ok, Info}，Info是包含节点元信息的映射
    ?assert(is_map(Info)).
    %% 验证返回的Info是映射类型
    %% 元信息应该是一个映射，包含各种配置和状态信息

%% Test custom options
%% @doc 测试用例：自定义选项配置测试
%% 
%% 本测试验证节点能否正确处理和返回自定义配置选项：
%% 1. 启动带有自定义选项的节点
%% 2. 向/~meta@1.0/info端点发送请求
%% 3. 验证自定义选项被正确存储和返回
%% 
%% 自定义选项机制：
%% - 节点配置通过Opts消息传递
%% - 自定义键值对会被存储在节点配置中
%% - 通过/~meta@1.0/info可以读取所有配置
custom_opts_test() ->
    Node = hb_http_server:start_node(#{
        %% 启动节点时传入自定义配置选项
        <<"my-key">> => <<"my-value">>
        %% 自定义键值对
        %% 这些选项会被合并到节点配置中
    }),
    {ok, Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    %% 获取节点元信息
    ?assertEqual(<<"my-value">>, hb_ao:get(<<"my-key">>, Info, #{})).
    %% 验证自定义选项被正确存储和返回
    %% hb_ao:get/4从Info映射中提取指定键的值
    %% 参数：键名、源映射、默认值、选项
    %% 如果键不存在，返回默认值not_found

%% Test configuration updates
%% @doc 测试用例：配置更新功能测试
%% 
%% 本测试验证节点配置能否被动态更新：
%% 1. 创建钱包并启动节点
%% 2. 获取当前节点配置
%% 3. 使用hb_http_server:set_opts/2更新配置
%% 4. 验证新配置包含更新后的值
%% 
%% 配置更新机制：
%% - set_opts/2接受一个Opts消息作为更新请求
%% - 返回更新后的完整配置映射
%% - 更新是原子性的，要么全部成功，要么全部失败
config_update_test() ->
    Wallet = ar_wallet:new(),
    %% 创建新钱包，用于标识节点身份
    _Node = hb_http_server:start_node(#{priv_wallet => Wallet}),
    %% 启动节点，指定使用新创建的钱包
    %% 下划线前缀表示此变量未使用，消除编译器警告
    
    Opts = hb_http_server:get_opts(#{
        http_server => hb_util:human_id(ar_wallet:to_address(Wallet))
    }),
    %% 获取当前节点的配置选项
    %% get_opts/1根据http_server标识获取对应节点配置
    %% 参数是一个映射，包含查询条件
    %% 返回当前节点的完整配置映射
    
    Request = #{<<"new-key">> => <<"new-value">>},
    %% 创建配置更新请求
    %% 指定要添加或修改的键值对
    {ok, UpdatedOpts} = hb_http_server:set_opts(Request, Opts),
    %% 调用set_opts/2执行配置更新
    %% 参数：更新请求、当前配置
    %% 返回{ok, UpdatedOpts}，UpdatedOpts是更新后的配置
    %% 注意：原配置Opts不会被修改，返回的是新配置映射
    
    ?assertEqual(
        <<"new-value">>, 
        hb_opts:get(<<"new-key">>, not_found, UpdatedOpts)
    ).
    %% 验证新配置包含更新后的值
    %% hb_opts:get/3从配置中获取指定键的值
    %% 参数：键名、默认值、配置映射
    %% 如果键不存在，返回指定的默认值not_found

%% Test configuration history
%% @doc 测试用例：配置历史记录测试
%% 
%% 本测试验证节点的配置历史记录功能：
%% 1. 创建钱包并启动节点
%% 2. 执行第一次配置更新
%% 3. 验证历史记录长度为1
%% 4. 执行第二次配置更新
%% 5. 验证历史记录长度为2
%% 
%% 历史记录机制：
%% - 每次配置更新都会记录到node_history列表中
%% - 历史记录按时间顺序保存最近的配置变更
%% - 通过hb_opts:get(node_history, [], Opts)获取历史记录
%% - 可以用于审计、回滚或调试配置变更
history_test() ->
    Wallet = ar_wallet:new(),
    _Node = hb_http_server:start_node(#{priv_wallet => Wallet}),
    
    Opts = hb_http_server:get_opts(#{
        http_server => hb_util:human_id(ar_wallet:to_address(Wallet))
    }),
    
    %% First update
    {ok, Opts1} = hb_http_server:set_opts(#{<<"k1">> => <<"v1">>}, Opts),
    %% 执行第一次配置更新，添加键k1
    History1 = hb_opts:get(node_history, [], Opts1),
    %% 获取配置历史记录
    %% node_history键存储所有配置变更的历史列表
    %% 如果不存在，返回空列表[]
    ?assertEqual(1, length(History1)),
    %% 验证历史记录长度为1
    
    %% Second update
    {ok, Opts2} = hb_http_server:set_opts(#{<<"k2">> => <<"v2">>}, Opts1),
    %% 执行第二次配置更新，添加键k2
    History2 = hb_opts:get(node_history, [], Opts2),
    %% 获取更新后的历史记录
    ?assertEqual(2, length(History2)).
    %% 验证历史记录长度为2
    %% 两次更新应该都记录在历史中

%% Test startup hook
%% @doc 测试用例：启动钩子执行测试
%% 
%% 本测试验证节点启动时钩子函数能否正确执行：
%% 1. 定义一个启动钩子函数
%% 2. 启动带有钩子配置的节点
%% 3. 向节点发送请求，触发钩子执行
%% 4. 验证钩子中设置的值存在
%% 
%% 钩子机制说明：
%% - 钩子在节点启动时执行，可以修改节点配置
%% - 钩子定义在节点的"on"配置中
%% - "start"钩子在节点启动时执行
%% - 钩子函数接收消息并返回修改后的消息
hook_test() ->
    Node = hb_http_server:start_node(#{
        on => #{
            <<"start">> => #{
                <<"device">> => #{
                    <<"start">> => fun(_, #{<<"body">> := Msg}, _) ->
                        %% 定义启动钩子函数
                        %% 参数：_（未使用）、消息映射、_（未使用）
                        %% 从消息中提取body键的值
                        {ok, #{<<"body">> => Msg#{<<"hook-ran">> => true}}}
                        %% 返回修改后的消息
                        %% 在body中添加hook-ran键，值为true
                    end
                }
            }
        }
    }),
    %% 启动节点，配置启动钩子
    %% on.start.device.start：钩子路径
    %% fun：匿名函数作为钩子处理器
    {ok, Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    %% 获取节点元信息
    ?assert(hb_ao:get(<<"hook-ran">>, Info, false, #{})).
    %% 验证钩子函数已执行
    %% 从Info中获取hook-ran键的值
    %% 如果不存在，返回默认值false
    %% 断言结果为true表示钩子已执行

%% Test server restart with same wallet
%% @doc 测试用例：服务器重启行为测试
%% 
%% 本测试验证使用相同钱包启动多个节点时的行为：
%% 1. 创建钱包和基础配置
%% 2. 启动第一个节点
%% 3. 使用相同钱包启动第二个节点
%% 4. 验证第二个节点可以正确访问
%% 
%% 钱包与节点关系：
%% - 钱包地址唯一标识一个节点身份
%% - 相同钱包配置的节点会共享某些状态
%% - 第二个节点会替换第一个节点的处理
restart_test() ->
    Wallet = ar_wallet:new(),
    %% 创建新钱包，用于标识节点身份
    BaseOpts = #{
        <<"test-key">> => <<"server-1">>,
        %% 测试键，用于验证节点身份
        priv_wallet => Wallet,
        %% 指定使用新创建的钱包
        protocol => http2
        %% 指定使用HTTP/2协议
    },
    _Node1 = hb_http_server:start_node(BaseOpts),
    %% 使用基础配置启动第一个节点
    %% 节点test-key值为"server-1"
    Node2 = hb_http_server:start_node(BaseOpts#{<<"test-key">> => <<"server-2">>}),
    %% 使用修改后的配置启动第二个节点
    %% test-key值改为"server-2"
    %% 第二个节点会接管第一个节点的请求处理
    ?assertEqual(
        {ok, <<"server-2">>},
        hb_http:get(Node2, <<"/~meta@1.0/info/test-key">>, #{protocol => http2})
    ).
    %% 验证第二个节点正确响应
    %% /~meta@1.0/info/test-key路径直接获取test-key的值
    %% 应该返回"server-2"，证明是第二个节点在处理请求
    %% 协议选项设置为http2确保使用HTTP/2
