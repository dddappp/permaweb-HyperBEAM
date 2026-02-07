%%% File: test_dev3.erl
-module(test_dev3).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").
 
%% Run with: rebar3 eunit --module=test_dev3
 
meta_info_test() ->
    Node = hb_http_server:start_node(#{
        test_config => <<"my_value">>
    }),
    {ok, Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    ?assertEqual(<<"my_value">>, hb_ao:get(<<"test_config">>, Info, #{})),
    ?debugFmt("Meta info: OK", []).
 
meta_build_test() ->
    Node = hb_http_server:start_node(#{}),
    {ok, NodeName} = hb_http:get(Node, <<"/~meta@1.0/build/node">>, #{}),
    ?assertEqual(<<"HyperBEAM">>, NodeName),
    ?debugFmt("Build info: OK", []).
 
router_routes_test() ->
    Routes = [
        #{<<"template">> => <<"/api/*">>, <<"node">> => <<"api-server">>},
        #{<<"template">> => <<"*">>, <<"node">> => <<"fallback">>}
    ],
    
    %% Match API route
    {ok, _} = dev_router:route(
        #{<<"path">> => <<"/api/users">>},
        #{routes => Routes}
    ),
    ?debugFmt("Router match: OK", []).
 
relay_call_test() ->
    Peer = hb_http_server:start_node(#{priv_wallet => ar_wallet:new()}),
    
    {ok, Res} = hb_ao:resolve(
        #{
            <<"device">> => <<"relay@1.0">>,
            <<"method">> => <<"GET">>,
            <<"path">> => <<"/~meta@1.0/build/node">>,
            <<"peer">> => Peer
        },
        <<"call">>,
        #{}
    ),
    ?debugFmt("Relay call: OK", []).
 
relay_cast_test() ->
    Peer = hb_http_server:start_node(#{priv_wallet => ar_wallet:new()}),
    
    Start = erlang:monotonic_time(millisecond),
    {ok, <<"OK">>} = hb_ao:resolve(
        #{
            <<"device">> => <<"relay@1.0">>,
            <<"method">> => <<"GET">>,
            <<"path">> => <<"/~meta@1.0/info">>,
            <<"peer">> => Peer
        },
        <<"cast">>,
        #{}
    ),
    Duration = erlang:monotonic_time(millisecond) - Start,
    ?assert(Duration < 100),  %% Cast returns immediately
    ?debugFmt("Relay cast: ~pms", [Duration]).
 
hook_pipeline_test() ->
    Handler1 = #{
        <<"device">> => #{
            <<"test">> => fun(_, Req, _) -> 
                {ok, Req#{<<"h1">> => true}} 
            end
        }
    },
    Handler2 = #{
        <<"device">> => #{
            <<"test">> => fun(_, Req, _) -> 
                {ok, Req#{<<"h2">> => true}} 
            end
        }
    },
    
    Opts = #{on => #{<<"test">> => [Handler1, Handler2]}},
    {ok, Result} = dev_hook:on(<<"test">>, #{<<"input">> => true}, Opts),
    
    ?assertEqual(true, maps:get(<<"h1">>, Result)),
    ?assertEqual(true, maps:get(<<"h2">>, Result)),
    ?debugFmt("Hook pipeline: OK", []).
 
hook_error_halt_test() ->
    Handler1 = #{
        <<"device">> => #{
            <<"test">> => fun(_, Req, _) -> {ok, Req#{<<"h1">> => true}} end
        }
    },
    Handler2 = #{
        <<"device">> => #{
            <<"test">> => fun(_, _, _) -> {error, <<"Halted">>} end
        }
    },
    Handler3 = #{
        <<"device">> => #{
            <<"test">> => fun(_, Req, _) -> {ok, Req#{<<"h3">> => true}} end
        }
    },
    
    Opts = #{on => #{<<"test">> => [Handler1, Handler2, Handler3]}},
    {error, <<"Halted">>} = dev_hook:on(<<"test">>, #{}, Opts),
    ?debugFmt("Hook error halt: OK", []).
 
complete_infrastructure_test() ->
    ?debugFmt("=== Complete Infrastructure Test ===", []),
    
    %% 1. Start node with hooks
    Parent = self(),
    RequestHook = #{
        <<"device">> => #{
            <<"request">> => fun(_, Req, _) ->
                Parent ! {hook, request},
                {ok, Req}
            end
        }
    },
    
    Node = hb_http_server:start_node(#{
        priv_wallet => ar_wallet:new(),
        on => #{<<"request">> => RequestHook}
    }),
    ?debugFmt("1. Started node with hooks", []),
    
    %% 2. Get node info
    {ok, _Info} = hb_http:get(Node, <<"/~meta@1.0/info">>, #{}),
    ?debugFmt("2. Retrieved node info", []),
    
    %% 3. Verify hook executed
    receive
        {hook, request} -> 
            ?debugFmt("3. Request hook executed", [])
    after 100 -> 
        error(hook_timeout)
    end,
    
    %% 4. Get build info
    {ok, <<"HyperBEAM">>} = hb_http:get(Node, <<"/~meta@1.0/build/node">>, #{}),
    ?debugFmt("4. Build info retrieved", []),
    
    ?debugFmt("=== All tests passed! ===", []).