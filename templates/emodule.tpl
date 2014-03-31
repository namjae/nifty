-module({{module}}).
-export([{% with fn=functions|fetch_keys %}{% for name in fn %}
	'{{name}}'/{{ functions|fetch:name|getNth:2|length }},{% endfor %}{% endwith %}
	get_types/0,
	erlptr_to_record/1,
	record_to_erlptr/1,
	new/1
	]).

-compile(nowarn_unused_record).

-define(TYPES, {{types}}).

-on_load(init/0).

-type addr() :: integer().
-type typename() :: string.
-type ptr() :: {addr(), typename()}.

init() -> %% loading code from jiffy
    PrivDir = case code:priv_dir(?MODULE) of
        {error, _} ->
            EbinDir = filename:dirname(code:which(?MODULE)),
            AppPath = filename:dirname(EbinDir),
            filename:join(AppPath, "priv");
        Path ->
            Path
    end,
    erlang:load_nif(filename:join(PrivDir, "{{module}}_nif"), 0).

{% with fn=functions|fetch_keys %}{% for name in fn %}'{{name}}'({% with arguments=symbols|fetch:name %}{% for argument in arguments %}{% if argument|is_argument %}_{% if not forloop.last %},{%endif%}{% endif %}{% endfor %}{% endwith %}) ->
	erlang:nif_error(nif_library_not_loaded).
{% endfor %}{% endwith %}
%%% defines
{% with type_keys=types|fetch_keys %}{% for type in type_keys %}{% with kind=types|fetch:type|getNth:1 %}{% if kind=="struct" %}
-record({{type}}, {
	{% with fields=types|fetch:type|getNth:2 %}{% for _, name, t, __ in fields %}{{name}}{% if not forloop.last %},{% endif %}{% endfor %}{% endwith %}
	}).
{% endif %}{% endwith%}{% endfor %}{% endwith %}
%%% static

-spec erlptr_to_record(ptr()) -> tuple().
erlptr_to_record(_) ->
    erlang:nif_error(nif_library_not_loaded).

-spec record_to_erlptr(tuple()) -> ptr().
record_to_erlptr(_) ->
    erlang:nif_error(nif_library_not_loaded).

-spec get_types() -> dict().
get_types() -> ?TYPES.

-spec new(typename()) -> term().
new(_) ->
    erlang:nif_error(nif_library_not_loaded).
