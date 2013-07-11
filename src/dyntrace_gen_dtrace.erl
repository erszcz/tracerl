%%%-------------------------------------------------------------------
%%% @author Pawel Chrzaszcz
%%% @copyright (C) 2013, Erlang Solutions Ltd.
%%% @doc Script generator for dtrace
%%%
%%% @end
%%% Created : 3 Jul 2013 by pawel.chrzaszcz@erlang-solutions.com
%%%-------------------------------------------------------------------
-module(dyntrace_gen_dtrace).

-compile(export_all).

-record(state, {pid}).

script(Probes) ->
    script(Probes, node()).

script(Probes, Node) when is_atom(Node) ->
    PidStr = rpc:call(Node, os, getpid, []),
    script(Probes, PidStr);
script(Probes, PidStr) ->
    State = init_state(PidStr),
    sep([probe(Probe, State) || Probe <- Probes], "\n").

init_state(PidStr) when is_list(PidStr) ->
    #state{pid = PidStr}.

probe({probe, 'BEGIN', Statements}, _State) ->
    ["BEGIN \n", op({group, Statements})];
probe({probe, Functions, Predicates, Statements}, State) ->
    [[["erlang", State#state.pid, ":::", Function, "\n"] ||
        Function <- Functions],
     case Predicates of
         [] -> [];
         _  -> ["/ ", probe_predicates(Predicates), " /\n"]
     end,
     op({group, Statements})
    ].

probe_predicates([SinglePred]) ->
    op(SinglePred);
probe_predicates(Preds) ->
    op({'&&', Preds}).

op({group, Items}) ->
    ["{\n", sep_ops(Items, ";\n"), ";\n}\n"];
op({action, exit}) ->
    ["exit(0)"];
op({'&&', Ops}) ->
    ["(", sep_ops(Ops, ") && ("), ")"];
op({'==', Op1, Op2}) ->
    [op(Op1), " == ", op(Op2)];
op({arg_str, N}) when is_integer(N), N > 0 ->
    ["copyinstr(arg",integer_to_list(N-1),")"];
op({arg, N}) when is_integer(N), N > 0 ->
    ["arg",integer_to_list(N-1)];
op({Func,List}) when is_atom(Func), is_list(List) ->
    [atom_to_list(Func), "(", sep_ops(List, ", "), ")"];
op(Pid) when is_pid(Pid) ->
    ["\"", pid_to_list(Pid), "\""];
op(Str) when is_integer(hd(Str)) ->
    io_lib:format("~p", [Str]);
op(Int) when is_integer(Int) ->
    integer_to_list(Int).

sep_ops([A,B|T], Sep) -> [op(A),Sep|sep_ops([B|T], Sep)];
sep_ops([H], _Sep)    -> op(H);
sep_ops([], _Sep)     -> [].

sep([A,B|T], Sep) -> [A,Sep|sep([B|T], Sep)];
sep([H], _Sep)    -> H;
sep([], _Sep)     -> [].
