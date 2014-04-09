-module(tracerl_carbon).

-behaviour(gen_server).

-include("tracerl_carbon.hrl").

-define(INFO(Fmt, Args), error_logger:info_msg(Fmt, Args)).

%% API
-export([start_link/2, start_link/3,
         send_to_carbon/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(state, tracerl_carbon_state).

%%
%% API
%%

start_link(Host, UDPPort) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Host, UDPPort], []).

start_link(Host, UDPPort, Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE,
                          [Host, UDPPort | Opts], []).

send_to_carbon(#carbon_sample{} = Sample) ->
    gen_server:cast(?SERVER, Sample).

%%
%% gen_server callbacks
%%

init([Host, UDPPort | Opts]) ->
    case gen_udp:open(0, []) of
        {ok, Socket} ->
            {ok,
             #?state{carbon_host = Host,
                     carbon_port = UDPPort,
                     udp_socket = Socket,
                     flush_freq = proplists:get_value(flush_freq, Opts,
                                                      ?CARBON_FLUSH_FREQ),
                     flush_time = proplists:get_value(flush_time, Opts,
                                                      ?CARBON_FLUSH_TIME)}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(Request, From, #?state{} = S) ->
    ?INFO("unexpected call from ~p: ~p~n", [From, Request]),
    Reply = ok,
    {reply, Reply, S, timeout(s)}.

handle_cast(#carbon_sample{} = Sample, #?state{} = S) ->
    case handle_cast_sample(Sample, S) of
        {ok, NewS} -> {noreply, NewS, timeout(S)};
        {error, _} = ER -> {stop, ER, S}
    end;
handle_cast(Msg, #?state{} = S) ->
    ?INFO("unexpected cast: ~p~n", [Msg]),
    {noreply, S, timeout(S)}.

handle_info(timeout, #?state{} = S) ->
    case send_batch(S) of
        {ok, NewS} -> {noreply, NewS, timeout(S)};
        {error, _} = ER -> {stop, ER, S}
    end;
handle_info(Info, #?state{} = S) ->
    ?INFO("unexpected info: ~p~n", [Info]),
    {noreply, S, timeout(S)}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
%% Internal functions
%%

-spec handle_cast_sample(carbon_sample(),
                         tracerl_carbon_state()) -> {ok, tracerl_carbon_state()}
                                                    | {error, any()}.
handle_cast_sample(#carbon_sample{} = Sample, #?state{} = S) ->
    BufferedS = buffer_sample(Sample, S),
    maybe_send_batch(BufferedS).

-spec buffer_sample(carbon_sample(),
                    tracerl_carbon_state()) -> tracerl_carbon_state().
buffer_sample(#carbon_sample{} = Sample,
              #?state{samples = Samples,
                      nsamples = NSamples} = S) ->
    S#?state{samples = [Sample | Samples],
             nsamples = NSamples + 1}.

-spec maybe_send_batch(tracerl_carbon_state()) -> {ok, tracerl_carbon_state()} |
                                                  {error, any()}.
maybe_send_batch(#?state{flush_freq = FlushFreq,
                         nsamples = NSamples} = S) ->
    if
        NSamples == FlushFreq -> send_batch(S);
        NSamples /= FlushFreq -> {ok, S}
    end.

-spec send_batch(tracerl_carbon_state()) -> {ok, tracerl_carbon_state()} |
                                            {error, any()}.
send_batch(#?state{nsamples = 0} = S) ->
    {ok, S};
send_batch(#?state{carbon_host = Addr, carbon_port = Port,
                   udp_socket = Socket, samples = Samples} = S) ->
    case gen_udp:send(Socket, Addr, Port,
                      samples_to_iodata(Samples)) of
        {error, _} = Error ->
            Error;
        ok ->
            {ok, S#?state{samples = [],
                          nsamples = 0}}
    end.

samples_to_iodata(Samples) ->
    [[sample_to_iodata(Sample), $\n] || Sample <- Samples].

sample_to_iodata(#carbon_sample{metric = Metric, value = Value,
                                timestamp = TS}) ->
    BValue = integer_to_binary(Value),
    BTS = integer_to_binary(timestamp_to_seconds(TS)),
    [Metric, $\ , BValue, $\ , BTS].

timestamp_to_seconds({Mega, Seconds, _}) ->
    1000 * 1000 * Mega + Seconds.

timeout(#?state{flush_time = Time}) ->
    timer:seconds(Time).
