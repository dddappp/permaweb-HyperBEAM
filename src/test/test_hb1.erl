-module(test_hb1).
%% @doc HyperBEAM核心工具函数测试模块
%% 
%% 本模块测试HyperBEAM的基础工具功能，包括：
%% - Erlang类型转换（Type Coercion）：binary、list、integer、atom之间的相互转换
%% - Base64url编码（Encoding）：用于URL安全的数据序列化
%% - JSON序列化（JSON）：AO消息的数据交换格式
%% - 加密哈希（Hashing）：SHA-256承诺机制和数据完整性验证
%% - HTTP头编码（Escaping）：URI百分号编码处理
%% 
%% 这些测试验证了HyperBEAM数据处理管道的基本构建块是否正确工作，
%% 是整个HyperBEAM运行时基础设施的功能基础。

-include_lib("eunit/include/eunit.hrl").
%% 引入EUnit测试框架的头文件，提供?assertEqual、?debugFmt等测试宏
%% 这些宏是Erlang标准测试框架的核心组成部分

-include("include/hb.hrl").
%% 引入HyperBEAM项目定义的头文件，包含项目级别的宏定义和类型声明
%% 如IS_ID宏用于验证32字节的加密安全标识符
 
%% Run with: rebar3 eunit --module=test_hb1
%% 使用rebar3命令运行此测试模块的说明注释
 
type_coercion_test() ->
    %% Integer conversion: 测试hb_util:int/1函数将二进制或列表转换为整数
    %% 该函数是HyperBEAM接收HTTP API输入时的类型标准化工具
    ?assertEqual(42, hb_util:int(<<"42">>)),
    %% 测试二进制字符串"42"到整数42的转换，验证binary_to_list和list_to_integer的组合
    ?assertEqual(42, hb_util:int("42")),
    %% 测试列表字符串"42"到整数42的转换，直接调用list_to_integer
    ?assertEqual(-123, hb_util:int(<<"-123">>)),
    %% 测试带负号的二进制字符串转换，验证负数处理逻辑
    ?debugFmt("Integer conversion: OK", []),
    %% 输出整数转换测试通过的调试信息
    
    %% Binary conversion: 测试hb_util:bin/1函数将各种Erlang类型转换为二进制
    %% 二进制是HyperBEAM中数据存储和传输的标准格式
    ?assertEqual(<<"hello">>, hb_util:bin(hello)),
    %% 测试原子hello转换为二进制<<"hello">>，调用atom_to_binary(Value, utf8)
    ?assertEqual(<<"42">>, hb_util:bin(42)),
    %% 测试整数42转换为二进制<<"42">>，调用integer_to_binary(Value)
    ?debugFmt("Binary conversion: OK", []),
    %% 输出二进制转换测试通过的调试信息
    
    %% List conversion: 测试hb_util:list/1函数将二进制转换为字符串列表
    %% 用于与传统的Erlang字符串处理接口兼容
    ?assertEqual("hello", hb_util:list(<<"hello">>)),
    %% 测试二进制<<"hello">>转换为列表"hello"，调用binary_to_list(Value)
    ?debugFmt("List conversion: OK", []).
    %% 输出列表转换测试通过的调试信息
 
