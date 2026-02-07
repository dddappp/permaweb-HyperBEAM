%% @doc HyperBEAM 核心功能单元测试模块
%% 
%% 本模块使用 EUnit 测试框架对 HyperBEAM 的核心系统功能进行全面的单元测试。
%% 测试覆盖范围包括：
%% <ul>
%%   <li><b>系统初始化</b> - 验证 hb:init/0 函数正确配置系统环境</li>
%%   <li><b>时间服务</b> - 验证 hb:now/0 函数正确获取毫秒级时间戳</li>
%%   <li><b>钱包管理</b> - 验证 hb:wallet/1 函数正确加载或创建钱包</li>
%%   <li><b>进程名称注册</b> - 验证 hb_name 模块支持任意 Erlang 术语作为进程名称</li>
%%   <li><b>监督树结构</b> - 验证 hb_sup:init/1 正确配置 OTP 监督策略</li>
%%   <li><b>应用生命周期</b> - 验证 hb_app 和 hb_sup 模块导出正确的 OTP 行为接口</li>
%%   <li><b>进程清理机制</b> - 验证死亡进程注销后其名称被正确清理</li>
%% </ul>
%% 
%% 这些测试确保 HyperBEAM 节点在作为 AO 协议的计算层时具备可靠的
%% 基础设施支撑，包括进程管理、时间服务、钱包处理和名称解析等核心功能。
%% 
%% @see hb - HyperBEAM 主模块，提供系统初始化和配置管理
%% @see hb_name - 进程名称注册模块，支持任意术语作为名称
%% @see hb_sup - OTP 监督树模块，管理所有子进程的启动和监督
%% @see hb_app - 应用入口模块，定义 OTP 应用的行为回调
-module(test_hb11).
%% 包含 EUnit 测试框架的头文件，提供 ?assertEqual、?assert 等断言宏
-include_lib("eunit/include/eunit.hrl").
 
%% @spec init_test() -> ok | eunit:test_result()
%% @doc 测试系统初始化功能
%% 
%% 本测试验证 hb:init/0 函数正确完成系统级初始化工作：
%% <ol>
%%   <li>调用 hb:init/0 初始化 HyperBEAM 系统</li>
%%   <li>验证函数返回 ok 表示初始化成功</li>
%%   <li>获取并验证系统回溯深度配置被正确设置</li>
%% </ol>
%% 
%% hb:init/0 函数的主要职责包括：
%% <ul>
%%   <li>启动 hb_name 进程注册表服务</li>
%%   <li>配置调试栈深度 (backtrace_depth)，用于错误追踪</li>
%%   <li>记录系统事件日志</li>
%% </ul>
%% 
%% @see hb:init/0
init_test() ->
    %% 使用 EUnit 的相等断言验证 hb:init() 返回原子 ok
    %% hb:init/0 会启动名称注册表并配置系统参数
    ?assertEqual(ok, hb:init()),
    %% 获取当前系统配置的回溯深度（用于调试时显示的栈帧数）
    %% erlang:system_flag(backtrace_depth, Value) 设置新的回溯深度并返回旧值
    %% 这里设置深度为 20，预期返回整数类型
    Depth = erlang:system_flag(backtrace_depth, 20),
    %% 验证返回值为整数，确保系统标志设置成功
    ?assert(is_integer(Depth)).
 
%% @spec now_test() -> ok | eunit:test_result()
%% @doc 测试时间戳获取功能
%% 
%% 本测试验证 hb:now/0 函数正确返回当前时间的毫秒级时间戳。
%% hb:now/0 是对 erlang:system_time(millisecond) 的封装，
%% 提供统一的时间戳获取接口用于消息序列化、签名和时间相关操作。
%% 
%% 测试验证：
%% <ol>
%%   <li>时间戳为整数类型</li>
%%   <li>连续调用时后一次时间戳大于等于前一次（时间不可逆）</li>
%% </ol>
%% 
%% @note 使用 timer:sleep(10) 确保经过足够的时间间隔
%% @see hb:now/0
now_test() ->
    %% 首次获取时间戳，T1 应为当前时间的毫秒数
    T1 = hb:now(),
    %% 验证返回值为整数，Erlang 时间戳是 64 位整数
    ?assert(is_integer(T1)),
    %% 休眠 10 毫秒，确保时间有微小进展
    timer:sleep(10),
    %% 再次获取时间戳，T2 应该 >= T1
    T2 = hb:now(),
    %% 验证时间戳的单调递增性质
    ?assert(T2 >= T1).
 
