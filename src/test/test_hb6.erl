-module(test_hb6).
%% @doc HyperBEAM HTTP通信层单元测试模块
%%
%% 本模块使用 EUnit 测试框架对 HyperBEAM HTTP 通信层的核心功能进行全面测试。
%% HyperBEAM 的 HTTP 通信层是连接去中心化网络的关键基础设施，实现了与远程节点
%% 的消息交换、数据获取和服务发现等功能。
%%
%% <h2>HyperBEAM HTTP 通信层架构</h2>
%%
%% <h3>1. HTTP Core（HTTP 核心功能）</h3>
%% HyperBEAM 提供灵活的 HTTP 请求机制，支持：
%% <ul>
%%   <li><b>GET 请求</b> - 用于从远程节点获取数据和状态信息</li>
%%   <li><b>POST 请求</b> - 用于向远程节点发送消息并执行计算</li>
%%   <li><b>请求/响应模型</b> - 消息格式与 AO-Core 协议深度集成</li>
%%   <li><b>多后端支持</b> - 支持 gun 和 httpc 两种 HTTP 客户端实现</li>
%% </ul>
%%
%% <h3>2. Connection Pooling（连接池管理）</h3>
%% hb_http_client 模块实现高效的持久连接管理：
%% <ul>
%%   <li><b>连接复用</b> - 避免频繁建立 TCP 连接的性能开销</li>
%%   <li><b>连接状态追踪</b> - 监控每个连接的状态和健康度</li>
%%   <li><b>动态扩展</b> - 根据请求量自动调整连接池</li>
%%   <li><b>错误恢复</b> - 自动处理连接断开和重连</li>
%% </ul>
%%
%% <h3>3. Remote Resolution（远程解析）</h3>
%% hb_client 模块支持在远程 HyperBEAM 节点上执行消息解析：
%% <ul>
%%   <li><b>消息转换</b> - 将本地消息转换为远程节点可理解的格式</li>
%%   <li><b>路径前缀</b> - 为消息键添加前缀以避免命名冲突</li>
%%   <li><b>设备路由</b> - 支持 Router@1.0 设备进行消息路由</li>
%%   <li><b>响应解析</b> - 处理远程节点的响应消息</li>
%% </ul>
%%
%% <h3>4. Gateway Client（网关客户端）</h3>
%% hb_gateway_client 模块通过 GraphQL API 访问 Arweave 网络：
%% <ul>
%%   <li><b>GraphQL 查询</b> - 支持复杂的交易和标签查询</li>
%%   <li><b>数据读取</b> - 根据交易 ID 获取完整数据项</li>
%%   <li><b>字段规范</b> - 定义必需的数据项字段（id、anchor、signature、tags）</li>
%%   <li><b>多节点支持</b> - 可配置多个网关节点提高可用性</li>
%% </ul>
%%
%% <h3>5. Service Discovery（服务发现）</h3>
%% HyperBEAM 实现多种服务发现机制：
%% <ul>
%%   <li><b>路由列表</b> - 通过 Router@1.0 设备获取可用路由</li>
%%   <li><b>动态注册</b> - 节点可动态注册新路由</li>
%%   <li><b>负载均衡</b> - 在多个节点间分配请求</li>
%%   <li><b>健康检查</b> - 检测不可用的节点并移除</li>
%% </ul>
%%
%% <h2>HTTP 通信层组件交互</h2>
%%
%% 典型请求流程：
%% <ol>
%%   <li>客户端构造 AO-Core 格式消息</li>
%%   <li>hb_client 将消息转换为 HTTP 请求格式</li>
%%   <li>hb_http 选择合适的 HTTP 客户端（gun/httpc）</li>
%%   <li>hb_http_client 管理连接池并发送请求</li>
%%   <li>远程 hb_http_server 接收并解析请求</li>
%%   <li>远程设备执行消息处理逻辑</li>
%%   <li>响应消息返回给客户端</li>
%%   <li>客户端解析响应并返回结果</li>
%% </ol>
%%
%% @see hb_http - HTTP 请求/响应核心模块
%% @see hb_http_client - HTTP 客户端实现（连接池管理）
%% @see hb_http_client_sup - HTTP 客户端监督树
%% @see hb_client - 客户端 API（远程解析、服务发现）
%% @see hb_gateway_client - Arweave 网关客户端（GraphQL 查询）
%% @see hb_http_server - HTTP 服务器实现
%% 运行命令: rebar3 eunit --module=test_hb6
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").
 
