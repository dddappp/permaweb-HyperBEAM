%%%-------------------------------------------------------------------
%%% @doc JavaScript Smart Contract Runtime Device
%%%
%%% ===================== 概述 =====================
%%% 这是一个 AO HyperBEAM 设备，用于在 WebAssembly 环境中执行 JavaScript 智能合约。
%%% 它利用 QuickJS（一个轻量级 JavaScript 引擎，编译为 WASM）来运行 JS 代码。
%%%
%%% ===================== 核心概念 =====================
%%% 1. 设备 (Device): AO 系统中的功能模块，每个设备负责特定功能
%%% 2. 设备栈 (Device Stack): 多个设备组合使用，栈底设备通常是 wasm-64
%%% 3. 消息 (Message): AO 系统中的通信单元，包含 M1（输入）和 M2（输出）
%%% 4. WASM 实例: QuickJS 在 WebAssembly 中的运行实例
%%%
%%% ===================== 功能 API =====================
%%%   init/3     - 初始化运行时环境
%%%   compute/3  - 执行消息处理器（处理智能合约）
%%%   snapshot/3 - 保存运行时状态（用于持久化）
%%%   normalize/3 - 恢复运行时状态（从快照恢复）
%%%
%%% ===================== 状态持久化机制 =====================
%%% 重要：普通设备无法自动保持状态！
%%% - dev_aojs 提供了 snapshot/normalize API
%%% - 但这些只是工具函数，需要配合进程机制才能工作
%%% - 进程调度器会自动调用 snapshot 保存状态，调用 normalize 恢复状态
%%%
%%% ===================== 架构位置 =====================
%%% dev_aojs 通常放在设备栈的顶层，下层是 dev_wasm（管理 WASM 实例）
%%%
%%% @end
%%%-------------------------------------------------------------------

%%%===================================================================
%%% 【模块声明部分】
%%%===================================================================

%% -module(模块名)
%% Erlang 的模块声明，每个 .erl 文件必须有，且必须与文件名一致
%% 这里的模块名是 dev_aojs，对应文件 dev_aojs.erl
-module(dev_aojs).

%% -export([函数名/参数个数, ...])
%% 声明模块的公共 API，供其他模块调用
%% 只有声明在 -export 中的函数才能被外部访问
-export([info/3, init/3, compute/3, snapshot/3, normalize/3]).
-export([load_js_module/2]).

%% -include("include/hb.hrl")
%% 包含 HyperBEAM 的头文件，定义了一些通用宏和记录类型
%% 例如消息结构、选项等通用定义
-include("include/hb.hrl").

%% -define(宏名, 值)
%% 定义常量，方便维护和修改
%% ?RESULT_BUF_SIZE 是一个宏，表示结果缓冲区大小
%% 65536 字节 = 64KB，用于存储 JavaScript 执行结果
-define(RESULT_BUF_SIZE, 65536).


%%%===================================================================
%%% 【设备信息部分】
%%%===================================================================

%% @doc info/3 - 获取设备信息
%%
%% ===================== 作用 =====================
%% 返回设备的元数据，包括名称、描述和导出的函数。
%% 这是 AO 设备的标准接口，hb_ao:resolve 会调用此函数获取设备信息。
%%
%% ===================== 参数说明 =====================
%% _M1: 第一个消息参数（此函数未使用）
%% _M2: 第二个消息参数（此函数未使用）
%% _Opts: 选项参数（此函数未使用）
%%
%% ===================== 返回值 =====================
%% {ok, #{
%%     <<"name">> => 设备名称,
%%     <<"description">> => 描述,
%%     <<"exports">> => 可导出的函数列表
%% }}
%%
%% ===================== 消息格式说明 =====================
%% <<"name">> 是二进制字符串语法，等同于 name 但类型是 binary
%% AO 系统中大量使用二进制字符串作为键名
info(_M1, _M2, _Opts) ->
    %% 返回设备信息映射表
    {ok, #{
        %% <<"name">> => 设备唯一标识符
        %% 格式：名称@版本号，这里是 aojs@1.0
        <<"name">> => <<"aojs@1.0">>,

        %% <<"description">> => 设备的功能描述
        <<"description">> => <<"JavaScript Smart Contract Runtime">>,

        %% <<"exports">> => 设备导出的函数列表
        %% 这些是设备支持的操作：初始化、计算（执行）、快照、保存
        <<"exports">> => [<<"init">>, <<"compute">>, <<"snapshot">>, <<"normalize">>]
    }}.


%%%===================================================================
%%% 【初始化部分】
%%%===================================================================

