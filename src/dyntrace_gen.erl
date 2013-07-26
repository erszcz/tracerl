%%%-------------------------------------------------------------------
%%% @author Pawel Chrzaszcz
%%% @copyright (C) 2013, Erlang Solutions Ltd.
%%% @doc Script generator
%%%
%%% @end
%%% Created : 26 Jul 2013 by pawel.chrzaszcz@erlang-solutions.com
%%%-------------------------------------------------------------------
-module(dyntrace_gen).

-export([script/2, script/3]).

script(CbkMod, ScriptSrc) ->
    script(CbkMod, ScriptSrc, node()).

script(CbkMod, ScriptSrc, Node) when is_atom(Node) ->
    PidStr = rpc:call(Node, os, getpid, []),
    script(CbkMod, ScriptSrc, PidStr);
script(CbkMod, ScriptSrc, PidStr) ->
    {Script, _State} =
        process(CbkMod, probes, ScriptSrc, CbkMod:init_state(PidStr)),
    Script.

process(CbkMod, F, Item, InState) ->
    process(CbkMod, F, nop, Item, InState).

process(CbkMod, PreF, PostF, Item, InState) ->
    {InChildren, State} = CbkMod:PreF(Item, InState),
    {OutChildren, OutState} = process_list(CbkMod, InChildren, State),
    CbkMod:PostF(OutChildren, OutState).

process_list(CbkMod, ItemL, InState) ->
    lists:mapfoldl(fun(L, St) when is_list(L) ->
                           process_list(CbkMod, L, St);
                      (I, St) when is_integer(I) ->
                           {I, St};
                      ({F, Item}, St) ->
                           process(CbkMod, F, Item, St);
                      ({PreF, PostF, Item}, St) ->
                           process(CbkMod, PreF, PostF, Item, St)
                   end, InState, ItemL).
