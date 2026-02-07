-module(test_hb10).
%% @doc HyperBEAM BEAMR运行时测试模块
%% 
%% 本模块测试HyperBEAM的WebAssembly运行时（BEAMR）功能，包括：
%% - 生命周期管理：WASM模块的加载、启动、停止
%% - 函数调用：调用WASM模块导出的函数
%% - 内存操作：读写WASM内存、字符串处理
%% - 导入函数：为WASM提供外部函数接口
%% - 状态管理：序列化、反序列化、检查点
%% 
%% BEAMR架构说明：
%% - BEAMR是HyperBEAM的WebAssembly运行时，基于WAMR（WebAssembly Micro Runtime）
%% - 每个WASM模块作为独立的异步Worker运行在BEAM中
%% - 通过Linked-In Driver（LID）与Erlang进程通信
%% - 支持长时间运行的WASM执行，易于与Erlang函数和进程交互
%% - 主要API：start/1、stop/1、call/N、serialize/1、deserialize/2
%% 
%% WASM内存模型：
%% - WASM模块有独立的线性内存空间
%% - 内存以页为单位管理，每页64KB
%% - 通过hb_beamr_io模块进行内存读写操作
%% - 支持字符串读写，需处理null终止符

-include_lib("eunit/include/eunit.hrl").
%% 引入EUnit测试框架的头文件，提供?assertEqual、?assert、?debugFmt等测试宏

-include("include/hb.hrl").
%% 引入HyperBEAM项目定义的头文件，包含项目级别的宏定义和类型声明

%% === LIFECYCLE TESTS ===
%% @doc 生命周期测试组
%% 测试WASM模块的基本生命周期管理功能

%% @doc 测试用例：基本启动功能
%% 
%% 本测试验证BEAMR能否成功加载和启动WASM模块：
%% 1. 读取WASM二进制文件
%% 2. 调用hb_beamr:start/1启动WASM运行时
%% 3. 验证返回的进程ID、导入函数列表、导出函数列表
%% 
%% 返回值说明：
%% - {ok, WASM, Imports, Exports}
%% - WASM：WASM实例的进程PID
%% - Imports：导入函数列表，由外部提供的函数
%% - Exports：导出函数列表，WASM模块提供的可调用函数
start_basic_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    %% 读取WASM二进制文件
    %% file:read_file/1返回{ok, Binary}，Binary是完整的WASM模块字节码
    {ok, WASM, Imports, Exports} = hb_beamr:start(File),
    %% 调用hb_beamr:start/1加载并初始化WASM模块
    %% 函数内部：加载驱动、打开端口、发送初始化命令
    %% 返回WASM进程PID和导入导出函数信息
    ?assert(is_pid(WASM)),
    %% 验证WASM是有效的进程标识符
    ?assert(is_list(Imports)),
    %% 验证Imports是列表类型
    ?assert(is_list(Exports)),
    %% 验证Exports是列表类型
    ?assert(length(Exports) > 0),
    %% 验证WASM模块至少导出一个函数
    hb_beamr:stop(WASM).
%% 调用hb_beamr:stop/1停止WASM实例
%% 内部发送stop消息给WASM进程，关闭端口

%% @doc 测试用例：停止清理功能
%% 
%% 本测试验证停止WASM实例后进程是否正确清理：
%% 1. 启动WASM模块
%% 2. 验证进程处于活动状态
%% 3. 停止WASM实例
%% 4. 等待后验证进程已终止
%% 
%% 停止机制：
%% - hb_beamr:stop/1发送stop消息给WASM进程
%% - WASM进程收到消息后关闭端口并退出
%% - timer:sleep(10)等待进程完全清理
stop_cleans_up_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    %% 启动WASM模块，忽略导入导出信息（下划线表示未使用）
    ?assert(is_process_alive(WASM)),
    %% 验证WASM进程处于活动状态
    %% is_process_alive/1检查进程是否仍在运行
    ok = hb_beamr:stop(WASM),
    %% 停止WASM实例
    timer:sleep(10),
    %% 等待10毫秒，确保进程有足够时间清理
    ?assert(not is_process_alive(WASM)).
    %% 验证WASM进程已终止

