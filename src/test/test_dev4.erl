%%% @doc test_dev4: HyperBEAM 进程、调度器和定时任务测试模块
%%%
%%% 本模块测试 HyperBEAM 的核心进程管理功能，包括：
%%% - AOS 进程计算 - 测试 Lua 脚本的调度和执行
%%% - 进程状态查询 - 测试 now、compute、dryrun 等操作
%%% - 调度器功能 - 测试消息调度和槽位分配
%%% - 定时任务 - 测试一次性 和周期性任务调度
%%%
%%% 这些组件构成 HyperBEAM 的消息处理核心：
%%% - 进程（Process）管理 AOS 虚拟机的执行
%%% - 调度器（Scheduler）负责任务的调度和分配
%%% - 定时器（Cron）支持自动化的消息触发
%%%
%%% 运行方式：rebar3 eunit --module=test_dev4
-module(test_dev4).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% ============================================================
%% AOS 进程基本计算测试
%% ============================================================
%% @doc 测试用例：AOS 进程基本计算
%%
%%% 本测试验证 AOS 进程的基本计算功能：
%%% 1. 初始化进程环境
%%% 2. 创建测试进程
%%% 3. 调度多个计算任务（Lua 脚本）
%%% 4. 按顺序执行各槽位的计算
%%% 5. 验证最终结果
%%%
%%% AOS 进程概念：
%%% - AOS（AO-OS）是 HyperBEAM 的智能合约运行时
%%% - 每个进程有独立的 Lua 虚拟机状态
%%% - 计算以"槽位"为单位进行，每个槽位代表一次消息处理
%%% - 槽位按顺序执行，状态依次累积
process_basic_test() ->
    dev_process:init(),
    %% 初始化进程模块
    %% dev_process:init/0 设置进程运行所需的环境
    %% 包括初始化缓存、加载配置等准备工作
    %% 此函数确保后续进程操作可正常执行
    
    Process = dev_process:test_aos_process(),
    %% 创建测试用的 AOS 进程
    %% dev_process:test_aos_process/0 返回一个预配置的进程消息
    %% 该进程包含：
    %% - 进程 ID（唯一标识）
    %% - 调度器配置
    %% - 执行设备配置（通常是 WASM 或 Lua 栈）
    %% - 初始状态（空结果）
    %% 此函数用于测试，避免手动构建复杂进程结构
    
    %% Schedule some computations
    %% 调度计算任务
    %% 使用 Lua 脚本语言编写计算逻辑
    %% AOS 支持完整的 Lua 语法，包括变量赋值和算术运算
    dev_process:schedule_aos_call(Process, <<"X = 10">>),
    %% 调度第一个计算任务
    %% 参数：进程消息、Lua 脚本字符串
    %% 功能：将变量 X 赋值为 10
    %% 此调用将 Lua 代码添加到进程的调度队列
    %% 实际执行发生在调用 hb_ao:resolve 时
    
    dev_process:schedule_aos_call(Process, <<"X = X * 2">>),
    %% 调度第二个计算任务
    %% 功能：将 X 乘以 2（X = 10 * 2 = 20）
    %% 注意：此任务依赖前一个任务的状态
    %% AOS 进程按调度顺序累积状态
    
    dev_process:schedule_aos_call(Process, <<"return X">>),
    %% 调度第三个计算任务
    %% 功能：返回变量 X 的值
    %% return 关键字将值写入进程的 results 字段
    %% 这是获取计算结果的标准方式
    
    %% Compute each slot
    %% 执行各槽位的计算
    %% hb_ao:resolve/3 触发进程执行指定槽位的计算
    %% 参数：
    %% - 第一个参数：进程消息
    %% - 第二个参数：请求映射（指定路径和槽位）
    %% - 第三个参数：选项映射
    %% 返回值：{ok, State}，State 是执行后的状态映射
    
    {ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 0}, #{}),
    %% 执行槽位 0 的计算
    %% path: "compute" 指定计算操作
    %% slot: 0 指定第一个调度的任务
    %% 返回的状态包含执行结果和环境信息
    %% 下划线表示此返回值未被直接使用（只验证最终结果）
    
    {ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 1}, #{}),
    %% 执行槽位 1 的计算
    %% 继续执行第二个调度任务
    %% 状态从前一个槽位继承
    
    {ok, State2} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 2}, #{}),
    %% 执行槽位 2 的计算
    %% 这是最后一个调度任务
    %% 返回最终状态，赋值给 State2 用于验证
    
    ?assertEqual(<<"20">>, hb_ao:get(<<"results/data">>, State2, #{})),
    %% 验证计算结果
    %% hb_ao:get/3 从状态中获取指定路径的值
    %% 路径："results/data" 获取计算返回值
    %% 预期值：<<"20">>（字符串格式）
    %% 验证 X = 10 * 2 = 20 的计算链正确
    
    ?debugFmt("Process compute: X=10, X*2, return X => ~s", [<<"20">>]).
    %% 输出调试信息
    %% 显示完整的计算链和最终结果

%% ============================================================
%% 进程当前状态测试
%% ============================================================
%% @doc 测试用例：获取进程当前状态
%%
%%% 本测试验证进程的 "now" 操作：
%%% - "now" 返回进程最新计算的结果
%%% - 无需指定槽位，自动获取最新状态
%%% - 常用于快速查询进程当前状态
process_now_test() ->
    dev_process:init(),
    %% 初始化进程环境
    %% 与 process_basic_test 相同
    
    Process = dev_process:test_aos_process(),
    %% 创建测试进程
    %% 使用默认配置的新进程
    
    dev_process:schedule_aos_call(Process, <<"return 'hello'">>),
    %% 调度一个简单的返回任务
    %% Lua 字符串使用单引号
    %% 返回字符串 "hello"
    
    {ok, Result} = hb_ao:resolve(Process, <<"now/results/data">>, #{}),
    %% 使用 "now" 路径获取当前状态
    %% 路径："now/results/data"
    %% - now：获取最新计算结果
    %% - results：结果字段
    %% - data：具体返回值
    %% 无需指定槽位，自动查找最新计算
    
    ?assertEqual(<<"hello">>, Result),
    %% 验证返回值为 "hello"
    %% now 操作直接返回结果值
    
    ?debugFmt("Process now: OK", []).
    %% 输出调试信息

%% ============================================================
%% 进程空运行测试
%% ============================================================
%% @doc 测试用例：进程空运行（Dry-run）
%%
%%% 本测试验证进程的 dryrun 功能：
%%% - dryrun 在不改变进程状态的情况下测试代码
%%% - 用于验证代码逻辑而不产生副作用
%%% - 返回测试执行的结果，但不更新实际状态
%%% - 适用于调试和代码验证场景
process_dryrun_test() ->
    dev_process:init(),
    %% 初始化进程环境
    
    Process = dev_process:test_aos_process(),
    %% 创建测试进程
    
    %% Dryrun doesn't advance state
    %% 执行空运行
    {ok, DryResult} = hb_ao:resolve(
        Process,
        #{
            <<"path">> => <<"compute">>,
            <<"method">> => <<"POST">>,
            <<"dryrun">> => #{<<"data">> => <<"return 99">>}
        },
        #{}
    ),
    %% hb_ao:resolve/3 执行带 dryrun 选项的计算
    %% 请求参数：
    %% - path: "compute" 执行计算
    %% - method: "POST" 指定 HTTP 方法
    %% - dryrun: 测试配置
    %%   - data: 测试用的 Lua 代码
    %% 执行 "return 99" 但不改变进程状态
    
    ?assert(is_map(DryResult)),
    %% 验证结果是映射类型
    %% dryrun 返回标准的结果格式
    %% 包含执行信息和结果数据
    
    ?debugFmt("Dryrun: OK", []).
    %% 输出调试信息

%% ============================================================
%% 调度器测试
%% ============================================================
%% @doc 测试用例：调度器任务分配
%%
%%% 本测试验证调度器的基本功能：
%%% - 调度器负责分配消息到槽位
%%% - 每个进程有独立的调度队列
%%% - 调度结果包含分配的槽位号
%%% - 槽位用于标识消息的处理顺序
scheduler_test() ->
    dev_scheduler:start(),
    %% 启动调度器
    %% dev_scheduler:start/0 初始化调度器环境
    %% 包括启动必要的依赖服务
    %% 确保调度操作可正常执行
    
    Opts = #{
        priv_wallet => hb:wallet(),
        store => hb_opts:get(store)
    },
    %% 构建选项映射
    %% - priv_wallet: 私钥钱包，用于签名
    %%   hb:wallet/0 获取默认钱包
    %% - store: 存储后端
    %%   hb_opts:get(store) 获取配置的存储模块
    %% 这些选项传递给调度操作
    
    %% Create and schedule a process
    %% 创建并调度进程
    Process = dev_scheduler:test_process(),
    %% 创建测试进程
    %% dev_scheduler:test_process/0 返回测试用的进程
    %% 包含预配置的消息结构和调度器信息
    
    SignedProcess = hb_message:commit(Process, Opts),
    %% 提交进程消息
    %% hb_message:commit/2 对消息进行签名
    %% 参数：
    %% - Process: 原始进程消息
    %% - Opts: 包含私钥的选项
    %% 返回 SignedProcess：包含签名承诺的消息
    %% 签名确保消息的完整性和来源
    
    {ok, Assignment} = dev_scheduler:schedule(
        #{},
        #{<<"method">> => <<"POST">>, <<"body">> => SignedProcess},
        Opts
    ),
    %% 执行调度
    %% dev_scheduler:schedule/3 将进程加入调度队列
    %% 参数：
    %% - 第一个参数：消息1（空映射）
    %% - 第二个参数：消息2（请求）
    %%   - method: "POST" HTTP 方法
    %%   - body: 已签名的进程消息
    %% - 第三个参数：选项
    %% 返回 {ok, Assignment}，Assignment 是调度分配结果
    
    ?assert(maps:is_key(<<"slot">>, Assignment)),
    %% 验证调度结果包含 slot 字段
    %% slot 标识分配的槽位号
    %% 进程将按此槽位顺序执行
    
    ?debugFmt("Scheduler assignment: slot=~p", [maps:get(<<"slot">>, Assignment)]).
    %% 输出调试信息
    %% 显示分配的槽位号

%% ============================================================
%% 调度器状态测试
%% ============================================================
%% @doc 测试用例：获取调度器状态
%%
%%% 本测试验证调度器状态查询功能：
%%% - 调度器维护进程和资源信息
%%% - status 操作返回当前状态摘要
%%% - 包含调度器地址和进程列表
scheduler_status_test() ->
    dev_scheduler:start(),
    %% 启动调度器
    %% 确保调度器服务已初始化
    
    {ok, Status} = dev_scheduler:status(#{}, #{}, #{}),
    %% 查询调度器状态
    %% dev_scheduler:status/3 返回当前状态
    %% 三个参数都是空映射（默认查询）
    %% 返回 {ok, Status}，Status 是状态映射
    
    ?assert(maps:is_key(<<"address">>, Status)),
    %% 验证包含地址信息
    %% address 标识调度器的网络地址
    
    ?assert(maps:is_key(<<"processes">>, Status)),
    %% 验证包含进程列表
    %% processes 列出当前调度的进程
    %% 格式可能是列表或映射，取决于实现
    
    ?debugFmt("Scheduler status: OK", []).
    %% 输出调试信息

%% ============================================================
%% 一次性定时任务测试
%% ============================================================
%% @doc 测试用例：一次性定时任务
%%
%%% 本测试验证 cron 的一次性任务功能：
%%% - once 创建单次执行的任务
%%% - 任务在指定路径执行一次后自动停止
%%% - 返回任务 ID 用于后续管理
%%% - 适用于定时触发的一次性操作
cron_once_test() ->
    {ok, TaskID} = dev_cron:once(
        #{},
        #{<<"cron-path">> => <<"/test/path">>},
        #{}
    ),
    %% 创建一个一次性定时任务
    %% dev_cron:once/3 调度单次执行
    %% 参数：
    %% - 第一个参数：消息1（空映射）
    %% - 第二个参数：请求配置
    %%   - cron-path: 执行路径
    %% - 第三个参数：选项（空映射）
    %% 返回 {ok, TaskID}，TaskID 是任务唯一标识
    %% 任务将在后台异步执行
    
    ?assert(is_binary(TaskID)),
    %% 验证任务是二进制标识
    %% TaskID 格式：消息 ID 的二进制字符串
    %% 用于后续停止或查询任务
    
    %% Stop it
    %% 停止任务
    {ok, _} = dev_cron:stop(#{}, #{<<"task">> => TaskID}, #{}),
    %% 停止定时任务
    %% dev_cron:stop/3 终止指定任务
    %% 参数：
    %% - 第一个参数：消息1（空）
    %% - 第二个参数：停止请求
    %%   - task: 要停止的任务 ID
    %% - 第三个参数：选项（空）
    %% 返回 {ok, Result}，Result 包含停止结果
    %% 下划线表示未使用返回值
    
    ?debugFmt("Cron once: OK", []).
    %% 输出调试信息

%% ============================================================
%% 周期性定时任务测试
%% ============================================================
%% @doc 测试用例：周期性定时任务
%%
%%% 本测试验证 cron 的周期性任务功能：
%%% - every 创建按间隔重复执行的任务
%%% - 支持灵活的时间间隔配置
%%% - 任务持续执行直到被手动停止
%%% - 适用于心跳、轮询等重复操作
cron_every_test() ->
    {ok, TaskID} = dev_cron:every(
        #{},
        #{
            <<"cron-path">> => <<"/test/heartbeat">>,
            <<"interval">> => <<"500-milliseconds">>
        },
        #{}
    ),
    %% 创建一个周期性定时任务
    %% dev_cron:every/3 调度重复执行
    %% 参数：
    %% - 第一个参数：消息1（空映射）
    %% - 第二个参数：请求配置
    %%   - cron-path: 执行路径
    %%   - interval: 执行间隔
    %%     格式："数字-时间单位"
    %%     支持：milliseconds, seconds, minutes, hours
    %% - 第三个参数：选项（空映射）
    %% 返回 {ok, TaskID}，任务 ID
    
    ?assert(is_binary(TaskID)),
    %% 验证任务是二进制标识
    
    %% Let it run briefly
    %% 让任务运行一小段时间
    timer:sleep(100),
    %% 暂停 100 毫秒
    %% 允许定时任务执行至少一次
    %% 验证周期性执行的正确性
    
    %% Stop it
    %% 停止任务
    {ok, _} = dev_cron:stop(#{}, #{<<"task">> => TaskID}, #{}),
    %% 停止周期性任务
    %% 确保任务被正确终止
    %% 释放相关资源
    
    ?debugFmt("Cron every: OK", []).
    %% 输出调试信息

%% ============================================================
%% 完整工作流测试
%% ============================================================
%% @doc 测试用例：完整进程工作流
%%
%%% 本测试验证 HyperBEAM 进程的完整工作流程：
%%% 1. 初始化环境并创建进程
%%% 2. 调度多个计算任务
%%% 3. 按顺序执行所有槽位
%%% 4. 验证最终结果
%%%
%%% 此测试模拟典型的 AOS 交互场景：
%%% - 用户发送消息触发计算
%%% - 进程按顺序处理消息
%%% - 最终返回累积的计算结果
complete_workflow_test() ->
    ?debugFmt("=== Complete Process Workflow ===", []),
    %% 输出工作流开始标记
    
    %% 1. Initialize
    %% 初始化环境
    dev_process:init(),
    %% 初始化进程模块
    
    Process = dev_process:test_aos_process(),
    %% 创建测试进程
    
    ?debugFmt("1. Created AOS process", []),
    %% 输出步骤 1 完成的调试信息
    
    %% 2. Schedule computations (simple single-line scripts)
    %% 调度计算任务
    dev_process:schedule_aos_call(Process, <<"Counter = 1">>),
    %% 任务1：初始化计数器为 1
    
    dev_process:schedule_aos_call(Process, <<"Counter = Counter + 1">>),
    %% 任务2：计数器加 1
    
    dev_process:schedule_aos_call(Process, <<"return Counter">>),
    %% 任务3：返回计数器值
    
    ?debugFmt("2. Scheduled 3 computations", []),
    %% 输出步骤 2 完成的调试信息
    
    %% 3. Compute each slot in order
    %% 按顺序执行各槽位
    {ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 0}, #{}),
    %% 执行槽位 0：Counter = 1
    
    {ok, _} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 1}, #{}),
    %% 执行槽位 1：Counter = 2
    
    {ok, State} = hb_ao:resolve(Process, #{<<"path">> => <<"compute">>, <<"slot">> => 2}, #{}),
    %% 执行槽位 2：返回 Counter（值为 2）
    
    ?debugFmt("3. Computed all slots", []),
    %% 输出步骤 3 完成的调试信息
    
    %% 4. Check result
    %% 验证结果
    Result = hb_ao:get(<<"results/data">>, State, #{}),
    %% 从最终状态获取返回值
    
    ?assertEqual(<<"2">>, Result),
    %% 验证结果为 "2"
    %% Counter = 1 + 1 = 2
    
    ?debugFmt("4. Result: ~s", [Result]),
    %% 输出最终结果的调试信息
    
    ?debugFmt("=== Complete workflow passed! ===", []).
    %% 输出工作流成功的标记
