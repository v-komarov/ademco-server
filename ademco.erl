-module(ademco).
-export([start/0,server/0,wait_connect/1]).


-define(TCP_ACCEPT_TIMEOUT, 1000).
-define(TCP_RECV_TIMEOUT, 1000).
-define(CMD_OFFICER,"cd ~/django/sur;python manage.py ademco-officer ").
-define(CMD_OFFICER_SYNC,"cd ~/django/sur;python manage.py officer-sync ").
-define(CMD_GENPW,"cd ~/django/sur;python manage.py gen-pw ").
-define(CMD_CHECKDES,"cd ~/django/sur;python manage.py check-des ").


%% Сервер приема сообщений от оборудования протокол ademco



start() ->
       process_flag(trap_exit, true),
       Pid = spawn_link(?MODULE, server, []),
       io:format("server has been started ~p~n",[calendar:local_time()]),
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
    wait_connect(ListenSocket).




wait_connect(ListenSocket) ->

    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(?MODULE, wait_connect, [ListenSocket]),
    get_request(Socket, []).




%%% Чтение первого байта после соединения
get_request(Socket, BinaryList) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->

	    io:format("Connect ~p~n",[self()]),
	    case Binary of
            <<249>> -> genword(Socket);
            <<_>> -> io:format("error ~p~p~n",[calendar:local_time(),Binary]);
            true -> ok

        end,

	    get_request(Socket, [Binary|BinaryList])


    end.






sync_answer(Socket) ->
    case gen_tcp:recv(Socket,5) of
        {ok, Binary} ->
            <<Panel:4/binary,Last:1/binary>> = Binary,

            if Last == <<251>> ->
                io:format("sync ~p ~p~n",[calendar:local_time(),Panel]),

                Data = binary_to_list(Panel),
                Cmd = lists:concat([?CMD_OFFICER_SYNC,Data]),
                os:cmd(Cmd),

                io:format("~p ~p~n",[calendar:local_time(),Cmd]),

                Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
                gen_tcp:send(Socket,<<Ans/binary>>);
                    true -> ok
            end,
        get_message(Socket)
    end.





%% Герерация секретного слова - проверка валидности соединения
genword(Socket) ->
    case gen_tcp:recv(Socket,9) of
        {ok, Binary} ->
            <<Mess:8/binary,249>> = Binary,

                io:format("Generic password word ~n"),
                <<Id:4/binary,Version:4/binary>> = Mess,
                Id_panel = binary_to_list(Id),
                Ver = binary_to_list(Version),
                Cmd = lists:concat([?CMD_GENPW,Id_panel," ",Ver]),
                A = element(1, lists:split(8,os:cmd(Cmd)) ),
                io:format("~p ~p ~p~n",[calendar:local_time(),Cmd,A]),
                B = list_to_binary(A),
                Ans = <<255,B/binary,255,26>>,
                io:format("~p ~n",[Ans]),
                gen_tcp:send(Socket,<<Ans/binary>>),

                    case gen_tcp:recv(Socket,18) of
                        {ok, Bin} ->
                        <<D:17/binary,250>> = Bin,
                        <<250,DES:16/binary>> = D,
                        io:format("DES ~p~n",[binary_to_list(DES)]),
                        Cmd2 = lists:concat([?CMD_CHECKDES,Id_panel," ",binary_to_list(DES)]),
                        io:format("~p ~p~n",[calendar:local_time(),Cmd2]),
                        K = os:cmd(Cmd2),
                        io:format("CHECK ~p~n",[K]),


                        if
                           K == "True\n" ->
                           Ans2 = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
                           gen_tcp:send(Socket,<<Ans2/binary>>),
                           io:format("CONNECT OK ~n",[]),
                           get_message(Socket);

                           K == "False\n" ->
                           io:format("CONNECT ERROR ~n",[]),
                           get_request(Socket,[])

                        end

                    end

    end.






%% Прием сообщений от панели
get_message(Socket) ->

    case gen_tcp:recv(Socket, 1) of
	        {ok, Binary} ->

	    %io:format("Connect ~p~n",[Binary]),
	    case Binary of
	        <<255>> -> get_ademco(Socket);
            <<254>> -> get_officer(Socket,[]);
            <<251>> -> sync_answer(Socket);
            <<_>> -> io:format("error ~p~p~n",[calendar:local_time(),Binary]);
            true -> ok

        end,

	    get_message(Socket)


    end.







%%% Читаем с панели 21 байт %%%%
get_ademco(Socket) ->
    case gen_tcp:recv(Socket, 21) of
         {ok, Binary} ->
            Data = binary_to_list(Binary),

            Cmd = lists:concat([?CMD_OFFICER,Data]),
            os:cmd(Cmd),
            io:format("~p ~p~n",[calendar:local_time(),Data]),
            Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
            io:format("~p ~p~n",[calendar:local_time(),Cmd]),
            gen_tcp:send(Socket,<<Ans/binary>>),
            get_message(Socket)

    end.





%%%%

%%% Читаем данные по Офицеру %%%
get_officer(Socket,BinaryList) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->
        if Binary == <<254>> ->
            Data = list_to_binary(lists:reverse(BinaryList)),
            DataList = binary_to_list(Data),
	        io:format("~p ~p~n",[calendar:local_time(),DataList]),
            Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
            gen_tcp:send(Socket,<<Ans/binary>>),
            get_request(Socket,[]);
                true -> ok
        end,

	    get_officer(Socket,[Binary|BinaryList])
    end.


