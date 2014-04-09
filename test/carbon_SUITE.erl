-module(carbon_SUITE).

-include_lib("test_server/include/test_server.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("tracerl_carbon.hrl").

-define(a(Exp), ?assert(Exp)).
-define(ae(E, A), ?assertEqual(E, A)).

-compile(export_all).

all() ->
    tests().

groups() ->
    [{tests, [sequence], tests()}].

tests() ->
    [startup_test,
     send_to_carbon_test,
     send_batch_to_carbon_test].

init_per_testcase(CaseName, Config)
  when CaseName =:= send_to_carbon_test;
       CaseName =:= send_batch_to_carbon_test ->
    meck:new(gen_udp, [unstick]),
    meck:expect(gen_udp, open, fun (_, _) -> {ok, meck_fake_socket} end),
    Self = self(),
    meck:expect(gen_udp, send, fun (meck_fake_socket, _, _, Data) ->
                                       Self ! {meck_fake_udp_send, Data},
                                       ok
                               end),
    Config;
init_per_testcase(_CaseName, Config) ->
    Config.

end_per_testcase(CaseName, _Config)
  when CaseName =:= send_to_carbon_test;
       CaseName =:= send_batch_to_carbon_test ->
    meck:unload(gen_udp),
    ok;
end_per_testcase(_CaseName, _Config) ->
    ok.

%%
%% Tests
%%

startup_test(_) ->
    startup(),
    ?a(is_running()).

%% The data should be flushed to the socket once,
%% i.e. just one call to gen_udp:send/4.
send_to_carbon_test(_) ->
    startup([{flush_freq, 1}]),
    ?a(is_running()),
    tracerl_carbon:send_to_carbon(sample("foo.bar.baz", 124, os:timestamp())),
    receive {meck_fake_udp_send, _} -> ok end,
    ?ae(1, meck:num_calls(gen_udp, send, '_')).

%% The data should be flushed to the socket once per big enough batch,
%% i.e. just one call to gen_udp:send/4 per 5 samples.
send_batch_to_carbon_test(_) ->
    startup([{flush_freq, 5}]),
    ?a(is_running()),
    BaseVal = 220,
    BaseTS = os:timestamp(),
    [send_to_carbon("foo.bar.baz", BaseVal + I, timestamp_add(BaseTS, {0,I,0}))
     || I <- lists:seq(1, 7)],
    receive {meck_fake_udp_send, _} -> ok end,
    ?ae(1, meck:num_calls(gen_udp, send, '_')),
    [send_to_carbon("foo.bar.baz", BaseVal + I, timestamp_add(BaseTS, {0,I,0}))
     || I <- lists:seq(8, 10)],
    receive {meck_fake_udp_send, _} -> ok end,
    ?ae(2, meck:num_calls(gen_udp, send, '_')).

%%
%% Helpers
%%

startup() ->
    startup([]).

startup(Opts) ->
    {ok, Pid} = tracerl_carbon:start_link({10,100,0,70}, 2003, Opts),
    Pid.

is_running() ->
    Pid = erlang:whereis(tracerl_carbon),
    is_pid(Pid) andalso erlang:is_process_alive(Pid).

sample(Metric, Value, Timestamp) ->
    #carbon_sample{metric = Metric,
                   value = Value,
                   timestamp = Timestamp}.

timestamp_add({Mega1, Secs1, Mili1}, {Mega2, Secs2, Mili2}) ->
    {Mega1 + Mega2, Secs1 + Secs2, Mili1 + Mili2}.

send_to_carbon(Metric, Value, TS) ->
    tracerl_carbon:send_to_carbon(sample(Metric, Value, TS)).
