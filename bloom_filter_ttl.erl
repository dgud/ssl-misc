-module(bloom_filter_ttl).
-compile(export_all).

-define(E, 2.718281828459045).
-define(DEFAULT_TABLE, bloom_filter).

%%--------------------------------------------------------------------
%% API ---------------------------------------------------------------
%%--------------------------------------------------------------------

%% Create new Bloom Filter with k hashes, m bits in the filter
new(Name, K, M) ->
    process_flag(trap_exit, true),
    Size = round(math:ceil(M / 8)),
    BitField = binary:copy(<<0000>>, Size),
    case ets:whereis(?DEFAULT_TABLE) of
	undefined ->
	    ets:new(?DEFAULT_TABLE, [public, named_table, ordered_set]),
	    LastUpdate = erlang:system_time(second),
	    ets:insert(?DEFAULT_TABLE, {Name, K, 0, M, 0, LastUpdate, BitField});
	_ ->
	    already_exists
    end.

%% FIX
%% Delete Bloom Filter
delete(Name) ->
    case ets:whereis(Name) of
	undefined ->
	    no_bloom_filter;
	_ ->
	    ets:delete(bloom_filter, Name)
    end.


%% Add new element to Bloom Filter
add_elem(Name, Elem) ->
    case ets:whereis(?DEFAULT_TABLE) of
	undefined ->
	    not_initialized;
	_ ->
	    [{_, K, N, M, _, LastUpdate, BitField0}] = ets:lookup(?DEFAULT_TABLE,Name),
	    Hash = hash(Elem, K, M),
	    Time = erlang:system_time(second),
	    Elapsed = Time - LastUpdate,
	    BitField = set_bits(BitField0, Hash, Elapsed),
	    P = false_positive(K, N + 1, M),
	    ets:insert(?DEFAULT_TABLE, {Name, K, N + 1, M, P, BitField})
    end.


%% Check if Bloom Filter contains element.
%% Returns a tuple {boolean(), <probability of false positive>}
contains(Name, Elem) ->
    case ets:whereis(?DEFAULT_TABLE) of
	undefined ->
	    not_initialized;
	_ ->
	    case ets:lookup(?DEFAULT_TABLE, Name) of
		[] ->
		    bloom_filter_not_exists;
		[{_, K, _, M, P, BitField}] ->
		    Hash = hash(Elem, K, M),
		    Fun = fun (Pos) -> bit_is_set(BitField, Pos) end,
		    {lists:all(Fun, Hash), P}
	    end
    end.



visualize(Name) ->
    case ets:whereis(?DEFAULT_TABLE) of
	undefined ->
	    not_initialized;
	_ ->
	    case ets:lookup(?DEFAULT_TABLE, Name) of
		[] ->
		    bloom_filter_not_exists;
		[{_, _, _, _, _, BitField}] ->
		    visualize(BitField, [])
	    end
    end.
%%
visualize(<<>>, Acc) ->
    lists:reverse(Acc);
visualize(<<Bit:1,T/bitstring>>, Acc) ->
    visualize(T, [Bit|Acc]).


%%--------------------------------------------------------------------
%% Internal functions ------------------------------------------------
%%--------------------------------------------------------------------
bit_is_set(<<1:1,_/bitstring>>, 0) ->
    true;
bit_is_set(BitField, N) ->
    case BitField of
	<<_:N,1:1,_/bitstring>> ->
	    true;
	_ ->
	    false
    end.


set_bits(BitField, [], _) ->
    BitField;
set_bits(BitField, [H|T], Elapsed) ->
    set_bits(set_bit(BitField, H, Elapsed), T, Elapsed).


set_bit(BitField, 0, Elasped) ->
    <<_:1,TTL:3,Rest/bitstring>> = BitField,
    Seconds = ttl_to_seconds(TTL),
    case update_ttl(TTL, Elasped) of

    <<1:1,Rest/bitstring>>;
set_bit(BitField, B) ->
    <<Front:B,_:1,Rest/bitstring>>  = BitField,
    <<Front:B,1:1,Rest/bitstring>>.


age_to_seconds(<<0:1,0:1,0:1>>) ->
    34;
age_to_seconds(<<0:1,0:1,0:1>>) ->
    21;
ttl_to_seconds(<<0:1,0:1,0:1>>) ->
    13;
ttl_to_seconds(<<0:1,0:1,0:1>>) ->
    8;
ttl_to_seconds(<<0:1,0:1,0:1>>) ->
    5;
ttl_to_seconds(<<0:1,0:1,0:1>>) ->
    3;
ttl_to_seconds(<<0:1,0:1,0:1>>) ->
    2;
ttl_to_seconds(<<0:1,0:1,0:1>>) ->
    1.

update_ttl(<<0:1,0:1,0:1>>, Elasped) ->



%% Bloom filter with k hashes, m bits in the filter, and n elements
%% that have been inserted.
false_positive(K, N, M) ->
    Exp = - K * N / M,
    P0 = 1 - math:pow(?E, Exp),
    math:pow(P0, K).


false_positive_optimized(N, M) ->
    Man = math:pow(0.5, math:log(2)),
    math:pow(Man, M / N).


optimal_k(N, M) ->
    M / N * math:log(2).


%% Kirsch-Mitzenmacher-Optimization
hash(Elem, K, M) ->
    hash(Elem, K, M, []).
%%
hash(_, 0, _, Acc) ->
    Acc;
hash(Elem, K, M, Acc) ->
    H = (erlang:phash2({Elem, 0}, M) + (K - 1) * erlang:phash2({Elem, 1}, M)) rem M,
    hash(Elem, K - 1, M, [H|Acc]).


trace() ->
    dbg:tracer(),
    dbg:p(all, c),
    dbg:tpl(bloom_filter, cx).


sieve([]) ->
    [];
sieve([H|T]) ->
    List = lists:filter(fun(N) -> N rem H /= 0 end, T),
    [H|sieve(List)];
sieve(N) ->
    sieve(lists:seq(2,N)).