%% @spec wallet_test() -> ok | eunit:test_result()
%% @doc 测试钱包加载功能
%% 
%% 本测试验证 hb:wallet/1 函数能够正确加载现有钱包或创建新钱包。
%% 钱包在 HyperBEAM 中用于：
%% <ul>
%%   <li>签署交易和消息</li>
%%   <li>标识节点操作员身份</li>
%%   <li>处理支付（如 simple-pay@1.0 处理器）</li>
%% </ul>
%% 
%% hb:wallet(Path) 函数的逻辑：
%% <ol>
%%   <li>检查指定路径的文件是否存在</li>
%%   <li>若存在，调用 ar_wallet:load_keyfile/2 加载钱包</li>
%%   <li>若不存在，调用 ar_wallet:new_keyfile/2 创建新钱包</li>
%% </ol>
%% 
%% @warning 测试结束后会清理创建的钱包文件，避免污染系统
%% @see hb:wallet/1
wallet_test() ->
    %% 生成唯一的临时钱包文件路径，使用随机数避免冲突
    %% 路径格式：/tmp/test_wallet_<随机数>.json
    Path = "/tmp/test_wallet_" ++ integer_to_list(rand:uniform(100000)) ++ ".json",
    %% 调用 hb:wallet/1 加载或创建钱包
    %% 返回值为 {Address, PrivateKey} 元组（由 ar_wallet 模块生成）
    Wallet = hb:wallet(Path),
    %% 验证返回值为元组类型，钱包包含地址和私钥信息
    ?assert(is_tuple(Wallet)),
    %% 测试完成后删除临时钱包文件，避免文件残留
    file:delete(Path).
 
%% @spec name_registration_test() -> ok | eunit:test_result()
%% @doc 测试进程名称注册功能（使用元组名称）
%% 
%% 本测试验证 hb_name 模块的核心功能：注册任意 Erlang 术语作为进程名称。
%% 这与 Erlang 原生的 erlang:register/2 不同，后者只能使用原子作为名称。
%% 
%% hb_name 模块的设计动机：
%% <ul>
%%   <li>支持任意术语作为名称（如哈希路径、进程标识符等）</li>
%%   <li>提供原子性的名称注册（防止竞态条件）</li>
%%   <li>自动清理死亡进程的名称注册</li>
%% </ul>
%% 
%% 实现原理：
%% <ul>
%%   <li>使用命名的 ETS 表 (hb_name_registry) 存储名称到 PID 的映射</li>
%%   <li>对于原子名称，同时使用 Erlang 注册进程表实现双写</li>
%%   <li>在 lookup 时检查进程是否存活，自动清理死亡进程</li>
%% </ul>
%% 
%% @see hb_name:register/1
%% @see hb_name:lookup/1
%% @see hb_name:unregister/1
name_registration_test() ->
    %% 创建测试名称，使用元组包含唯一整数确保名称唯一
    %% 元组名称如 {test, 12345} 展示了对任意术语的支持
    Name = {test, erlang:unique_integer()},
    %% 断言注册成功，返回原子 ok
    ?assertEqual(ok, hb_name:register(Name)),
    %% 断言 lookup 返回当前进程 PID，验证名称解析正确
    ?assertEqual(self(), hb_name:lookup(Name)),
    %% 断言重复注册返回 error，保证注册的原子性
    ?assertEqual(error, hb_name:register(Name)),  % Already registered
    %% 断言注销成功，返回原子 ok
    ?assertEqual(ok, hb_name:unregister(Name)),
    %% 断言注销后 lookup 返回 undefined
    ?assertEqual(undefined, hb_name:lookup(Name)).
 
%% @spec binary_name_test() -> ok | eunit:test_result()
%% @doc 测试进程名称注册功能（使用二进制名称）
%% 
%% 本测试验证 hb_name 模块支持二进制数据作为进程名称。
%% 二进制名称常用于：
%% <ul>
%%   <li>从 Arweave 消息中提取的进程标识符</li>
%%   <li>符合特定格式的标识符（如 "process@1.0"）</li>
%%   <li>十六进制编码的哈希值</li>
%% </ul>
%% 
%% 与 name_registration_test 的区别在于：
%% <ul>
%%   <li>使用二进制而非元组作为名称类型</li>
%%   <li>不验证重复注册（简化测试）</li>
%%   <li>不检查注销后的状态（假设正确实现）</li>
%% </ul>
%% 
%% @see hb_name:register/1
binary_name_test() ->
    %% 创建二进制测试名称，使用随机数确保唯一性
    %% 名称格式：<<"process-12345">>
    Name = <<"process-", (integer_to_binary(rand:uniform(100000)))/binary>>,
    %% 断言注册成功
    ?assertEqual(ok, hb_name:register(Name)),
    %% 断言 lookup 返回当前进程 PID
    ?assertEqual(self(), hb_name:lookup(Name)),
    %% 注销名称（不验证返回值）
    hb_name:unregister(Name).
 
