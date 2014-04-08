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
                                                      ?CARBON_FLUSH_FREQ)}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(Request, From, State) ->
    ?INFO("unexpected call from ~p: ~p~n", [From, Request]),
    Reply = ok,
    {reply, Reply, State}.

handle_cast(#carbon_sample{} = Sample, #?state{} = S) ->
    case handle_cast_sample(Sample, S) of
        {ok, NewS} -> {noreply, NewS};
        {error, _} = ER -> {stop, ER, S}
    end;
handle_cast(Msg, State) ->
    ?INFO("unexpected cast: ~p~n", [Msg]),
    {noreply, State}.

handle_info(Info, State) ->
    ?INFO("unexpected info: ~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
%% Internal functions
%%

handle_cast_sample(#carbon_sample{} = Sample,
                   #?state{carbon_host = Addr,
                           carbon_port = Port,
                           udp_socket = Socket,
                           flush_freq = FlushFreq,
                           samples = Samples,
                           nsamples = NSamples} = S)
  when NSamples + 1 == FlushFreq ->
    case gen_udp:send(Socket, Addr, Port,
                      samples_to_iodata([Sample | Samples])) of
        {error, _} = Error -> Error;
        ok ->
            {ok, S#?state{samples = [],
                          nsamples = 0}}
    end;
handle_cast_sample(#carbon_sample{} = Sample,
                   #?state{samples = Samples,
                           nsamples = NSamples} = S) ->
    {ok, S#?state{samples = [Sample | Samples],
                  nsamples = NSamples + 1}}.

samples_to_iodata(Samples) ->
    [[sample_to_iodata(Sample), $\n] || Sample <- Samples].

sample_to_iodata(#carbon_sample{metric = Metric, value = Value,
                                timestamp = TS}) ->
    BValue = integer_to_binary(Value),
    BTS = integer_to_binary(timestamp_to_seconds(TS)),
    %[Metric, $\ , BValue, $\ , BTS].
    iolist_to_binary([Metric, $\ , BValue, $\ , BTS]).

timestamp_to_seconds({Mega, Seconds, _}) ->
    1000 * 1000 * Mega + Seconds.
