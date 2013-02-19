%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1998-2011. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(s_group).

%% Groups nodes into s_groups with an own global name space.

-behaviour(gen_server).

%% External exports
-export([start/0, start_link/0, stop/0, init/1]).
-export([handle_call/3, handle_cast/2, handle_info/2, 
	 terminate/2, code_change/3]).

-export([register_name/3]).
-export([register_name_external/3]).
-export([unregister_name/2]).
-export([unregister_name_external/2]).
-export([re_register_name/3]).
-export([send/3]).
-export([send/4]).
-export([whereis_name/2]).
-export([whereis_name/3]).
-export([s_groups/0]).
-export([own_nodes/0]).
-export([own_nodes/1]).
-export([own_groups/0]).

-export([registered_names/1]).
-export([sync/0]).
-export([info/0]).
-export([get_own_nodes/0, get_own_nodes_with_errors/0,
         get_own_s_groups_with_nodes/0]).
-export([monitor_nodes/1]).
-export([publish_on_nodes/0]).

-export([s_groups_changed/1]).
-export([s_groups_added/1]).
-export([s_groups_removed/1]).
-export([ng_add_check/2, ng_add_check/3]).
-export([config_scan/1, config_scan/2]).

-export([registered_names_test/1]).
-export([send_test/2]).
-export([whereis_name_test/1]).

%% Internal exports
-export([sync_init/4]).


-define(cc_vsn, 2).


-define(debug(_), ok).

%%-define(debug(Term), erlang:display(Term)).

%%%====================================================================================

-type publish_type() :: 'hidden' | 'normal'.
-type sync_state()   :: 'no_conf' | 'synced'.

-type group_name()  :: atom().
-type group_tuple() :: {GroupName :: group_name(), [node()]}
                     | {GroupName :: group_name(),
                        PublishType :: publish_type(),
                        [node()]}.

%%%====================================================================================
%%% The state of the s_group process
%%% 
%%% sync_state =  no_conf (s_groups not defined, inital state) |
%%%               synced 
%%% group_name =  Own global group name
%%% nodes =       Nodes in the own global group
%%% no_contact =  Nodes which we haven't had contact with yet
%%% sync_error =  Nodes which we haven't had contact with yet
%%% other_grps =  list of other global group names and nodes, [{otherName, [Node]}]
%%% node_name =   Own node 
%%% monitor =     List of Pids requesting nodeup/nodedown
%%%====================================================================================

-record(state, {sync_state = no_conf        :: sync_state(),
		connect_all                 :: boolean(),
		group_names = []            :: [group_name()],  %% type changed by HL;
		nodes = []                  :: [node()],
		no_contact = []             :: [node()],
		sync_error = []             :: [node()],
		other_grps = []             :: [{group_name(), [node()]}],
                own_grps =[]                :: [{group_name(), [node()]}], %% added by HL;
		node_name = node()          :: node(),
		monitor = []                :: [pid()],
		publish_type = normal       :: publish_type(),
		group_publish_type = normal :: publish_type()}).



%%%====================================================================================
%%% External exported
%%%====================================================================================

-spec s_groups() ->  {GroupName, GroupNames}  | undefined when
              GroupName ::[group_name()], GroupNames :: [GroupName].
s_groups() ->
    request(s_groups).

-spec monitor_nodes(Flag) -> 'ok' when
      Flag :: boolean().
monitor_nodes(Flag) -> 
    case Flag of
	true -> request({monitor_nodes, Flag});
	false -> request({monitor_nodes, Flag});
	_ -> {error, not_boolean}
    end.

-spec own_nodes() -> Nodes when
      Nodes :: [Node :: node()].
own_nodes() ->
    request({own_nodes}).

-spec own_nodes(SGroupName) -> Nodes when
      SGroupName :: group_name(),
      Nodes :: [Node :: node()].
own_nodes(SGroupName) ->
    request({own_nodes, SGroupName}).

-spec own_groups() -> GroupTuples when
      GroupTuples :: [GroupTuple :: group_tuple()].
own_groups() ->
    request(own_groups).

-type name()  :: atom().
-type where() :: {'node', node()} | {'group', group_name()}.

-spec registered_names(Where) -> Names when
      Where :: where(),
      Names :: [Name :: name()].
registered_names(Arg) ->
    request({registered_names, Arg}).

-spec send(Name, SGroupName, Msg) -> pid() | {'badarg', {Name, SGroupName, Msg}} when
      Name :: name(),
      SGroupName :: group_name(),
      Msg :: term().
send(Name, SGroupName, Msg) ->
    request({send, Name, SGroupName, Msg}).

-spec send(Node, Name, SGroupName, Msg) -> pid() | {'badarg', {Name, SGroupName, Msg}} when
      Node :: node(),
      Name :: name(),
      SGroupName :: group_name(),
      Msg :: term().
send(Node, Name, SGroupName, Msg) ->
    request({send, Node, Name, SGroupName, Msg}).




-spec register_name(Name, SGroupName, Pid) -> 'yes' | 'no' when	%NC
      Name :: term(),
      SGroupName :: group_name(),
      Pid :: pid().
register_name(Name, SGroupName, Pid) when is_pid(Pid) ->
    request({register_name, Name, SGroupName, Pid}).

-spec register_name_external(Name, SGroupName, Pid) -> 'yes' | 'no' when	%NC
      Name :: term(),
      SGroupName :: group_name(),
      Pid :: pid().
register_name_external(Name, SGroupName, Pid) when is_pid(Pid) ->
    request({register_name_external, Name, SGroupName, Pid}).

-spec unregister_name(Name, SGroupName) -> _ when
      Name :: term(),
      SGroupName :: group_name().
unregister_name(Name, SGroupName) ->
      request({unregister_name, Name, SGroupName}).

unregister_name_external(Name, SGroupName) ->
      request({unregister_name, Name, SGroupName}).

-spec re_register_name(Name, SGroupName, Pid) -> 'yes' | 'no' when
      Name :: term(),
      SGroupName :: group_name(),
      Pid :: pid().
re_register_name(Name, SGroupName, Pid) when is_pid(Pid) ->
      request({re_register_name, Name, SGroupName, Pid}).

-spec whereis_name(Name, SGroupName) -> pid() | 'undefined' when
      Name :: name(),
      SGroupName :: group_name().
whereis_name(Name, SGroupName) ->
    request({whereis_name, Name, SGroupName}).

-spec whereis_name(Node, Name, SGroupName) -> pid() | 'undefined' when
      Node :: node(),
      Name :: name(),
      SGroupName :: group_name().
whereis_name(Node, Name, SGroupName) ->
    request({whereis_name, Node, Name, SGroupName}).




s_groups_changed(NewPara) ->
    request({s_groups_changed, NewPara}).

s_groups_added(NewPara) ->
    request({s_groups_added, NewPara}).

s_groups_removed(NewPara) ->
    request({s_groups_removed, NewPara}).

-spec sync() -> 'ok'.
sync() ->
    request(sync).

ng_add_check(Node, OthersNG) ->
    ng_add_check(Node, normal, OthersNG).

ng_add_check(Node, PubType, OthersNG) ->
    request({ng_add_check, Node, PubType, OthersNG}).

-type info_item() :: {'state', State :: sync_state()}
                   | {'own_group_names', GroupName :: [group_name()]}
                   | {'own_group_nodes', Nodes :: [node()]}
                   | {'synched_nodes', Nodes :: [node()]}
                   | {'sync_error', Nodes :: [node()]}
                   | {'no_contact', Nodes :: [node()]}
                   | {'own_groups', OwnGroups::[group_tuple()]}
                   | {'other_groups', Groups :: [group_tuple()]}
                   | {'monitoring', Pids :: [pid()]}.

-spec info() -> [info_item()].
info() ->
    request(info, 3000).

