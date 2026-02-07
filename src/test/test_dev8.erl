%%% @doc test_dev8：HyperBEAM认证系统测试模块
%%%
%%% 本模块测试HyperBEAM的多种认证机制，包括：
%%% - HTTP Basic认证——基于Authorization头的认证
%%% - Cookie认证——基于Cookie的会话认证
%%% - Secret管理——密钥的生成、导入、导出和列表
%%%
%%% 认证架构：
%%% - HTTP Auth适用于API和HTTP请求认证
%%% - Cookie Auth适用于Web应用的会话管理
%%% - Secret模块提供密钥的安全管理功能
%%%
%%% 运行方式：rebar3 eunit --module=test_dev8
-module(test_dev8).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% ============================================================
%% Auth Hook导出测试
%% ============================================================
%% @doc 测试用例：认证钩子模块导出
%%%
%%% 本测试验证认证钩子模块的导出函数：
%%% - request函数处理认证请求
%%%
%%% 认证钩子作用：
%%% - 在请求处理流程中插入认证检查
%%% - 支持多种认证方式的统一接口
auth_hook_exports_test() ->
    code:ensure_loaded(dev_auth_hook),
    %% 确保认证钩子模块已加载
    %% code:ensure_loaded/1尝试加载模块到运行时

    ?assert(erlang:function_exported(dev_auth_hook, request, 3)),
    %% 验证request/3函数已导出
    %% 参数：Msg1, Msg2, Opts
    %% 返回认证处理结果

    ?debugFmt("Auth hook exports: OK", []).
    %% 输出调试信息