encoding_test() ->
    %% Encoding: 测试hb_util:encode/1和decode/1函数的Base64url编解码
    %% Base64url是URL安全的Base64变体，不使用+和/字符
    %% 使用b64fast库实现高效编码，是HyperBEAM标识符的标准表示法
    
    %% Generate random data: 生成32字节的加密安全随机数据
    %% crypto:strong_rand_bytes/1是Erlang的加密安全随机数生成器
    Data = crypto:strong_rand_bytes(32),
    %% 创建32字节（256位）的随机二进制数据，用于测试编码功能
    
    %% Encode and decode: 测试Base64url编码和解码的完整性
    Encoded = hb_util:encode(Data),
    %% 将32字节二进制编码为Base64url字符串，输出约43个字符
    ?debugFmt("Encoded 32 bytes to ~p chars", [byte_size(Encoded)]),
    %% 输出编码结果的字符数，byte_size获取二进制长度
    
    Decoded = hb_util:decode(Encoded),
    %% 将Base64url字符串解码回原始二进制数据
    ?assertEqual(Data, Decoded),
    %% 验证解码结果与原始数据完全一致，确认编解码对称性
    ?debugFmt("Roundtrip encoding: OK", []),
    %% 输出完整编码轮转测试通过的调试信息
    
    %% URL-safe (no + or /): 验证Base64url的URL安全特性
    %% 标准Base64使用+和/，但在URL中会有问题
    %% Base64url使用-和_替代，是IETF RFC 4648定义的标准
    ?assertEqual(nomatch, binary:match(Encoded, <<"+">>)),
    %% 验证编码结果中不包含+字符，使用binary:match进行模式匹配
    ?assertEqual(nomatch, binary:match(Encoded, <<"/">>)),
    %% 验证编码结果中不包含/字符
    ?debugFmt("URL-safe encoding verified", []).
    %% 输出URL安全编码验证通过的调试信息
 
json_test() ->
    %% JSON: 测试hb_json:encode/1和decode/1函数的JSON序列化功能
    %% JSON是AO消息与外部系统交换数据的主要格式
    %% hb_json模块封装了底层的json库，提供统一的编码解码接口
    
    %% Encode map: 测试简单的键值对映射编码为JSON字符串
    Term = #{<<"name">> => <<"Alice">>, <<"age">> => 30},
    %% 创建包含字符串键和值的映射，键使用二进制是Erlang的JSON最佳实践
    JSON = hb_json:encode(Term),
    %% 将Erlang映射编码为JSON字符串，如{"name":"Alice","age":30}
    ?debugFmt("Encoded JSON: ~s", [JSON]),
    %% 输出编码后的JSON字符串内容
    
    %% Decode back: 测试JSON字符串解码回Erlang映射
    Decoded = hb_json:decode(JSON),
    %% 将JSON字符串解码回Erlang数据类型
    ?assertEqual(Term, Decoded),
    %% 验证解码结果与原始映射完全一致
    ?debugFmt("JSON roundtrip: OK", []),
    %% 输出JSON编解码轮转测试通过的调试信息
    
    %% Nested structures: 测试嵌套数据结构的JSON处理
    Complex = #{
        <<"user">> => #{
            %% 嵌套的映射结构，模拟真实的消息数据格式
            <<"name">> => <<"Bob">>,
            <<"tags">> => [<<"admin">>, <<"active">>]
            %% 嵌套的列表结构，测试复杂数据类型的处理
        }
    },
    ComplexJSON = hb_json:encode(Complex),
    %% 将嵌套结构编码为JSON字符串
    ?assertEqual(Complex, hb_json:decode(ComplexJSON)),
    %% 验证嵌套结构的完整轮转，保持数据结构层次
    ?debugFmt("Nested JSON: OK", []).
    %% 输出嵌套JSON处理测试通过的调试信息
 