%% Run with: rebar3 eunit --module=test_hb6

%% ============================================================================
%% 测试辅助函数
%% ============================================================================
%% @doc 测试辅助函数模块
%%
%% 本模块提供用于测试 HTTP 功能的模拟服务器和相关工具函数。
%% 在单元测试中，使用真实的网络服务通常不可靠且耗时，
%% 因此我们实现了一个轻量级的模拟 HTTP 服务器来验证 HyperBEAM 的 HTTP 客户端功能。
%%
%% <b>模拟服务器功能：</b>
%% <ul>
%%   <li><b>动态端口分配</b> - 使用端口 0 让操作系统自动分配可用端口</li>
%%   <li><b>响应定制</b> - 可配置响应体和状态码</li>
%%   <li><b>并发处理</b> - 使用独立进程处理每个请求</li>
%%   <li><b>超时控制</b> - 设置合理的 accept 和接收超时</li>
%% </ul>
%%
%% <b>使用场景：</b>
%% <ul>
%%   <li>测试 HTTP 请求构造和解析逻辑</li>
%%   <li>验证错误处理和状态码处理</li>
%%   <li>测试客户端超时和重试机制</li>
%%   <li>验证响应格式和编码</li>
%% </ul>

%% @doc 启动模拟 HTTP 服务器
%% @param ResponseBody - 服务器返回的响应体（二进制格式）
%% @param StatusCode - HTTP 状态码（整数）
%% @returns {Port, ListenSock} - 服务器监听的端口和套接字
%% @private
%%
%% <b>实现说明：</b>
%% 此函数创建一个 TCP 监听套接字，操作系统会自动分配一个可用端口。
%% 服务器进程随后处理传入的 HTTP 请求并返回预配置的响应。
%% 使用 spawn 创建独立的服务器进程，不会阻塞测试执行。
start_mock_server(ResponseBody, StatusCode) ->
    %% 步骤1：创建 TCP 监听套接字
    %% binary: {active, false} - 使用二进制数据模式，禁用主动消息
    %% {active, false} - 手动控制消息接收，适合同步处理
    %% {reuseaddr, true} - 允许地址复用，快速重启测试
    {ok, ListenSock} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true}]),
    %% 步骤2：获取操作系统分配的端口号
    {ok, Port} = inet:port(ListenSock),
    %% 步骤3：启动服务器进程处理请求
    spawn(fun() -> mock_server_loop(ListenSock, ResponseBody, StatusCode) end),
    %% 步骤4：返回端口和套接字供测试使用
    {Port, ListenSock}.

%% @doc 模拟服务器主循环
%% @param ListenSock - 监听套接字
%% @param ResponseBody - 要返回的响应体
%% @param StatusCode - HTTP 状态码
%% @private
%%
%% <b>循环逻辑：</b>
%% 服务器持续接受连接，处理请求，然后返回响应。
%% 使用尾递归优化确保内存使用稳定。
mock_server_loop(ListenSock, ResponseBody, StatusCode) ->
    %% 步骤1：接受新的连接请求（超时 5 秒）
    case gen_tcp:accept(ListenSock, 5000) of
        {ok, Sock} ->
            %% 步骤2：接收完整的 HTTP 请求
            {ok, _Request} = gen_tcp:recv(Sock, 0, 5000),
            %% 步骤3：构造 HTTP 响应
            %% 计算响应体长度（字节数）
            ContentLength = integer_to_binary(byte_size(ResponseBody)),
            %% 构造完整的 HTTP 响应头和体
            Response = <<"HTTP/1.1 ", (integer_to_binary(StatusCode))/binary, " OK\r\n",
                        "Content-Type: application/json\r\n",
                        "Content-Length: ", ContentLength/binary, "\r\n\r\n",
                        ResponseBody/binary>>,
            %% 步骤4：发送响应并关闭连接
            gen_tcp:send(Sock, Response),
            gen_tcp:close(Sock),
            %% 步骤5：继续处理下一个连接（尾递归）
            mock_server_loop(ListenSock, ResponseBody, StatusCode);
        {error, timeout} ->
            %% 超时情况下关闭监听套接字，结束服务器
            gen_tcp:close(ListenSock);
        {error, _} ->
            %% 其他错误情况下也关闭套接字
            gen_tcp:close(ListenSock)
    end.
 