%% ============================================================
%% HTTP认证生成测试
%% ============================================================
%% @doc 测试用例：HTTP Basic认证密钥生成
%%%
%%% 本测试验证HTTP Basic认证的密钥生成：
%%% 1. 创建Base64编码的凭据
%%% 2. 构建Authorization头
%%% 3. 生成认证密钥
%%% 4. 验证密钥有效
%%%
%%% HTTP Basic认证流程：
%%% - 用户名密码组合后Base64编码
%%% - 添加"Basic "前缀形成Authorization头
%%% - 服务器解码并验证凭据
http_auth_generate_test() ->
    Credentials = base64:encode(<<"user:password">>),
    %% 创建凭据字符串
    %% base64:encode/1将二进制转为Base64编码
    %% "user:password"是标准凭据格式

    Req = #{<<"authorization">> => <<"Basic ", Credentials/binary>>},
    %% 构建Authorization请求头
    %% HTTP Basic格式："Basic " + Base64编码凭据

    {ok, Key} = dev_codec_http_auth:generate(#{}, Req, #{}),
    %% 生成认证密钥
    %% dev_codec_http_auth:generate/3参数：
    %%   第一个参数：Msg1（空）
    %%   第二个参数：包含authorization的请求
    %%   第三个参数：选项（空）
    %% 返回值：{ok, Key}，Key是生成的认证密钥

    ?assert(is_binary(Key)),
    %% 验证密钥是二进制类型

    ?assert(byte_size(Key) > 0),
    %% 验证密钥长度大于0

    ?debugFmt("HTTP auth generate: OK (key size ~p)", [byte_size(Key)]).
    %% 输出密钥长度调试信息

%% ============================================================
%% HTTP认证无头测试
%% ============================================================
%% @doc 测试用例：HTTP认证缺失头处理
%%%
%%% 本测试验证HTTP认证对缺失认证头的处理：
%%% 1. 发送不含Authorization头的请求
%%% 2. 验证返回401未授权错误
%%% 3. 验证WWW-Authenticate头正确设置
%%%
%%% 错误响应规范：
%%% - 状态码401表示需要认证
%%% - WWW-Authenticate头指示认证类型
http_auth_no_header_test() ->
    Result = dev_codec_http_auth:generate(#{}, #{}, #{}),
    %% 发送无认证头的请求
    %% Msg1、Msg2、Optes均为空

    ?assertMatch(
        {error, #{<<"status">> := 401, <<"www-authenticate">> := <<"Basic">>}},
        Result
    ),
    %% 验证返回错误格式
    %% status: 401 HTTP状态码
    %% www-authenticate: "Basic"指示Basic认证方式

    ?debugFmt("HTTP auth 401: OK", []).
    %% 输出调试信息

%% ============================================================
%% HTTP认证提交测试
%% ============================================================
%% @doc 测试用例：HTTP认证消息提交
%%%
%%% 本测试验证HTTP认证的消息签名功能：
%%% 1. 创建凭据和请求头
%%% 2. 准备待签名消息
%%% 3. 提交消息进行签名
%%% 4. 验证签名承诺生成
%%%
%%% 签名机制：
%%% - 消息包含 commitments 字段
%%% - commitments 包含认证信息和签名数据
http_auth_commit_test() ->
    Credentials = base64:encode(<<"user:password">>),
    %% 创建Base64编码凭据

    Base = #{<<"data">> => <<"test message">>},
    %% 创建待签名消息

    Req = #{<<"authorization">> => <<"Basic ", Credentials/binary>>},
    %% 构建认证请求头

    {ok, Signed} = dev_codec_http_auth:commit(Base, Req, #{}),
    %% 提交消息进行签名
    %% dev_codec_http_auth:commit/3参数：
    %%   第一个参数：待签名消息
    %%   第二个参数：认证请求
    %%   第三个参数：选项
    %% 返回值：{ok, Signed}，Signed是签名后的消息

    ?assert(maps:is_key(<<"commitments">>, Signed)),
    %% 验证签名结果包含 commitments 字段
    %% commitments 包含签名承诺信息

    ?debugFmt("HTTP auth commit: OK", []).
    %% 输出调试信息

%% ============================================================
%% Cookie认证提交测试
%% ============================================================
%% @doc 测试用例：Cookie认证消息提交
%%%
%%% 本测试验证Cookie认证的消息签名功能：
%%% 1. 创建待签名消息
%%% 2. 提交消息进行Cookie签名
%%% 3. 验证签名承诺生成
%%% 4. 验证承诺数量正确
%%%
%%% Cookie签名特点：
%%% - 使用会话密钥进行签名
%%% - 支持密钥轮换
cookie_auth_commit_test() ->
    Base = #{<<"data">> => <<"test">>},
    %% 创建待签名消息

    {ok, Signed} = dev_codec_cookie_auth:commit(Base, #{}, #{}),
    %% 提交Cookie认证签名
    %% dev_codec_cookie_auth:commit/3参数：
    %%   第一个参数：待签名消息
    %%   第二个参数：请求配置（空）
    %%   第三个参数：选项配置（空）
    %% 返回值：{ok, Signed}，签名后的消息

    ?assert(maps:is_key(<<"commitments">>, Signed)),
    %% 验证包含签名承诺

    Commitments = maps:get(<<"commitments">>, Signed),
    %% 提取签名承诺映射

    ?assertEqual(1, map_size(Commitments)),
    %% 验证只有一个签名承诺
    %% map_size/1返回映射中键值对数量

    ?debugFmt("Cookie auth commit: OK", []).
    %% 输出调试信息

%% ============================================================
%% Cookie认证生成测试
%% ============================================================
%% @doc 测试用例：Cookie认证密钥生成
%%%
%%% 本测试验证Cookie认证的密钥生成：
%%% 1. 调用密钥生成接口
%%% 2. 验证返回secret字段
%%% 3. 验证secret格式正确
%%%
%%% Secret格式：
%%% - secret字段包含密钥列表
%%% - 支持多个密钥用于密钥轮换
cookie_auth_generate_test() ->
    {ok, Result} = dev_codec_cookie_auth:generate(#{}, #{}, #{}),
    %% 生成Cookie认证密钥
    %% 所有参数为空

    ?assert(maps:is_key(<<"secret">>, Result)),
    %% 验证结果包含secret字段

    Secrets = maps:get(<<"secret">>, Result),
    %% 提取密钥列表

    ?assert(is_list(Secrets)),
    %% 验证secret是列表类型

    ?assertEqual(1, length(Secrets)),
    %% 验证列表长度为1
    %% 初始生成一个密钥

    ?debugFmt("Cookie auth generate: OK", []).
    %% 输出调试信息

%% ============================================================
%% Cookie解析测试
%% ============================================================
%% @doc 测试用例：Cookie字符串解析
%%%
%%% 本测试验证Cookie字符串的解析功能：
%%% 1. 创建原始Cookie字符串
%%% 2. 调用解析接口
%%% 3. 验证键值对正确提取
%%%
%%% Cookie格式：
%%% - 键值对使用分号分隔
%%% - 键值之间使用等号连接
cookie_parse_test() ->
    Msg = #{<<"cookie">> => <<"key1=value1; key2=value2">>},
    %% 创建Cookie字符串消息
    %% 格式："key1=value1; key2=value2"

    {ok, Cookies} = dev_codec_cookie:extract(Msg, #{}, #{}),
    %% 解析Cookie字符串
    %% dev_codec_cookie:extract/3参数：
    %%   第一个参数：包含cookie字段的消息
    %%   第二个参数：请求配置（空）
    %%   第三个参数：选项配置（空）
    %% 返回值：{ok, Cookies}，Cookies是解析后的映射

    ?assertEqual(<<"value1">>, maps:get(<<"key1">>, Cookies)),
    %% 验证key1的值正确

    ?assertEqual(<<"value2">>, maps:get(<<"key2">>, Cookies)),
    %% 验证key2的值正确

    ?debugFmt("Cookie parse: OK", []).
    %% 输出调试信息

%% ============================================================
%% Cookie存储测试
%% ============================================================
%% @doc 测试用例：Cookie存储功能
%%%
%%% 本测试验证Cookie的存储和提取：
%%% 1. 创建基础消息和请求
%%% 2. 存储Cookie数据
%%% 3. 提取并验证Cookie内容
%%%
%%% 存储机制：
%%% - store函数将数据存储到Cookie
%%% - extract函数从Cookie提取数据
cookie_store_test() ->
    Base = #{},
    %% 创建基础消息

    Req = #{
        <<"session">> => <<"abc123">>,
        <<"user">> => <<"john">>
    },
    %% 创建存储请求
    %% 包含session和user数据

    {ok, Updated} = dev_codec_cookie:store(Base, Req, #{}),
    %% 存储Cookie数据
    %% dev_codec_cookie:store/3参数：
    %%   第一个参数：基础消息
    %%   第二个参数：包含要存储数据的请求
    %%   第三个参数：选项配置
    %% 返回值：{ok, Updated}，Updated是更新后的消息

    {ok, Cookies} = dev_codec_cookie:extract(Updated, #{}, #{}),
    %% 提取存储的Cookie

    ?assertEqual(<<"abc123">>, maps:get(<<"session">>, Cookies)),
    %% 验证session值正确

    ?assertEqual(<<"john">>, maps:get(<<"user">>, Cookies)),
    %% 验证user值正确

    ?debugFmt("Cookie store: OK", []).
    %% 输出调试信息

%% ============================================================
%% Cookie获取测试
%% ============================================================
%% @doc 测试用例：Cookie获取功能
%%%
%%% 本测试验证Cookie的按字段获取：
%%% 1. 创建包含Cookie的消息
%%% 2. 设置Cookie字段
%%% 3. 获取指定Cookie值
%%%
%%% 获取机制：
%%% - get_cookie函数提取特定Cookie值
%%% - 简化单一字段的获取操作
cookie_get_test() ->
    Opts = hb_private:opts(#{}),
    %% 获取私有选项
    %% hb_private:opts/1从空映射创建默认选项

    Base = hb_private:set(#{}, <<"cookie">>, #{
        <<"session">> => <<"abc123">>
    }, Opts),
    %% 设置Cookie字段
    %% hb_private:set/4参数：
    %%   第一个参数：基础消息
    %%   第二个参数：字段名
    %%   第三个参数：字段值
    %%   第四个参数：选项
    %% 返回更新后的消息

    Req = #{<<"key">> => <<"session">>},
    %% 创建获取请求
    %% 指定要获取的Cookie键

    {ok, Cookie} = dev_codec_cookie:get_cookie(Base, Req, #{}),
    %% 获取指定Cookie值
    %% dev_codec_cookie:get_cookie/3参数：
    %%   第一个参数：包含Cookie的消息
    %%   第二个参数：获取请求
    %%   第三个参数：选项配置
    %% 返回值：{ok, Cookie}，Cookie是获取的值

    ?assertEqual(<<"abc123">>, Cookie),
    %% 验证获取的Cookie值正确

    ?debugFmt("Cookie get: OK", []).
    %% 输出调试信息

%% ============================================================
%% Secret模块导出测试
%% ============================================================
%% @doc 测试用例：Secret模块接口验证
%%%
%%% 本测试验证Secret管理模块的导出函数：
%%% - generate：生成新密钥
%%% - import：导入外部密钥
%%% - list：列出所有密钥
%%% - commit：提交密钥承诺
%%% - export：导出密钥
%%%
%%% Secret管理功能：
%%% - 提供密钥的全生命周期管理
%%% - 支持安全的密钥存储和传输
secret_exports_test() ->
    code:ensure_loaded(dev_secret),
    %% 确保Secret模块已加载

    ?assert(erlang:function_exported(dev_secret, generate, 3)),
    %% 验证generate/3函数已导出
    %% 生成新密钥

    ?assert(erlang:function_exported(dev_secret, import, 3)),
    %% 验证import/3函数已导出
    %% 导入外部密钥

    ?assert(erlang:function_exported(dev_secret, list, 3)),
    %% 验证list/3函数已导出
    %% 列出所有密钥

    ?assert(erlang:function_exported(dev_secret, commit, 3)),
    %% 验证commit/3函数已导出
    %% 提交密钥承诺

    ?assert(erlang:function_exported(dev_secret, export, 3)),
    %% 验证export/3函数已导出
    %% 导出密钥

    ?debugFmt("Secret device exports: OK", []).
    %% 输出调试信息

%% ============================================================
%% 完整认证工作流测试
%% ============================================================
%% @doc 测试用例：完整认证工作流
%%%
%%% 本测试验证多种认证机制的完整工作流程：
%%% 1. HTTP Basic认证密钥生成
%%% 2. HTTP认证消息签名
%%% 3. Cookie认证消息签名
%%% 4. Cookie提取和密钥重用
%%%
%%% 此测试模拟典型的多认证场景：
%%% - 用户使用HTTP Basic认证
%%% - 系统生成认证密钥
%%% - 用户使用Cookie认证
%%% - 系统提取并重用密钥
complete_auth_workflow_test() ->
    ?debugFmt("=== Complete Auth Workflow ===", []),
    %% 输出工作流开始标记

    %% 1. HTTP Basic认证流程
    Credentials = base64:encode(<<"alice:secret123">>),
    %% 创建Base64编码凭据

    AuthReq = #{<<"authorization">> => <<"Basic ", Credentials/binary>>},
    %% 构建Authorization请求头

    {ok, Key} = dev_codec_http_auth:generate(#{}, AuthReq, #{}),
    %% 生成HTTP认证密钥

    ?assert(is_binary(Key)),
    %% 验证密钥是二进制类型

    ?debugFmt("1. HTTP auth key derived", []),
    %% 输出调试信息

    %% 2. 使用HTTP认证签名消息
    Message = #{<<"action">> => <<"transfer">>, <<"amount">> => 100},
    %% 创建交易消息

    {ok, SignedHttp} = dev_codec_http_auth:commit(Message, AuthReq, #{}),
    %% 使用HTTP认证签名消息

    ?assert(maps:is_key(<<"commitments">>, SignedHttp)),
    %% 验证签名结果包含承诺

    ?debugFmt("2. Message signed with HTTP auth", []),
    %% 输出调试信息

    %% 3. Cookie认证流程
    {ok, SignedCookie} = dev_codec_cookie_auth:commit(Message, #{}, #{}),
    %% 使用Cookie认证签名消息

    ?assert(maps:is_key(<<"commitments">>, SignedCookie)),
    %% 验证签名结果包含承诺

    ?debugFmt("3. Message signed with cookie auth", []),
    %% 输出调试信息

    %% 4. 提取并重用Cookie
    {ok, Cookies} = dev_codec_cookie:extract(SignedCookie, #{}, #{}),
    %% 从签名消息提取Cookie

    SecretKeys = [K || <<"secret-", _/binary>> = K <- maps:keys(Cookies)],
    %% 提取以"secret-"开头的密钥键
    %% 列表推导过滤匹配键

    ?assert(length(SecretKeys) > 0),
    %% 验证存在密钥

    ?debugFmt("4. Cookie extracted for reuse", []),
    %% 输出调试信息

    ?debugFmt("=== All tests passed! ===", []).
    %% 输出工作流成功标记