hashing_test() ->
    %% Hashing: 测试hb_crypto模块的SHA-256哈希和相关算法
    %% 哈希是HyperBEAM承诺机制的核心，用于创建不可逆的数据指纹
    %% SHA-256产生32字节（256位）输出，是加密安全的单向函数
    
    %% SHA-256 produces 32 bytes: 验证SHA-256哈希的输出长度
    Hash = hb_crypto:sha256(<<"hello world">>),
    %% 计算"hello world"的SHA-256哈希值
    ?assertEqual(32, byte_size(Hash)),
    %% 验证哈希输出长度为32字节（256位），这是SHA-256的标准输出长度
    ?debugFmt("SHA-256 hash size: 32 bytes", []),
    %% 输出哈希长度验证通过的调试信息
    
    %% Deterministic: 验证SHA-256的确定性（同输入必产生同输出）
    Hash1 = hb_crypto:sha256(<<"test">>),
    Hash2 = hb_crypto:sha256(<<"test">>),
    %% 对相同输入计算两次哈希
    ?assertEqual(Hash1, Hash2),
    %% 验证两次哈希结果完全相同，这是密码学哈希的基本性质
    ?debugFmt("SHA-256 deterministic: OK", []),
    %% 输出确定性验证通过的调试信息
    
    %% Hash chaining: 测试sha256_chain/2函数将两个ID链接成单一哈希
    %% 哈希链用于创建有序的承诺序列，每个承诺依赖于前一个
    ID1 = <<1:256>>,
    ID2 = <<2:256>>,
    %% 创建两个256位的测试标识符，<<N:256>>创建固定长度的二进制
    Chain = hb_crypto:sha256_chain(ID1, ID2),
    %% 将ID1和ID2链接：sha256(<<ID1:32/binary, ID2/binary>>)
    ?assertEqual(32, byte_size(Chain)),
    %% 验证链接后的哈希仍然是32字节
    ?debugFmt("Hash chain: OK", []),
    %% 输出哈希链测试通过的调试信息
    
    %% Order matters in chaining: 验证哈希链的顺序依赖性
    Chain1 = hb_crypto:sha256_chain(ID1, ID2),
    Chain2 = hb_crypto:sha256_chain(ID2, ID1),
    %% 交换顺序创建两个不同的哈希链
    ?assertNotEqual(Chain1, Chain2),
    %% 验证顺序影响结果，这是哈希链用于排序的基础
    ?debugFmt("Chain order dependency verified", []).
    %% 输出顺序依赖验证通过的调试信息
 
accumulation_test() ->
    %% Accumulation: 测试hb_crypto:accumulate/2函数的ID累加功能
    %% 累加算法将两个256位ID的值相加，产生新的256位承诺
    %% 与哈希链不同，累加不保留顺序信息，适用于顺序无关的场景
    
    %% Accumulate two IDs: 测试两个ID的基本累加功能
    ID1 = <<1:256>>,
    ID2 = <<2:256>>,
    %% 创建数值为1和2的256位测试标识符
    Result = hb_crypto:accumulate(ID1, ID2),
    %% 累加两个ID：<<(ID1Int + ID2Int):256>> = <<3:256>>
    
    <<ResultInt:256>> = Result,
    %% 将累加结果解构为256位整数，用于验证数值计算
    ?assertEqual(3, ResultInt),
    %% 验证1 + 2 = 3，累加功能正确工作
    ?debugFmt("Accumulate 1 + 2 = 3: OK", []),
    %% 输出累加数值验证的调试信息
    
    %% Order independent: 验证累加的交换律（顺序无关）
    Acc1 = hb_crypto:accumulate(ID1, ID2),
    Acc2 = hb_crypto:accumulate(ID2, ID1),
    %% 以不同顺序累加相同的ID
    ?assertEqual(Acc1, Acc2),
    %% 验证结果相同，累加是交换的
    ?debugFmt("Accumulation order-independent: OK", []),
    %% 输出顺序无关性验证的调试信息
    
    %% Accumulate list: 测试累加列表中多个ID的功能
    IDs = [<<1:256>>, <<2:256>>, <<3:256>>],
    %% 创建包含多个ID的列表
    ListResult = hb_crypto:accumulate(IDs),
    %% 使用lists:foldl累加整个列表：0+1+2+3 = 6
    <<ListInt:256>> = ListResult,
    %% 解构结果为整数
    ?assertEqual(6, ListInt),
    %% 验证累加结果为6 (1+2+3)
    ?debugFmt("Accumulate list [1,2,3] = 6: OK", []).
    %% 输出列表累加验证的调试信息
 
