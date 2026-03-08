-module(talc_npm_ffi).
-export([run_npm/2]).

%% Runs an npm command in the given working directory.
%% Returns {ok, {ExitCode, OutputBinary}} or {error, nil} on timeout.
run_npm(Args, WorkDir) ->
    Cmd = "npm " ++ binary_to_list(Args),
    Port = open_port({spawn, Cmd}, [
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
    after 120000 ->
        {error, nil}
    end.
