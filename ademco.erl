-module(ademco).
-export([start/0,server/1,wait_connect/1,dog/1,check_proc/1]).


-define(DEBUG,true).

-ifdef(DEBUG).
-define(CMD_OFFICER,"cd ~/django/sur;python manage.py ademco-officer ").
-define(CMD_OFFICER_SYNC,"cd ~/django/sur;python manage.py officer-sync ").
-define(CMD_GENPW,"cd ~/django/sur;python manage.py gen-pw ").
-define(CMD_CHECKDES,"cd ~/django/sur;python manage.py check-des ").
-define(CMD_GETCOM,"cd ~/django/sur;python manage.py get-command ").
-else.
-define(CMD_OFFICER,"cd /srv/django/sur;python manage.py ademco-officer ").
-define(CMD_OFFICER_SYNC,"cd /srv/django/sur;python manage.py officer-sync ").
-define(CMD_GENPW,"cd /srv/django/sur;python manage.py gen-pw ").
-define(CMD_CHECKDES,"cd /srv/django/sur;python manage.py check-des ").
-define(CMD_GETCOM,"cd /srv/django/sur;python manage.py get-command ").
-endif.

-define(TCP_ACCEPT_TIMEOUT, 1000).
-define(TCP_RECV_TIMEOUT, 1000).


%% Сервер приема сообщений от оборудования протокол ademco





start() ->

       Tabid = ets:new(aliveTab,[ordered_set,public]),

       process_flag(trap_exit, true),
       Pid = spawn_link(?MODULE, server, [Tabid]),
       register(main,Pid),
       io:format("server has been started ~p ~w~n",[calendar:local_time(),Pid]),
       loop(Pid).




loop(Pid) ->
    receive
        {'EXIT', Pid, _} ->
            timer:sleep(20000),
            start()
    end,
    loop(Pid).






%% Наблюдение за состоянием связи
dog(Tabid) ->
    receive
        {alive,Pid} ->
            ets:insert(Tabid,{Pid,erlang:timestamp()}),
            io:format("~w~n",[ets:match_object(Tabid,{'_','_'})]),
            io:format("alive ~w~n",[Pid]),
            check_proc(Tabid);
        _Other -> dog(Tabid)
    end,
    dog(Tabid).





check_proc(Tabid) ->

    lists:map(
       fun(Elem) ->
          io:format("~w~n",[timer:now_diff(erlang:timestamp(),element(2,Elem))/1000]),
          A = timer:now_diff(erlang:timestamp(),element(2,Elem)) / 1000,
          if A  > 86400 ->
            ets:match_delete(Tabid,{element(1,Elem),'_'}),
            exit(element(1,Elem),timeout);
            true -> ok
          end
       end, ets:match_object(Tabid,{'_','_'})  ),

    dog(Tabid).





server(Tabid) ->
    process_flag(trap_exit, true),
    Pid2 = spawn_link(?MODULE, dog, [Tabid]),
    register(dw,Pid2),
    io:format("dog has been started ~p ~w~n",[calendar:local_time(),Pid2]),
    {ok, ListenSocket} = gen_tcp:listen(11114, [binary, {active, false}]),
    wait_connect(ListenSocket).





wait_connect(ListenSocket) ->

    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(?MODULE, wait_connect, [ListenSocket]),
    get_request(Socket, []).





%%% Чтение первого байта после соединения
get_request(Socket, BinaryList) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->

	    io:format("Connect ~w~n",[self()]),
	    case Binary of
            <<249>> -> genword(Socket);
            <<_>> -> io:format("error ~p~p ~w~n",[calendar:local_time(),Binary,self()]);
            true -> ok

        end,

	    get_request(Socket, [Binary|BinaryList])


    end.






