-module(e2e_test_ffi).
-export([run_command/2]).

%% Runs a shell command in the given working directory.
%% Returns {ok, {ExitCode, OutputBinary}}.
run_command(Cmd, WorkDir) ->
    Port = open_port({spawn, binary_to_list(Cmd)}, [
        exit_status,
        stderr_to_stdout,
        binary,
        {cd, binary_to_list(WorkDir)}
    ]),
    collect_port(Port, <<>>).

collect_port(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_port(Port, <<Acc/binary, Data/binary>>);
        {Port, {exit_status, Code}} ->
            {ok, {Code, Acc}}
    after 60000 ->
        {error, nil}
    end.
