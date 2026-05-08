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
            OsPid = case erlang:port_info(Port, os_pid) of
                {os_pid, Pid} -> Pid;
                _ -> undefined
            end,
            Deadline = erlang:monotonic_time(millisecond) + 60000,
            collect_port(Port, OsPid, Deadline, [])
    end.

collect_port(Port, OsPid, Deadline, Chunks) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    if
        Remaining =< 0 ->
            kill_port(Port, OsPid),
            {error, run_timeout};
        true ->
            receive
                {Port, {data, Data}} ->
                    collect_port(Port, OsPid, Deadline, [Data | Chunks]);
                {Port, {exit_status, Code}} ->
                    Output = iolist_to_binary(lists:reverse(Chunks)),
                    {ok, {Code, Output}}
            after Remaining ->
                kill_port(Port, OsPid),
                {error, run_timeout}
            end
    end.

kill_port(Port, OsPid) ->
    port_close(Port),
    case OsPid of
        undefined -> ok;
        Pid ->
            %% OsPid comes from erlang:port_info/2, so integer_to_list is safe.
            os:cmd("kill -9 " ++ integer_to_list(Pid)),
            ok
    end.

random_id() ->
    list_to_binary(integer_to_list(erlang:unique_integer([positive]))).