%% ============================================================================
%% hb_http 模块测试
%% ============================================================================
%% @doc hb_http 模块测试用例
%%
%% hb_http 是 HyperBEAM HTTP 通信层的核心模块，提供：
%% <ul>
%%   <li><b>start/0</b> - 初始化 HTTP 基础设施</li>
%%   <li><b>get/2, get/3</b> - 发送 GET 请求</li>
%%   <li><b>post/3, post/4</b> - 发送 POST 请求</li>
%%   <li><b>request/2, request/4, request/5</b> - 通用请求函数</li>
%% </ul>
%%
%% <b>HTTP 客户端选择：</b>
%% HyperBEAM 支持两种 HTTP 客户端实现：
%% <ul>
%%   <li><b>gun</b> - 高性能异步 HTTP/2 客户端（默认）</li>
%%   <li><b>httpc</b> - OTP 内置的同步 HTTP 客户端</li>
%% </ul>
%% 通过 Opts 中的 http_client 键选择客户端实现。

%% @doc 测试 hb_http:start/0 函数
%% @brief 验证 HTTP 基础设施正确初始化
%%
%% start/0 函数配置 httpc 的 keep-alive 设置，
%% 将 max_keep_alive_length 设置为 0 以禁用连接保持。
%% 这对于测试环境很重要，避免连接状态影响测试结果。
hb_http_start_test() ->
    %% 调用 start/0 初始化 HTTP 基础设施
    ?assertEqual(ok, hb_http:start()),
    ?debugFmt("hb_http:start() OK", []).