sync_answer(Socket,Panell) ->
    case gen_tcp:recv(Socket,5) of
        {ok, Binary} ->
            <<Panel:4/binary,Last:1/binary>> = Binary,

            if Last == <<251>> ->
                io:format("sync ~p ~p ~w~n",[calendar:local_time(),Panel,self()]),

                Data = binary_to_list(Panel),
                Cmd = lists:concat([?CMD_OFFICER_SYNC,Data]),
                os:cmd(Cmd),

                io:format("~p ~p ~w~n",[calendar:local_time(),Cmd,self()]),

                dw ! {alive,self()},

                Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
                gen_tcp:send(Socket,<<Ans/binary>>);
                    true -> ok
            end,
        get_message(Socket,Panell)
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
                io:format("~p ~p ~p ~w~n",[calendar:local_time(),Cmd,A,self()]),
                B = list_to_binary(A),
                Ans = <<255,B/binary,255,26>>,
                io:format("~p ~w ~n",[Ans,self()]),
                gen_tcp:send(Socket,<<Ans/binary>>),

                    case gen_tcp:recv(Socket,18) of
                        {ok, Bin} ->
                        <<D:17/binary,250>> = Bin,
                        <<250,DES:16/binary>> = D,
                        io:format("DES ~p ~w~n",[binary_to_list(DES),self()]),
                        Cmd2 = lists:concat([?CMD_CHECKDES,Id_panel," ",binary_to_list(DES)]),
                        io:format("~p ~p ~w~n",[calendar:local_time(),Cmd2,self()]),
                        K = os:cmd(Cmd2),
                        io:format("CHECK ~p ~w~n",[K,self()]),


                        if
                           K == "True\n" ->
                               Ans2 = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
                               gen_tcp:send(Socket,<<Ans2/binary>>),
                               io:format("CONNECT OK ~w~n",[self()]),
                               get_message(Socket,Id_panel);

                           K == "False\n" ->
                               io:format("CONNECT ERROR ~w~n",[self()]),
                               get_request(Socket,[])

                        end

                    end

    end.













%% Прием сообщений от панели
get_message(Socket,Panell) ->


    case gen_tcp:recv(Socket, 1,5000) of
	        {ok, Binary} ->

                %io:format("Connect ~p~n",[Binary]),
                case Binary of
                    <<255>> -> get_ademco(Socket,Panell);
                    <<247>> -> get_listademco(Socket,[],Panell);
                    <<254>> -> get_officer(Socket,[],Panell);
                    <<251>> -> sync_answer(Socket,Panell);
                    <<_>> -> io:format("error ~p~p ~w~n",[calendar:local_time(),Binary,self()]);
                    true -> ok

                end;

            {error, timeout} ->

                %%%% Передача команды в панель! НАЧАЛО %%%%
                %%%% Если 5 секунд нет от панели сообщений , то передаем команду в панель! %%%%
                Cmd = lists:concat([?CMD_GETCOM,Panell]),
                os:cmd(Cmd),
                io:format("GETCOMMAND ~p~n",[Cmd]),




                %%%%% Передача в панель КОНЕЦ %%%%%
                get_message(Socket,Panell)



    end.






%%% Читаем с панели 21 байт %%%%
get_ademco(Socket,Panell) ->
    case gen_tcp:recv(Socket, 21) of
         {ok, Binary} ->
            Data = binary_to_list(Binary),

            Cmd = lists:concat([?CMD_OFFICER,Data]),
            os:cmd(Cmd),
            io:format("~p ~p ~w~n",[calendar:local_time(),Data,self()]),
            Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
            io:format("~p ~p ~w~n",[calendar:local_time(),Cmd,self()]),
            gen_tcp:send(Socket,<<Ans/binary>>),
            get_message(Socket,Panell)

    end.






%%%% Читаем с панели пакет сообщений %%%%
get_listademco(Socket,BinaryList,Panell) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->
        if Binary == <<247>> ->
            run_listademco(Socket,lists:reverse(BinaryList),Panell);
                true -> ok
        end,

	    get_listademco(Socket,[Binary|BinaryList],Panell)
    end.





%%%% Выполнение пакета сообщений %%%%
run_listademco(Socket,DataList,Panell) ->

    if length(DataList) < 21 ->
        Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
        gen_tcp:send(Socket,<<Ans/binary>>),
        get_message(Socket,Panell);
                true -> ok
    end,
    MessList = lists:split(21,DataList),
    H = element(1,MessList),

    Data = list_to_binary(H),
    Cmd = lists:concat([?CMD_OFFICER,binary_to_list(Data)]),
    os:cmd(Cmd),
    io:format("~p ~p ~w~n",[calendar:local_time(),Cmd,self()]),

    T = element(2,MessList),
    run_listademco(Socket,T,Panell).






%%% Читаем данные по Офицеру %%%
get_officer(Socket,BinaryList,Panell) ->
    case gen_tcp:recv(Socket, 1) of
	{ok, Binary} ->
        if Binary == <<254>> ->
            Data = list_to_binary(lists:reverse(BinaryList)),
            DataList = binary_to_list(Data),
	        io:format("~p ~p ~w~n",[calendar:local_time(),DataList,self()]),
            Ans = list_to_binary([<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>,<<26>>]),
            gen_tcp:send(Socket,<<Ans/binary>>),
            get_request(Socket,[]);
                true -> ok
        end,

	    get_officer(Socket,[Binary|BinaryList],Panell)
    end.