%% @doc 测试用例：无效WASM文件处理
%% 
%% 本测试验证BEAMR能正确处理无效的WASM二进制：
%% 1. 创建无效的WASM数据
%% 2. 尝试启动WASM模块
%% 3. 验证返回错误
%% 
%% 错误处理：
%% - 无效的WASM二进制会导致初始化失败
%% - hb_beamr:start/1返回{error, Reason}
%% - Reason包含具体的错误原因
invalid_wasm_test() ->
    InvalidWASM = <<"not a valid wasm file">>,
    %% 创建无效的WASM二进制数据
    %% 有效的WASM二进制以特定魔数开头（0x00 0x61 0x73 0x6D）
    Result = hb_beamr:start(InvalidWASM),
    %% 尝试加载无效的WASM模块
    ?assertMatch({error, _}, Result).
    %% 使用模式匹配验证返回错误
    %% {error, _}匹配任何错误元组

%% === FUNCTION CALL TESTS ===
%% @doc 函数调用测试组
%% 测试调用WASM模块导出函数的功能

%% @doc 测试用例：阶乘函数调用
%% 
%% 本测试验证BEAMR能正确调用WASM模块的导出函数：
%% 1. 加载WASM模块
%% 2. 调用fac函数计算阶乘
%% 3. 验证计算结果正确
%% 
%% 函数调用机制：
%% - hb_beamr:call/3调用WASM导出函数
%% - 参数自动从Erlang类型转换为WASM类型
%% - 返回值从WASM类型转换回Erlang类型
%% - WASM数值类型主要是f64（64位浮点数）
call_factorial_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    %% 加载WASM模块
    
    {ok, [Fac5]} = hb_beamr:call(WASM, "fac", [5.0]),
    %% 调用fac函数计算5的阶乘
    %% 参数是浮点数5.0
    %% 返回{ok, [Result]}，Result是计算结果
    ?assertEqual(120.0, Fac5),
    %% 验证5! = 120
    
    {ok, [Fac10]} = hb_beamr:call(WASM, "fac", [10.0]),
    %% 计算10的阶乘
    ?assertEqual(3628800.0, Fac10),
    %% 验证10! = 3,628,800
    
    hb_beamr:stop(WASM).

%% @doc 测试用例：二进制函数名调用
%% 
%% 本测试验证可以使用二进制类型的函数名调用WASM函数：
%% - 函数名可以是字符串或二进制类型
%% - hb_beamr:call/3内部会处理类型转换
call_binary_name_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    {ok, [Result]} = hb_beamr:call(WASM, <<"fac">>, [4.0]),
    %% 使用二进制<<"fac">>作为函数名
    %% 等价于调用hb_beamr:call(WASM, "fac", [4.0])
    ?assertEqual(24.0, Result),
    %% 验证4! = 24
    hb_beamr:stop(WASM).

%% @doc 测试用例：多次函数调用
%% 
%% 本测试验证WASM实例能正确处理多次函数调用：
%% 1. 调用fac函数计算1到5的阶乘
%% 2. 验证所有结果正确
%% 
%% 列表推导式说明：
%% - lists:seq(1, 5)生成[1,2,3,4,5]
%% - 列表推导式对每个N调用fac(N)
%% - 结果收集到Results列表中
call_multiple_times_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    Results = [begin
        {ok, [R]} = hb_beamr:call(WASM, "fac", [float(N)]),
        R
    end || N <- lists:seq(1, 5)],
    %% 列表推导式：计算1到5的阶乘
    %% float(N)将整数N转换为浮点数
    %% 每个结果R收集到Results列表
    
    ?assertEqual([1.0, 2.0, 6.0, 24.0, 120.0], Results),
    %% 验证所有阶乘结果
    hb_beamr:stop(WASM).

%% === MEMORY TESTS ===
%% @doc 内存操作测试组
%% 测试WASM内存的读写功能