%% @doc init/3 - 初始化 JavaScript 运行时
%%
%% ===================== 作用 =====================
%% 初始化 dev_aojs 设备，确保运行时环境已准备就绪。
%% 实际上，WASM 实例是由下层的 dev_wasm 设备创建的，
%% dev_aojs 只负责检查和标记初始化状态。
%%
%% ===================== 状态管理 =====================
%% 使用 priv 存储初始化状态：
%% - priv[prefixed_key(Prefix, <<"initialized">>] = true 表示已初始化
%% - priv[prefixed_key(Prefix, <<"instance">>] = WASM 实例引用
%%
%% ===================== 为什么需要初始化检查 =====================
%% 1. 避免重复初始化（多次调用 init 不应出错）
%% 2. 确保 WASM 实例已创建（下层设备创建）
%% 3. 提供一个 ready 标记，告知上层设备可以使用了
%%
init(M1, _M2, Opts) ->
    %% dev_stack:prefix(M1, #{}, Opts)
    %% ==============================
    %% 获取设备栈的前缀，用于隔离不同设备栈的状态。
    %% 设备栈前缀是一个唯一的标识符，确保不同设备实例的状态互不干扰。
    %% 例如：如果有两个进程使用同一个 dev_aojs，它们的状态通过前缀隔离。
    %%
    %% M1: 当前消息
    %% #{}: 额外的上下文（空映射）
    %% Opts: 选项参数
    %%
    %% 返回值：二进制前缀，如 <<"proc-123/slot-0/aojs@1.0">>
    Prefix = dev_stack:prefix(M1, #{}, Opts),

    %% hb_private:get(键, 消息, 默认值, 选项)
    %% ==============================
    %% 从消息的私有部分获取值。
    %% priv 是消息中专门用于存储私有/内部数据的字段。
    %% 与公共数据不同，priv 数据不会被写入缓存（见 hb_cache.erl:268）。
    %%
    %% prefixed_key(Prefix, <<"initialized">>)
    %% 生成带前缀的键，如：<<"proc-123/slot-0/initialized">>
    %% 这样不同设备栈的初始化状态不会互相冲突。
    %%
    %% M1: 当前消息，从其 priv 中读取
    %% not_found: 如果键不存在，返回此默认值
    %% Opts: 选项参数
    %%
    %% 返回值：如果已初始化返回 true，否则返回 not_found
    case hb_private:get(prefixed_key(Prefix, <<"initialized">>), M1, not_found, Opts) of
        %% 如果已初始化，直接返回成功
        %% 注意：这里不重复初始化，避免浪费资源
        true ->
            {ok, M1};

        %% 如果未初始化（或 not_found），执行初始化
        _ ->
            do_init(M1, Prefix, Opts)
    end.

%% prefixed_key/2 - 生成带前缀的键
%% ===================== 作用 =====================
%% 将前缀和键组合成一个完整的键，用于状态隔离。
%%
%% ===================== 两种情况 =====================
%% 1. 前缀为空时，直接返回原键
%% 2. 前缀非空时，格式为 prefix/key（使用 / 分隔）
%%
%% ===================== 示例 =====================
%% prefixed_key(<<>>, <<"instance">>) -> <<"instance">>
%% prefixed_key(<<"proc-123">>, <<"instance">>) -> <<"proc-123/instance">>
prefixed_key(<<>>, Key) -> Key;
prefixed_key(Prefix, Key) -> <<Prefix/binary, "/", Key/binary>>.

%% @doc do_init/3 - 执行实际的初始化工作
%% ===================== 作用 =====================
%% 检查 WASM 实例是否存在，如果存在则标记为就绪。
%%
%% ===================== 初始化流程 =====================
%% 1. 从 priv 中获取下层 dev_wasm 创建的 WASM 实例
%% 2. 检查实例是否存在
%% 3. 设置 ready 标记，表示 dev_aojs 已准备就绪
%%
do_init(M1, Prefix, Opts) ->
    %% hb_private:get/4
    %% ==============================
    %% 从 priv 中获取 WASM 实例引用。
    %% 这个实例是由设备栈中 dev_wasm 设备创建的。
    %% dev_wasm 会将实例保存到 priv[prefixed_key(Prefix, <<"instance">>)]
    %%
    %% 注意：dev_aojs 依赖下层设备（dev_wasm）来创建和管理 WASM 实例
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),

    case Instance of
        %% 如果实例不存在，返回错误
        %% 这种情况通常是设备栈配置不正确，或者 dev_wasm 未初始化
        not_found ->
            {error, #{<<"error">> => <<"wasm_instance_not_found">>}};

        %% 如果实例存在，标记为就绪
        %% hb_private:set/4
        %% ==============================
        %% 将值存储到消息的 priv 部分。
        %%
        %% M1: 原消息
        %% prefixed_key(Prefix, <<"ready">>): 要设置的键
        %% true: 要存储的值
        %% Opts: 选项
        %%
        %% 返回：更新后的消息，M1' = M1#{priv => #{ready => true}}
        _ ->
            {ok, hb_private:set(M1, prefixed_key(Prefix, <<"ready">>), true, Opts)}
    end.


%%%===================================================================
%%% 【JavaScript 模块加载部分】
%%%===================================================================

%% @doc load_js_module/2 - 加载 JavaScript 模块
%%
%% ===================== 作用 =====================
%% 加载用户提供的 JavaScript 合约代码到 QuickJS 运行时。
%% 这个函数会：
%% 1. 注入 AO 运行时环境（如果需要）
%% 2. 找到模块源代码
%% 3. 执行代码以注册处理器
%%
%% ===================== 加载时机 =====================
%% 在 compute 函数中被调用，确保每次消息处理前模块已加载。
%% 这样可以支持动态更新模块。
%%
%% ===================== JavaScript 模块格式 =====================
%% 模块应该定义 Handlers 对象来注册消息处理器：
%% Handlers.add('ActionName', (msg) => { ... return result; });
%% 也可以使用 state 对象存储持久化状态。
%%
load_js_module(M1, Opts) ->
    %% 获取设备栈前缀
    Prefix = dev_stack:prefix(M1, #{}, Opts),

    %% 获取 WASM 实例
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),

    %% 条件判断：如果需要，注入 AO 运行时
    %% ===================== needs_runtime_injection =====================
    %% 检查 Handlers 对象是否已存在
    %% 如果不存在，说明 AO 运行时还未注入，需要先注入
    %%
    %% eval_js/3
    %% ==============================
    %% 在 WASM 中执行 JavaScript 代码并获取结果。
    %% 这里执行 "typeof Handlers" 来检查 Handlers 是否存在。
    %%
    %% 返回值：
    %% - {ok, <<"object">>}: Handlers 已存在（运行时已注入）
    %% - 其他值：运行时未注入，需要注入
    %%
    case needs_runtime_injection(M1, Instance, Opts) of
        true ->
            %% 注入 AO 运行时环境
            inject_ao_runtime(Instance, Opts);
        false ->
            ok
    end,

    %% 查找并加载模块源代码
    case find_module_source(M1, Opts) of
        not_found ->
            %% 没有找到模块，可能是不需要模块的操作
            {ok, M1};

        Source when is_binary(Source) ->
            %% 执行 JavaScript 代码
            case eval_js(Instance, Source, Opts) of
                {ok, _} ->
                    %% 执行成功，返回更新后的消息
                    {ok, M1};
                {error, Error} ->
                    %% 执行失败，返回错误
                    {error, #{<<"error">> => Error}}
            end
    end.

%% needs_runtime_injection/3 - 检查是否需要注入运行时
%% ===================== 作用 =====================
%% 通过执行 JavaScript 代码检查 AO 运行时是否已注入。
%% AO 运行时提供了 Handlers、ao.send 等全局对象。
needs_runtime_injection(_M1, Instance, Opts) ->
    %% 执行 JS 检查：如果 Handlers 是对象类型，说明已注入
    case eval_js(Instance, <<"typeof Handlers">>, Opts) of
        {ok, <<"object">>} ->
            %% Handlers 已存在，返回 false（不需要注入）
            false;
        _ ->
            %% Handlers 不存在或其他情况，返回 true（需要注入）
            true
    end.

%% inject_ao_runtime/2 - 注入 AO 运行时
%% ===================== 作用 =====================
%% 将 ao-runtime.js 的内容注入到 QuickJS 运行时。
%% ao-runtime.js 提供了 AO 智能合约的运行环境。
%%
%% ===================== ao-runtime.js 包含什么 =====================
%% 1. Handlers 对象：用于注册消息处理器
%% 2. ao 对象：用于发送消息（ao.send）
%% 3. state 对象：用于存储状态
%% 4. 确定性 PRNG（xorshift128+ 伪随机数生成器）
%% 5. 确定性 Date 实现（使用 env.Timestamp，默认为 0）
%% 6. _clearOutbox()、_getOutbox() 等辅助函数
%% 7. _setSeed() 用于设置随机种子（已定义但当前未被调用）
%% 8. _h 内部注册表（Handlers._h）
%%
%% ===================== 注意 =====================
%% 随机种子 _seed 初始值为 [1, 2]。虽然 _setSeed() 已定义，
%% 但当前 dev_aojs 代码中未调用它来设置种子。
%% 如需启用完全确定性的 PRNG，需要在 execute_handler 中调用 _setSeed。
%%
%% ===================== 文档参考 =====================
%% 详见 docs/drafts/quickjs-wasm-compilation-guide.md 第 3.4 节
%%
inject_ao_runtime(Instance, Opts) ->
    %% 从文件读取 AO 运行时代码
    Runtime = ao_runtime_js(),
    %% 执行代码
    eval_js(Instance, Runtime, Opts).

%% ao_runtime_js/0 - 读取 AO 运行时文件
%% ===================== 作用 =====================
%% 从文件系统读取 ao-runtime.js 的内容。
%% 返回的已经是二进制格式，可以直接传给 eval_js。
ao_runtime_js() ->
    %% file:read_file/1
    %% ==============================
    %% Erlang 标准库函数，读取文件内容。
    %%
    %% "aojs/ao-runtime.js": 文件路径，相对于项目根目录
    %% 返回值：{ok, Content} 或 {error, Reason}
    %%
    %% Content 是二进制类型，包含文件的全部内容
    {ok, Content} = file:read_file("aojs/ao-runtime.js"),
    Content.

%% find_module_source/2 - 查找模块源代码
%% ===================== 作用 =====================
%% 查找用户提供的 JavaScript 模块源代码。
%% 查找顺序：
%% 1. 先检查消息中是否直接包含模块（aojs-module 字段）
%% 2. 再检查是否有模块 ID，从文件加载（module-id 字段）
%% 3. 都找不到返回 not_found
%%
%% ===================== 两种来源 =====================
%% 1. 消息内联：M2[<<"aojs-module">>] = JS 代码二进制
%% 2. 文件引用：M2[<<"module-id">>] = 模块文件名（不含 .js 后缀）
%%    从 aojs/aojs-modules/{module-id}.js 加载
%%
find_module_source(M1, Opts) ->
    %% hb_maps:get/4
    %% ==============================
    %% 从映射（map）中安全获取值。
    %%
    %% 第一个参数：键
    %% 第二个参数：要搜索的映射（M1 或 M2）
    %% 第三个参数：默认值（如果键不存在）
    %% 第四个参数：选项
    %%
    %% 这里检查 M1 中是否有 aojs-module 字段
    case hb_maps:get(<<"aojs-module">>, M1, not_found, Opts) of
        not_found ->
            %% 没有内联模块，检查是否有模块 ID
            case hb_maps:get(<<"module-id">>, M1, not_found, Opts) of
                not_found ->
                    %% 既没有内联模块，也没有模块 ID
                    not_found;
                ModuleId ->
                    %% 构建模块文件路径
                    %% 格式：aojs/aojs-modules/{ModuleId}.js
                    Path = <<"aojs/aojs-modules/", ModuleId/binary, ".js">>,

                    %% 尝试读取文件
                    case file:read_file(Path) of
                        {ok, Content} ->
                            %% 成功读取，返回内容
                            Content;
                        _ ->
                            %% 文件不存在或读取失败
                            not_found
                    end
            end;
        Source ->
            %% 直接使用内联的模块源代码
            Source
    end.


%%%===================================================================
%%% 【消息处理部分（Compute）】
%%%===================================================================

%% @doc compute/3 - 执行消息处理器
%%
%% ===================== 作用 =====================
%% 处理传入的消息，执行对应的 JavaScript 处理器函数。
%% 这是 dev_aojs 的核心功能：接收消息 → 执行 JS → 返回结果。
%%
%% ===================== 消息处理流程 =====================
%% 1. 确保 JavaScript 模块已加载（调用 load_js_module）
%% 2. 构建消息和环境的 JSON 对象
%% 3. 注入到 QuickJS 运行时
%% 4. 调用 Handlers.handle(msg) 执行处理器
%% 5. 解析结果和 outbox
%% 6. 返回结果
%%
compute(M1, M2, Opts) ->
    %% 确保模块已加载
    %% 如果尚未加载，这会注入运行时并加载模块
    {ok, M1Loaded} = load_js_module(M1, Opts),

    %% 执行处理器
    execute_handler(M1Loaded, M2, Opts).

%% @doc execute_handler/3 - 执行 JavaScript 处理器
%% ===================== 作用 =====================
%% 实际执行消息处理逻辑的函数。
%% 它会：
%% 1. 获取 WASM 实例
%% 2. 从消息中提取数据和元信息
%% 3. 构建 JavaScript 可执行的代码
%% 4. 执行代码并处理结果
%%
execute_handler(M1, M2, Opts) ->
    %% 获取设备栈前缀
    Prefix = dev_stack:prefix(M1, M2, Opts),

    %% 获取 WASM 实例引用
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),

    %% 构建消息 JSON
    %% ===================== 消息结构 =====================
    %% 从消息中提取：
    %% - Id: 消息 ID
    %% - From: 发送者进程 ID
    %% - Action: 操作类型（路由到对应的处理器）
    %% - Data: 消息数据
    %% - Tags: 标签（除保留字段外的其他键值对）
    %% - Block-Height: 区块高度
    %%
    Message = hb_maps:get(<<"body">>, M2, #{}, Opts),
    Process = hb_maps:get(<<"process">>, M1, #{}, Opts),

    %% 构建消息和环境的 JSON 字符串
    %% 这些 JSON 将被注入到 JavaScript 运行时中
    MsgJson = build_msg_json(Message, M2, Opts),
    EnvJson = build_env_json(Process, Opts),

    %% 构建要执行的 JavaScript 代码
    %% ===================== 代码注入方式 =====================
    %% 通过字符串拼接构建 JS 代码，然后执行。
    %% 这是 Erlang 和 JavaScript 之间的数据传递方式。
    %%
    %% 代码结构：
    %% _clearOutbox();              - 清空 outbox
    %% globalThis.msg = {...};      - 注入消息对象
    %% globalThis.env = {...};      - 注入环境对象
    %% JSON.stringify(Handlers.handle(msg))  - 调用处理器
    %%
    JsCode = iolist_to_binary([
        <<"_clearOutbox();globalThis.msg=">>, MsgJson,
        <<";globalThis.env=">>, EnvJson,
        <<";JSON.stringify(Handlers.handle(msg))">>
    ]),

    %% 执行 JavaScript 代码
    case eval_js(Instance, JsCode, Opts) of
        {ok, ResultJson} ->
            %% 成功执行，获取 outbox
            OutboxJson = read_outbox(Instance, Opts),
            %% 处理结果
            process_results(M1, ResultJson, OutboxJson, Opts);
        {error, Error} ->
            {error, #{<<"error">> => Error}}
    end.

%% build_msg_json/3 - 构建消息 JSON
%% ===================== 作用 =====================
%% 将 AO 消息格式转换为 JavaScript 可以理解的 JSON 格式。
%% 提取消息的关键字段并打包成 JSON。
%%
%% ===================== 字段映射 =====================
%% AO 消息字段 -> JavaScript 对象字段
%% <<"id">> -> Id
%% <<"from-process">> -> From
%% <<"action">> / <<"Action">> -> Action
%% <<"data">> -> Data
%% 其他字段 -> Tags（除保留字段外）
%% <<"block-height">> (来自 M2) -> Block-Height
%%
build_msg_json(Message, M2, Opts) ->
    %% 提取各个字段
    Id = hb_maps:get(<<"id">>, Message, <<>>, Opts),
    From = hb_maps:get(<<"from-process">>, Message, <<>>, Opts),
    Action = hb_maps:get(<<"action">>, Message, <<"default">>, Opts),
    Data = hb_maps:get(<<"data">>, Message, <<>>, Opts),
    BlockHeight = hb_maps:get(<<"block-height">>, M2, 0, Opts),

    %% 构建映射
    MsgMap = #{
        <<"Id">> => Id,
        <<"From">> => From,
        <<"Action">> => Action,
        <<"Data">> => Data,
        <<"Tags">> => build_tags(Message, Opts),
        <<"Block-Height">> => BlockHeight
    },

    %% 编码为 JSON 字符串
    %% hb_json:encode/1 将 Erlang 映射转换为 JSON 字符串
    hb_json:encode(MsgMap).

%% build_env_json/2 - 构建环境 JSON
%% ===================== 作用 =====================
%% 构建 JavaScript 运行时的环境信息。
%% 主要包含进程相关的上下文信息。
%%
%% ===================== env 对象包含什么 =====================
%% env.Process.Id: 当前进程的 ID
%%
%% 注意：文档中提到的 env.Timestamp 实际上未被实现！
%% （见 quickjs-wasm-compilation-guide.md 第 8.7 节分析）
build_env_json(Process, Opts) ->
    %% 提取进程 ID
    ProcId = hb_maps:get(<<"id">>, Process, <<>>, Opts),

    %% 构建环境映射
    EnvMap = #{
        <<"Process">> => #{<<"Id">> => ProcId}
    },

    %% 编码为 JSON
    hb_json:encode(EnvMap).

%% @doc build_tags/2 - 构建标签映射
%% ===================== 作用 =====================
%% 从消息中提取标签（Tags），排除保留字段。
%% 标签是消息的元数据，以键值对形式存在。
%%
%% ===================== 保留字段（排除项）=====================
%% - id: 消息 ID
%% - from: 发送者
%% - action: 操作类型
%% - data: 消息数据
%% - priv: 私有数据
%%
%% ===================== 过滤规则 =====================
%% 只保留二进制或整数类型的值
%% 其他类型（如映射、列表）被排除
build_tags(Message, _Opts) when is_map(Message) ->
    %% 要排除的保留键列表
    ExcludeKeys = [<<"id">>, <<"from">>, <<"action">>, <<"data">>, <<"priv">>],

    %% maps:fold/3
    %% ==============================
    %% 遍历映射的每个键值对，累积结果。
    %%
    %% Fun: 处理函数，接收 (Key, Value, Acc) 返回新 Acc
    %% Acc0: 初始累加值（这里是空映射 #{}）
    %% Message: 要遍历的映射
    %%
    maps:fold(fun(Key, Value, Acc) ->
        %% hb_ao:normalize_key/1
        %% ==============================
        %% 规范化键名（可能涉及大小写转换等）
        %%
        %% lists:member/2
        %% ==============================
        %% 检查键是否在排除列表中
        case lists:member(hb_ao:normalize_key(Key), ExcludeKeys) of
            true ->
                %% 在排除列表中，跳过
                Acc;
            false when is_binary(Value); is_integer(Value) ->
                %% 二进制或整数类型，保留
                Acc#{Key => Value};
            false ->
                %% 其他类型，跳过
                Acc
        end
    end, #{}, Message);
build_tags(_, _) ->
    %% 如果消息不是映射，返回空映射
    #{}.


%%%===================================================================
%%% 【JavaScript 执行接口（WASM 接口）】
%%%===================================================================

%% @doc eval_js/3 - 在 WASM 中执行 JavaScript 代码
%%
%% ===================== 作用 =====================
%% 这是 Erlang 与 WASM 运行时交互的核心函数。
%% 它负责：
%% 1. 将 JavaScript 代码写入 WASM 内存
%% 2. 调用 WASM 中的 qjs_eval 函数执行代码
%% 3. 读取执行结果
%% 4. 管理内存分配和释放
%%
%% ===================== 内存管理 =====================
%% WASM 运行在沙盒中，Erlang 需要显式地：
%% - 分配内存：hb_beamr_io:malloc/2
%% - 写入数据：hb_beamr_io:write_string/2
%% - 读取数据：hb_beamr_io:read/3
%% - 释放内存：hb_beamr_io:free/2
%%
%% ===================== 结果格式约定 =====================
%% - 非负返回值：表示结果字符串的长度
%% - 负返回值：表示错误，-1 表示一般错误
%% - 错误信息存储在结果缓冲区中
%%
eval_js(Instance, Code, _Opts) ->
    %% 步骤 1: 将 JavaScript 代码写入 WASM 内存
    %% ===================== hb_beamr_io:write_string/2 =====================
    %% 将字符串写入 WASM 实例的内存。
    %% WASM 内存是线性的字节数组，需要通过指针访问。
    %%
    %% 参数：
    %% - Instance: WASM 实例 PID
    %% - Code: 要写入的二进制字符串
    %%
    %% 返回值：
    %% - {ok, CodePtr}: 成功，返回代码在内存中的指针地址
    %% - {error, E}: 失败
    %%
    case hb_beamr_io:write_string(Instance, Code) of
        {ok, CodePtr} ->
            %% 代码长度（字节）
            CodeLen = byte_size(Code),

            %% 步骤 2: 分配结果缓冲区
            %% ===================== hb_beamr_io:malloc/2 =====================
            %% 在 WASM 内存中分配一块区域用于存储结果。
            %% ?RESULT_BUF_SIZE = 65536 (64KB)
            %%
            %% 返回值：
            %% - {ok, ResultPtr}: 成功，返回结果缓冲区的指针
            %%
            case hb_beamr_io:malloc(Instance, ?RESULT_BUF_SIZE) of
                {ok, ResultPtr} ->
                    %% 步骤 3: 调用 qjs_eval 执行代码
                    %% ===================== hb_beamr:call/3 =====================
                    %% 调用 WASM 实例中导出的函数。
                    %%
                    %% 参数：
                    %% - Instance: WASM 实例
                    %% - "qjs_eval": 要调用的函数名
                    %% - [CodePtr, CodeLen, ResultPtr, ?RESULT_BUF_SIZE]: 参数列表
                    %%   1. CodePtr: 代码字符串的指针
                    %%   2. CodeLen: 代码长度
                    %%   3. ResultPtr: 结果缓冲区的指针
                    %%   4. ?RESULT_BUF_SIZE: 缓冲区大小
                    %%
                    %% 返回值：
                    %% - {ok, [Length]}: Length 是结果长度或错误码
                    %%
                    Result = hb_beamr:call(Instance, "qjs_eval",
                        [CodePtr, CodeLen, ResultPtr, ?RESULT_BUF_SIZE]),

                    %% 步骤 4: 处理执行结果
                    EvalResult = case Result of
                        {ok, [Length]} when Length >= 0 ->
                            %% 非负结果：成功，读取实际结果
                            %% max(1, Length) 确保至少读取 1 个字节
                            %% 即使 Length 是 0（空字符串），也要尝试读取
                            {ok, ResultBin} = hb_beamr_io:read(Instance, ResultPtr, max(1, Length)),
                            {ok, ResultBin};
                        {ok, [Length]} when Length < 0 ->
                            %% 负结果：出错，读取错误信息
                            %% hb_beamr_io:read_string/2 读取以 null 结尾的字符串
                            {ok, ErrorBin} = hb_beamr_io:read_string(Instance, ResultPtr),
                            {error, ErrorBin};
                        {error, E} ->
                            {error, E}
                    end,

                    %% 步骤 5: 释放内存
                    %% 非常重要！WASM 内存不会自动回收，需要手动释放
                    hb_beamr_io:free(Instance, CodePtr),
                    hb_beamr_io:free(Instance, ResultPtr),

                    EvalResult;
                {error, E} ->
                    %% 如果结果缓冲区分配失败，也要释放代码内存
                    hb_beamr_io:free(Instance, CodePtr),
                    {error, E}
            end;
        {error, E} ->
            {error, E}
    end.

%% @doc read_outbox/2 - 读取 outbox
%% ===================== 作用 =====================
%% 从 JavaScript 运行时读取 outbox（待发送消息列表）。
%% outbox 由 ao.send() 调用填充。
%%
%% ===================== _getOutbox 函数 =====================
%% 在 ao-runtime.js 中定义：
%% globalThis._getOutbox = () => JSON.stringify(_outbox);
%% 返回 _outbox 数组的 JSON 字符串表示。
%%
read_outbox(Instance, Opts) ->
    case eval_js(Instance, <<"_getOutbox()">>, Opts) of
        {ok, OutboxJson} ->
            OutboxJson;
        _ ->
            %% 如果读取失败，返回空数组
            <<"[]">>
    end.

%% @doc process_results/4 - 处理执行结果
%% ===================== 作用 =====================
%% 解析 JavaScript 执行结果和 outbox，
%% 将它们打包成 AO 消息格式返回。
%%
%% ===================== 返回结果格式 =====================
%% {
%%     "results": {
%%         "data": {...},    // 处理器返回值
%%         "outbox": [...]  // 待发送消息列表
%%     }
%% }
%%
process_results(M1, ResultJson, OutboxJson, _Opts) ->
    %% 解析 JSON 字符串
    %% hb_json:decode/1 将 JSON 字符串转换为 Erlang 映射
    Result = hb_json:decode(ResultJson),
    Outbox = hb_json:decode(OutboxJson),

    %% 构建返回消息
    {ok, M1#{
        <<"results">> => #{
            <<"data">> => Result,
            <<"outbox">> => Outbox
        }
    }}.


%%%===================================================================
%%% 【状态持久化部分（Snapshot & Normalize）】
%%%===================================================================

%% @doc snapshot/3 - 保存运行时状态
%%
%% ===================== 作用 =====================
%% 将 QuickJS 运行时的当前状态保存为快照。
%% 这是状态持久化的关键函数。
%%
%% ===================== 快照机制 =====================
%% dev_aojs 使用 WASM 内存序列化模式：
%% 1. 调用 hb_beamr:serialize/1 将整个 WASM 内存导出为二进制
%% 2. 快照存储在消息的 <<"snapshot">> 字段中
%% 3. 进程调度器会调用 cache-control: store 保存到缓存
%%
%% ===================== 为什么需要快照 =====================
%% QuickJS 在 WASM 中运行，WASM 实例的内存包含：
%% - JavaScript 堆（对象、字符串等）
%% - JavaScript 调用栈
%% - 全局变量
%% - Handlers 注册表
%% 这些内存数据需要保存才能在进程重启后恢复。
%%
%% ===================== 对比 dev_counter =====================
%% dev_counter 使用缓存模式（保存 state 映射）
%% dev_aojs 使用序列化模式（保存整个 WASM 内存）
%% 序列化模式更适合复杂运行时状态。
%%
%% ===================== 文档参考 =====================
%% 详见 docs/drafts/ao-device-state-persistence-verification.md 第 10.2 节
%% 详见 docs/drafts/quickjs-wasm-compilation-guide.md 第 5.3 节
%%
snapshot(M1, _M2, Opts) ->
    %% 获取设备栈前缀
    Prefix = dev_stack:prefix(M1, #{}, Opts),

    %% 获取 WASM 实例
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),

    case Instance of
        not_found ->
            {error, <<"no_wasm_instance">>};
        _ ->
            %% 调用 hb_beamr:serialize/1 序列化 WASM 实例
            case hb_beamr:serialize(Instance) of
                {ok, Snapshot} ->
                    %% 快照存储在消息中
                    {ok, M1#{<<"snapshot">> => Snapshot}};
                {error, E} ->
                    {error, E}
            end
    end.

%% @doc normalize/3 - 恢复运行时状态
%%
%% ===================== 作用 =====================
%% 从快照恢复 QuickJS 运行时的状态。
%% 与 snapshot 配对使用，实现状态的保存和恢复。
%%
%% ===================== 恢复流程 =====================
%% 1. 从消息中获取 <<"snapshot">> 字段
%% 2. 如果不存在，说明是新进程，直接返回
%% 3. 如果存在，调用 hb_beamr:deserialize/2 恢复 WASM 内存
%% 4. 从消息中移除 snapshot 字段（因为已恢复）
%%
%% ===================== 注意事项 =====================
%% - deserialize 会覆盖 WASM 实例的整个内存
%% - 恢复后，QuickJS 的状态与快照时完全一致
%% - snapshot 字段在恢复后被移除，避免重复恢复
%%
normalize(M1, _M2, Opts) ->
    %% 检查是否有快照
    case hb_maps:get(<<"snapshot">>, M1, not_found, Opts) of
        not_found ->
            %% 没有快照，新进程或无需恢复
            {ok, M1};
        Snapshot ->
            %% 有快照，执行恢复
            Prefix = dev_stack:prefix(M1, #{}, Opts),
            Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),

            case hb_beamr:deserialize(Instance, Snapshot) of
                ok ->
                    %% 恢复成功，从消息中移除 snapshot 字段
                    {ok, maps:remove(<<"snapshot">>, M1)};
                {error, E} ->
                    {error, E}
            end
    end.


%%%===================================================================
%%% 【测试部分】
%%%===================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%% @doc start/0 - 测试初始化辅助函数
%% ===================== 作用 =====================
%% 设置测试环境：
%% 1. 确保 hb 应用已启动
%% 2. 初始化随机数种子（用于测试的可重复性）
%%
%% ===================== random seed =====================
%% Erlang 的 rand 模块需要种子才能生成确定性的随机数。
%% 这里使用强随机字节生成种子。
start() ->
    application:ensure_all_started(hb),
    %% 生成 12 字节的随机数
    <<I1:32, I2:32, I3:32>> = crypto:strong_rand_bytes(12),
    %% 设置随机数种子为 {I1, I2, I3}
    rand:seed(exsplus, {I1, I2, I3}).

%% @doc setup_test_env/0 - 设置测试环境
%% ===================== 作用 =====================
%% 创建一个用于测试的存储后端。
%% 返回包含 store 选项的映射。
setup_test_env() ->
    start(),
    %% hb_test_utils:test_store/1
    %% ==============================
    %% 创建一个测试用的存储后端。
    %% hb_store_fs 表示使用文件系统存储。
    %%
    Store = hb_test_utils:test_store(hb_store_fs),
    #{store => [Store]}.

%% -------------------------
%% 设备信息测试
%% -------------------------

info_test() ->
    start(),
    %% 使用 {as, dev_aojs, Msg} 语法直接调用设备
    %% 这不需要设备注册，适用于单元测试
    %%
    %% hb_ao:resolve/3
    %% ==============================
    %% 解析并执行 AO 消息。
    %%
    %% 参数：
    %% - {as, dev_aojs, #{}}: 消息1，指定使用 dev_aojs 设备
    %% - #{<<"path">> => <<"info">>}: 消息2，请求 info 操作
    %% - #{}: 选项
    %%
    {ok, Info} = hb_ao:resolve(
        {as, dev_aojs, #{}},
        #{<<"path">> => <<"info">>},
        #{}
    ),
    %% 验证返回值
    ?assertEqual(<<"aojs@1.0">>, maps:get(<<"name">>, Info)),
    ?assertEqual(<<"JavaScript Smart Contract Runtime">>, maps:get(<<"description">>, Info)).

%% -------------------------
%% WASM 初始化测试
%% -------------------------

aojs_wasm_init_test_() ->
    {timeout, 60, fun aojs_wasm_init/0}.

aojs_wasm_init() ->
    Opts = setup_test_env(),

    %% 缓存 WASM 镜像
    %% dev_wasm:cache_wasm_image/2
    %% ==============================
    %% 加载并缓存 WASM 文件。
    %% 返回包含 image 字段的消息。
    %%
    %% "aojs/aojs.wasm": WASM 文件路径
    #{<<"image">> := WASMImageID} = dev_wasm:cache_wasm_image("aojs/aojs.wasm", Opts),

    %% 构建设备栈消息
    %% dev_aojs 需要一个设备栈，栈底是 wasm-64 设备
    StackMsg = #{
        <<"device">> => <<"stack@1.0">>,
        <<"device-stack">> => [<<"wasm-64@1.0">>],
        <<"stack-keys">> => [<<"init">>, <<"compute">>],
        <<"image">> => WASMImageID
    },

    %% 初始化设备栈
    %% 这会加载 WASM 模块并创建实例
    {ok, M1} = hb_ao:resolve(StackMsg, #{<<"path">> => <<"init">>}, Opts),

    %% 验证返回
    ?assertMatch(#{}, M1),

    %% 调用 qjs_init 初始化 QuickJS
    %% dev_wasm 提供了直接调用 WASM 函数的接口
    {ok, InitResult} = hb_ao:resolve(
        M1,
        #{
            <<"path">> => <<"compute">>,
            <<"body">> => #{
                <<"function">> => <<"qjs_init">>,
                <<"parameters">> => []
            }
        },
        Opts
    ),

    %% qjs_init 返回 0 表示成功
    Output = hb_ao:get(<<"results/output">>, InitResult, Opts),
    ?assertEqual([0], Output),

    ok.

%% @doc test_aojs_process/1 - 创建 AOJS 进程的辅助函数
%% ===================== 作用 =====================
%% 创建一个用于测试的 AO 进程消息。
%% 这个消息包含了创建进程所需的所有配置。
%%
%% ===================== 进程配置 =====================
%% - device: process@1.0（进程设备）
%% - execution-device: stack@1.0（执行设备栈）
%% - scheduler-device: scheduler@1.0（调度器设备）
%% - image: WASM 镜像 ID
%% - 其他配置...
%%
test_aojs_process(Opts) ->
    Wallet = hb_opts:get(priv_wallet, hb:wallet(), Opts),
    Address = hb_util:human_id(ar_wallet:to_address(Wallet)),
    #{<<"image">> := WASMImageID} = dev_wasm:cache_wasm_image("aojs/aojs.wasm", Opts),

    %% hb_message:commit/2
    %% ==============================
    %% 提交消息（签名并准备发送）。
    %%
    %% 返回的消息包含进程的所有配置信息
    hb_message:commit(
        #{
            <<"device">> => <<"process@1.0">>,
            <<"scheduler-device">> => <<"scheduler@1.0">>,
            <<"scheduler-location">> => Address,
            <<"type">> => <<"Process">>,
            <<"test-random-seed">> => rand:uniform(1337),
            <<"execution-device">> => <<"stack@1.0">>,
            <<"device-stack">> => [<<"wasm-64@1.0">>],
            <<"stack-keys">> => [<<"init">>, <<"compute">>],
            <<"image">> => WASMImageID,
            <<"scheduler">> => Address,
            <<"authority">> => Address
        },
        Opts#{priv_wallet => Wallet}
    ).

%% -------------------------
%% 进程消息创建测试
%% -------------------------

process_msg_creation_test_() ->
    {timeout, 60, fun process_msg_creation/0}.

process_msg_creation() ->
    start(),
    Opts = #{
        priv_wallet => hb:wallet(),
        store => hb_opts:get(store)
    },

    %% 创建 AOJS 进程消息
    Msg1 = test_aojs_process(Opts),

    %% 验证消息结构
    ?assertEqual(<<"process@1.0">>, maps:get(<<"device">>, Msg1)),
    ?assertEqual(<<"stack@1.0">>, maps:get(<<"execution-device">>, Msg1)),
    ?assertEqual(<<"scheduler@1.0">>, maps:get(<<"scheduler-device">>, Msg1)),
    ?assertEqual(<<"Process">>, maps:get(<<"type">>, Msg1)),

    %% 验证 WASM 镜像已设置
    ?assertMatch(<<_/binary>>, maps:get(<<"image">>, Msg1)),

    ok.

%% @doc schedule_test_message/2,3,4 - 调度测试消息
%% ===================== 作用 =====================
%% 向进程发送一个测试消息。
%% 支持重载，提供不同的参数组合。
schedule_test_message(Msg1, Text, Opts) ->
    schedule_test_message(Msg1, Text, #{}, Opts).
schedule_test_message(Msg1, Text, MsgBase, Opts) ->
    Wallet = hb:wallet(),
    UncommittedBase = hb_message:uncommitted(MsgBase, Opts),
    Msg2 =
        hb_message:commit(#{
                <<"path">> => <<"schedule">>,
                <<"method">> => <<"POST">>,
                <<"body">> =>
                    hb_message:commit(
                        UncommittedBase#{
                            <<"type">> => <<"Message">>,
                            <<"test-label">> => Text
                        },
                        Opts#{ priv_wallet => Wallet }
                    )
            },
            Opts#{ priv_wallet => Wallet }
        ),
    {ok, _} = hb_ao:resolve(Msg1, Msg2, Opts).

%% -------------------------
%% 进程调度器集成测试
%% -------------------------

process_scheduler_integration_test_() ->
    {timeout, 60, fun process_scheduler_integration/0}.

process_scheduler_integration() ->
    Opts = setup_test_env(),

    %% 创建 AOJS 进程
    Msg1 = test_aojs_process(Opts),

    %% 调度测试消息
    schedule_test_message(Msg1, <<"TEST TEXT 1">>, Opts),
    schedule_test_message(Msg1, <<"TEST TEXT 2">>, Opts),

    %% 获取调度器状态
    {ok, SchedulerRes} =
        hb_ao:resolve(Msg1, #{
            <<"method">> => <<"GET">>,
            <<"path">> => <<"schedule">>
        }, Opts),

    %% 验证消息已调度
    ?assertMatch(
        <<"TEST TEXT 1">>,
        hb_ao:get(<<"assignments/0/body/test-label">>, SchedulerRes, Opts)
    ),
    ?assertMatch(
        <<"TEST TEXT 2">>,
        hb_ao:get(<<"assignments/1/body/test-label">>, SchedulerRes, Opts)
    ),

    ok.

%% @doc setup_js_runtime/1 - 设置 JS 运行时环境
%% ===================== 作用 =====================
%% 创建一个可用于测试的 JavaScript 运行时环境。
%% 这是多个测试的共享设置函数。
%%
%% ===================== 返回值 =====================
%% {M1, Instance}
%% - M1: 初始化后的消息
%% - Instance: WASM 实例引用
%%
setup_js_runtime(Opts) ->
    #{<<"image">> := WASMImageID} = dev_wasm:cache_wasm_image("aojs/aojs.wasm", Opts),
    StackMsg = #{
        <<"device">> => <<"stack@1.0">>,
        <<"device-stack">> => [<<"wasm-64@1.0">>],
        <<"stack-keys">> => [<<"init">>, <<"compute">>],
        <<"image">> => WASMImageID
    },
    {ok, M1} = hb_ao:resolve(StackMsg, #{<<"path">> => <<"init">>}, Opts),
    {ok, _} = hb_ao:resolve(M1, #{
        <<"path">> => <<"compute">>,
        <<"body">> => #{<<"function">> => <<"qjs_init">>, <<"parameters">> => []}
    }, Opts),
    Instance = dev_wasm:instance(M1, #{}, Opts),
    {M1, Instance}.

%% -------------------------
%% JavaScript 基础求值测试
%% -------------------------

js_basic_eval_test_() ->
    {timeout, 60, fun js_basic_eval/0}.

js_basic_eval() ->
    Opts = setup_test_env(),
    {_M1, Instance} = setup_js_runtime(Opts),

    %% 测试简单算术
    {ok, Result1} = eval_js(Instance, <<"1 + 2">>, Opts),
    ?assertEqual(<<"3">>, Result1),

    %% 测试 JSON 序列化
    {ok, Result2} = eval_js(Instance, <<"JSON.stringify({a: 1, b: 2})">>, Opts),
    ?assertEqual(<<"{\"a\":1,\"b\":2}">>, Result2),
    ok.

%% -------------------------
%% Counter 模块测试
%% -------------------------

js_counter_module_test_() ->
    {timeout, 60, fun js_counter_module/0}.

js_counter_module() ->
    Opts = setup_test_env(),
    {_M1, Instance} = setup_js_runtime(Opts),

    %% 初始化状态和 Handlers
    {ok, _} = eval_js(Instance, <<"var state = {}; var Handlers = {_handlers: [], add: function(name, fn) { this._handlers.push({name: name, fn: fn}); }, call: function(name) { for(var i=0; i<this._handlers.length; i++) { if(this._handlers[i].name === name) return this._handlers[i].fn({}); } } };">>, Opts),

    %% 加载 counter 模块
    {ok, CounterCode} = file:read_file("aojs/aojs-modules/counter.js"),
    {ok, _} = eval_js(Instance, CounterCode, Opts),

    %% 测试 GetCount
    {ok, Count0} = eval_js(Instance, <<"JSON.stringify(Handlers.call('GetCount'))">>, Opts),
    ?assertEqual(<<"{\"count\":0}">>, Count0),

    %% 测试 Increment
    {ok, _} = eval_js(Instance, <<"Handlers.call('Increment')">>, Opts),
    {ok, Count2} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Increment'))">>, Opts),
    ?assertEqual(<<"{\"count\":2}">>, Count2),

    %% 测试 Decrement
    {ok, Count1} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Decrement'))">>, Opts),
    ?assertEqual(<<"{\"count\":1}">>, Count1),

    %% 测试 Reset
    {ok, Count0Again} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Reset'))">>, Opts),
    ?assertEqual(<<"{\"count\":0}">>, Count0Again),
    ok.

%% -------------------------
%% Token 模块测试
%% -------------------------

js_token_module_test_() ->
    {timeout, 60, fun js_token_module/0}.

js_token_module() ->
    Opts = setup_test_env(),
    {_M1, Instance} = setup_js_runtime(Opts),

    %% 初始化 state、Handlers 和 ao.send
    {ok, _} = eval_js(Instance, <<"var state = {}; var ao = {send: function(m) { ao._outbox.push(m); }, _outbox: []}; var Handlers = {_handlers: [], add: function(name, fn) { this._handlers.push({name: name, fn: fn}); }, call: function(name, msg) { for(var i=0; i<this._handlers.length; i++) { if(this._handlers[i].name === name) return this._handlers[i].fn(msg || {}); } } };">>, Opts),

    %% 加载 token 模块
    {ok, TokenCode} = file:read_file("aojs/aojs-modules/token.js"),
    {ok, _} = eval_js(Instance, TokenCode, Opts),

    %% 测试 Info
    {ok, Info} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Info'))">>, Opts),
    ?assertMatch(<<"{\"name\":\"TestToken\"", _/binary>>, Info),

    %% 测试初始余额
    {ok, Balance0} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Balance', {From: 'alice'}))">>, Opts),
    ?assertEqual(<<"{\"balance\":0}">>, Balance0),

    %% 测试 Mint
    {ok, MintResult} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Mint', {From: 'alice', Tags: {Quantity: '100'}}))">>, Opts),
    ?assertEqual(<<"{\"success\":true,\"balance\":100}">>, MintResult),

    %% 验证 Mint 后的余额
    {ok, Balance100} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Balance', {From: 'alice'}))">>, Opts),
    ?assertEqual(<<"{\"balance\":100}">>, Balance100),
    ok.

-endif. %% TEST
