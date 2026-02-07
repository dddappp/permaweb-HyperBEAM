%%% @doc test_dev2: HyperBEAM 编解码器功能测试模块
%%%
%%% 本模块测试 HyperBEAM 的核心编解码器功能，包括：
%%% - HTTP 消息签名 (HTTPSig) - 支持 RSA-PSS 和 HMAC 两种算法
%%% - 结构化类型编码 (TABM) - 支持整数、浮点数、原子、列表等丰富类型
%%% - JSON 编解码 - 用于 HTTP 传输的 JSON 序列化
%%% - 扁平化转换 - 嵌套映射与扁平键路径之间的转换
%%%
%%% 这些编解码器是 HyperBEAM 消息处理管道的基础组件，
%%% 确保消息能够在不同的表示格式之间正确转换。
%%%
%%% 运行方式：rebar3 eunit --module=test_dev2
-module(test_dev2).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% ============================================================
%% RSA-PSS 数字签名测试
%% ============================================================
%% @doc 测试用例：RSA-PSS-SHA512 数字签名
%%
%% 本测试验证 RSA-PSS-SHA512 数字签名算法的签名和验证功能：
%% 1. 创建新钱包（包含公钥/私钥对）
%% 2. 创建测试消息
%% 3. 使用私钥对消息进行签名
%% 4. 验证签名是否有效
%%
%% RSA-PSS 是一种概率签名方案，相比普通 RSA 具有更强的安全性，
%% 能够抵抗特定的密码学攻击。
%%
%% 签名类型 rsa-pss-sha512：
%% - 使用 SHA512 哈希算法
%% - 使用 PSS（概率签名方案）进行填充
%% - 密钥长度为 4096 位（ar_wallet:new() 的默认值）
httpsig_rsa_test() ->
    Wallet = ar_wallet:new(),
    %% 创建新钱包
    %% ar_wallet:new/0 生成包含公钥和私钥的钱包
    %% 私钥用于签名，公钥用于验证
    %% 默认生成 4096 位 RSA 密钥对
    
    Msg = #{<<"data">> => <<"test">>},
    %% 创建测试消息
    %% 包含一个简单的 data 字段，值为二进制字符串 "test"
    %% 签名将基于此消息内容生成
    
    %% Sign
    %% 使用 dev_codec_httpsig:commit/3 对消息进行签名
    {ok, Signed} = dev_codec_httpsig:commit(
        Msg,
        #{<<"type">> => <<"rsa-pss-sha512">>},
        #{priv_wallet => Wallet}
    ),
    %% commit/3 参数说明：
    %% 第一个参数：待签名的消息（Msg）
    %% 第二个参数：签名请求配置，指定使用 RSA-PSS-SHA512 算法
    %% 第三个参数：选项映射，包含私钥（priv_wallet）
    %% 返回值：{ok, Signed}，Signed 是包含签名的消息副本
    %% 签名结果存储在 Signed 的 commitments 字段中
    
    ?assert(maps:is_key(<<"commitments">>, Signed)),
    %% 验证签名结果包含 commitments 字段
    %% 签名承诺（commitment）包含签名值和元数据
    %% 如果签名失败，commitments 字段不会存在
    
    ?debugFmt("RSA-PSS signed: OK", []),
    %% 输出签名成功的调试信息
    
    %% Verify
    %% 验证签名的有效性
    ?assert(hb_message:verify(Signed, all, #{})),
    %% hb_message:verify/3 验证消息签名
    %% 第一个参数：已签名的消息
    %% 第二个参数：验证范围（all 表示验证所有签名）
    %% 第三个参数：选项映射（空映射）
    %% 内部过程：
    %% 1. 提取签名承诺中的公钥信息
    %% 2. 重新计算签名的基准字符串
    %% 3. 使用公钥验证签名值
    %% 如果验证通过，断言成功；否则抛出异常
    
    ?debugFmt("Verification: OK", []).
    %% 输出验证成功的调试信息

%% ============================================================
%% HMAC 消息认证码测试
%% ============================================================
%% @doc 测试用例：HMAC-SHA256 消息认证码
%%
%% 本测试验证 HMAC（Hash-based Message Authentication Code）消息认证功能：
%% 1. 生成随机密钥（64字节）
%% 2. 创建测试消息
%% 3. 使用 HMAC-SHA256 算法生成消息认证码
%% 4. 验证认证码是否有效
%%
%% HMAC 特点：
%% - 对称密钥算法，通信双方共享同一密钥
%% - 比普通哈希提供更强的消息完整性保证
%% - 适用于客户端/服务器之间的消息认证
%% - 无需公钥基础设施，更轻量级
httpsig_hmac_test() ->
    Secret = hb_util:encode(crypto:strong_rand_bytes(64)),
    %% 生成随机密钥
    %% crypto:strong_rand_bytes/1 生成密码学安全的随机字节
    %% 参数 64 表示生成 64 字节（512 位）的密钥
    %% hb_util:encode/1 将二进制转换为 Base64url 编码的字符串
    %% 生成的密钥用于 HMAC 计算
    
    Msg = #{<<"data">> => <<"test">>},
    %% 创建测试消息（与 RSA 测试相同）
    
    {ok, Signed} = dev_codec_httpsig:commit(
        Msg,
        #{<<"type">> => <<"hmac-sha256">>, <<"secret">> => Secret},
        #{}
    ),
    %% 使用 HMAC-SHA256 算法签名
    %% 签名请求配置：
    %% - type: 指定使用 hmac-sha256 算法
    %% - secret: 共享密钥（此处使用刚生成的 Secret）
    %% 注意：HMAC 不需要私钥选项，使用共享密钥
    %% 返回值：{ok, Signed}，包含 HMAC 认证码的消息
    
    ?assert(maps:is_key(<<"commitments">>, Signed)),
    %% 验证签名结果包含 commitments 字段
    %% HMAC 的 commitments 包含认证码值
    
    ?debugFmt("HMAC signed: OK", []).
    %% 输出 HMAC 签名成功的调试信息
    %% 注意：此测试未验证签名（用户只要求签名）

%% ============================================================
%% 结构化类型编码测试
%% ============================================================
%% @doc 测试用例：TABM 结构化类型编码
%%
%% 本测试验证 Type-Annotated Binary Message (TABM) 格式的编解码功能：
%% 1. 创建包含多种类型（整数、原子）消息
%% 2. 编码为 TABM 格式（保留类型信息）
%% 3. 验证编码结果
%% 4. 解码回原始格式
%% 5. 验证解码结果与原始消息一致
%%
%% TABM 格式特点：
%% - HTTP 结构化字段（RFC 9651）的二进制变体
%% - 支持整数、浮点数、原子、列表等丰富类型
%% - 类型信息通过 ao-types 字段标注
%% - 用于 HyperBEAM 内部消息表示
structured_types_test() ->
    Msg = #{
        <<"count">> => 42,
        <<"name">> => <<"test">>,
        <<"module">> => my_handler
    },
    %% 创建测试消息
    %% 包含三种不同类型的字段：
    %% - count: 整数类型 (42)
    %% - name: 二进制字符串 ("test")
    %% - module: 原子类型 (my_handler)
    %% 注意：原子类型在编码时会保留
    
    %% Encode to TABM
    %% 编码为 TABM 格式
    {ok, TABM} = dev_codec_structured:from(Msg, #{}, #{}),
    %% dev_codec_structured:from/3 将消息转换为 TABM
    %% 参数：
    %% - Msg: 原始消息映射
    %% - 第二个参数：请求配置（空）
    %% - 第三个参数：选项配置（空）
    %% 返回值：{ok, TABM}，TABM 是编码后的消息
    %% 编码过程：
    %% 1. 规范化消息键（排序、转换）
    %% 2. 识别各字段的类型
    %% 3. 生成 ao-types 字段记录类型信息
    %% 4. 返回包含类型标注的二进制消息
    
    ?assert(is_binary(maps:get(<<"count">>, TABM))),
    %% 验证编码后 count 字段是二进制类型
    %% TABM 编码会将整数转换为二进制字符串表示
    %% 例如：42 -> <<"42">>
    
    ?assert(maps:is_key(<<"ao-types">>, TABM)),
    %% 验证编码结果包含 ao-types 字段
    %% ao-types 字段存储类型元数据，格式如：
    %% "count=\"integer\",module=\"atom\""
    
    ?debugFmt("Structured encode: OK", []),
    %% 输出编码成功的调试信息
    
    %% Decode back
    %% 从 TABM 解码回原始格式
    {ok, Decoded} = dev_codec_structured:to(TABM, #{}, #{}),
    %% dev_codec_structured:to/3 将 TABM 转换回原始格式
    %% 参数与 from/3 相同
    %% 返回值：{ok, Decoded}，Decoded 是解码后的消息
    %% 解码过程：
    %% 1. 解析 ao-types 字段获取类型信息
    %% 2. 根据类型信息转换各字段值
    %% 3. 移除 ao-types 辅助字段
    %% 4. 返回原始类型的消息
    
    ?assertEqual(42, maps:get(<<"count">>, Decoded)),
    %% 验证解码后 count 恢复为整数 42
    %% 成功解码应该恢复原始类型
    
    ?assertEqual(my_handler, maps:get(<<"module">>, Decoded)),
    %% 验证解码后 module 恢复为原子 my_handler
    %% 原子类型在 TABM 中编码后能够完整恢复
    
    ?debugFmt("Structured decode: OK", []).
    %% 输出解码成功的调试信息

%% ============================================================
%% JSON 往返编码测试
%% ============================================================
%% @doc 测试用例：JSON 编解码往返测试
%%
%% 本测试验证 JSON 格式的编码和解码功能：
%% 1. 创建包含多种类型（字符串、整数、列表）的消息
%% 2. 编码为 JSON 字符串
%% 3. 验证编码结果
%% 4. 解码回消息格式
%% 5. 验证数据完整性
%%
%% JSON 编解码特点：
%% - JSON 不支持原子类型，原子会被转换为字符串
%% - 数字和字符串保持类型
%% - 列表转换为 JSON 数组
%% - 主要用于 HTTP 传输和 API 响应
json_roundtrip_test() ->
    Msg = #{
        <<"name">> => <<"Alice">>,
        <<"age">> => 30,
        <<"items">> => [1, 2, 3]
    },
    %% 创建测试消息
    %% 包含三种不同类型的字段：
    %% - name: 二进制字符串 ("Alice")
    %% - age: 整数 (30)
    %% - items: 整数列表 ([1, 2, 3])
    
    %% Encode to JSON
    %% 编码为 JSON 字符串
    {ok, JSON} = dev_codec_json:to(Msg, #{}, #{}),
    %% dev_codec_json:to/3 将消息转换为 JSON 字符串
    %% 参数：
    %% - Msg: 原始消息
    %% - 第二个参数：请求配置（空）
    %% - 第三个参数：选项配置（空）
    %% 返回值：{ok, JSON}，JSON 是 JSON 格式的二进制字符串
    %% 编码过程：
    %% 1. 先转换为结构化格式（保留类型）
    %% 2. 处理嵌套链接（如果需要）
    %% 3. 转换为 JSON 格式
    %% 注意：原子类型在此步骤会丢失（转为字符串）
    
    ?assert(is_binary(JSON)),
    %% 验证结果是二进制类型（JSON 字符串）
    
    ?debugFmt("JSON: ~s", [JSON]),
    %% 输出 JSON 内容，~s 表示字符串格式化
    %% 预期输出：{"name":"Alice","age":30,"items":[1,2,3]}
    
    %% Decode back
    %% 从 JSON 解码回消息格式
    {ok, Decoded} = dev_codec_json:from(JSON, #{}, #{}),
    %% dev_codec_json:from/3 将 JSON 字符串转换回消息
    %% 参数与 to/3 相同
    %% 返回值：{ok, Decoded}，Decoded 是解码后的消息
    %% 解码过程：
    %% 1. 使用标准 JSON 解析器解析字符串
    %% 2. 转换为结构化格式
    %% 3. 再转换为 TABM 格式
    %% 注意：此过程类型信息会有所损失
    
    ?assertEqual(<<"Alice">>, maps:get(<<"name">>, Decoded)),
    %% 验证 name 字段正确解码
    %% 二进制字符串在 JSON 中保持类型
    
    ?debugFmt("JSON roundtrip: OK", []).
    %% 输出往返编码成功的调试信息

%% ============================================================
%% 扁平化转换测试
%% ============================================================
%% @doc 测试用例：扁平化与反扁平化转换
%%
%% 本测试验证嵌套映射与扁平键路径之间的转换：
%% 1. 创建嵌套结构的消息
%% 2. 转换为扁平格式（使用路径作为键）
%% 3. 验证扁平化结果
%% 4. 反扁平化回嵌套结构
%% 5. 验证数据完整性
%%
%% 扁平化用途：
%% - 配置文件的扁平化存储
%% - 命令行参数解析
%% - 数据库字段映射
%% - API 参数处理
%%
%% 路径格式：使用斜杠分隔嵌套键
%% 例如：db.host -> "db/host"
flat_conversion_test() ->
    Nested = #{
        <<"db">> => #{
            <<"host">> => <<"localhost">>,
            <<"port">> => <<"5432">>
        }
    },
    %% 创建嵌套结构的消息
    %% 包含数据库配置：
    %% - db.host = "localhost"
    %% - db.port = "5432"
    
    %% Flatten
    %% 转换为扁平格式
    {ok, Flat} = dev_codec_flat:to(Nested, #{}, #{}),
    %% dev_codec_flat:to/3 将嵌套映射转换为扁平格式
    %% 参数：
    %% - Nested: 嵌套结构的消息
    %% - 第二个参数：请求配置（空）
    %% - 第三个参数：选项配置（空）
    %% 返回值：{ok, Flat}，Flat 是扁平化的映射
    %% 转换规则：
    %% - 嵌套键使用斜杠连接：db.host -> <<"db/host">>
    %% - 嵌套对象展平为顶层键
    %% 示例结果：#{
    %%     <<"db/host">> => <<"localhost">>,
    %%     <<"db/port">> => <<"5432">>
    %% }
    
    ?assertEqual(<<"localhost">>, maps:get(<<"db/host">>, Flat)),
    %% 验证扁平化后可以使用路径键访问值
    %% db/host 路径对应原始嵌套的 db.host 字段
    
    ?debugFmt("Flattened: OK", []),
    %% 输出扁平化成功的调试信息
    
    %% Unflatten
    %% 反扁平化回嵌套结构
    {ok, Unflat} = dev_codec_flat:from(Flat, #{}, #{}),
    %% dev_codec_flat:from/3 将扁平映射转换回嵌套格式
    %% 参数与 to/3 相同
    %% 返回值：{ok, Unflat}，Unflat 是嵌套结构的消息
    %% 转换规则：
    %% - 按路径分隔符拆分键
    %% - 重建嵌套结构
    %% 示例结果：#{
    %%     <<"db">> => #{
    %%         <<"host">> => <<"localhost">>,
    %%         <<"port">> => <<"5432">>
    %%     }
    %% }
    
    ?assertEqual(<<"localhost">>, hb_ao:get(<<"db/host">>, Unflat, #{})),
    %% 验证反扁平化结果
    %% 使用 hb_ao:get/3 通过路径访问嵌套值
    %% 参数：
    %% - 第一个参数：路径键（支持嵌套访问）
    %% - 第二个参数：消息映射
    %% - 第三个参数：选项（空）
    %% 返回值：嵌套中的 host 值
    
    ?debugFmt("Unflattened: OK", []).
    %% 输出反扁平化成功的调试信息

%% ============================================================
%% 完整编解码工作流测试
%% ============================================================
%% @doc 测试用例：完整编解码工作流
%%
%% 本测试验证 HyperBEAM 编解码器的完整工作流程：
%% 1. 创建包含丰富类型数据的原始消息
%% 2. 转换为结构化格式（保留类型信息）
%% 3. 使用 RSA-PSS-SHA512 签名消息
%% 4. 序列化为 JSON 格式（用于 HTTP 传输）
%% 5. 验证签名有效性
%%
%% 此测试模拟典型的消息处理场景：
%% - 用户创建交易消息
%% - 消息被序列化为标准格式
%% - 签名确保消息完整性和来源
%% - 接收方验证并处理消息
complete_workflow_test() ->
    ?debugFmt("=== Complete Codec Workflow ===", []),
    %% 输出工作流开始标记
    
    %% 1. Create message with rich types
    %% 创建包含丰富类型的原始消息
    Msg = #{
        <<"type">> => <<"transfer">>,
        <<"amount">> => 1000,
        <<"recipient">> => <<"alice@example.com">>
    },
    %% 创建转账消息示例
    %% - type: 消息类型（transfer）
    %% - amount: 转账金额（整数 1000）
    %% - recipient: 接收者邮箱
    %% 注意：amount 是整数，在后续编码中会保留类型
    
    ?debugFmt("1. Created message with integer amount", []),
    %% 输出步骤 1 完成的调试信息
    
    %% 2. Convert to structured (preserve types)
    %% 转换为结构化格式（保留类型信息）
    {ok, Structured} = dev_codec_structured:from(Msg, #{}, #{}),
    %% 使用结构化编码器转换消息
    %% 转换后整数 1000 会标注为 integer 类型
    %% ao-types 字段记录：amount="integer"
    
    ?assert(maps:is_key(<<"ao-types">>, Structured)),
    %% 验证结构化结果包含类型标注
    %% 如果转换成功，Structured 应有 ao-types 字段
    
    ?debugFmt("2. Converted to structured format", []),
    %% 输出步骤 2 完成的调试信息
    
    %% 3. Sign the message
    %% 对消息进行数字签名
    Wallet = ar_wallet:new(),
    %% 创建新钱包用于签名
    %% 实际应用中通常使用用户已有的钱包
    
    {ok, Signed} = dev_codec_httpsig:commit(
        Structured,
        #{<<"type">> => <<"rsa-pss-sha512">>},
        #{priv_wallet => Wallet}
    ),
    %% 使用 HTTPSig 编码器签名消息
    %% 签名基于结构化消息（包括类型信息）
    %% 签名承诺添加到 Signed 的 commitments 字段
    
    ?debugFmt("3. Signed with RSA-PSS", []),
    %% 输出步骤 3 完成的调试信息
    
    %% 4. Serialize to JSON for HTTP
    %% 序列化为 JSON 格式（用于 HTTP 传输）
    {ok, Response} = dev_codec_json:serialize(Signed, #{}, #{}),
    %% 使用 JSON 编码器序列化签名后的消息
    %% serialize/3 返回包含 content-type 和 body 的映射
    %% 这是准备 HTTP 响应的标准格式
    
    ?assertEqual(<<"application/json">>, maps:get(<<"content-type">>, Response)),
    %% 验证响应 Content-Type 为 application/json
    %% 这对于 HTTP 客户端正确解析响应很重要
    
    ?debugFmt("4. Serialized for HTTP", []),
    %% 输出步骤 4 完成的调试信息
    
    %% 5. Verify on receiving end
    %% 在接收端验证签名
    ?assert(hb_message:verify(Signed, all, #{})),
    %% 验证签名的有效性
    %% 签名验证确保：
    %% 1. 消息未被篡改
    %% 2. 消息来自持有对应私钥的签名者
    %% 验证通过表示整个工作流正确无误
    
    ?debugFmt("5. Verified signature", []),
    %% 输出步骤 5 完成的调试信息
    
    ?debugFmt("=== All tests passed! ===", []).
    %% 输出所有测试通过的标记