escape_test() ->
    %% Escaping: 测试hb_escape:encode/1和decode/1函数的URI百分号编码
    %% 百分号编码将特殊字符转换为%XX格式，用于HTTP头的安全传输
    %% AO-Core消息通过HTTP/2和HTTP/3传输，需要对header key进行编码
    
    %% Percent encoding: 测试基本的百分号编码功能
    Encoded = hb_escape:encode(<<"Hello World!">>),
    %% 将包含空格的字符串编码为URI安全格式
    %% "Hello World!" -> "Hello%20World%21"
    ?debugFmt("Encoded: ~s", [Encoded]),
    %% 输出编码后的结果
    
    Decoded = hb_escape:decode(Encoded),
    %% 将百分号编码的字符串解码回原始数据
    ?assertEqual(<<"Hello World!">>, Decoded),
    %% 验证解码结果与原始输入完全一致
    ?debugFmt("Escape roundtrip: OK", []),
    %% 输出编码解码轮转测试通过的调试信息
    
    %% Lowercase preserved: 验证编码过程中字母大小写保持不变
    %% 百分号编码不改变字母字符本身，只编码特殊字符
    ?assertEqual(<<"hello">>, hb_escape:encode(<<"hello">>)),
    %% 纯小写字母字符串编码后保持不变（无特殊字符需要编码）
    ?debugFmt("Lowercase preserved: OK", []).
    %% 输出大小写保持验证的调试信息
 
complete_workflow_test() ->
    %% Complete Workflow: 集成测试，验证HyperBEAM工具函数的完整工作流
    %% 模拟真实场景：创建消息、序列化、哈希、编码、传输、解码
    ?debugFmt("=== Complete Workflow Test ===", []),
    %% 输出工作流测试开始的调试信息
    
    %% 1. Create some data: 创建测试数据，模拟AO消息结构
    Data = #{
        <<"type">> => <<"message">>,
        %% 消息类型字段，使用二进制键是HyperBEAM的约定
        <<"content">> => <<"Hello, HyperBEAM!">>,
        %% 消息内容字段
        <<"timestamp">> => 1234567890
        %% 时间戳字段，Unix时间戳格式
    },
    ?debugFmt("1. Created data structure", []),
    %% 输出步骤1完成的调试信息
    
    %% 2. Serialize to JSON: 将数据结构序列化为JSON字符串
    JSON = hb_json:encode(Data),
    %% 调用hb_json:encode将映射转换为JSON格式
    ?debugFmt("2. Serialized to JSON: ~s", [JSON]),
    %% 输出JSON序列化结果的调试信息
    
    %% 3. Hash the content: 计算JSON内容的SHA-256哈希
    Hash = hb_crypto:sha256(JSON),
    %% 对JSON字符串计算密码学哈希，用于承诺和数据完整性验证
    HashHex = hb_util:to_hex(Hash),
    %% 将二进制哈希转换为十六进制字符串便于阅读和调试
    ?debugFmt("3. SHA-256 hash: ~s", [HashHex]),
    %% 输出哈希值的调试信息
    
    %% 4. Encode hash for URLs: 将哈希编码为Base64url格式
    HashEncoded = hb_util:encode(Hash),
    %% Base64url编码适合URL参数和标识符传输
    ?debugFmt("4. Base64url encoded: ~s", [HashEncoded]),
    %% 输出Base64url编码结果的调试信息
    
    %% 5. Verify roundtrip: 验证Base64url编码的完整性
    HashDecoded = hb_util:decode(HashEncoded),
    %% 将编码后的字符串解码回原始二进制
    ?assertEqual(Hash, HashDecoded),
    %% 验证解码结果与原始哈希一致
    ?debugFmt("5. Verified roundtrip encoding", []),
    %% 输出编码轮转验证通过的调试信息
    
    %% 6. Parse JSON back: 验证JSON数据的可恢复性
    Recovered = hb_json:decode(JSON),
    %% 将JSON字符串解码回Erlang数据结构
    ?assertEqual(Data, Recovered),
    %% 验证恢复的数据与原始数据完全一致
    ?debugFmt("6. Verified JSON roundtrip", []),
    %% 输出JSON轮转验证通过的调试信息
    
    ?debugFmt("=== All tests passed! ===", []).
    %% 输出所有测试通过的总结信息