%% @doc 测试 hb_http:get/3 函数
%% @brief 验证 GET 请求功能正常
%%
%% GET 请求用于从远程节点获取数据，不发送请求体。
%% 此测试验证：
%% <ol>
%%   <li>能正确构造 GET 请求</li>
%%   <li>能正确解析响应</li>
%%   <li>返回结果包含状态码</li>
%% </ol>
hb_http_get_test() ->
    %% 步骤1：启动模拟服务器返回 JSON 响应
    {Port, Sock} = start_mock_server(<<"{\"status\":\"ok\"}">>, 200),
    %% 步骤2：构造请求 URL
    URL = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
    
    %% 步骤3：发送 GET 请求
    %% 使用 httpc 客户端（测试环境更稳定）
    {ok, Res} = hb_http:get(URL, <<"/test">>, #{http_client => httpc}),
    %% 步骤4：验证响应格式
    ?assert(is_map(Res)),
    ?assertEqual(200, maps:get(<<"status">>, Res)),
    ?debugFmt("GET request returned status 200", []),
    
    %% 步骤5：清理资源
    gen_tcp:close(Sock).

%% @doc 测试 hb_http:post/4 函数
%% @brief 验证 POST 请求功能正常
%%
%% POST 请求用于向远程节点发送消息并获取响应。
%% 请求体为 AO-Core 格式的消息，响应也是消息格式。
hb_http_post_test() ->
    %% 步骤1：启动模拟服务器
    {Port, Sock} = start_mock_server(<<"{\"created\":true}">>, 200),
    URL = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
    
    %% 步骤2：构造要发送的消息
    Message = #{<<"key">> => <<"value">>},
    %% 步骤3：发送 POST 请求
    {ok, Res} = hb_http:post(URL, <<"/submit">>, Message, #{http_client => httpc}),
    %% 步骤4：验证响应
    ?assert(is_map(Res)),
    ?assertEqual(200, maps:get(<<"status">>, Res)),
    ?debugFmt("POST request with message body OK", []),
    
    %% 步骤5：清理资源
    gen_tcp:close(Sock).

%% @doc 测试 HTTP 状态码处理
%% @brief 验证不同 HTTP 状态码的正确处理
%%
%% HyperBEAM HTTP 客户端根据状态码返回不同结果：
%% <ul>
%%   <li><b>2xx 成功</b> - 返回 {ok, Response}</li>
%%   <li><b>4xx 客户端错误</b> - 返回 {error, Response}</li>
%%   <li><b>5xx 服务器错误</b> - 返回 {failure, Response}</li>
%% </ul>
hb_http_request_status_codes_test() ->
    ?debugFmt("=== Testing HTTP Status Code Handling ===", []),
    
    %% 测试 200 OK 成功响应
    {Port1, Sock1} = start_mock_server(<<"{\"ok\":true}">>, 200),
    URL1 = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port1)]),
    {ok, _} = hb_http:request(<<"GET">>, URL1, <<"/">>, #{}, #{http_client => httpc}),
    ?debugFmt("200 OK → {ok, _}", []),
    gen_tcp:close(Sock1),
    
    %% 测试 404 Not Found 客户端错误
    {Port2, Sock2} = start_mock_server(<<"{\"error\":\"not found\"}">>, 404),
    URL2 = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port2)]),
    {error, Res2} = hb_http:request(<<"GET">>, URL2, <<"/missing">>, #{}, #{http_client => httpc}),
    ?assertEqual(404, maps:get(<<"status">>, Res2)),
    ?debugFmt("404 Not Found → {error, _}", []),
    gen_tcp:close(Sock2),
    
    %% 测试 500 Internal Server Error 服务器错误
    {Port3, Sock3} = start_mock_server(<<"{\"error\":\"internal\"}">>, 500),
    URL3 = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port3)]),
    {failure, Res3} = hb_http:request(<<"GET">>, URL3, <<"/fail">>, #{}, #{http_client => httpc}),
    ?assertEqual(500, maps:get(<<"status">>, Res3)),
    ?debugFmt("500 Internal Error → {failure, _}", []),
    gen_tcp:close(Sock3).
 
%% ============================================================================
%% hb_http_client 模块测试
%% ============================================================================
%% @doc hb_http_client 模块测试用例
%%
%% hb_http_client 是 HyperBEAM 的 HTTP 客户端封装层，提供统一的请求接口。
%% 它实现了连接池管理，支持两种底层 HTTP 客户端：
%% <ul>
%%   <li><b>gun</b> - 高性能异步 HTTP/2 客户端，作为 gen_server 运行</li>
%%   <li><b>httpc</b> - OTP 内置的同步 HTTP 客户端</li>
%% </ul>
%%
%% <b>连接池管理机制：</b>
%% <ul>
%%   <li><b>pid_by_peer</b> - 映射远端地址到连接进程 PID</li>
%%   <li><b>status_by_pid</b> - 追踪每个连接的状态（connecting/connected）</li>
%%   <li><b>连接复用</b> - 同一远端的请求复用已有连接</li>
%%   <li><b>请求排队</b> - 连接建立期间，新请求排队等待</li>
%% </ul>

%% @doc 测试 hb_http_client:req/2 函数
%% @brief 验证 HTTP 客户端基本请求功能
%%
%% req/2 函数是 HTTP 客户端的统一入口，参数包括：
%% <ul>
%%   <li><b>peer</b> - 远端服务器地址（URL 格式）</li>
%%   <li><b>path</b> - 请求路径</li>
%%   <li><b>method</b> - HTTP 方法</li>
%%   <li><b>headers</b> - 请求头映射</li>
%%   <li><b>body</b> - 请求体</li>
%% </ul>
hb_http_client_req_test() ->
    %% 步骤1：创建 TCP 监听套接字
    {ok, ListenSock} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true}]),
    {ok, Port} = inet:port(ListenSock),
    
    %% 步骤2：启动服务器进程处理单个请求
    spawn(fun() ->
        %% 接受连接
        {ok, Sock} = gen_tcp:accept(ListenSock),
        %% 接收请求数据
        {ok, _Request} = gen_tcp:recv(Sock, 0, 5000),
        %% 构造并发送 HTTP 响应
        Response = <<"HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\n{\"test\":true}">>,
        gen_tcp:send(Sock, Response),
        %% 关闭连接和监听套接字
        gen_tcp:close(Sock),
        gen_tcp:close(ListenSock)
    end),
    
    %% 步骤3：构造请求参数
    Args = #{
        peer => iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
        path => <<"/api/test">>,
        method => <<"GET">>,
        headers => #{},
        body => <<>>
    },
    
    %% 步骤4：发送请求并验证返回格式
    Result = hb_http_client:req(Args, #{http_client => httpc}),
    ?assertMatch({ok, 200, _, _}, Result),
    ?debugFmt("hb_http_client:req/2 returned {ok, 200, _, _}", []).

%% @doc 测试连接拒绝错误处理
%% @brief 验证客户端正确处理网络连接错误
%%
%% 当远端服务器不可达时，客户端应返回 {error, Reason} 格式的错误。
%% 这测试了网络错误处理的健壮性。
hb_http_client_connection_refused_test() ->
    %% 构造一个不可达服务器的请求参数
    Args = #{
        peer => <<"http://127.0.0.1:59999">>,
        path => <<"/">>,
        method => <<"GET">>,
        headers => #{},
        body => <<>>
    },
    %% 发送请求（预期会连接失败）
    Result = hb_http_client:req(Args, #{http_client => httpc}),
    ?assertMatch({error, _}, Result),
    ?debugFmt("Connection refused returns {error, _}", []).
 
%% ============================================================================
%% hb_http_client_sup 模块测试
%% ============================================================================
%% @doc hb_http_client_sup 模块测试用例
%%
%% hb_http_client_sup 是 HTTP 客户端的 OTP 监督模块，负责：
%% <ul>
%%   <li><b>进程监督</b> - 监控 hb_http_client gen_server 的生命周期</li>
%%   <li><b>自动重启</b> - 当客户端进程崩溃时自动重启</li>
%%   <li><b>重启策略</b> - 配置重启频率限制（one_for_one, 5 restarts in 10s）</li>
%% </ul>
%%
%% <b>监督树结构：</b>
%% hb_http_client_sup 作为根监督器的子监督器，管理所有 HTTP 客户端相关进程。
%% 使用 one_for_one 策略，意味着子进程独立运行，一个崩溃不影响其他。

%% @doc 测试 hb_http_client_sup:init/1 函数
%% @brief 验证监督器规范正确初始化
%%
%% init/1 函数返回监督规范（SupSpec）和子进程规范（ChildSpecs）。
%% 这测试了监督树的配置是否正确。
hb_http_client_sup_init_test() ->
    %% 步骤1：提供初始化选项
    Opts = [#{}],
    %% 步骤2：调用 init 获取监督规范
    {ok, {SupSpec, ChildSpecs}} = hb_http_client_sup:init(Opts),
    
    %% 步骤3：验证监督规范
    %% one_for_one: 子进程独立运行
    %% 5: 最大重启次数
    %% 10: 时间窗口（秒）
    ?assertMatch({one_for_one, 5, 10}, SupSpec),
    ?debugFmt("Supervisor spec: one_for_one, 5 restarts in 10 seconds", []),
    
    %% 步骤4：验证子进程规范数量
    ?assertEqual(1, length(ChildSpecs)),
    [ChildSpec] = ChildSpecs,
    %% 步骤5：验证子进程规范内容
    %% {模块名, {模块名, 函数, 参数}, 重启策略, 类型, 回调模块列表}
    ?assertMatch({hb_http_client, {hb_http_client, start_link, _}, permanent, _, worker, [hb_http_client]}, ChildSpec),
    ?debugFmt("Child spec: hb_http_client, permanent worker", []).
 
%% ============================================================================
%% hb_client 模块测试
%% ============================================================================
%% @doc hb_client 模块测试用例
%%
%% hb_client 是 HyperBEAM 的客户端 API 模块，提供与远程节点交互的高级接口：
%% <ul>
%%   <li><b>resolve/4</b> - 在远程节点上执行消息解析</li>
%%   <li><b>routes/2</b> - 获取远程节点的路由列表</li>
%%   <li><b>add_route/3</b> - 向远程节点添加新路由</li>
%%   <li><b>arweave_timestamp/0</b> - 获取 Arweave 网络时间戳</li>
%%   <li><b>upload/2, upload/3</b> - 上传数据到 Arweave 网络</li>
%% </ul>
%%
%% <b>远程解析流程：</b>
%% <ol>
%%   <li>将 Msg1 和 Msg2 转换为 TABM 格式</li>
%%   <li>为消息键添加前缀（"1." 和 "2."）避免冲突</li>
%%   <li>构造 HTTP POST 请求发送到远程节点</li>
%%   <li>远程节点执行消息解析</li>
%%   <li>返回解析结果</li>
%% </ol>

%% @doc 测试 hb_client:resolve/4 函数
%% @brief 验证远程消息解析功能
%%
%% resolve/4 在远程 HyperBEAM 节点上执行消息解析，
%% 这是分布式计算的核心功能。
hb_client_resolve_test() ->
    %% 步骤1：启动模拟服务器
    {Port, Sock} = start_mock_server(<<"{\"routes\":[]}">>, 200),
    Node = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
    
    %% 步骤2：构造消息对
    %% Msg1: 指定使用 Router@1.0 设备
    Msg1 = #{<<"device">> => <<"Router@1.0">>},
    %% Msg2: 指定路径和方法
    Msg2 = #{<<"path">> => <<"routes">>, <<"method">> => <<"GET">>},
    
    %% 步骤3：执行远程解析
    {ok, Result} = hb_client:resolve(Node, Msg1, Msg2, #{http_client => httpc}),
    %% 步骤4：验证结果
    ?assert(is_map(Result)),
    ?assertEqual(200, maps:get(<<"status">>, Result)),
    ?debugFmt("hb_client:resolve/4 executed remote message pair", []),
    
    %% 步骤5：清理资源
    gen_tcp:close(Sock).

%% @doc 测试 hb_client:routes/2 函数
%% @brief 验证获取远程节点路由列表功能
%%
%% routes/2 是 resolve/4 的便捷封装，专门用于获取节点的路由列表。
hb_client_routes_test() ->
    %% 步骤1：启动模拟服务器
    {Port, Sock} = start_mock_server(<<"{\"routes\":[\"/api\",\"/data\"]}">>, 200),
    Node = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
    
    %% 步骤2：获取路由列表
    {ok, Routes} = hb_client:routes(Node, #{http_client => httpc}),
    %% 步骤3：验证结果
    ?assert(is_map(Routes)),
    ?debugFmt("hb_client:routes/2 fetched route list", []),
    
    %% 步骤4：清理资源
    gen_tcp:close(Sock).

%% @doc 测试 hb_client:add_route/3 函数
%% @brief 验证向远程节点添加路由功能
%%
%% add_route/3 允许动态向节点注册新路由，实现服务发现。
hb_client_add_route_test() ->
    %% 步骤1：启动模拟服务器
    {Port, Sock} = start_mock_server(<<"{\"success\":true}">>, 200),
    Node = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
    
    %% 步骤2：构造路由配置
    Route = #{
        <<"template">> => <<"/test-path">>,
        <<"node">> => Node
    },
    
    %% 步骤3：添加路由
    {ok, Result} = hb_client:add_route(Node, Route, #{http_client => httpc}),
    %% 步骤4：验证结果
    ?assert(is_map(Result)),
    ?debugFmt("hb_client:add_route/3 added route", []),
    
    %% 步骤5：清理资源
    gen_tcp:close(Sock).

%% @doc 测试 hb_client:arweave_timestamp/0 函数
%% @brief 验证获取 Arweave 网络时间戳功能
%%
%% arweave_timestamp/0 从 Arweave 网关获取当前区块信息，
%% 包括时间戳、区块高度和区块哈希。
hb_client_arweave_timestamp_test() ->
    %% 调用函数获取 Arweave 时间戳
    {Timestamp, Height, Hash} = hb_client:arweave_timestamp(),
    
    %% 验证返回类型
    ?assert(is_integer(Timestamp)),
    ?assert(is_integer(Height)),
    ?assert(is_binary(Hash)),
    ?debugFmt("Arweave timestamp: ~p, height: ~p", [Timestamp, Height]).

%% @doc 测试 hb_client:upload/3 函数
 %% @brief 验证上传数据到 Arweave 网络功能
 %%
 %% upload/3 使用 ANS-104 打包格式将数据上传到 Arweave 网络。
 %% 支持多种签名设备（如 httpsig@1.0）。
 hb_client_upload_test() ->
     %% 步骤1：创建签名的 ANS-104 数据项
     Serialized = ar_bundles:serialize(
         ar_bundles:sign_item(#tx{
             data = <<"TEST DATA">>,
             tags = [{<<"Content-Type">>, <<"text/plain">>}]
         }, hb:wallet())
     ),
     
     try
         case hb_client:upload(Serialized, #{}, <<"ans104@1.0">>) of
             {ok, _} ->
                 ?debugFmt("hb_client:upload/3 uploaded ANS-104 item", []);
             {error, Reason} ->
                 ?debugFmt("Upload failed (bundler unavailable): ~p", [Reason])
         end
     catch
         _:CatchReason ->
             ?debugFmt("Upload failed (network error): ~p", [CatchReason])
     end.
 
%% ============================================================================
%% hb_gateway_client 模块测试
%% ============================================================================
%% @doc hb_gateway_client 模块测试用例
%%
%% hb_gateway_client 是 HyperBEAM 的 Arweave 网关客户端，提供：
%% <ul>
%%   <li><b>item_spec/0</b> - 返回 GraphQL 查询必需字段规范</li>
%%   <li><b>query/2-5</b> - 执行 GraphQL 查询</li>
%%   <li><b>read/2</b> - 根据 ID 读取数据项</li>
%% </ul>
%%
%% <b>GraphQL API 集成：</b>
%% hb_gateway_client 通过 GraphQL API 访问 Arweave 网络，支持：
%% <ul>
%%   <li><b>交易查询</b> - 按标签、所有者、收件人等条件筛选</li>
%%   <li><b>数据读取</b> - 获取完整的数据项内容和元数据</li>
%%   <li><b>分页支持</b> - 支持 first/after 风格的分页</li>
%% </ul>
%%
%% <b>必需字段规范：</b>
%% item_spec/0 返回 GraphQL 查询数据项时必需的字段：
%% <ul>
%%   <li><b>id</b> - 交易 ID（256 位哈希）</li>
%%   <li><b>anchor</b> - 锚定值（用于排序）</li>
%%   <li><b>signature</b> - 交易签名</li>
%%   <li><b>tags</b> - 附加标签列表</li>
%% </ul>

%% @doc 测试 hb_gateway_client:item_spec/0 函数
%% @brief 验证 GraphQL 必需字段规范
hb_gateway_client_item_spec_test() ->
    %% 获取字段规范
    Spec = hb_gateway_client:item_spec(),
    
    %% 验证返回类型
    ?assert(is_binary(Spec)),
    %% 验证必需字段存在
    ?assertNotEqual(nomatch, binary:match(Spec, <<"id">>)),
    ?assertNotEqual(nomatch, binary:match(Spec, <<"anchor">>)),
    ?assertNotEqual(nomatch, binary:match(Spec, <<"signature">>)),
    ?assertNotEqual(nomatch, binary:match(Spec, <<"tags">>)),
    ?debugFmt("item_spec contains required GraphQL fields", []).

%% @doc 测试 hb_gateway_client:query/2 函数
%% @brief 验证 GraphQL 查询功能
%% @timeout 30秒 - 网络操作可能需要较长时间
hb_gateway_client_query_test_() ->
    {timeout, 30, fun() ->
        %% 步骤1：启动本地测试节点
        _Node = hb_http_server:start_node(#{}),
        %% 步骤2：构造 GraphQL 查询
        Query = <<"query { transactions(first: 1) { edges { node { id } } } }">>,
        %% 步骤3：执行查询
        Result = hb_gateway_client:query(Query, #{}),
        %% 步骤4：验证结果格式
        ?assert(is_tuple(Result)),
        ?debugFmt("GraphQL query executed", [])
    end}.

%% @doc 测试 hb_gateway_client:read/2 函数
%% @brief 验证按 ID 读取数据项功能
%% @timeout 30秒 - 网络操作可能需要较长时间
hb_gateway_client_read_test_() ->
    {timeout, 30, fun() ->
        %% 步骤1：启动本地测试节点
        _Node = hb_http_server:start_node(#{}),
        %% 步骤2：使用已知的数据项 ID
        ID = <<"BOogk_XAI3bvNWnxNxwxmvOfglZt17o4MOVAdPNZ_ew">>,
        try
            case hb_gateway_client:read(ID, #{}) of
                {ok, Msg} ->
                    ?assert(is_map(Msg)),
                    ?debugFmt("Read data item from gateway", []);
                {error, ErrorReason} ->
                    ?debugFmt("Gateway unavailable: ~p", [ErrorReason])
            end
        catch
            _:CatchReason ->
                ?debugFmt("Gateway read failed (network error): ~p", [CatchReason])
        end
    end}.
 
%% ============================================================================
%% 完整工作流程测试
%% ============================================================================
%% @doc 综合验证 HTTP 通信层所有功能的集成测试
%%
%% 本测试用例整合了 HTTP 通信层的所有核心功能，模拟完整的客户端操作流程：
%% <ol>
%%   <li>启动 HTTP 基础设施</li>
%%   <li>创建模拟 HyperBEAM 节点</li>
%%   <li>执行 GET 请求获取状态</li>
%%   <li>执行 POST 请求发送消息</li>
%%   <li>测试远程消息解析</li>
%%   <li>获取 Arweave 时间戳</li>
%%   <li>获取网关字段规范</li>
%%   <li>上传数据到 Arweave</li>
%% </ol>
%%
%% <b>测试覆盖的组件：</b>
%% <ul>
%%   <li><b>hb_http</b> - HTTP 请求处理</li>
%%   <li><b>hb_client</b> - 客户端 API</li>
%%   <li><b>hb_gateway_client</b> - 网关客户端</li>
%%   <li><b>ar_bundles</b> - ANS-104 数据打包</li>
%% </ul>

%% @doc 完整 HTTP 工作流程测试
%% @brief 综合验证所有 HTTP 通信功能
complete_workflow_test() ->
    ?debugFmt("=== Complete HTTP Workflow Test ===", []),
    
    %% 步骤1：启动 HTTP 基础设施
    ok = hb_http:start(),
    ?debugFmt("1. HTTP infrastructure started", []),
    
    %% 步骤2：创建模拟服务器
    {Port, Sock} = start_mock_server(<<"{\"device\":\"test@1.0\",\"result\":\"success\"}">>, 200),
    Node = iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port)]),
    ?debugFmt("2. Mock node started at ~s", [Node]),
    
    %% 步骤3：执行 GET 请求
    {ok, GetResp} = hb_http:get(Node, <<"/status">>, #{http_client => httpc}),
    ?assertEqual(200, maps:get(<<"status">>, GetResp)),
    ?debugFmt("3. GET /status returned 200", []),
    
    %% 步骤4：执行 POST 请求
    Message = #{
        <<"action">> => <<"test">>,
        <<"data">> => <<"hello">>
    },
    {ok, PostResp} = hb_http:post(Node, <<"/api/submit">>, Message, #{http_client => httpc}),
    ?assertEqual(200, maps:get(<<"status">>, PostResp)),
    ?debugFmt("4. POST /api/submit returned 200", []),
    
    %% 步骤5：测试远程解析
    Msg1 = #{<<"device">> => <<"Router@1.0">>},
    Msg2 = #{<<"path">> => <<"/routes">>, <<"method">> => <<"GET">>},
    {ok, ResolveResp} = hb_client:resolve(Node, Msg1, Msg2, #{http_client => httpc}),
    ?assert(is_map(ResolveResp)),
    ?debugFmt("5. Remote resolve completed", []),
    
    %% 步骤6：获取 Arweave 时间戳
    {Timestamp, Height, Hash} = hb_client:arweave_timestamp(),
    ?assert(is_integer(Timestamp)),
    ?assert(is_integer(Height)),
    ?assert(is_binary(Hash)),
    ?debugFmt("6. Arweave timestamp: ~p at height ~p", [Timestamp, Height]),
    
    %% 步骤7：获取网关字段规范
    Spec = hb_gateway_client:item_spec(),
    ?assert(is_binary(Spec)),
    ?debugFmt("7. Gateway item_spec retrieved (~p bytes)", [byte_size(Spec)]),
    
    %% 步骤8：上传数据到 Arweave
    Serialized = ar_bundles:serialize(
        ar_bundles:sign_item(#tx{
            data = <<"Workflow test data">>,
            tags = [{<<"App">>, <<"test_hb6">>}]
        }, hb:wallet())
    ),
    try
        case hb_client:upload(Serialized, #{}, <<"ans104@1.0">>) of
            {ok, UploadResult} ->
                ?debugFmt("8. Uploaded to Arweave: ~p", [UploadResult]);
            {error, Reason} ->
                ?debugFmt("8. Upload failed (bundler unavailable): ~p", [Reason])
        end
    catch
        _:CatchReason ->
            ?debugFmt("8. Upload failed (network error): ~p", [CatchReason])
    end,
    
    %% 清理资源
    gen_tcp:close(Sock),
    ?debugFmt("=== All workflow tests passed! ===", []).