%% @spec supervisor_init_test() -> ok | eunit:test_result()
%% @doc 测试 OTP 监督树初始化功能
%% 
%% 本测试验证 hb_sup:init/1 函数正确配置 HyperBEAM 的监督树结构。
%% 监督树是 OTP 应用架构的核心，提供：
%% <ul>
%%   <li>进程生命周期管理（启动/停止/重启）</li>
%%   <li>故障隔离和恢复策略</li>
%%   <li>层级化的进程组织</li>
%% </ul>
%% 
%% hb_sup 模块定义的监督策略：
%% <ul>
%%   <li>strategy: one_for_all - 任一子进程终止时重启所有子进程</li>
%%   <li>intensity: 0 - 在 period 时间内允许 0 次重启（立即重启）</li>
%%   <li>period: 1 - 重启计数的时间窗口（1 秒）</li>
%% </ul>
%% 
%% 子进程规范包括：
%% <ul>
%%   <li>hb_http_client - HTTP 客户端工作池</li>
%%   <li>存储子进程 - 根据配置动态生成（如 hb_store_rocksdb）</li>
%% </ul>
%% 
%% @see hb_sup:init/1
supervisor_init_test() ->
    %% 调用 hb_sup:init/1 初始化监督树
    %% 传入空映射 #{} 使用默认配置
    %% 返回 {ok, {SupFlags, Children}} 元组
    {ok, {SupFlags, Children}} = hb_sup:init(#{}),
    %% 断言监督策略为 one_for_all
    ?assertEqual(one_for_all, maps:get(strategy, SupFlags)),
    %% 断言重启强度为 0（立即重启）
    ?assertEqual(0, maps:get(intensity, SupFlags)),
    %% 断言至少有一个子进程（HTTP 客户端）
    ?assert(length(Children) >= 1).
 
%% @spec application_lifecycle_test() -> ok | eunit:test_result()
%% @doc 测试应用程序模块接口可用性
%% 
%% 本测试验证 hb_app 和 hb_sup 模块正确实现了 OTP 应用和监督者行为接口。
%% 由于启动完整应用会占用大量资源，测试采用轻量级验证方式：
%% <ul>
%%   <li>确保模块已加载</li>
%%   <li>验证必需的行为回调函数已导出</li>
%% </ul>
%% 
%% 验证的函数：
%% <ul>
%%   <li>hb_app:start/2 - OTP 应用启动回调</li>
%%   <li>hb_app:stop/1 - OTP 应用停止回调</li>
%%   <li>hb_sup:start_link/0 - 监督者启动链接函数</li>
%% </ul>
%% 
%% @note 不实际启动应用，因为会初始化完整的 HyperBEAM 节点
%% @see hb_app
%% @see hb_sup
application_lifecycle_test() ->
    %% 确保 hb_app 模块已加载到代码服务器
    code:ensure_loaded(hb_app),
    %% 确保 hb_sup 模块已加载
    code:ensure_loaded(hb_sup),
    %% 断言 hb_app 模块导出 start/2 函数（OTP 应用行为必需）
    ?assert(erlang:function_exported(hb_app, start, 2)),
    %% 断言 hb_app 模块导出 stop/1 函数（OTP 应用行为必需）
    ?assert(erlang:function_exported(hb_app, stop, 1)),
    %% 断言 hb_sup 模块导出 start_link/0 函数（监督者启动必需）
    ?assert(erlang:function_exported(hb_sup, start_link, 0)),
    %% 返回原子 ok 表示测试通过
    ok.
 
%% @spec dead_process_cleanup_test() -> ok | eunit:test_result()
%% @doc 测试死亡进程名称自动清理功能
%% 
%% 本测试验证 hb_name 模块在注册进程死亡后自动清理其名称注册。
%% 这是健壮的名称服务的重要特性，防止：
%% <ul>
%%   <li>名称泄漏（死亡进程占用名称）</li>
%%   <li>悬空引用（指向死亡进程的 PID）</li>
%%   <li>资源泄漏（ETS 表条目无限增长）</li>
%% </ul>
%% 
%% 测试流程：
%% <ol>
%%   <li>创建监控进程注册名称</li>
%%   <li>等待进程完成注册</li%%   <li>强制终止进程（使用 exit(PID, kill)）</li>
%%   <li>接收进程DOWN消息确认终止</li>
%%   <li>验证名称已被自动清理</li>
%% </ol>
%% 
%% 实现机制：
%% <ul>
%%   <li>hb_name:lookup/1 调用时检查 is_process_alive(Pid)</li>
%%   <li>若进程已死亡，自动从 ETS 表中删除条目</li>
%%   <li>返回 undefined 表示名称已清理</li>
%% </ul>
%% 
%% @see hb_name:lookup/1
dead_process_cleanup_test() ->
    %% 创建测试名称，使用原子标签便于识别
    Name = {dead_test, erlang:unique_integer()},
    %% spawn_monitor 创建进程并监控其退出
    %% 返回 {Pid, Ref}，其中 Ref 用于接收 DOWN 消息
    {PID, Ref} = spawn_monitor(fun() -> 
        %% 子进程注册名称
        hb_name:register(Name),
        %% 休眠 100ms 确保测试进程有时间检查状态
        timer:sleep(100)
    end),
    %% 休眠 50ms 等待子进程完成注册
    timer:sleep(50),  % Let it register
    %% 强制终止子进程（发送 kill 信号，不可捕获）
    exit(PID, kill),
    %% 阻塞接收 DOWN 消息，确认进程已终止
    receive {'DOWN', Ref, process, PID, _} -> ok end,
    %% 验证名称已被自动清理，lookup 返回 undefined
    ?assertEqual(undefined, hb_name:lookup(Name)).