-module(rebar_digraph).

-export([compile_order/1
        ,restore_graph/1
        ,subgraph/2
        ,format_error/1]).

-include("rebar.hrl").

%% Sort apps with topological sort to get proper build order
%% 给所有的应用组建依赖有向图，然后取得依赖顺序
compile_order(Apps) ->
    Graph = digraph:new(),
    lists:foreach(fun(App) ->
                          Name = rebar_app_info:name(App),
                          Deps = all_apps_deps(App),
                          add(Graph, {Name, Deps})
                  end, Apps),
    Order =
		%% 获得有向图的拓扑排序
        case digraph_utils:topsort(Graph) of
            false ->
                case digraph_utils:is_acyclic(Graph) of
                    true ->
                        {error, no_sort};
                    false ->
                        Cycles = lists:sort(
                                   [lists:sort(Comp) || Comp <- digraph_utils:strong_components(Graph),
                                                        length(Comp)>1]),
                        {error, {cycles, Cycles}}
                end;
            V ->
				%% 根据拓扑排序的所有应用以及传入进来的实体应用得到真实的应用
                {ok, names_to_apps(lists:reverse(V), Apps)}
        end,
	%% 最终删除有向图
    true = digraph:delete(Graph),
    Order.

%% 根据依赖关系增加应用节点以及应用依赖之间的边
add(Graph, {PkgName, Deps}) ->
    case digraph:vertex(Graph, PkgName) of
        false ->
            V = digraph:add_vertex(Graph, PkgName);
        {V, []} ->
            V
    end,

    lists:foreach(fun(DepName) ->
                          Name1 = case DepName of
                                      {Name, _Vsn} ->
                                          ec_cnv:to_binary(Name);
                                      Name ->
                                          ec_cnv:to_binary(Name)
                                  end,
                          V3 = case digraph:vertex(Graph, Name1) of
                                   false ->
                                       digraph:add_vertex(Graph, Name1);
                                   {V2, []} ->
                                       V2
                               end,
                          digraph:add_edge(Graph, V, V3)
                  end, Deps).

restore_graph({Vs, Es}) ->
    Graph = digraph:new(),
    lists:foreach(fun({V, LastUpdated}) ->
                          digraph:add_vertex(Graph, V, LastUpdated)
                  end, Vs),
    lists:foreach(fun({V1, V2}) ->
                          digraph:add_edge(Graph, V1, V2)
                  end, Es),
    Graph.

format_error(no_solution) ->
    io_lib:format("No solution for packages found.", []).

%%====================================================================
%% Internal Functions
%%====================================================================

subgraph(Graph, Vertices) ->
    digraph_utils:subgraph(Graph, Vertices).

-spec names_to_apps([atom()], [rebar_app_info:t()]) -> [rebar_app_info:t()].
%% 根据拓扑顺序图以及实体应用列表得到最终有序的实体应用列表
names_to_apps(Names, Apps) ->
    [element(2, App) || App <- [find_app_by_name(Name, Apps) || Name <- Names], App =/= error].

-spec find_app_by_name(atom(), [rebar_app_info:t()]) -> {ok, rebar_app_info:t()} | error.
find_app_by_name(Name, Apps) ->
    ec_lists:find(fun(App) ->
                          rebar_app_info:name(App) =:= Name
                  end, Apps).

%% The union of all entries in the applications list for an app and
%% the deps listed in its rebar.config is all deps that may be needed
%% for building the app.
all_apps_deps(App) ->
    Applications = lists:usort([atom_to_binary(X, utf8) || X <- rebar_app_info:applications(App)]),
    Deps = lists:usort(lists:map(fun({Name, _}) -> Name; (Name) -> Name end, rebar_app_info:deps(App))),
    lists:umerge(Deps, Applications).
