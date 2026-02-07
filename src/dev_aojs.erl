%%%-------------------------------------------------------------------
%%% @doc JavaScript Smart Contract Runtime Device
%%%
%%% Executes JavaScript smart contracts using QuickJS compiled to WASM.
%%% This device interfaces with hb_beamr to run JavaScript code in a
%%% sandboxed WebAssembly environment.
%%%
%%% API:
%%%   init/3     - Initialize the runtime
%%%   compute/3  - Execute a handler for a message
%%%   snapshot/3 - Save runtime state
%%%   normalize/3 - Restore runtime state
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(dev_aojs).
-export([info/3, init/3, compute/3, snapshot/3, normalize/3]).
-export([load_js_module/2]).
 
-include("include/hb.hrl").
 
-define(RESULT_BUF_SIZE, 65536).

%%% ============================================================
%%% Device Info
%%% ============================================================
 
info(_M1, _M2, _Opts) ->
    {ok, #{
        <<"name">> => <<"aojs@1.0">>,
        <<"description">> => <<"JavaScript Smart Contract Runtime">>,
        <<"exports">> => [<<"init">>, <<"compute">>, <<"snapshot">>, <<"normalize">>]
    }}.

%%% ============================================================
%%% Initialize
%%% ============================================================
 
init(M1, _M2, Opts) ->
    Prefix = dev_stack:prefix(M1, #{}, Opts),
 
    %% Check if already initialized
    case hb_private:get(prefixed_key(Prefix, <<"initialized">>), M1, not_found, Opts) of
        true ->
            {ok, M1};
        _ ->
            do_init(M1, Prefix, Opts)
    end.

prefixed_key(<<>>, Key) -> Key;
prefixed_key(Prefix, Key) -> <<Prefix/binary, "/", Key/binary>>.

do_init(M1, Prefix, Opts) ->
    %% Get WASM instance (created by dev_wasm below us in the stack)
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),
 
    case Instance of
        not_found ->
            {error, #{<<"error">> => <<"wasm_instance_not_found">>}};
        _ ->
            {ok, hb_private:set(M1, prefixed_key(Prefix, <<"ready">>), true, Opts)}
    end.

%%% ============================================================
%%% Load JavaScript Module
%%% ============================================================
 
load_js_module(M1, Opts) ->
    Prefix = dev_stack:prefix(M1, #{}, Opts),
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),
 
    %% Inject AO runtime if needed
    case needs_runtime_injection(M1, Instance, Opts) of
        true ->
            inject_ao_runtime(Instance, Opts);
        false ->
            ok
    end,
 
    %% Get and load the JavaScript module source
    case find_module_source(M1, Opts) of
        not_found ->
            {ok, M1};
        Source when is_binary(Source) ->
            case eval_js(Instance, Source, Opts) of
                {ok, _} -> {ok, M1};
                {error, Error} -> {error, #{<<"error">> => Error}}
            end
    end.
 
needs_runtime_injection(_M1, Instance, Opts) ->
    case eval_js(Instance, <<"typeof Handlers">>, Opts) of
        {ok, <<"object">>} -> false;
        _ -> true
    end.
 
inject_ao_runtime(Instance, Opts) ->
    Runtime = ao_runtime_js(),
    eval_js(Instance, Runtime, Opts).
 
ao_runtime_js() ->
    %% Read from aojs/ao-runtime.js
    {ok, Content} = file:read_file("aojs/ao-runtime.js"),
    Content.
 
find_module_source(M1, Opts) ->
    %% Check for module in message or load from file
    case hb_maps:get(<<"aojs-module">>, M1, not_found, Opts) of
        not_found ->
            case hb_maps:get(<<"module-id">>, M1, not_found, Opts) of
                not_found -> not_found;
                ModuleId ->
                    Path = <<"aojs/aojs-modules/", ModuleId/binary, ".js">>,
                    case file:read_file(Path) of
                        {ok, Content} -> Content;
                        _ -> not_found
                    end
            end;
        Source ->
            Source
    end.

%%% ============================================================
%%% Compute - Handle Messages
%%% ============================================================
 
compute(M1, M2, Opts) ->
    %% Ensure module is loaded
    {ok, M1Loaded} = load_js_module(M1, Opts),
    execute_handler(M1Loaded, M2, Opts).
 
execute_handler(M1, M2, Opts) ->
    Prefix = dev_stack:prefix(M1, M2, Opts),
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),
 
    %% Get message and process info
    Message = hb_maps:get(<<"body">>, M2, #{}, Opts),
    Process = hb_maps:get(<<"process">>, M1, #{}, Opts),
 
    %% Build JSON for JavaScript
    MsgJson = build_msg_json(Message, M2, Opts),
    EnvJson = build_env_json(Process, Opts),
 
    %% Execute handler
    JsCode = iolist_to_binary([
        <<"_clearOutbox();globalThis.msg=">>, MsgJson,
        <<";globalThis.env=">>, EnvJson,
        <<";JSON.stringify(Handlers.handle(msg))">>
    ]),
 
    case eval_js(Instance, JsCode, Opts) of
        {ok, ResultJson} ->
            OutboxJson = read_outbox(Instance, Opts),
            process_results(M1, ResultJson, OutboxJson, Opts);
        {error, Error} ->
            {error, #{<<"error">> => Error}}
    end.

build_msg_json(Message, M2, Opts) ->
    Id = hb_maps:get(<<"id">>, Message, <<>>, Opts),
    From = hb_maps:get(<<"from-process">>, Message, <<>>, Opts),
    Action = hb_maps:get(<<"action">>, Message, <<"default">>, Opts),
    Data = hb_maps:get(<<"data">>, Message, <<>>, Opts),
    BlockHeight = hb_maps:get(<<"block-height">>, M2, 0, Opts),
 
    MsgMap = #{
        <<"Id">> => Id,
        <<"From">> => From,
        <<"Action">> => Action,
        <<"Data">> => Data,
        <<"Tags">> => build_tags(Message, Opts),
        <<"Block-Height">> => BlockHeight
    },
    hb_json:encode(MsgMap).
 
build_env_json(Process, Opts) ->
    ProcId = hb_maps:get(<<"id">>, Process, <<>>, Opts),
    EnvMap = #{
        <<"Process">> => #{<<"Id">> => ProcId}
    },
    hb_json:encode(EnvMap).
 
build_tags(Message, _Opts) when is_map(Message) ->
    ExcludeKeys = [<<"id">>, <<"from">>, <<"action">>, <<"data">>, <<"priv">>],
    maps:fold(fun(Key, Value, Acc) ->
        case lists:member(hb_ao:normalize_key(Key), ExcludeKeys) of
            true -> Acc;
            false when is_binary(Value); is_integer(Value) ->
                Acc#{Key => Value};
            false -> Acc
        end
    end, #{}, Message);
build_tags(_, _) -> #{}.

%%% ============================================================
%%% JavaScript Evaluation (WASM Interface)
%%% ============================================================
 
eval_js(Instance, Code, _Opts) ->
    %% Write code to WASM memory
    case hb_beamr_io:write_string(Instance, Code) of
        {ok, CodePtr} ->
            CodeLen = byte_size(Code),
            %% Allocate result buffer
            case hb_beamr_io:malloc(Instance, ?RESULT_BUF_SIZE) of
                {ok, ResultPtr} ->
                    %% Call qjs_eval(code, len, out, out_size)
                    Result = hb_beamr:call(Instance, "qjs_eval",
                        [CodePtr, CodeLen, ResultPtr, ?RESULT_BUF_SIZE]),
 
                    EvalResult = case Result of
                        {ok, [Length]} when Length >= 0 ->
                            {ok, ResultBin} = hb_beamr_io:read(Instance, ResultPtr, max(1, Length)),
                            {ok, ResultBin};
                        {ok, [Length]} when Length < 0 ->
                            {ok, ErrorBin} = hb_beamr_io:read_string(Instance, ResultPtr),
                            {error, ErrorBin};
                        {error, E} ->
                            {error, E}
                    end,
 
                    %% Free memory
                    hb_beamr_io:free(Instance, CodePtr),
                    hb_beamr_io:free(Instance, ResultPtr),
                    EvalResult;
                {error, E} ->
                    hb_beamr_io:free(Instance, CodePtr),
                    {error, E}
            end;
        {error, E} ->
            {error, E}
    end.
 
read_outbox(Instance, Opts) ->
    case eval_js(Instance, <<"_getOutbox()">>, Opts) of
        {ok, OutboxJson} -> OutboxJson;
        _ -> <<"[]">>
    end.
 
process_results(M1, ResultJson, OutboxJson, _Opts) ->
    Result = hb_json:decode(ResultJson),
    Outbox = hb_json:decode(OutboxJson),
    {ok, M1#{
        <<"results">> => #{
            <<"data">> => Result,
            <<"outbox">> => Outbox
        }
    }}.

%%% ============================================================
%%% Snapshot and Normalize (State Persistence)
%%% ============================================================
 
snapshot(M1, _M2, Opts) ->
    Prefix = dev_stack:prefix(M1, #{}, Opts),
    Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),
    case Instance of
        not_found ->
            {error, <<"no_wasm_instance">>};
        _ ->
            case hb_beamr:serialize(Instance) of
                {ok, Snapshot} -> {ok, M1#{<<"snapshot">> => Snapshot}};
                {error, E} -> {error, E}
            end
    end.

normalize(M1, _M2, Opts) ->
    case hb_maps:get(<<"snapshot">>, M1, not_found, Opts) of
        not_found ->
            {ok, M1};
        Snapshot ->
            Prefix = dev_stack:prefix(M1, #{}, Opts),
            Instance = hb_private:get(prefixed_key(Prefix, <<"instance">>), M1, not_found, Opts),
            case hb_beamr:deserialize(Instance, Snapshot) of
                ok -> {ok, maps:remove(<<"snapshot">>, M1)};
                {error, E} -> {error, E}
            end
    end.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
 
%% Test helper - start environment
start() ->
    application:ensure_all_started(hb),
    <<I1:32, I2:32, I3:32>> = crypto:strong_rand_bytes(12),
    rand:seed(exsplus, {I1, I2, I3}),
    ok.
 
%% Test helper - setup store
setup_test_env() ->
    start(),
    Store = hb_test_utils:test_store(hb_store_fs),
    #{store => [Store]}.

%% Test device info via hb_ao:resolve with {as, dev_aojs, Msg}
info_test() ->
    start(),
    %% Use {as, dev_aojs, Msg} to resolve without device registration
    {ok, Info} = hb_ao:resolve(
        {as, dev_aojs, #{}},
        #{<<"path">> => <<"info">>},
        #{}
    ),
    ?assertEqual(<<"aojs@1.0">>, maps:get(<<"name">>, Info)),
    ?assertEqual(<<"JavaScript Smart Contract Runtime">>, maps:get(<<"description">>, Info)).

%% Test WASM-based AOJS device stack initialization
aojs_wasm_init_test_() ->
    {timeout, 60, fun aojs_wasm_init/0}.
 
aojs_wasm_init() ->
    Opts = setup_test_env(),
 
    %% Cache the WASM image
    #{<<"image">> := WASMImageID} = dev_wasm:cache_wasm_image("aojs/aojs.wasm", Opts),
 
    %% Create a device stack: wasm-64 at the bottom
    StackMsg = #{
        <<"device">> => <<"stack@1.0">>,
        <<"device-stack">> => [<<"wasm-64@1.0">>],
        <<"stack-keys">> => [<<"init">>, <<"compute">>],
        <<"image">> => WASMImageID
    },
 
    %% Initialize the stack - this loads the WASM
    {ok, M1} = hb_ao:resolve(StackMsg, #{<<"path">> => <<"init">>}, Opts),
 
    %% Verify we got a valid message back
    ?assertMatch(#{}, M1),
 
    %% Try calling qjs_init via compute
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
 
    %% qjs_init returns 0 on success
    Output = hb_ao:get(<<"results/output">>, InitResult, Opts),
    ?assertEqual([0], Output), 

    ok.

%% Helper to create AOJS process with WASM
test_aojs_process(Opts) ->
    Wallet = hb_opts:get(priv_wallet, hb:wallet(), Opts),
    Address = hb_util:human_id(ar_wallet:to_address(Wallet)),
    #{<<"image">> := WASMImageID} = dev_wasm:cache_wasm_image("aojs/aojs.wasm", Opts),
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
 
%% Test process message creation
process_msg_creation_test_() ->
    {timeout, 60, fun process_msg_creation/0}.
 
process_msg_creation() ->
    start(),
    Opts = #{
        priv_wallet => hb:wallet(),
        store => hb_opts:get(store)
    },
 
    %% Create aojs process message
    Msg1 = test_aojs_process(Opts),
 
    %% Verify message structure
    ?assertEqual(<<"process@1.0">>, maps:get(<<"device">>, Msg1)),
    ?assertEqual(<<"stack@1.0">>, maps:get(<<"execution-device">>, Msg1)),
    ?assertEqual(<<"scheduler@1.0">>, maps:get(<<"scheduler-device">>, Msg1)),
    ?assertEqual(<<"Process">>, maps:get(<<"type">>, Msg1)),
 
    %% Verify WASM image is set
    ?assertMatch(<<_/binary>>, maps:get(<<"image">>, Msg1)),
 
    ok.

%% Helper to schedule a test message to a process
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
 
%% Test full process lifecycle with scheduler
process_scheduler_integration_test_() ->
    {timeout, 60, fun process_scheduler_integration/0}.
 
process_scheduler_integration() ->
    Opts = setup_test_env(),
 
    %% Create AOJS process
    Msg1 = test_aojs_process(Opts),
 
    %% Schedule test messages
    schedule_test_message(Msg1, <<"TEST TEXT 1">>, Opts),
    schedule_test_message(Msg1, <<"TEST TEXT 2">>, Opts),
 
    %% Get scheduler status to verify messages are scheduled
    {ok, SchedulerRes} =
        hb_ao:resolve(Msg1, #{
            <<"method">> => <<"GET">>,
            <<"path">> => <<"schedule">>
        }, Opts),
 
    %% Verify test messages are scheduled (slot 0 and 1)
    ?assertMatch(
        <<"TEST TEXT 1">>,
        hb_ao:get(<<"assignments/0/body/test-label">>, SchedulerRes, Opts)
    ),
    ?assertMatch(
        <<"TEST TEXT 2">>,
        hb_ao:get(<<"assignments/1/body/test-label">>, SchedulerRes, Opts)
    ),
 
    ok.

%% Helper to setup WASM stack and get instance for JS testing
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
 
%% Test basic JavaScript evaluation
js_basic_eval_test_() ->
    {timeout, 60, fun js_basic_eval/0}.
 
js_basic_eval() ->
    Opts = setup_test_env(),
    {_M1, Instance} = setup_js_runtime(Opts),
 
    %% Test simple arithmetic
    {ok, Result1} = eval_js(Instance, <<"1 + 2">>, Opts),
    ?assertEqual(<<"3">>, Result1),
 
    %% Test JSON.stringify
    {ok, Result2} = eval_js(Instance, <<"JSON.stringify({a: 1, b: 2})">>, Opts),
    ?assertEqual(<<"{\"a\":1,\"b\":2}">>, Result2),
    ok.
 
%% Test counter.js module
js_counter_module_test_() ->
    {timeout, 60, fun js_counter_module/0}.
 
js_counter_module() ->
    Opts = setup_test_env(),
    {_M1, Instance} = setup_js_runtime(Opts),
 
    %% Initialize state and Handlers
    {ok, _} = eval_js(Instance, <<"var state = {}; var Handlers = {_handlers: [], add: function(name, fn) { this._handlers.push({name: name, fn: fn}); }, call: function(name) { for(var i=0; i<this._handlers.length; i++) { if(this._handlers[i].name === name) return this._handlers[i].fn({}); } } };">>, Opts),
 
    %% Load counter module
    {ok, CounterCode} = file:read_file("aojs/aojs-modules/counter.js"),
    {ok, _} = eval_js(Instance, CounterCode, Opts),
 
    %% Test GetCount (should be 0 initially)
    {ok, Count0} = eval_js(Instance, <<"JSON.stringify(Handlers.call('GetCount'))">>, Opts),
    ?assertEqual(<<"{\"count\":0}">>, Count0),
 
    %% Test Increment twice
    {ok, _} = eval_js(Instance, <<"Handlers.call('Increment')">>, Opts),
    {ok, Count2} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Increment'))">>, Opts),
    ?assertEqual(<<"{\"count\":2}">>, Count2),
 
    %% Test Decrement
    {ok, Count1} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Decrement'))">>, Opts),
    ?assertEqual(<<"{\"count\":1}">>, Count1),
 
    %% Test Reset
    {ok, Count0Again} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Reset'))">>, Opts),
    ?assertEqual(<<"{\"count\":0}">>, Count0Again),
    ok.
 
%% Test token.js module
js_token_module_test_() ->
    {timeout, 60, fun js_token_module/0}.
 
js_token_module() ->
    Opts = setup_test_env(),
    {_M1, Instance} = setup_js_runtime(Opts),
 
    %% Initialize state, Handlers, and ao.send
    {ok, _} = eval_js(Instance, <<"var state = {}; var ao = {send: function(m) { ao._outbox.push(m); }, _outbox: []}; var Handlers = {_handlers: [], add: function(name, fn) { this._handlers.push({name: name, fn: fn}); }, call: function(name, msg) { for(var i=0; i<this._handlers.length; i++) { if(this._handlers[i].name === name) return this._handlers[i].fn(msg || {}); } } };">>, Opts),
 
    %% Load token module
    {ok, TokenCode} = file:read_file("aojs/aojs-modules/token.js"),
    {ok, _} = eval_js(Instance, TokenCode, Opts),
 
    %% Test Info
    {ok, Info} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Info'))">>, Opts),
    ?assertMatch(<<"{\"name\":\"TestToken\"", _/binary>>, Info),
 
    %% Test initial Balance (should be 0)
    {ok, Balance0} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Balance', {From: 'alice'}))">>, Opts),
    ?assertEqual(<<"{\"balance\":0}">>, Balance0),
 
    %% Test Mint
    {ok, MintResult} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Mint', {From: 'alice', Tags: {Quantity: '100'}}))">>, Opts),
    ?assertEqual(<<"{\"success\":true,\"balance\":100}">>, MintResult),
 
    %% Verify balance after mint
    {ok, Balance100} = eval_js(Instance, <<"JSON.stringify(Handlers.call('Balance', {From: 'alice'}))">>, Opts),
    ?assertEqual(<<"{\"balance\":100}">>, Balance100),
    ok.
 
-endif. %% TEST
