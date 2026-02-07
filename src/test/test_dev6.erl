%%% @doc test_dev6：HyperBEAM运行时环境测试模块
%%%
%%% 本模块测试HyperBEAM支持的多种运行时环境，包括：
%%% - WASM运行时——通过BEAMR执行WebAssembly模块
%%% - Lua运行时——通过Lua解释器执行Lua脚本
%%% - WASI运行时——WebAssembly系统接口支持
%%%
%%% 这些运行时环境是HyperBEAM智能合约执行的基础：
%%% - WASM提供高性能、可移植的代码执行
%%% - Lua提供灵活的脚本能力和快速开发
%%% - WASI提供文件系统、网络等系统级接口
%%%
%%% 运行方式：rebar3 eunit --module=test_dev6
-module(test_dev6).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% ============================================================
%% WASM基本测试
%% ============================================================
%% @doc 测试用例：WASM模块初始化
%%%
%%% 本测试验证WASM运行时的基本初始化流程：
%%% 1. 确保HB应用已启动
%%% 2. 初始化HyperBEAM环境
%%% 3. 加载WASM镜像到缓存
%%% 4. 初始化WASM实例
%%% 5. 验证实例创建成功
%%%
%%% WASM初始化过程：
%%% - cache_wasm_image加载WASM字节码并缓存
%%% - init操作创建WASM实例环境
%%% - 实例对象包含运行时状态和内存
wasm_basic_test() ->
    application:ensure_all_started(hb),
    %% 确保HB应用已启动
    %% application:ensure_all_started/1启动指定应用及其依赖
    %% 确保所有必要的服务可用

    hb:init(),
    %% 初始化HyperBEAM
    %% hb:init/0执行全局初始化
    %% 包括加载配置、初始化缓存等准备工作

    %% 加载WASM镜像
    Msg0 = dev_wasm:cache_wasm_image("test/test.wasm"),
    %% 加载WASM镜像文件
    %% dev_wasm:cache_wasm_image/1参数说明：
    %%   第一个参数：WASM文件路径
    %% 返回值：包含WASM镜像的消息
    %% 函数执行过程：
    %%   1. 读取WASM文件内容
    %%   2. 解析WASM模块结构
    %%   3. 缓存字节码并返回引用消息

    %% 初始化实例
    {ok, Msg1} = hb_ao:resolve(Msg0, <<"init">>, #{}),
    %% 初始化WASM实例
    %% hb_ao:resolve/3执行消息解析
    %%   第一个参数：WASM镜像消息
    %%   第二个参数：操作路径（"init"执行初始化）
    %%   第三个参数：选项配置（空）
    %% 返回值：{ok, Msg1}，Msg1包含初始化后的实例信息

    %% 验证实例存在
    Priv = hb_private:from_message(Msg1),
    %% 从消息中提取私有数据
    %% hb_private:from_message/1获取消息的私有字段
    %% 私有字段包含实例运行时信息

    {ok, Instance} = hb_ao:resolve(Priv, <<"instance">>, #{}),
    %% 解析获取实例PID
    %% 从私有数据中提取WASM实例进程标识
    %% 实例是实际执行WASM代码的实体

    ?assert(is_pid(Instance)),
    %% 验证Instance是有效的进程标识
    %% WASM实例作为独立进程运行

    ?debugFmt("WASM init: OK (instance=~p)", [Instance]).
    %% 输出初始化成功调试信息
    %% 显示实例进程ID

%% ============================================================
%% WASM阶乘计算测试
%% ============================================================
%% @doc 测试用例：WASM函数调用——计算阶乘
%%%
%%% 本测试验证WASM运行时的函数调用能力：
%%% 1. 加载并初始化WASM模块
%%% 2. 设置要调用的函数名和参数
%%% 3. 执行计算操作
%%% 4. 验证计算结果正确
%%%
%%% WASM函数调用机制：
%%% - function字段指定要调用的导出函数
%%% - parameters字段以列表形式传递参数
%%% - results/output获取函数返回值
wasm_factorial_test() ->
    application:ensure_all_started(hb),
    %% 确保应用运行

    hb:init(),
    %% 初始化环境

    Msg0 = dev_wasm:cache_wasm_image("test/test.wasm"),
    %% 加载WASM镜像

    {ok, Msg1} = hb_ao:resolve(Msg0, <<"init">>, #{}),
    %% 初始化实例

    %% 计算5的阶乘
    Msg2 = Msg1#{
        <<"function">> => <<"fac">>,
        <<"parameters">> => [5.0]
    },
    %% 创建计算请求消息
    %% function指定要调用的导出函数名
    %% parameters以列表形式传递参数
    %% 5.0表示计算5的阶乘

    {ok, Result} = hb_ao:resolve(Msg2, <<"compute">>, #{}),
    %% 执行计算
    %% compute路径触发WASM函数执行
    %% Result包含计算结果和执行状态

    {ok, [120.0]} = hb_ao:resolve(Result, <<"results/output">>, #{}),
    %% 获取计算结果
    %% results/output路径获取函数的输出值
    %% 阶乘结果应为120.0（5×4×3×2×1）

    ?debugFmt("WASM factorial: 5! = 120", []).
    %% 输出调试信息

%% ============================================================
%% Lua基本测试
%% ============================================================
%% @doc 测试用例：Lua模块初始化
%%%
%%% 本测试验证Lua运行时的基本初始化：
%%% 1. 定义包含Lua代码的模块
%%% 2. 初始化Lua运行环境
%%% 3. 验证初始化成功
%%%
%%% Lua模块格式：
%%% - content-type指定为application/lua
%%% - body包含Lua源代码
lua_basic_test() ->
    %% 创建简单的Lua进程
    Process = #{
        <<"module">> => #{
            <<"content-type">> => <<"application/lua">>,
            <<"body">> => <<"
                function add(a, b)
                    return a + b
                end
            ">>
        }
    },
    %% 创建Lua模块定义
    %% module字段包含模块配置
    %% content-type指定为Lua脚本类型
    %% body包含实际的Lua源代码
    %% add函数实现两个数值相加

    {ok, Initialized} = dev_lua:init(Process, #{}, #{}),
    %% 初始化Lua环境
    %% dev_lua:init/3参数说明：
    %%   第一个参数：进程消息
    %%   第二个参数：请求配置（空）
    %%   第三个参数：选项配置（空）
    %% 返回值：{ok, Initialized}，包含初始化后的环境

    ?assert(is_map(Initialized)),
    %% 验证返回结果是映射类型
    %% 包含Lua运行时状态和上下文

    ?debugFmt("Lua init: OK", []).
    %% 输出调试信息

%% ============================================================
%% Lua函数列表测试
%% ============================================================
%% @doc 测试用例：Lua函数导出
%%%
%%% 本测试验证Lua模块的函数发现功能：
%%% 1. 定义包含多个函数的Lua模块
%%% 2. 初始化Lua环境
%%% 3. 查询可用的导出函数列表
%%% 4. 验证函数正确导出
%%%
%%% 函数发现机制：
%%% - dev_lua:functions/3解析Lua源代码
%%% - 识别所有定义的函数名
%%%
%%% 返回格式为函数名列表
lua_functions_test() ->
    Process = #{
        <<"module">> => #{
            <<"content-type">> => <<"application/lua">>,
            <<"body">> => <<"
                function test1() return 1 end
                function test2() return 2 end
                function test3() return 3 end
            ">>
        }
    },
    %% 创建包含三个函数的Lua模块
    %% 每个函数简单返回对应数字

    {ok, Initialized} = dev_lua:init(Process, #{}, #{}),
    %% 初始化Lua环境

    {ok, Functions} = dev_lua:functions(Initialized, #{}, #{}),
    %% 查询导出函数列表
    %% dev_lua:functions/3解析并返回函数名
    %% 返回值是函数名列表

    ?assert(lists:member(<<"test1">>, Functions)),
    %% 验证test1在函数列表中

    ?assert(lists:member(<<"test2">>, Functions)),
    %% 验证test2在函数列表中

    ?assert(lists:member(<<"test3">>, Functions)),
    %% 验证test3在函数列表中

    ?debugFmt("Lua functions: ~p", [Functions]).
    %% 输出函数列表调试信息

%% ============================================================
%% Lua编码解码测试
%% ============================================================
%% @doc 测试用例：Lua数据编码解码
%%%
%%% 本测试验证Lua数据的序列化能力：
%%% 1. 创建测试数据映射
%%% 2. 编码为Lua格式
%%% 3. 解码回原始格式
%%% 4. 验证数据完整性
%%%
%%% 编码格式说明：
%%% - dev_lua:encode/2将Erlang映射转为Lua表格式
%%% - dev_lua:decode/2将Lua表转回Erlang映射
lua_encode_decode_test() ->
    Term = #{<<"key">> => <<"value">>, <<"num">> => 42},
    %% 创建测试数据
    %% 包含字符串和整数类型

    Encoded = dev_lua:encode(Term, #{}),
    %% 编码为Lua格式
    %% dev_lua:encode/2将映射转为Lua表字符串
    %% 例如：{key = "value", num = 42}

    Decoded = dev_lua:decode(Encoded, #{}),
    %% 解码回映射
    %% dev_lua:decode/2解析Lua表还原为Erlang类型

    ?assertEqual(Term, Decoded),
    %% 验证编解码后数据一致

    ?debugFmt("Lua encode/decode: OK", []).
    %% 输出调试信息

%% ============================================================
%% WASI初始化测试
%% ============================================================
%% @doc 测试用例：WASI环境初始化
%%%
%%% 本测试验证WASI运行时的初始化：
%%% 1. 初始化WASI环境
%%% 2. 验证虚拟文件系统创建
%%% 3. 验证标准文件描述符分配
%%%
%%% WASI组件说明：
%%% - VFS（虚拟文件系统）提供目录结构
%%% - 文件描述符0、1、2对应标准输入、输出、错误
wasi_init_test() ->
    {ok, Msg} = dev_wasi:init(#{}, #{}, #{}),
    %% 初始化WASI环境
    %% dev_wasi:init/3创建WASI运行时上下文
    %% 返回包含VFS和文件描述符的消息

    %% 验证VFS
    VFS = hb_ao:get(<<"vfs">>, Msg, #{}),
    %% 从初始化消息提取虚拟文件系统
    %% vfs字段包含目录结构定义

    ?assert(maps:is_key(<<"dev">>, VFS)),
    %% 验证VFS包含dev目录
    %% dev目录包含设备特殊文件

    %% 验证文件描述符
    FDs = hb_ao:get(<<"file-descriptors">>, Msg, #{}),
    %% 提取文件描述符表
    %% 文件描述符是进程访问文件的句柄

    ?assert(maps:is_key(<<"0">>, FDs)),
    %% 验证标准输入（stdin）存在

    ?assert(maps:is_key(<<"1">>, FDs)),
    %% 验证标准输出（stdout）存在

    ?assert(maps:is_key(<<"2">>, FDs)),
    %% 验证标准错误（stderr）存在

    ?debugFmt("WASI init: VFS and FDs created", []).
    %% 输出调试信息

%% ============================================================
%% WASI标准输出测试
%% ============================================================
%% @doc 测试用例：WASI标准输出处理
%%%
%%% 本测试验证WASI的stdout处理能力：
%%% 1. 创建包含stdout数据的VFS配置
%%% 2. 调用stdout函数验证输出
%%%
%%% stdout机制：
%%% - 写入stdout文件的内容会被捕获
%%%
%%% 用于测试和调试输出捕获
wasi_stdout_test() ->
    Msg = #{
        <<"vfs">> => #{
            <<"dev">> => #{
                <<"stdout">> => <<"Hello, World!">>
            }
        }
    },
    %% 创建VFS配置
    %% dev/stdout文件包含输出内容

    ?assertEqual(<<"Hello, World!">>, dev_wasi:stdout(Msg)),
    %% 验证stdout函数返回正确内容
    %% dev_wasi:stdout/1从VFS提取stdout数据

    ?debugFmt("WASI stdout: OK", []).
    %% 输出调试信息

%% ============================================================
%% CU模块导出测试
%% ============================================================
%% @doc 测试用例：CU模块接口验证
%%%
%%% 本测试验证CU（计算单元）模块的导出函数：
%%% - 确保模块已加载
%%% - 验证关键函数已导出
%%%
%%% CU模块功能：
%%% - push：推送计算任务
%%% - execute：执行计算
cu_exports_test() ->
    %% 验证CU模块导出
    code:ensure_loaded(dev_cu),
    %% 确保模块已加载
    %% code:ensure_loaded/1尝试加载模块

    ?assert(erlang:function_exported(dev_cu, push, 2)),
    %% 验证push/2函数已导出
    %% 参数：模块名、函数名、参数个数

    ?assert(erlang:function_exported(dev_cu, execute, 2)),
    %% 验证execute/2函数已导出

    ?debugFmt("CU exports: OK", []).
    %% 输出调试信息

%% ============================================================
%% 完整WASM工作流测试
%% ============================================================
%% @doc 测试用例：完整WASM运行工作流
%%%
%%% 本测试验证WASM运行时的完整执行流程：
%%% 1. 加载WASM镜像
%%% 2. 初始化实例
%%% 3. 执行阶乘计算
%%% 4. 创建状态快照
%%%
%%% 此测试模拟典型的WASM执行场景：
%%% - 用户加载智能合约
%%% - 初始化合约状态
%%% - 调用合约函数
%%% - 保存执行结果供后续使用
complete_wasm_workflow_test() ->
    ?debugFmt("=== Complete WASM Workflow ===", []),
    %% 输出工作流开始标记

    application:ensure_all_started(hb),
    %% 确保应用运行

    hb:init(),
    %% 初始化环境

    %% 1. 加载镜像
    Msg0 = dev_wasm:cache_wasm_image("test/test.wasm"),
    %% 加载WASM模块文件

    ?debugFmt("1. Loaded WASM image", []),
    %% 输出步骤信息

    %% 2. 初始化
    {ok, Msg1} = hb_ao:resolve(Msg0, <<"init">>, #{}),
    %% 创建WASM实例

    ?debugFmt("2. Initialized WASM instance", []),
    %% 输出步骤信息

    %% 3. 计算阶乘
    Msg2 = Msg1#{<<"function">> => <<"fac">>, <<"parameters">> => [6.0]},
    %% 创建计算请求
    %% 计算6的阶乘

    {ok, Result} = hb_ao:resolve(Msg2, <<"compute">>, #{}),
    %% 执行计算

    {ok, [720.0]} = hb_ao:resolve(Result, <<"results/output">>, #{}),
    %% 验证结果
    %% 6! = 720

    ?debugFmt("3. Computed 6! = 720", []),
    %% 输出步骤信息

    %% 4. 创建快照
    {ok, Snapshot} = hb_ao:resolve(Result, <<"snapshot">>, #{}),
    %% 创建执行快照
    %% 快照保存当前状态供后续恢复

    ?assert(maps:is_key(<<"body">>, Snapshot)),
    %% 验证快照包含body字段
    %% body包含序列化后的状态数据

    ?debugFmt("4. Created snapshot", []),
    %% 输出步骤信息

    ?debugFmt("=== All tests passed! ===", []).
    %% 输出工作流成功标记