%% ==== ONLY for test suites ====
registered_names_test(Arg) ->
    request({registered_names_test, Arg}).
send_test(Name, Msg) ->
    request({send_test, Name, Msg}).
whereis_name_test(Name) ->
    request({whereis_name_test, Name}).
%% ==== ONLY for test suites ====


request(Req) ->
    request(Req, infinity).

request(Req, Time) ->
    case whereis(s_group) of
	P when is_pid(P) ->
	    gen_server:call(s_group, Req, Time);
	_Other -> 
	    {error, s_group_not_runnig}
    end.

%%%====================================================================================
%%% gen_server start
%%%
%%% The first thing to happen is to read if the s_groups key is defined in the
%%% .config file. If not defined, the whole system is started as one s_group, 
%%% and the services of s_group are superfluous.
%%% Otherwise a sync process is started to check that all nodes in the own global
%%% group have the same configuration. This is done by sending 'conf_check' to all
%%% other nodes and requiring 'conf_check_result' back.
%%% If the nodes are not in agreement of the configuration the s_group process 
%%% will remove these nodes from the #state.nodes list. This can be a normal case
%%% at release upgrade when all nodes are not yet upgraded.
%%%
%%% It is possible to manually force a sync of the s_group. This is done for 
%%% instance after a release upgrade, after all nodes in the group beeing upgraded.
%%% The nodes are not synced automatically because it would cause the node to be
%%% disconnected from those not yet beeing upgraded.
%%%
%%% The three process dictionary variables (registered_names, send, and whereis_name) 
%%% are used to store information needed if the search process crashes. 
%%% The search process is a help process to find registered names in the system.
%%%====================================================================================
start() -> gen_server:start({local, s_group}, s_group, [], []).
start_link() -> gen_server:start_link({local, s_group},s_group,[],[]).
stop() -> gen_server:call(s_group, stop, infinity).

init([]) ->
    process_flag(priority, max),
    ok = net_kernel:monitor_nodes(true),
    put(registered_names, [undefined]),
    put(send, [undefined]),
    put(whereis_name, [undefined]),
    process_flag(trap_exit, true),
    Ca = case init:get_argument(connect_all) of
	     {ok, [["false"]]} ->
		 false;
	     _ ->
		 true
	 end,
    PT = publish_arg(),
    case application:get_env(kernel, s_groups) of
	undefined ->
	    update_publish_nodes(PT),
	    {ok, #state{publish_type = PT,
			connect_all = Ca}};
	{ok, []} ->
	    update_publish_nodes(PT),
	    {ok, #state{publish_type = PT,
			connect_all = Ca}};
	{ok, NodeGrps} ->
            case catch config_scan(NodeGrps, publish_type) of
                {error, _Error2} ->
                    update_publish_nodes(PT),
                    exit({error, {'invalid g_groups definition', NodeGrps}});
                {ok, DefOwnSGroupsT, DefOtherSGroupsT} ->
                    ?debug({".config file scan result:",  {ok, DefOwnSGroupsT, DefOtherSGroupsT}}),
                    DefOwnSGroupsT1 = [{GroupName,GroupNodes}||
                                          {GroupName, _PubType, GroupNodes}
                                              <- DefOwnSGroupsT],
                    {DefSGroupNamesT1, DefSGroupNodesT1}=lists:unzip(DefOwnSGroupsT1),
                    DefSGroupNamesT = lists:usort(DefSGroupNamesT1),
                    DefSGroupNodesT = lists:usort(lists:append(DefSGroupNodesT1)),
                    update_publish_nodes(PT, {normal, DefSGroupNodesT}),
                    %% First disconnect any nodes not belonging to our own group
                    disconnect_nodes(nodes(connected) -- DefSGroupNodesT),
                    lists:foreach(fun(Node) ->
                                          erlang:monitor_node(Node, true)
                                  end,
                                  DefSGroupNodesT),
                    NewState = #state{publish_type = PT, group_publish_type = normal,
                                      sync_state = synced, group_names = DefSGroupNamesT,
                                      no_contact = lists:delete(node(), DefSGroupNodesT),
                                      own_grps = DefOwnSGroupsT1,
                                      other_grps = DefOtherSGroupsT},
                    ?debug({"NewState", NewState}),
                    {ok, NewState}
            end
    end.
                        


