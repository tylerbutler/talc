-module(talc_npm_ffi).
-export([run_npm/3]).

%% Runs an npm command with argv-style execution in the given working directory.
%% Returns {ok, {ExitCode, OutputBinary}} or {error, nil} on timeout or if npm is not found.
run_npm(Command, Args, WorkDir) ->
    case os:find_executable("npm") of
        false ->
            {error, nil};
        NpmPath ->
            Port = open_port(
                {spawn_executable, NpmPath},
                [
                    {args, [Command | Args]},
                    {cd, binary_to_list(WorkDir)},
                    exit_status,
                    stderr_to_stdout,
                    binary
                ]
            ),
            collect_port(Port, [])
    end.

collect_port(Port, Chunks) ->
    receive
        {Port, {data, Data}} ->
            collect_port(Port, [Data | Chunks]);
        {Port, {exit_status, Code}} ->
            Output = iolist_to_binary(lists:reverse(Chunks)),
            {ok, {Code, Output}}
    after 120000 ->
        port_close(Port),
        {error, nil}
    end.
