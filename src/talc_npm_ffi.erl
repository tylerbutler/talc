-module(talc_npm_ffi).
-export([run_npm/3]).

%% Runs an npm command with argv-style execution in the given working directory.
%% Returns {ok, {ExitCode, OutputBinary}}, {error, run_not_found} if npm is
%% missing, or {error, run_timeout} on timeout.
run_npm(Command, Args, WorkDir) ->
    case os:find_executable("npm") of
        false ->
            {error, run_not_found};
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
            OsPid = case erlang:port_info(Port, os_pid) of
                {os_pid, Pid} -> Pid;
                _ -> undefined
            end,
            Deadline = erlang:monotonic_time(millisecond) + 120000,
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
