-module(talc_interface_ffi).
-export([run_gleam_export/1, random_id/0]).

%% Runs `gleam export package-interface --out OutPath` via argv-style execution.
%% Returns {ok, {ExitCode, OutputBinary}}, {error, run_not_found} if gleam is
%% missing, or {error, run_timeout} on timeout.
run_gleam_export(OutPath) ->
    case os:find_executable("gleam") of
        false ->
            {error, run_not_found};
        GleamPath ->
            Port = open_port(
                {spawn_executable, GleamPath},
                [
                    {args, ["export", "package-interface", "--out", binary_to_list(OutPath)]},
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
    after 60000 ->
        port_close(Port),
        {error, run_timeout}
    end.

random_id() ->
    list_to_binary(integer_to_list(erlang:unique_integer([positive]))).