%%%====================================================================================
%%% sync() -> ok 
%%%
%%% An operator ordered sync of the own global group. This must be done after
%%% a release upgrade. It can also be ordered if somthing has made the nodes
%%% to disagree of the s_groups definition.
%%%====================================================================================
handle_call(sync, _From, S) ->
    ?debug({"sync:",[node(), application:get_env(kernel, s_groups)]}),
    case application:get_env(kernel, s_groups) of
	undefined ->
	    update_publish_nodes(S#state.publish_type),
	    {reply, ok, S};
	{ok, []} ->
	    update_publish_nodes(S#state.publish_type),
	    {reply, ok, S};
	{ok, NodeGrps} ->
	    {DefGroupNames, PubTpGrp, DefNodes, DefOwn, DefOther} = 
		case catch config_scan(NodeGrps, publish_type) of
		    {error, _Error2} ->
			exit({error, {'invalid s_groups definition', NodeGrps}});
                    {ok, DefOwnSGroupsT, DefOtherSGroupsT} ->
                        DefOwnSGroupsT1 = [{GroupName,GroupNodes}||
                                              {GroupName, _PubType, GroupNodes}
                                                  <- DefOwnSGroupsT],
                        {DefSGroupNamesT1, DefSGroupNodesT1}=lists:unzip(DefOwnSGroupsT1),
                        DefSGroupNamesT = lists:usort(DefSGroupNamesT1),
                        DefSGroupNodesT = lists:usort(lists:append(DefSGroupNodesT1)),
                        PubType = normal,
                        update_publish_nodes(S#state.publish_type, {PubType, DefSGroupNodesT}),
                        %% First inform global on all nodes not belonging to our own group
			disconnect_nodes(nodes(connected) -- DefSGroupNodesT),
			%% Sync with the nodes in the own group
                        kill_s_group_check(),
                        Pid = spawn_link(?MODULE, sync_init, 
					 [sync, DefSGroupNamesT, PubType, DefOwnSGroupsT1]),
			register(s_group_check, Pid),
                        {DefSGroupNamesT, PubType, 
                         lists:delete(node(), DefSGroupNodesT),
                         DefOwnSGroupsT1, DefOtherSGroupsT}
                end,
            {reply, ok, S#state{sync_state = synced, group_names = DefGroupNames, 
				no_contact = lists:sort(DefNodes), 
                                own_grps = DefOwn,
				other_grps = DefOther, group_publish_type = PubTpGrp}}
    end;



%%%====================================================================================
%%% Get the names of the s_groups
%%%====================================================================================
handle_call(s_groups, _From, S) ->
    Result = case S#state.sync_state of
		 no_conf ->
		     undefined;
		 synced ->
		     Other = lists:foldl(fun({N,_L}, Acc) -> Acc ++ [N]
					 end,
					 [], S#state.other_grps),
		     {S#state.group_names, Other}
	     end,
    {reply, Result, S};


%%%====================================================================================
%%% monitor_nodes(bool()) -> ok 
%%%
%%% Monitor nodes in the own global group. 
%%%   True => send nodeup/nodedown to the requesting Pid
%%%   False => stop sending nodeup/nodedown to the requesting Pid
%%%====================================================================================
handle_call({monitor_nodes, Flag}, {Pid, _}, StateIn) ->
    %%io:format("***** handle_call ~p~n",[monitor_nodes]),
    {Res, State} = monitor_nodes(Flag, Pid, StateIn),
    {reply, Res, State};


%%%====================================================================================
%%% own_nodes() -> [Node]
%%% own_nodes(SGroupName) -> [Node] 
%%%
%%% Get a list of nodes in the own s_groups
%%%====================================================================================
handle_call({own_nodes}, _From, S) ->
    Nodes = case S#state.sync_state of
		no_conf ->
		    [node() | nodes()];
		synced ->
		    get_own_nodes()
	    end,
    {reply, Nodes, S};

handle_call({own_nodes, SGroupName}, _From, S) ->
    Nodes = case S#state.sync_state of
		no_conf ->
		    [];
		synced ->
		       case lists:member(SGroupName, S#state.group_names) of
		       	    true ->
			    	{SGroupName, Nodes1} = lists:keyfind(SGroupName, 1, S#state.own_grps),
				Nodes1;
			    _ ->
				[]
		       end
	    end,
    {reply, Nodes, S};


%%%====================================================================================
%%% own_groups() -> [GroupTuples] 
%%%
%%% Get a list of own group_tuples
%%%====================================================================================
handle_call(own_groups, _From, S) ->
    GroupTuples = case S#state.sync_state of
		no_conf ->
		    [];
		synced ->
		    S#state.own_grps
	    end,
    {reply, GroupTuples, S};

%%%====================================================================================
%%% registered_names({node, Node}) -> [Name] | {error, ErrorMessage}
%%% registered_names({s_group, SGroupName}) -> [Name] | {error, ErrorMessage}
%%%
%%% Get the registered names from a specified Node or SGroupName.
%%%====================================================================================
handle_call({registered_names, {s_group, SGroupName}}, From, S) -> %NC
    %%erlang:display(lists:member(SGroupName, S#state.group_names)),
    case lists:member(SGroupName, S#state.group_names) of 
        true ->
            %%Res1 = s_group_names1(SGroupName, global:registered_names(all_names), []),
	    %%erlang:display({res1, Res1}),
	    Res = s_group_names(global:registered_names(all_names), [], SGroupName),
            {reply, Res, S};
        false ->		 %NC fix
            case lists:keysearch(SGroupName, 1, S#state.other_grps) of
                false ->
                    {reply, [], S};
                {value, {SGroupName, []}} ->
                    {reply, [], S};
                {value, {SGroupName, Nodes}} ->
                    Pid = global_search:start(names, {s_group, Nodes, From}),
                    Wait = get(registered_names),
                    put(registered_names, [{Pid, From} | Wait]),
                    {noreply, S}
            end
    end;
handle_call({registered_names, {node, Node}}, _From, S) when Node =:= node() ->
    Res = global:registered_names(all_names),
    {reply, Res, S};
handle_call({registered_names, {node, Node}}, From, S) ->
    Pid = global_search:start(names, {node, Node, From}),
    Wait = get(registered_names),
    put(registered_names, [{Pid, From} | Wait]),
    {noreply, S};



%%%====================================================================================
%%% send(Name, SGroupName, Msg) -> Pid | {badarg, {Name, SGroupName, Msg}}
%%% send(Node, Name, SGroupName, Msg) -> Pid | {badarg, {Name, SGroupName, Msg}}
%%%
%%% Send the Msg to the specified globally registered Name in own s_group,
%%% in specified Node, or SGroupName.
%%% But first the receiver is to be found, the thread is continued at
%%% handle_cast(send_res)
%%%====================================================================================
%% Search in the whole known world, but check own node first.
handle_call({send, Name, SGroupName, Msg}, From, S) -> %NC?
    case global:whereis_name(Name, SGroupName) of
	undefined ->
	    Pid = global_search:start(send, {any, S#state.other_grps, Name, SGroupName, Msg, From}),
	    Wait = get(send),
	    put(send, [{Pid, From, Name, SGroupName, Msg} | Wait]),
	    {noreply, S};
	Found ->
	    Found ! Msg,
	    {reply, Found, S}
    end;

%% Search in the specified global group, which happens to be the own group.
%handle_call({send, Name, SGroupName, Msg}, From, S) ->
%    case lists:member(SGroupName, S#state.group_names) of
%        true ->
%            case global:whereis_name(Name, SGroupName) of
%                undefined ->
%                    {reply, {badarg, {Name, SGroupName, Msg}}, S};
%                Pid ->
%                    Pid ! Msg,
%                    {reply, Pid, S}
%            end;
%        false ->
%            case lists:keysearch(SGroupName, 1, S#state.other_grps) of
%                false ->
%                    {reply, {badarg, {Name, SGroupName, Msg}}, S};
%                {value, {SGroupName, []}} ->
%                    {reply, {badarg, {Name, SGroupName, Msg}}, S};
%                {value, {SGroupName, Nodes}} ->
%                    Pid = global_search:start(send, {group, Nodes, Name, SGroupName, Msg, From}),
%                    Wait = get(send),
%                    put(send, [{Pid, From, Name, SGroupName, Msg} | Wait]),
%                    {noreply, S}
%            end
%    end;

%% Search on the specified node.
handle_call({send, Node, Name, SGroupName, Msg}, From, S) ->
    Pid = global_search:start(send, {node, Node, Name, SGroupName, Msg, From}),
    Wait = get(send),
    put(send, [{Pid, From, Name, SGroupName, Msg} | Wait]),
    {noreply, S};


%%%====================================================================================
%%% register_name(Name, SGroupName, Pid) -> 'yes' | 'no'
%%% register_name_external(Name, SGroupName, Pid) -> 'yes' | 'no'
%%% unregister_name(Name, SGroupName) -> _
%%% re_register_name(Name, SGroupName, Pid) -> 'yes' | 'no'
%%%
handle_call({register_name, Name, SGroupName, Pid}, _From, S) ->
    %%erlang:display({s_group_rname_3, lists:member(SGroupName, S#state.group_names)}),
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:register_name(Name, SGroupName, Pid, fun global:random_exit_name/3),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;

handle_call({register_name_external, Name, SGroupName, Pid}, _From, S) ->
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:register_name_external(Name, SGroupName, Pid, fun global:random_exit_name/3),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;

handle_call({unregister_name, Name, SGroupName}, _From, S) ->
    %%erlang:display(lists:member(SGroupName, S#state.group_names)),
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:unregister_name(Name, SGroupName),
	    erlang:display(Res),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;

handle_call({re_register_name, Name, SGroupName, Pid}, _From, S) ->
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:re_register_name(Name, SGroupName, Pid, fun global:random_exit_name/3),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;
%%%====================================================================================
%%% whereis_name(Name, SGroupName) -> Pid | undefined
%%% whereis_name(Node, Name, SGroupName) -> Pid | undefined
%%%
%%% Get the Pid of a globally registered Name in own s_group,
%%% in specified Node, or SGroupName.
%%% But first the process is to be found, 
%%% the thread is continued at handle_cast(find_name_res)
%%%====================================================================================
%% Search on the specified node.
handle_call({whereis_name, Node, Name, SGroupName}, From, S) ->
    Pid = global_search:start(whereis, {node, Node, Name, SGroupName, From}),
    Wait = get(whereis_name),
    put(whereis_name, [{Pid, From} | Wait]),
    {noreply, S};

%% Search in the whole known world, but check own node first.
handle_call({whereis_name, Name, SGroupName}, From, S) ->
    case global:whereis_name(Name, SGroupName) of
	undefined ->
	    Pid = global_search:start(whereis, {any, S#state.other_grps, Name, SGroupName, From}),
	    Wait = get(whereis_name),
	    put(whereis_name, [{Pid, From} | Wait]),
	    {noreply, S};
	Found ->
	    {reply, Found, S}
    end;

%% Search in the specified global group, which happens to be the own group. % Need to change!! HL.
%handle_call({whereis_name, Name, SGroupName}, From, S) ->
%    case lists:member(SGroupName, S#state.group_names) of
%        true ->
%            Res = global:whereis_name(Name, SGroupName),
%            {reply, Res, S};
%        false ->
%            case lists:keysearch(SGroupName, 1, S#state.other_grps) of
%                false ->
%                    {reply, undefined, S};
%                {value, {SGroupName, []}} ->
%                    {reply, undefined, S};
%                {value, {SGroupName, Nodes}} ->
%                    Pid = global_search:start(whereis, {group, Nodes, Name, SGroupName, From}),
%                    Wait = get(whereis_name),
%                    put(whereis_name, [{Pid, From} | Wait]),
%                    {noreply, S}
%            end
%    end;

%%%====================================================================================
%%% s_groups parameter changed
%%% The node is not resynced automatically because it would cause this node to
%%% be disconnected from those nodes not yet been upgraded.
%%%====================================================================================
handle_call({s_groups_changed, NewPara}, _From, S) ->
    %% Need to be changed because of the change of config_scan HL
    {NewGroupName, PubTpGrp, NewNodes, NewOther} = 
	case catch config_scan(NewPara, publish_type) of
	    {error, _Error2} ->
		exit({error, {'invalid s_groups definition', NewPara}});
	    {DefGroupName, PubType, DefNodes, DefOther} ->
		update_publish_nodes(S#state.publish_type, {PubType, DefNodes}),
		{DefGroupName, PubType, DefNodes, DefOther}
	end,

    %% #state.nodes is the common denominator of previous and new definition
    NN = NewNodes -- (NewNodes -- S#state.nodes),
    %% rest of the nodes in the new definition are marked as not yet contacted
    NNC = (NewNodes -- S#state.nodes) --  S#state.sync_error,
    %% remove sync_error nodes not belonging to the new group
    NSE = NewNodes -- (NewNodes -- S#state.sync_error),

    %% Disconnect the connection to nodes which are not in our old global group.
    %% This is done because if we already are aware of new nodes (to our global
    %% group) global is not going to be synced to these nodes. We disconnect instead
    %% of connect because upgrades can be done node by node and we cannot really
    %% know what nodes these new nodes are synced to. The operator can always 
    %% manually force a sync of the nodes after all nodes beeing uppgraded.
    %% We must disconnect also if some nodes to which we have a connection
    %% will not be in any global group at all.
    force_nodedown(nodes(connected) -- NewNodes),

    NewS = S#state{group_names = [NewGroupName], 
		   nodes = lists:sort(NN), 
		   no_contact = lists:sort(lists:delete(node(), NNC)), 
		   sync_error = lists:sort(NSE), 
		   other_grps = NewOther,
		   group_publish_type = PubTpGrp},
    {reply, ok, NewS};


%%%====================================================================================
%%% s_groups parameter added
%%% The node is not resynced automatically because it would cause this node to
%%% be disconnected from those nodes not yet been upgraded.
%%%====================================================================================
handle_call({s_groups_added, NewPara}, _From, S) ->
    %%io:format("### s_groups_changed, NewPara ~p ~n",[NewPara]),
    %% Need to be changed because of the change of config_scan!! HL
    {NewGroupName, PubTpGrp, NewNodes, NewOther} = 
	case catch config_scan(NewPara, publish_type) of
	    {error, _Error2} ->
		exit({error, {'invalid s_groups definition', NewPara}});
	    {DefGroupName, PubType, DefNodes, DefOther} ->
		update_publish_nodes(S#state.publish_type, {PubType, DefNodes}),
		{DefGroupName, PubType, DefNodes, DefOther}
	end,

    %% disconnect from those nodes which are not going to be in our global group
    force_nodedown(nodes(connected) -- NewNodes),

    %% Check which nodes are already updated
    OwnNG = get_own_nodes(),
    NGACArgs = case S#state.group_publish_type of
		   normal ->
		       [node(), OwnNG];
		   _ ->
		       [node(), S#state.group_publish_type, OwnNG]
	       end,
    {NN, NNC, NSE} = 
	lists:foldl(fun(Node, {NN_acc, NNC_acc, NSE_acc}) -> 
			    case rpc:call(Node, s_group, ng_add_check, NGACArgs) of
				{badrpc, _} ->
				    {NN_acc, [Node | NNC_acc], NSE_acc};
				agreed ->
				    {[Node | NN_acc], NNC_acc, NSE_acc};
				not_agreed ->
				    {NN_acc, NNC_acc, [Node | NSE_acc]}
			    end
		    end,
		    {[], [], []}, lists:delete(node(), NewNodes)),
    NewS = S#state{sync_state = synced, group_names = [NewGroupName], nodes = lists:sort(NN), 
		   sync_error = lists:sort(NSE), no_contact = lists:sort(NNC), 
		   other_grps = NewOther, group_publish_type = PubTpGrp},
    {reply, ok, NewS};


%%%====================================================================================
%%% s_groups parameter removed
%%%====================================================================================
handle_call({s_groups_removed, _NewPara}, _From, S) ->
    %%io:format("### s_groups_removed, NewPara ~p ~n",[_NewPara]),
    update_publish_nodes(S#state.publish_type),
    NewS = S#state{sync_state = no_conf, group_names = [], nodes = [], 
		   sync_error = [], no_contact = [], 
		   other_grps = []},
    {reply, ok, NewS};


%%%====================================================================================
%%% s_groups parameter added to some other node which thinks that we
%%% belong to the same global group.
%%% It could happen that our node is not yet updated with the new node_group parameter
%%%====================================================================================
handle_call({ng_add_check, Node, PubType, OthersNG}, _From, S) ->
    %% Check which nodes are already updated
    erlang:diaplay("TTTTTTTTTTTTTTTTTTTTTTTTTTTTT\n"),
    OwnNG = get_own_nodes(),
    case S#state.group_publish_type =:= PubType of
	true ->
	    case OwnNG of
		OthersNG ->
		    NN = [Node | S#state.nodes],
		    NSE = lists:delete(Node, S#state.sync_error),
		    NNC = lists:delete(Node, S#state.no_contact),
		    NewS = S#state{nodes = lists:sort(NN), 
				   sync_error = NSE, 
				   no_contact = NNC},
		    {reply, agreed, NewS};
		_ ->
		    {reply, not_agreed, S}
	    end;
	_ ->
	    {reply, not_agreed, S}
    end;



%%%====================================================================================
%%% Misceleaneous help function to read some variables
%%%====================================================================================
handle_call(info, _From, S) ->    
    Reply = [{state,          S#state.sync_state},
	     {own_group_names, S#state.group_names},
	     {own_group_nodes, get_own_nodes()},
             %{"nodes()",      lists:sort(nodes())},
	     {synced_nodes,   S#state.nodes},
	     {sync_error,     S#state.sync_error},
	     {no_contact,     S#state.no_contact},
             {own_groups,     S#state.own_grps},
	     {other_groups,   S#state.other_grps},
	     {monitoring,     S#state.monitor}],

    {reply, Reply, S};

handle_call(get, _From, S) ->
    {reply, get(), S};


%%%====================================================================================
%%% Only for test suites. These tests when the search process exits.
%%%====================================================================================
handle_call({registered_names_test, {node, 'test3844zty'}}, From, S) ->
    Pid = global_search:start(names_test, {node, 'test3844zty'}),
    Wait = get(registered_names),
    put(registered_names, [{Pid, From} | Wait]),
    {noreply, S};
handle_call({registered_names_test, {node, _Node}}, _From, S) ->
    {reply, {error, illegal_function_call}, S};
handle_call({send_test, Name, 'test3844zty'}, From, S) ->
    Pid = global_search:start(send_test, 'test3844zty'),
    Wait = get(send),
    put(send, [{Pid, From, Name, 'test3844zty'} | Wait]),
    {noreply, S};
handle_call({send_test, _Name, _Msg }, _From, S) ->
    {reply, {error, illegal_function_call}, S};
handle_call({whereis_name_test, 'test3844zty'}, From, S) ->
    Pid = global_search:start(whereis_test, 'test3844zty'),
    Wait = get(whereis_name),
    put(whereis_name, [{Pid, From} | Wait]),
    {noreply, S};
handle_call({whereis_name_test, _Name}, _From, S) ->
    {reply, {error, illegal_function_call}, S};

handle_call(Call, _From, S) ->
     %%io:format("***** handle_call ~p~n",[Call]),
    {reply, {illegal_message, Call}, S}.





%%%====================================================================================
%%% registered_names({node, Node}) -> [Name] | {error, ErrorMessage}
%%% registered_names({s_group, SGroupName}) -> [Name] | {error, ErrorMessage}
%%%
%%% Get a list of nodes in the own global group
%%%====================================================================================
handle_cast({registered_names, User}, S) ->
    Res = global:registered_names(all_names),
    User ! {registered_names_res, Res},
    {noreply, S};

handle_cast({registered_names_res, Result, Pid, From}, S) ->
    unlink(Pid),
    exit(Pid, normal),
    Wait = get(registered_names),
    NewWait = lists:delete({Pid, From},Wait),
    put(registered_names, NewWait),
    gen_server:reply(From, Result),
    {noreply, S};


%%%====================================================================================
%%% send(Name, SGroupName, Msg) -> Pid | {error, ErrorMessage}
%%% send(Node, Name, SGroupName, Msg) -> Pid | {error, ErrorMessage}
%%%
%%% The registered Name is found; send the message to it, kill the search process,
%%% and return to the requesting process.
%%%====================================================================================
handle_cast({send_res, Result, Name, SGroupName, Msg, Pid, From}, S) ->	%NC
    case Result of
	{badarg,{Name, SGroupName, Msg}} ->
	    continue;
	ToPid ->
	    ToPid ! Msg
    end,
    unlink(Pid),
    exit(Pid, normal),
    Wait = get(send),
    NewWait = lists:delete({Pid, From, Name, SGroupName, Msg},Wait),
    put(send, NewWait),
    gen_server:reply(From, Result),
    {noreply, S};



%%%====================================================================================
%%% A request from a search process to check if this Name is registered at this node.
%%%====================================================================================
handle_cast({find_name, User, Name}, S) ->	%NC?
    Res = global:whereis_name(Name),
    User ! {find_name_res, Res},
    {noreply, S};

handle_cast({find_name, User, Name, SGroupName}, S) ->	%NC
    Res = global:whereis_name(Name, SGroupName),
    User ! {find_name_res, Res},
    {noreply, S};
%%%====================================================================================
%%% whereis_name(Name, SGroupName) -> Pid | undefined
%%% whereis_name(Node, Name, SGroupName) -> Pid | undefined
%%%
%%% The registered Name is found; kill the search process
%%% and return to the requesting process.
%%%====================================================================================
handle_cast({find_name_res, Result, Pid, From}, S) ->
    unlink(Pid),
    exit(Pid, normal),
    Wait = get(whereis_name),
    NewWait = lists:delete({Pid, From},Wait),
    put(whereis_name, NewWait),
    gen_server:reply(From, Result),
    {noreply, S};


%%%====================================================================================
%%% The node is synced successfully
%%%====================================================================================
handle_cast({synced, NoContact}, S) ->
    %io:format("~p>>>>> synced ~p  ~n",[node(), NoContact]),
    kill_s_group_check(),
    Nodes = get_own_nodes() -- [node() | NoContact],
    {noreply, S#state{nodes = lists:sort(Nodes),
		      sync_error = [],
		      no_contact = NoContact}};    


%%%====================================================================================
%%% The node could not sync with some other nodes.
%%%====================================================================================
handle_cast({sync_error, NoContact, ErrorNodes}, S) ->
    Txt = io_lib:format("Global group: Could not synchronize with these nodes ~p~n"
			"because s_groups were not in agreement. ~n", [ErrorNodes]),
    error_logger:error_report(Txt),
    ?debug(lists:flatten(Txt)),
    kill_s_group_check(),
    Nodes = (get_own_nodes() -- [node() | NoContact]) -- ErrorNodes,
    {noreply, S#state{nodes = lists:sort(Nodes), 
		      sync_error = ErrorNodes,
		      no_contact = NoContact}};


%%%====================================================================================
%%% Another node is checking this node's group configuration
%%%====================================================================================
handle_cast({conf_check, Vsn, Node, From, sync, CCName, CCNodes}, S) ->
    handle_cast({conf_check, Vsn, Node, From, sync, CCName, normal, CCNodes}, S);

handle_cast({conf_check, Vsn, Node, From, sync, CCName, PubType, CCNodes}, S) ->
    CurNodes = S#state.nodes,
    %    io:format(">>>>> conf_check,sync  Node ~p~n",[Node]),
    %% Another node is syncing, 
    %% done for instance after upgrade of global_groups parameter
    NS = 
	case application:get_env(kernel, s_groups) of
	    undefined ->
		%% We didn't have any node_group definition
		update_publish_nodes(S#state.publish_type),
		disconnect_nodes([Node]),
		{s_group_check, Node} ! {config_error, Vsn, From, node()},
		S;
	    {ok, []} ->
		%% Our node_group definition was empty
		update_publish_nodes(S#state.publish_type),
		disconnect_nodes([Node]),
		{s_group_check, Node} ! {config_error, Vsn, From, node()},
		S;
	    %%---------------------------------
	    %% s_groups defined
	    %%---------------------------------
	    {ok, NodeGrps} ->
                case config_scan(NodeGrps, publish_type) of
		    {error, _Error2} ->
			%% Our node_group definition was erroneous
			disconnect_nodes([Node]),
			{s_group_check, Node} ! {config_error, Vsn, From, node()},
			S#state{nodes = lists:delete(Node, CurNodes)};
                    {ok, OwnSGroups, _OtherSGroups} ->
                        case lists:keyfind(CCName, 1, OwnSGroups) of
                            {CCName, PubType, CCNodes} ->
                                %% OK, add the node to the #state.nodes if it isn't there
                                update_publish_nodes(S#state.publish_type, {PubType, CCNodes}),
                                ?debug({global_name_server, {nodeup, CCName,Node}}),
                                global_name_server ! {nodeup, CCName, Node},
                                {s_group_check, Node} ! {config_ok, Vsn, From, CCName, node()},
                                case lists:member(Node, CurNodes) of
                                    false ->
                                        NewNodes = lists:sort([Node | CurNodes]),
                                        NSE = lists:delete(Node, S#state.sync_error),
                                        NNC = lists:delete(Node, S#state.no_contact),
                                        S#state{nodes = NewNodes, 
                                                sync_error = NSE,
                                                no_contact = NNC};
                                    true ->
                                        S
                                end;
                            _ ->
                                %% node_group definitions were not in agreement
                                disconnect_nodes([Node]),
                                {s_group_check, Node} ! {config_error, Vsn, From, node()},
                                NN = lists:delete(Node, S#state.nodes),
                                NSE = lists:delete(Node, S#state.sync_error),
                                NNC = lists:delete(Node, S#state.no_contact),
                                S#state{nodes = NN,
                                        sync_error = NSE,
                                        no_contact = NNC}
                        end
                end
        end,
    {noreply, NS};

handle_cast(_Cast, S) ->
%    io:format("***** handle_cast ~p~n",[_Cast]),
    {noreply, S}.
    


%%%====================================================================================
%%% A node went down. If no global group configuration inform global;
%%% if global group configuration inform global only if the node is one in
%%% the own global group.
%%%====================================================================================
handle_info({nodeup, Node}, S) when S#state.sync_state =:= no_conf ->
    case application:get_env(kernel, s_groups) of 
        undefined ->
            %%io:format("~p>>>>> nodeup, Node ~p ~n",[node(), Node]),
            ?debug({"NodeUp:",  node(), Node}),
            send_monitor(S#state.monitor, {nodeup, Node}, S#state.sync_state),
            global_name_server ! {nodeup, no_group, Node},
            {noreply, S};
        _ ->
         handle_node_up(Node,S)
    end;            
handle_info({nodeup, Node}, S) ->
    %% io:format("~p>>>>> nodeup, Node ~p ~n",[node(), Node]),
    ?debug({"NodeUp:",  node(), Node}),
    handle_node_up(Node, S);
%%%====================================================================================
%%% A node has crashed. 
%%% nodedown must always be sent to global; this is a security measurement
%%% because during release upgrade the s_groups parameter is upgraded
%%% before the node is synced. This means that nodedown may arrive from a
%%% node which we are not aware of.
%%%====================================================================================
handle_info({nodedown, Node}, S) when S#state.sync_state =:= no_conf ->
%    io:format("~p>>>>> nodedown, no_conf Node ~p~n",[node(), Node]),
    send_monitor(S#state.monitor, {nodedown, Node}, S#state.sync_state),
    global_name_server ! {nodedown, Node},
    {noreply, S};
handle_info({nodedown, Node}, S) ->
%    io:format("~p>>>>> nodedown, Node ~p  ~n",[node(), Node]),
    send_monitor(S#state.monitor, {nodedown, Node}, S#state.sync_state),
    global_name_server ! {nodedown, Node},
    NN = lists:delete(Node, S#state.nodes),
    NSE = lists:delete(Node, S#state.sync_error),
    NNC = case {lists:member(Node, get_own_nodes()), 
		lists:member(Node, S#state.no_contact)} of
	      {true, false} ->
		  [Node | S#state.no_contact];
	      _ ->
		  S#state.no_contact
	  end,
    {noreply, S#state{nodes = NN, no_contact = NNC, sync_error = NSE}};


%%%====================================================================================
%%% A node has changed its s_groups definition, and is telling us that we are not
%%% included in his group any more. This could happen at release upgrade.
%%%====================================================================================
handle_info({disconnect_node, Node}, S) ->
%    io:format("~p>>>>> disconnect_node Node ~p CN ~p~n",[node(), Node, S#state.nodes]),
    case {S#state.sync_state, lists:member(Node, S#state.nodes)} of
	{synced, true} ->
	    send_monitor(S#state.monitor, {nodedown, Node}, S#state.sync_state);
	_ ->
	    cont
    end,
    global_name_server ! {nodedown, Node}, %% nodedown is used to inform global of the
                                           %% disconnected node
    NN = lists:delete(Node, S#state.nodes),
    NNC = lists:delete(Node, S#state.no_contact),
    NSE = lists:delete(Node, S#state.sync_error),
    {noreply, S#state{nodes = NN, no_contact = NNC, sync_error = NSE}};




handle_info({'EXIT', ExitPid, Reason}, S) ->
    check_exit(ExitPid, Reason),
    {noreply, S};


handle_info(_Info, S) ->
%    io:format("***** handle_info = ~p~n",[_Info]),
    {noreply, S}.

handle_node_up(Node, S) ->
    OthersNG = case S#state.sync_state==no_conf andalso 
                   application:get_env(kernel, s_groups)==undefined of 
                   true -> 
                       [];
                   false ->
                       X = (catch rpc:call(Node, s_group, get_own_s_groups_with_nodes, [])),
		       case X of
			   X when is_list(X) ->
			       X;
			   _ ->
			       []
		       end
               end,
    ?debug({"OthersNG:",OthersNG}),
    OwnNGs = get_own_s_groups_with_nodes(),
    OwnGroups = element(1, lists:unzip(OwnNGs)),
    ?debug({"ownsNG:",OwnNGs}),
    NNC = lists:delete(Node, S#state.no_contact),
    NSE = lists:delete(Node, S#state.sync_error),
    case shared_s_groups_match(OwnNGs, OthersNG) of 
        true->
            %% OwnGroups =  S#state.group_names,
            OthersGroups = element(1, lists:unzip(OthersNG)),
            CommonGroups = intersection(OwnGroups, OthersGroups),
            send_monitor(S#state.monitor, {nodeup, Node}, S#state.sync_state),
            ?debug({nodeup, OwnGroups, Node, CommonGroups}),
	    [global_name_server ! {nodeup, Group, Node}||Group<-CommonGroups],  
	    case lists:member(Node, S#state.nodes) of
		false ->
		    NN = lists:sort([Node | S#state.nodes]),
		    {noreply, S#state{
                                sync_state=synced,
                                group_names = OwnGroups,
                                nodes = NN, 
                                no_contact = NNC,
                                sync_error = NSE}};
		true ->
		    {noreply, S#state{
                                sync_state=synced,
                                group_names = OwnGroups,
                                no_contact = NNC,
                                sync_error = NSE}}
	    end;
	false ->
            case {lists:member(Node, get_own_nodes()), 
		  lists:member(Node, S#state.sync_error)} of
		{true, false} ->
		    NSE2 = lists:sort([Node | S#state.sync_error]),
		    {noreply, S#state{
                                sync_state = synced,
                                group_names = OwnGroups,
                                no_contact = NNC,
                                sync_error = NSE2}};
                _ ->
                    {noreply, S#state{sync_state=synced,
                                      group_names = OwnGroups}}
	    end
    end.



shared_s_groups_match(OwnSGroups, OthersSGroups) ->
    OwnSGroupNames = [G||{G, _Nodes}<-OwnSGroups],
    OthersSGroupNames = [G||{G, _Nodes}<-OthersSGroups],
    SharedSGroups = intersection(OwnSGroupNames, OthersSGroupNames),
    case SharedSGroups of 
        [] -> false;
        Gs ->
            Own =[{G, lists:sort(Nodes)}
                  ||{G, Nodes}<-OwnSGroups, lists:member(G, Gs)],
            Others= [{G, lists:sort(Nodes)}
                     ||{G, Nodes}<-OthersSGroups, lists:member(G, Gs)],
            lists:sort(Own) == lists:sort(Others)
    end.
intersection(_, []) -> 
    [];
intersection(L1, L2) ->
    L1 -- (L1 -- L2).


terminate(_Reason, _S) ->
    ok.
    

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.





%%%====================================================================================
%%% Check the global group configuration.
%%%====================================================================================

%% type spec added by HL.
-spec config_scan(NodeGrps::[group_tuple()])->
                         {ok, OwnGrps::[{group_name(), [node()]}], 
                          OtherGrps::[{group_name(), [node()]}]}
                             |{error, any()}.

%% Functionality rewritten by HL.
config_scan(NodeGrps) ->
    config_scan(NodeGrps, original).

config_scan(NodeGrps, original) ->
     config_scan(NodeGrps, publish_type);

config_scan(NodeGrps, publish_type) ->
    config_scan(node(), NodeGrps, [], []).

config_scan(_MyNode, [], MyOwnNodeGrps, OtherNodeGrps) ->
    {ok, MyOwnNodeGrps, OtherNodeGrps};
config_scan(MyNode, [GrpTuple|NodeGrps], MyOwnNodeGrps, OtherNodeGrps) ->
    {GrpName, PubTypeGroup, Nodes} = grp_tuple(GrpTuple),
    case lists:member(MyNode, Nodes) of
	true ->
            %% HL: is PubTypeGroup needed?
            config_scan(MyNode, NodeGrps, 
                        [{GrpName, PubTypeGroup,lists:sort(Nodes)}
                         |MyOwnNodeGrps], 
                        OtherNodeGrps);
	false ->
	    config_scan(MyNode,NodeGrps, MyOwnNodeGrps,
                        [{GrpName, lists:sort(Nodes)}|
                         OtherNodeGrps])
    end.

grp_tuple({Name, Nodes}) ->
    {Name, normal, Nodes};
grp_tuple({Name, hidden, Nodes}) ->
    {Name, hidden, Nodes};
grp_tuple({Name, normal, Nodes}) ->
    {Name, normal, Nodes}.

    
%% config_scan(NodeGrps) ->
%%     config_scan(NodeGrps, original).

%% config_scan(NodeGrps, original) ->
%%     case config_scan(NodeGrps, publish_type) of
%% 	{DefGroupName, _, DefNodes, DefOther} ->
%% 	    {DefGroupName, DefNodes, DefOther};
%% 	Error ->
%% 	    Error
%%     end;
%% config_scan(NodeGrps, publish_type) ->
%%     config_scan(node(), normal, NodeGrps, no_name, [], []).

%% config_scan(_MyNode, PubType, [], Own_name, OwnNodes, OtherNodeGrps) ->
%%     {Own_name, PubType, lists:sort(OwnNodes), lists:reverse(OtherNodeGrps)};
%% config_scan(MyNode, PubType, [GrpTuple|NodeGrps], Own_name, OwnNodes, OtherNodeGrps) ->
%%     {Name, PubTypeGroup, Nodes} = grp_tuple(GrpTuple),
%%     case lists:member(MyNode, Nodes) of
%% 	true ->
%% 	    case Own_name of
%% 		no_name ->
%% 		    config_scan(MyNode, PubTypeGroup, NodeGrps, Name, Nodes, OtherNodeGrps);
%% 		_ ->
%% 		    {error, {'node defined twice', {Own_name, Name}}}
%% 	    end;
%% 	false ->
%% 	    config_scan(MyNode,PubType,NodeGrps,Own_name,OwnNodes,
%% 			[{Name, Nodes}|OtherNodeGrps])
%%     end.

    
%%%====================================================================================
%%% The special process which checks that all nodes in the own global group
%%% agrees on the configuration.
%%%====================================================================================
-spec sync_init(_, _, _, _) -> no_return().
sync_init(Type, _Cname, PubType, SGroupNodesPairs) ->
    ?debug({"Sync int:", Type, _Cname, PubType, SGroupNodesPairs}),
    NodeGroupPairs = lists:append([[{Node, GroupName}||Node<-Nodes]
                                   ||{GroupName, Nodes}<-SGroupNodesPairs]),
    Nodes = lists:usort(element(1,lists:unzip(NodeGroupPairs))),
    ?debug({"node(), Nodes:", node(), Nodes}),
    {Up, Down} = sync_check_node(lists:delete(node(), Nodes), [], []),
    ?debug({"updown:", Up, Down}),
    sync_check_init(Type, Up, NodeGroupPairs, Down, PubType).

sync_check_node([], Up, Down) ->
    {Up, Down};
sync_check_node([Node|Nodes], Up, Down) ->
    case net_adm:ping(Node) of
	pang ->
	    sync_check_node(Nodes, Up, [Node|Down]);
	pong ->
	    sync_check_node(Nodes, [Node|Up], Down)
    end.



%%%-------------------------------------------------------------
%%% Check that all nodes are in agreement of the global
%%% group configuration.
%%%-------------------------------------------------------------
-spec sync_check_init(_, _, _, _, _) -> no_return().
sync_check_init(Type, Up, NodeGroupPairs, Down, PubType) ->
    sync_check_init(Type, Up, NodeGroupPairs, 3, [], Down, PubType).

-spec sync_check_init(_, _, _, _, _, _,  _) -> no_return().
sync_check_init(_Type, NoContact, _NodeGroupPairss, 0,
                ErrorNodes, Down, _PubType) ->
    case ErrorNodes of
	[] -> 
	    gen_server:cast(s_group, {synced, lists:sort(NoContact ++ Down)});
	_ ->
	    gen_server:cast(s_group, {sync_error, lists:sort(NoContact ++ Down),
					   ErrorNodes})
    end,
    receive
	kill ->
	    exit(normal)
    after 5000 ->
	    exit(normal)
    end;

sync_check_init(Type, Up, NodeGroupPairs, N, ErrorNodes, Down, PubType) ->
    lists:foreach(fun(Node) ->
                          {Node, Group} = lists:keyfind(Node, 1, NodeGroupPairs),
                          GroupNodes = [Node1||{Node1, G}<-NodeGroupPairs, G==Group],
                          ConfCheckMsg = 
                              case PubType of
                                  normal ->
                                      {conf_check, ?cc_vsn, node(), self(), Type, 
                                       Group, GroupNodes};
                                  _ ->
                                      {conf_check, ?cc_vsn, node(), self(), Type,
                                       Group, PubType, GroupNodes}
                              end,
                          ?debug({conf_check, s_group, Node, ConfCheckMsg}),
                          gen_server:cast({s_group, Node}, ConfCheckMsg)
		  end, Up),
    case sync_check(Up) of
	{ok, synced} ->
	    sync_check_init(Type, [],NodeGroupPairs, 0,
                            ErrorNodes, Down, PubType);
	{error, NewErrorNodes} ->
	    sync_check_init(Type, [], NodeGroupPairs, 0,
                            ErrorNodes ++ NewErrorNodes, Down, PubType);
	{more, Rem, NewErrorNodes} ->
	    %% Try again to reach the s_group, 
	    %% obviously the node is up but not the s_group process.
	    sync_check_init(Type, Rem, NodeGroupPairs, N - 1,
                            ErrorNodes ++ NewErrorNodes, Down, PubType)
    end.

sync_check(Up) ->
    sync_check(Up, Up, []).

sync_check([], _Up, []) ->
    {ok, synced};
sync_check([], _Up, ErrorNodes) ->
    {error, ErrorNodes};
sync_check(Rem, Up, ErrorNodes) ->
    receive
	{config_ok, ?cc_vsn, Pid, GroupName, Node} when Pid =:= self() ->
	    global_name_server ! {nodeup, GroupName, Node},
	    sync_check(Rem -- [Node], Up, ErrorNodes);
	{config_error, ?cc_vsn, Pid, Node} when Pid =:= self() ->
	    sync_check(Rem -- [Node], Up, [Node | ErrorNodes]);
	{no_s_group_configuration, ?cc_vsn, Pid, Node} when Pid =:= self() ->
	    sync_check(Rem -- [Node], Up, [Node | ErrorNodes]);
	%% Ignore, illegal vsn or illegal Pid
	_ ->
	    sync_check(Rem, Up, ErrorNodes)
    after 2000 ->
	    %% Try again, the previous conf_check message  
	    %% apparently disapared in the magic black hole.
	    {more, Rem, ErrorNodes}
    end.


%%%====================================================================================
%%% A process wants to toggle monitoring nodeup/nodedown from nodes.
%%%====================================================================================
monitor_nodes(true, Pid, State) ->
    link(Pid),
    Monitor = State#state.monitor,
    {ok, State#state{monitor = [Pid|Monitor]}};
monitor_nodes(false, Pid, State) ->
    Monitor = State#state.monitor,
    State1 = State#state{monitor = delete_all(Pid,Monitor)},
    do_unlink(Pid, State1),
    {ok, State1};
monitor_nodes(_, _, State) ->
    {error, State}.

delete_all(From, [From |Tail]) -> delete_all(From, Tail);
delete_all(From, [H|Tail]) ->  [H|delete_all(From, Tail)];
delete_all(_, []) -> [].

%% do unlink if we have no more references to Pid.
do_unlink(Pid, State) ->
    case lists:member(Pid, State#state.monitor) of
	true ->
	    false;
	_ ->
%	    io:format("unlink(Pid) ~p~n",[Pid]),
	    unlink(Pid)
    end.



%%%====================================================================================
%%% Send a nodeup/down messages to monitoring Pids in the own global group.
%%%====================================================================================
send_monitor([P|T], M, no_conf) -> safesend_nc(P, M), send_monitor(T, M, no_conf);
send_monitor([P|T], M, SyncState) -> safesend(P, M), send_monitor(T, M, SyncState);
send_monitor([], _, _) -> ok.

safesend(Name, {Msg, Node}) when is_atom(Name) ->
    case lists:member(Node, get_own_nodes()) of
	true ->
	    case whereis(Name) of 
		undefined ->
		    {Msg, Node};
		P when is_pid(P) ->
		    P ! {Msg, Node}
	    end;
	false ->
	    not_own_group
    end;
safesend(Pid, {Msg, Node}) -> 
    case lists:member(Node, get_own_nodes()) of
	true ->
	    Pid ! {Msg, Node};
	false ->
	    not_own_group
    end.

safesend_nc(Name, {Msg, Node}) when is_atom(Name) ->
    case whereis(Name) of 
	undefined ->
	    {Msg, Node};
	P when is_pid(P) ->
	    P ! {Msg, Node}
    end;
safesend_nc(Pid, {Msg, Node}) -> 
    Pid ! {Msg, Node}.






%%%====================================================================================
%%% Check which user is associated to the crashed process.
%%%====================================================================================
check_exit(ExitPid, Reason) ->
%    io:format("===EXIT===  ~p ~p ~n~p   ~n~p   ~n~p ~n~n",[ExitPid, Reason, get(registered_names), get(send), get(whereis_name)]),
    check_exit_reg(get(registered_names), ExitPid, Reason),
    check_exit_send(get(send), ExitPid, Reason),
    check_exit_where(get(whereis_name), ExitPid, Reason).


check_exit_reg(undefined, _ExitPid, _Reason) ->
    ok;
check_exit_reg(Reg, ExitPid, Reason) ->
    case lists:keysearch(ExitPid, 1, lists:delete(undefined, Reg)) of
	{value, {ExitPid, From}} ->
	    NewReg = lists:delete({ExitPid, From}, Reg),
	    put(registered_names, NewReg),
	    gen_server:reply(From, {error, Reason});
	false ->
	    not_found_ignored
    end.


check_exit_send(undefined, _ExitPid, _Reason) ->
    ok;
check_exit_send(Send, ExitPid, _Reason) ->
    case lists:keysearch(ExitPid, 1, lists:delete(undefined, Send)) of
	{value, {ExitPid, From, Name, Msg}} ->
	    NewSend = lists:delete({ExitPid, From, Name, Msg}, Send),
	    put(send, NewSend),
	    gen_server:reply(From, {badarg, {Name, Msg}});
	false ->
	    not_found_ignored
    end.


check_exit_where(undefined, _ExitPid, _Reason) ->
    ok;
check_exit_where(Where, ExitPid, Reason) ->
    case lists:keysearch(ExitPid, 1, lists:delete(undefined, Where)) of
	{value, {ExitPid, From}} ->
	    NewWhere = lists:delete({ExitPid, From}, Where),
	    put(whereis_name, NewWhere),
	    gen_server:reply(From, {error, Reason});
	false ->
	    not_found_ignored
    end.



%%%====================================================================================
%%% Kill any possible s_group_check processes
%%%====================================================================================
kill_s_group_check() ->
    case whereis(s_group_check) of
	undefined ->
	    ok;
	Pid ->
	    unlink(Pid),
	    s_group_check ! kill,
	    unregister(s_group_check)
    end.


%%%====================================================================================
%%% Disconnect nodes not belonging to own s_groups
%%%====================================================================================
disconnect_nodes(DisconnectNodes) ->
    lists:foreach(fun(Node) ->
			  {s, Node} ! {disconnect_node, node()},
			  global:node_disconnected(Node)
		  end,
		  DisconnectNodes).


%%%====================================================================================
%%% Disconnect nodes not belonging to own s_groups
%%%====================================================================================
force_nodedown(DisconnectNodes) ->
    lists:foreach(fun(Node) ->
			  erlang:disconnect_node(Node),
			  global:node_disconnected(Node)
		  end,
		  DisconnectNodes).


%%%====================================================================================
%%% Get the current s_groups definition
%%%====================================================================================
get_own_nodes_with_errors() ->
    case application:get_env(kernel, s_groups) of
	undefined ->
	    {ok, all};
	{ok, []} ->
	    {ok, all};
	{ok, NodeGrps} ->
            case catch config_scan(NodeGrps, publish_type) of
		{error, Error} ->
		    {error, Error};
                {ok, OwnSGroups, _} ->
                    Nodes = lists:append([Nodes||{_, _, Nodes}<-OwnSGroups]),
                    {ok, lists:usort(Nodes)}
            end
	    end.

get_own_nodes() ->
    case get_own_nodes_with_errors() of
	{ok, all} ->
	    [];
	{error, _} ->
	    [];
	{ok, Nodes} ->
	    Nodes
    end.


get_own_s_groups_with_nodes() ->
    case application:get_env(kernel, s_groups) of
	undefined ->
	    [];
	{ok, []} ->
	    [];
	{ok, NodeGrps} ->
            case catch config_scan(NodeGrps, publish_type) of
                {error,_Error} ->
                    [];
                {ok, OwnSGroups, _} ->
                    [{Group, Nodes}||{Group, _PubType, Nodes}<-OwnSGroups]
            end
    end.
%%%====================================================================================
%%% -hidden command line argument
%%%====================================================================================
publish_arg() ->
    case init:get_argument(hidden) of
	{ok,[[]]} ->
	    hidden;
	{ok,[["true"]]} ->
	    hidden;
	_ ->
	    normal
    end.


%%%====================================================================================
%%% Own group publication type and nodes
%%%====================================================================================
own_group() ->
    case application:get_env(kernel, s_groups) of
	undefined ->
	    no_group;
	{ok, []} ->
	    no_group;
	{ok, NodeGrps} ->
	    case catch config_scan(NodeGrps, publish_type) of
		{error, _} ->
		    no_group;
                {ok, OwnSGroups, _OtherSGroups} ->
                    NodesDef = lists:append([Nodes||{_, _, Nodes}<-OwnSGroups]),
                    {normal, NodesDef}
            end
    end.
 

%%%====================================================================================
%%% Help function which computes publication list
%%%====================================================================================
publish_on_nodes(normal, no_group) ->
    all;
publish_on_nodes(hidden, no_group) ->
    [];
publish_on_nodes(normal, {normal, _}) ->
    all;
publish_on_nodes(hidden, {_, Nodes}) ->
    Nodes;
publish_on_nodes(_, {hidden, Nodes}) ->
    Nodes.

%%%====================================================================================
%%% Update net_kernels publication list
%%%====================================================================================
update_publish_nodes(PubArg) ->
    update_publish_nodes(PubArg, no_group).
update_publish_nodes(PubArg, MyGroup) ->
    net_kernel:update_publish_nodes(publish_on_nodes(PubArg, MyGroup)).


%%%====================================================================================
%%% Fetch publication list
%%%====================================================================================
publish_on_nodes() ->
    publish_on_nodes(publish_arg(), own_group()).


%%%====================================================================================
%%% Draft function for registered_names, {s_group, SGroupName}handle_call({registered_names, {s_group, SGroupName}}, From, S)
%%%====================================================================================
s_group_names([], Names, _SGroupName) ->
    Names;
s_group_names([{Name, SGroupName1} | Tail], Names, SGroupName) when SGroupName1 =:= SGroupName ->
    s_group_names(Tail, [{Name, SGroupName} | Names], SGroupName);
s_group_names([{_Name, _SGroupName1} | Tail], Names, SGroupName) ->
    s_group_names(Tail, Names, SGroupName).
    
%% Caculates wrong
%%s_group_names1(_SGroupName, [], Names) ->
%%    Names;
%%s_group_names1(SGroupName, [H | T], Names) ->
%%    NameTuple = lists:keyfind(SGroupName, 2, [H | T]),
%%    case NameTuple of
%%    	 false ->
%%	       s_group_names1(SGroupName, T, Names);
%%	 _ ->
%%	       s_group_names1(SGroupName, T, [NameTuple | Names])
%%    end.
