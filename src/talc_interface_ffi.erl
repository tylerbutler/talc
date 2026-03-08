-module(talc_interface_ffi).
-export([run_gleam_export/1, random_id/0]).

run_gleam_export(OutPath) ->
    Cmd = "gleam export package-interface --out " ++ binary_to_list(OutPath),
    Port = open_port({spawn, Cmd}, [exit_status, stderr_to_stdout, binary]),
    collect_port(Port).

collect_port(Port) ->
    receive
        {Port, {exit_status, Code}} ->
            {ok, Code};
        {Port, {data, _}} ->
            collect_port(Port)
    after 60000 ->
        {error, nil}
    end.

random_id() ->
    list_to_binary(integer_to_list(erlang:unique_integer([positive]))).
