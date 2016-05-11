-module(ademco).
-export([start/0,server/0,wait_connect/2]).


-define(TCP_ACCEPT_TIMEOUT, 1000).
-define(TCP_RECV_TIMEOUT, 1000).



%% Сервер приема сообщений от оборудования протокол ademco



start() ->
       process_flag(trap_exit, true),
       Pid = spawn_link(?MODULE, server, []),
       io:format("server has been started ~p~n",[calendar:local_time()]),
	   register(?MODULE, Pid),
	   loop(Pid).



loop(Pid) ->
    receive
        {'EXIT', Pid, _} ->
            timer:sleep(20000),
            start()

    end,
    loop(Pid).



server() ->
    {ok, ListenSocket} = gen_tcp:listen(11112, [binary, {active, false}]),
    wait_connect(ListenSocket, 0).




wait_connect(ListenSocket, Count) ->

%%    case gen_tcp:accept(ListenSocket, ?TCP_ACCEPT_TIMEOUT) of
%%         {ok, Socket} ->
%%            io:format("Connect ~p~n",[Count]),
%%            spawn(?MODULE, wait_connect, [ListenSocket, Count+1]),
%%            get_request(Socket, [], Count);
%%         {error, timeout} ->

%%    end.

    {ok, Socket} = gen_tcp:accept(ListenSocket),
    %% io:format("Connect ~p~n",[Count]),
    spawn(?MODULE, wait_connect, [ListenSocket, Count+1]),
    get_request(Socket, [], Count).




get_request(Socket, BinaryList, Count) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->

	    %% io:format("Connect ~p~n",[Count]),
	    if Binary == <<255>> -> get_ademco(Socket,Count);
		    true -> ok
	    end,
        if Binary == <<253>> -> answer(Socket,Count);
            true -> ok
        end,
        if Binary == <<254>> -> get_officer(Socket,[],Count);
            true -> ok
        end,

	    get_request(Socket, [Binary|BinaryList], Count)


    end.





answer(Socket,Count) ->
    case gen_tcp:recv(Socket,5) of
        {ok, Binary} ->
            <<_:4/binary,Last:1/binary>> = Binary,

            if Last == <<253>> ->
                io:format("1A OK ~p~n",[calendar:local_time()]),
                Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
                gen_tcp:send(Socket,<<Ans/binary>>);
                    true -> ok
            end,
        get_request(Socket,[], Count)
    end.





%%% Читаем с панели 16 байт %%%%
get_ademco(Socket, Count) ->
    case gen_tcp:recv(Socket, 16) of
         {ok, Binary} ->
            Data = binary_to_list(Binary),

            Cmd = lists:concat(["/usr/bin/psql db_sentry sur -h 127.0.0.1 -c \"SELECT getademco\(\'",Data,"\'\)\""]),
            os:cmd(Cmd),
            io:format("~p ~p~n",[calendar:local_time(),Data]),
            Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
            gen_tcp:send(Socket,<<Ans/binary>>),
            get_request(Socket,[], Count)

    end.



%%%%

%%% Читаем данные по Офицеру %%%
get_officer(Socket,BinaryList,Count) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->
        if Binary == <<254>> ->
            Data = list_to_binary(lists:reverse(BinaryList)),
            DataList = binary_to_list(Data),
	        io:format("~p ~p~n",[calendar:local_time(),DataList]),
            Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
            gen_tcp:send(Socket,<<Ans/binary>>),
            get_request(Socket,[], Count);
                true -> ok
        end,

	    get_officer(Socket,[Binary|BinaryList],Count)
    end.