%% @doc 测试用例：内存大小查询
%% 
%% 本测试验证BEAMR能正确查询WASM实例的内存大小：
%% - WASM内存以页为单位，每页64KB
%% - hb_beamr_io:size/1返回当前分配的内存大小（字节）
%% 
%% WASM内存限制：
%% - 内存一旦分配不能减少（只能增加）
%% - 初始内存大小由WASM模块定义
memory_size_test() ->
    {ok, File} = file:read_file("test/test-print.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    {ok, Size} = hb_beamr_io:size(WASM),
    %% 调用hb_beamr_io:size/1获取内存大小
    %% 内部向WASM进程发送size命令
    ?assertEqual(65536, Size),
    %% 验证内存大小为65536字节（64KB）
    %% 1页 = 64KB = 65536字节
    hb_beamr:stop(WASM).

%% @doc 测试用例：内存读写功能
%% 
%% 本测试验证BEAMR能正确读写WASM实例的内存：
%% 1. 向WASM内存写入数据
%% 2. 从相同位置读取数据
%% 3. 验证读写数据一致
%% 
%% 内存读写机制：
%% - hb_beamr_io:write/3在指定偏移处写入二进制数据
%% - hb_beamr_io:read/3从指定偏移处读取指定长度的数据
%% - 偏移量是字节偏移，从0开始
memory_read_write_test() ->
    {ok, File} = file:read_file("test/test-print.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    TestData = <<"Hello, BEAMR!">>,
    %% 创建测试数据二进制
    ok = hb_beamr_io:write(WASM, 1000, TestData),
    %% 在偏移量1000处写入TestData
    %% ok表示写入成功
    {ok, ReadBack} = hb_beamr_io:read(WASM, 1000, byte_size(TestData)),
    %% 从偏移量1000读取byte_size(TestData)字节
    %% byte_size/1返回二进制的字节长度
    
    ?assertEqual(TestData, ReadBack),
    %% 验证读取的数据与写入的数据一致
    hb_beamr:stop(WASM).

%% @doc 测试用例：字符串往返读写
%% 
%% 本测试验证BEAMR能正确处理包含Unicode的字符串：
%% 1. 使用write_string写入字符串
%% 2. 使用read_string读取字符串
%% 3. 验证读写数据一致
%% 
%% 字符串处理说明：
%% - write_string自动添加null终止符
%% - read_string按null终止符读取字符串
%% - 支持完整的Unicode字符集
memory_string_roundtrip_test() ->
    {ok, File} = file:read_file("test/test-calling.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    TestStr = <<"Test string with unicode: 日本語">>,
    %% 创建包含Unicode字符的测试字符串
    {ok, Ptr} = hb_beamr_io:write_string(WASM, TestStr),
    %% 写入字符串到WASM内存
    %% 返回分配的内存指针Ptr
    {ok, ReadBack} = hb_beamr_io:read_string(WASM, Ptr),
    %% 从Ptr指向的位置读取字符串
    
    ?assertEqual(TestStr, ReadBack),
    %% 验证读取的字符串与写入的一致
    hb_beamr:stop(WASM).

%% @doc 测试用例：内存越界访问处理
%% 
%% 本测试验证BEAMR能正确处理内存越界访问：
%% - 尝试读取超出内存范围的区域
%% - 验证返回错误而非崩溃
%% 
%% 边界检查：
%% - WASM有严格的内存安全检查
%% - 越界访问会触发运行时错误
%% - hb_beamr_io返回{error, Reason}而非崩溃
memory_out_of_bounds_test() ->
    {ok, File} = file:read_file("test/test-print.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    Result = hb_beamr_io:read(WASM, 999999, 100),
    %% 尝试从偏移999999读取100字节
    %% 这个偏移量很可能超出分配的内存范围
    
    ?assertMatch({error, _}, Result),
    %% 验证返回错误而非正常数据
    %% 错误可能是out_of_bounds或类似描述
    hb_beamr:stop(WASM).

%% === IMPORT TESTS ===
%% @doc 导入函数测试组
%% 测试为WASM模块提供外部函数的功能

%% @doc 测试用例：简单导入函数
%% 
%% 本测试验证BEAMR能正确调用带导入函数的WASM模块：
%% - 导入函数由Erlang提供，WASM模块调用
%% - pow_calculator.wasm需要pow导入函数
%% 
%% 导入函数机制：
%% - 导入函数是WASM调用外部（Erlang）的接口
%% - 定义为fun/3，接收state、args、opts参数
%% - 返回{ok, [Result], NewState}
import_simple_test() ->
    {ok, File} = file:read_file("test/pow_calculator.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    %% 加载pow_calculator模块，它需要pow导入函数
    
    ImportFun = fun(State, #{args := [A, B]}, _Opts) ->
        %% 定义导入函数
        %% 参数：State（状态映射）、args（参数映射）、Opts（选项）
        %% #{args := [A, B]}从参数映射中提取列表
        {ok, [A * B], State}
        %% 返回{ok, [结果], 新状态}
        %% 结果必须是列表，因为WASM可能有多个返回值
    end,
    
    {ok, [Result], _} = hb_beamr:call(WASM, <<"pow">>, [2, 5], ImportFun),
    %% 调用WASM的pow函数，传入ImportFun
    %% 参数[2, 5]传给ImportFun的args
    ?assertEqual(32, Result),
    %% 验证2^5 = 32
    
    hb_beamr:stop(WASM).

%% @doc 测试用例：有状态导入函数
%% 
%% 本测试验证导入函数能维护和修改状态：
%% - 每次调用导入函数可以更新状态
%% - 状态在多次调用间保持
%% 
%% 状态管理：
%% - 初始状态通过InitState参数传入
%% - 导入函数返回新的状态映射
%% - 状态可以是任意Erlang数据结构
import_stateful_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    InitState = #{calls => 0},
    %% 初始化状态，包含calls计数器
    
    ImportFun = fun(#{calls := N} = State, _, _) ->
        %% 定义有状态导入函数
        %% 模式匹配提取State中的calls键
        {ok, [0], State#{calls => N + 1}}
        %% 返回结果0，并将calls加1
    end,
    
    {ok, _, State1} = hb_beamr:call(WASM, "fac", [3.0], ImportFun, InitState, #{}),
    %% 调用fac函数，传入有状态导入函数
    %% 返回{ok, Result, FinalState}
    
    %% fac doesn't use imports, so count stays at 0
    ?assertEqual(0, maps:get(calls, State1)),
    %% fac函数没有调用导入函数，所以calls仍为0
    %% 如果调用了导入函数，calls会增加
    
    hb_beamr:stop(WASM).

%% @doc 测试用例：存根函数
%% 
%% 本测试验证hb_beamr:stub/3函数的功能：
%% - 存根函数是不执行实际操作的占位函数
%% - 用于不需要导入函数的场景
%% 
%% stub函数用途：
%% - 提供默认的导入函数实现
%% - 保持函数调用接口一致
%% - 简单返回默认值，不修改状态
stub_test() ->
    State = #{key => value},
    %% 初始状态映射
    Import = #{func => <<"test">>, args => [1, 2]},
    %% 导入信息，包含函数名和参数
    
    {ok, [0], NewState} = hb_beamr:stub(State, Import, #{}),
    %% 调用stub/3
    %% 返回{ok, [返回值], 新状态}
    %% stub返回[0]作为默认返回值
    ?assertEqual(State, NewState).
    %% 验证状态未被修改（stub不改变状态）

%% === STATE MANAGEMENT TESTS ===
%% @doc 状态管理测试组
%% 测试WASM实例状态的序列化和持久化

%% @doc 测试用例：序列化功能
%% 
%% 本测试验证BEAMR能将WASM实例状态序列化为二进制：
%% 1. 加载WASM模块
%% 2. 调用serialize/1获取状态快照
%% 3. 验证序列化结果是二进制
%% 
%% 序列化用途：
%% - 保存WASM实例的完整状态
%% - 用于检查点、快照、迁移
%% - 序列化的二进制可以later反序列化恢复
serialize_test() ->
    {ok, File} = file:read_file("test/test-print.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    {ok, Memory} = hb_beamr:serialize(WASM),
    %% 序列化WASM实例
    %% 返回{ok, Binary}，Binary包含完整的内存状态
    ?assert(is_binary(Memory)),
    %% 验证序列化结果是二进制类型
    
    {ok, Size} = hb_beamr_io:size(WASM),
    ?assertEqual(Size, byte_size(Memory)),
    %% 验证序列化二进制大小与内存大小一致
    %% 序列化应该包含完整的内存数据
    
    hb_beamr:stop(WASM).

%% @doc 测试用例：反序列化往返
%% 
%% 本测试验证序列化和反序列化能正确恢复WASM状态：
%% 1. 写入测试数据
%% 2. 序列化状态
%% 3. 覆盖内存数据
%% 4. 反序列化恢复
%% 5. 验证原始数据恢复
%% 
%% 检查点工作流：
%% - serialize保存当前状态
%% - 可以在任意时刻deserialize恢复
%% - 恢复后内存数据与序列化时一致
deserialize_roundtrip_test() ->
    {ok, File} = file:read_file("test/test-print.wasm"),
    {ok, WASM, _, _} = hb_beamr:start(File),
    
    %% Write data
    TestData = <<"Checkpoint data!">>,
    ok = hb_beamr_io:write(WASM, 500, TestData),
    %% 在偏移500处写入测试数据
    
    %% Serialize
    {ok, Checkpoint} = hb_beamr:serialize(WASM),
    %% 创建检查点，保存当前状态
    
    %% Overwrite
    ok = hb_beamr_io:write(WASM, 500, <<"OVERWRITTEN!!!!">>),
    %% 覆盖内存数据
    
    %% Deserialize
    ok = hb_beamr:deserialize(WASM, Checkpoint),
    %% 从检查点恢复状态
    
    %% Verify original restored
    {ok, Restored} = hb_beamr_io:read(WASM, 500, byte_size(TestData)),
    ?assertEqual(TestData, Restored),
    %% 验证原始数据已恢复
    
    hb_beamr:stop(WASM).

%% @doc 测试用例：检查点文件持久化
%% 
%% 本测试验证检查点能保存到文件并在新的WASM实例中恢复：
%% 1. 在WASM1中写入数据并创建检查点
%% 2. 保存检查点到文件
%% 3. 停止WASM1
%% 4. 启动新的WASM2实例
%% 5. 从文件加载检查点
%% 6. 验证数据正确恢复
%% 
%% 持久化应用场景：
%% - 服务重启后恢复状态
%% - 跨节点迁移WASM实例
%% - 备份和恢复机制
checkpoint_to_file_test() ->
    {ok, File} = file:read_file("test/test-print.wasm"),
    {ok, WASM1, _, _} = hb_beamr:start(File),
    
    %% Setup state
    ok = hb_beamr_io:write(WASM1, 0, <<"Persistent state">>),
    %% 在内存起始位置写入持久化数据
    
    %% Save checkpoint
    {ok, Checkpoint} = hb_beamr:serialize(WASM1),
    %% 创建检查点
    CheckpointFile = "/tmp/test_checkpoint.bin",
    ok = file:write_file(CheckpointFile, Checkpoint),
    %% 将检查点保存到文件
    hb_beamr:stop(WASM1),
    %% 停止第一个WASM实例
    
    %% Load into new instance
    {ok, WASM2, _, _} = hb_beamr:start(File),
    %% 启动新的WASM实例
    {ok, SavedCheckpoint} = file:read_file(CheckpointFile),
    %% 从文件读取检查点
    ok = hb_beamr:deserialize(WASM2, SavedCheckpoint),
    %% 在新实例中恢复状态
    
    %% Verify
    {ok, Data} = hb_beamr_io:read(WASM2, 0, 16),
    ?assertEqual(<<"Persistent state">>, Data),
    %% 验证持久化数据正确恢复
    
    hb_beamr:stop(WASM2),
    file:delete(CheckpointFile).
%% 清理临时文件

%% === INTEGRATION TESTS ===
%% @doc 集成测试组
%% 测试完整的BEAMR工作流程

%% @doc 测试用例：完整工作流
%% 
%% 本测试验证BEAMR的完整工作流程：
%% 1. 加载WASM模块
%% 2. 查询内存大小
%% 3. 调用导出函数
%% 4. 创建检查点
%% 
%% 这是综合性的端到端测试
full_workflow_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, WASM, _, Exports} = hb_beamr:start(File),
    ?debugFmt("Loaded WASM with ~p exports", [length(Exports)]),
    %% 输出WASM模块的导出函数数量
    
    %% Check memory
    {ok, Size} = hb_beamr_io:size(WASM),
    ?debugFmt("Memory size: ~p bytes", [Size]),
    %% 输出内存大小
    
    %% Call functions
    {ok, [R1]} = hb_beamr:call(WASM, "fac", [5.0]),
    ?debugFmt("fac(5) = ~p", [R1]),
    %% 调用fac函数并输出结果
    
    %% Checkpoint
    {ok, Checkpoint} = hb_beamr:serialize(WASM),
    ?debugFmt("Checkpoint size: ~p bytes", [byte_size(Checkpoint)]),
    %% 输出检查点大小
    
    hb_beamr:stop(WASM).
