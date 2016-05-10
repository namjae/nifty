%%% -------------------------------------------------------------------
%%% Copyright (c) 2015, Andreas Löscher <andreas.loscher@it.uu.se> and
%%%                     Konstantinos Sagonas <kostis@it.uu.se>
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%% -------------------------------------------------------------------

-module(nifty).
-export([%% create modules
         compile/3,
         compile/2,
         %% strings
         list_to_cstr/1,
         cstr_to_list/1,
         %% pointers
         dereference/1,
         pointer/0,
         pointer/1,
         pointer_of/2,
         pointer_of/1,
         %% enums
         enum_value/2,
         %% types
         as_type/2,
         size_of/1,
         %% memory allocation
         mem_write/1,
         mem_write/2,
         mem_read/2,
         mem_alloc/1,
         mem_copy/3,
         malloc/1,
         free/1,
         %% configuration
         get_config/0,
         get_env/0,
         %% builtin types
         get_types/0,
         %% array utilities
         array_new/2,
         array_ith/2,
         array_element/2,
         array_set/3,
         list_to_array/2,
         array_to_list/2
        ]).

-on_load(init/0).

-type reason() :: atom().
-type addr() :: integer().
-type ptr() :: {addr(), nonempty_string()}.
-type options() :: proplists:proplist().
-type cvalue() :: ptr() | integer() | float() | tuple() | {string(), integer()} | {'error', reason()}.

init() -> %% loading code from jiffy
    PrivDir = case code:priv_dir(?MODULE) of
                  {error, _} ->
                      EbinDir = filename:dirname(code:which(?MODULE)),
                      AppPath = filename:dirname(EbinDir),
                      filename:join(AppPath, "priv");
                  Path ->
                      Path
              end,
    ok = erlang:load_nif(filename:join(PrivDir, "nifty"), 0),
    load_dependencies().

load_dependencies() ->
    ok = load_dependency(rebar),
    ok = load_dependency(erlydtl).

load_dependency(Module) ->
    case code:ensure_loaded(Module) of
        {error, nofile} ->
            %% module not found
            NiftyPath = code:lib_dir(nifty, deps),
            case code:add_patha(filename:join([NiftyPath, atom_to_list(Module), "ebin"])) of
                {error, _} ->
                    {error, dependencie_not_found};
                true ->
                    ok
            end;
        {module, Module} ->
            ok
    end.

%% @doc Generates a NIF module out of a C header file and compiles it,
%% generating wrapper functions for all functions present in the header file.
%% <code>InterfaceFile</code> specifies the header file. <code>Module</code> specifies
%% the module name of the translated NIF. <code>Options</code> specifies the compile
%% options. These options are equivalent to rebar's config options.
-spec compile(string(), module(), options()) -> 'ok' | {'error', reason()} | {'warning' , {'not_complete' , [nonempty_string()]}}.
compile(InterfaceFile, Module, Options) ->
    nifty_compiler:compile(InterfaceFile, Module, Options).

%% @doc same as compile(InterfaceFile, Module, []).
-spec compile(string(), module()) -> 'ok' | {'error', reason()} | {'warning' , {'not_complete' , [nonempty_string()]}}.
compile(InterfaceFile, Module) ->
    nifty_compiler:compile(InterfaceFile, Module, []).

%% @doc Returns nifty's base types as a dict
-spec get_types() -> dict:dict().
get_types() ->
    %% builtin types:
    %%  int types ( [(short|long)] [(long|short)] int; [(signed|unsigned)] char )
    %%  float types ( float; double)
    %%  string (char *)
    %%  pointer (void *)
    dict:from_list(
      [{"signed char",{base,["char","signed","none"]}},
       {"char",{base,["char","signed","none"]}},
       {"unsigned char",{base,["char","unsigned","none"]}},
       {"short",{base,["int","signed","short"]}},
       {"unsigned short",{base,["int","unsigned","short"]}},
       {"int",{base,["int","signed","none"]}},
       {"unsigned int",{base,["int","unsigned","none"]}},
       {"long",{base,["int","signed","long"]}},
       {"unsigned long",{base,["int","unsigned","long"]}},
       {"long long",{base,["int","signed","longlong"]}},
       {"unsigned long long",{base,["int","unsigned","longlong"]}},
       {"float",{base,["float","signed","none"]}},
       {"double",{base,["double","signed","none"]}},
       %% pointers
       {"signed char *",{base,["*","char","signed","none"]}},
       {"char *",{base,["*","char","signed","none"]}},
       {"unsigned char *",{base,["*","char","unsigned","none"]}},
       {"short *",{base,["*","int","signed","short"]}},
       {"unsigned short *",{base,["*","int","unsigned","short"]}},
       {"int *",{base,["*","int","signed","none"]}},
       {"unsigned int *",{base,["*","int","unsigned","none"]}},
       {"long *",{base,["*","int","signed","long"]}},
       {"unsigned long *",{base,["*","int","unsigned","long"]}},
       {"long long *",{base,["*","int","signed","longlong"]}},
       {"unsigned long long *",{base,["*","int","unsigned","longlong"]}},
       {"float *",{base,["*","float","signed","none"]}},
       {"double *",{base,["*","double","signed","none"]}},
       {"_Bool", {typedef, "int"}},
       %% special types
       {"void *",{base,["*","void","signed","none"]}},
       {"char *",{base,["*","char","signed","none"]}}
      ]).

get_derefed_type(Type, Module) ->
    Types = Module:get_types(),
    case dict:is_key(Type, Types) of
        true ->
            ResType = nifty_types:resolve_type(Type, Types),
            {_, TypeDef} = dict:fetch(ResType, Types),
            [H|_] = TypeDef,
            case (H=:="*") orelse (string:str(H, "[")>0) of
                true ->
                    [[_|PointerDef]|Token] = lists:reverse(string:tokens(ResType, " ")),
                    NType = case PointerDef of
                                [] ->string:join(lists:reverse(Token), " ");
                                _ -> string:join(lists:reverse([PointerDef|Token]), " ")
                            end,
                    ResNType = nifty_types:resolve_type(NType, Types),
                    case dict:is_key(ResNType, Types) of
                        true ->
                            {_, DTypeDef} = dict:fetch(ResNType, Types),
                            [DH|_] = DTypeDef,
                            case DH of
                                {_, _} -> {final, ResNType};
                                _ -> case (DH=:="*") orelse (string:str(DH, "[")>0) of
                                         true -> {pointer, ResNType};
                                         false -> {final, ResNType}
                                     end
                            end;
                        false ->
                            undef
                    end;
                false ->
                    {final, ResType}
            end;
        false ->
            case lists:last(Type) of
                $* ->
                    %% pointer
                    NName = string:strip(string:left(Type, length(Type)-1)),
                    case lists:last(NName) of
                        $* ->
                            {pointer, NName};
                        _ ->
                            {final, NName}
                    end;
                _ ->
                    {error, unknown_type}
            end
    end.

%% @doc Dereference a nifty pointer
-spec dereference(ptr()) -> cvalue().
dereference(Pointer) ->
    {Address, ModuleType} = Pointer,
    [ModuleName, Type] = case string:tokens(ModuleType, ".") of
                             [NiftyType] -> ["nifty", NiftyType];
                             FullType -> FullType
                         end,
    Module = list_to_atom(ModuleName),
    %% case Module of
    %%  nifty ->
    %%      build_builtin_type(Type, Address);
    %%  _ ->
    NType = get_derefed_type(Type, Module),
    case NType of
        {pointer, PType} ->
            {raw_deref(Address), ModuleName++"."++PType};
        {final, DType} ->
            build_type(Module, DType, Address);
        undef ->
            {error, undef}
    end.
%% end.

%% build_builtin_type(DType, Address) ->
%%     case DType of
%%      "void *" -> {raw_deref(Address), "undef"};
%%      "char *" -> cstr_to_list({Address, "nifty.char *"});
%%      _ -> build_type(nifty, DType, Address)
%%     end.

build_type(Module, Type, Address) ->
    Types = Module:get_types(),
    case dict:is_key(Type, Types) of
        true ->
            RType = nifty_types:resolve_type(Type, Types),
            {Kind, Def} =  dict:fetch(RType, Types),
            case Kind of
                userdef ->
                    case Def of
                        [{struct, Name}] ->
                            Module:erlptr_to_record({Address, Name});
                        _ ->
                            {error, undef2}
                    end;
                base ->
                    case Def of
                        ["char", Sign, _] ->
                            int_deref(Address, 1, Sign);
                        ["int", Sign, L] ->
                            {_, {ShI, I, LI, LLI, _, _}} = proplists:lookup("sizes", get_config()),
                            Size = case L of
                                       "short" ->
                                           ShI;
                                       "none" ->
                                           I;
                                       "long" ->
                                           LI;
                                       "longlong" ->
                                           LLI
                                   end,
                            int_deref(Address, Size, Sign);
                        ["float", _, _] ->
                            float_deref(Address);
                        ["double", _, _] ->
                            double_deref(Address);
                        _ ->
                            {error, unknown_builtin_type}
                    end;
                _ ->
                    {error, unknown_type}
            end;
        false ->
            {error, unknown_type}
    end.

int_deref(Addr, Size, Sign) ->
    I = int_deref(lists:reverse(mem_read({Addr, "nifty.void *"}, Size)), 0),
    case Sign of
        "signed" ->
            case I > (trunc(math:pow(2, (Size*8)-1))-1) of
                true ->
                    I - trunc(math:pow(2,(Size*8)));
                false ->
                    I
            end;
        "unsigned" ->
            I
    end.

int_deref([], Acc) -> Acc;
int_deref([E|T], Acc) ->
    int_deref(T, (Acc bsl 8) + E).

%% @doc Free's the memory associated with a nifty pointer
-spec free(ptr()) -> 'ok'.
free({Addr, _}) ->
    raw_free(Addr).

%% @doc Allocates the specified amount of bytes and returns a pointer to the allocated memory
-spec malloc(non_neg_integer()) -> ptr().
malloc(Size) ->
    mem_alloc(Size).

%%% NIF Functions
raw_free(_) ->
    erlang:nif_error(nif_library_not_loaded).

float_deref(_) ->
    erlang:nif_error(nif_library_not_loaded).

float_ref(_) ->
    erlang:nif_error(nif_library_not_loaded).

double_deref(_) ->
    erlang:nif_error(nif_library_not_loaded).

double_ref(_) ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Converts an erlang string into a 0 terminated C string and returns a nifty pointer to it
-spec list_to_cstr(string()) -> ptr().
list_to_cstr(_) ->
    erlang:nif_error(nif_library_not_loaded).
%% @doc Converts a nifty pointer to a 0 terminated C string into a erlang string.
-spec cstr_to_list(ptr()) -> string().
cstr_to_list(_) ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc size of a base type, no error handling
-spec size_of(nonempty_string()) -> integer() | undef.
size_of(Type) ->
    Types = get_types(),
    case dict:is_key(Type, Types) of
        true ->
            %% builtin
            case dict:fetch(Type, Types) of
                {base, ["char", _, _]} ->
                    1;
                {base, ["int", _, L]} ->
                    {_, {ShI, I, LI, LLI, _, _}} = proplists:lookup("sizes", get_config()),
                    case L of
                        "short" ->
                            ShI;
                        "none" ->
                            I;
                        "long" ->
                            LI;
                        "longlong" ->
                            LLI
                    end;
                {base, ["float", _, _]}->
                    {_, {_, _, _, _, Fl, _}} = proplists:lookup("sizes", get_config()),
                    Fl;
                {base, ["double", _, _]}->
                    {_, {_, _, _, _, _, Dbl}} = proplists:lookup("sizes", get_config()),
                    Dbl;
                {base, ["*"|_]} ->
                    {_, {_, P}} = proplists:lookup("arch", get_config()),
                    P
            end;
        false ->
            %% full referenced
            case string:tokens(Type, ".") of
                ["nifty", TypeName] ->
                    %% builtin
                    size_of(TypeName);
                [ModuleName, TypeName] ->
                    Mod = list_to_atom(ModuleName),
                    case {module, Mod}=:=code:ensure_loaded(Mod) andalso
                        proplists:is_defined(size_of, Mod:module_info(exports)) of
                        true ->
                            Mod:size_of(TypeName);
                        false ->
                            undef
                    end;
                _ ->
                    undef
            end
    end.

%% @doc Returns the integer value associated with an enum alias
-spec enum_value(atom(), nonempty_string() | atom()) -> integer() | undef.
enum_value(Module, Value) when is_atom(Value) ->
    enum_value(Module, atom_to_list(Value));
enum_value(Module, Value) ->
    case {module, Module}=:=code:ensure_loaded(Module) andalso
        proplists:is_defined(get_enum_aliases, Module:module_info(exports)) of
        true ->
            case proplists:lookup(Value, Module:get_enum_aliases()) of
                {Value, IntValue} -> IntValue;
                _ -> undef
            end;
        false ->
            undef
    end.


%% @doc Returns a pointer to a memory area that is the size of a pointer
-spec pointer() -> ptr().
pointer() ->
    {_, Size} = proplists:get_value("arch", nifty:get_config()),
    mem_alloc(Size).

referred_type(Type) ->
    case lists:last(Type) of
        $* -> Type++"*";
        _ -> Type++" *"
    end.

%% @doc Returns a pointer to the specified <code>Type</code>. This function allocates memory of <b>sizeof(</b><code>Type</code><b>)</b>
-spec pointer(nonempty_string()) -> ptr() | undef.
pointer(Type) ->
    case size_of(Type) of
        undef -> undef;
        S -> as_type(mem_alloc(S), referred_type(Type))
    end.

%% @doc Returns a pointer to the given pointer
-spec pointer_of(ptr()) -> ptr() | undef.
pointer_of({_, Type} = Ptr) ->
    pointer_of(Ptr, Type).

%% @doc Returns a pointer to the <code>Value</code> with the type <code>Type</code>
-spec pointer_of(term(), string()) -> ptr() | undef.
pointer_of(Value, Type) ->
    case string:right(Type, 1) of
        "*" ->
            %% pointer
            {Addr, VType} = Value,
            case VType=:=Type of
                true ->
                    {_, Size} = proplists:get_value("arch", nifty:get_config()),
                    {NAddr, _} = int_constr(Addr, Size),
                    {NAddr, Type++"*"};
                false ->
                    undef
            end;
        _ ->
            %% something else
            case string:tokens(Type, ".") of
                [_] ->
                    %% base types
                    builtin_pointer_of(Value, Type);
                ["nifty", T] ->
                    %% base type
                    builtin_pointer_of(Value, T);
                [ModuleName, T] ->
                    case builtin_pointer_of(Value, T) of
                        undef ->
                            %% no base type, try the module
                            %% resolve type and try again
                            Module = list_to_atom(ModuleName),
                            Types = Module:get_types(),
                            case nifty_types:resolve_type(T, Types) of
                                undef ->
                                    %% can (right now) only be a struct
                                    Module:record_to_erlptr(Value);
                                ResT ->
                                    case builtin_pointer_of(Value, ResT) of
                                        undef ->
                                            %% can (right now) only be a struct
                                            Module:record_to_erlptr(Value);
                                        Ptr ->
                                            Ptr
                                    end
                            end;
                        Ptr ->
                            Ptr
                    end
            end
    end.

builtin_pointer_of(Value, Type) ->
    Types = get_types(),
    case dict:is_key(Type, Types) of
        true ->
            case dict:fetch(Type, Types) of
                {base, ["float", _, _]}->
                    float_ref(Value);
                {base, ["double", _, _]}->
                    double_ref(Value);
                _ -> case size_of(Type) of
                         undef ->
                             undef;
                         Size ->
                             case is_integer(Value) of
                                 true ->
                                     as_type(int_constr(Value, Size), "nifty."++Type++" *");
                                 false ->
                                     undef
                             end
                     end
            end;
        false ->
            undef
    end.

int_constr(Value, Size) ->
    mem_write(int_constr(Value, Size, [])).

int_constr(_, 0, Acc) ->
    lists:reverse(Acc);
int_constr(Val, S, Acc) ->
    R = Val rem 256,
    V = Val div 256,
    int_constr(V, S-1, [R|Acc]).

raw_deref(_) ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Writes the <code>Data</code> to the memory area pointed to by <code>Ptr</code> and returns a the pointer; the list elements are interpreted as byte values
-spec mem_write(ptr(), binary() | list()) -> ptr().
mem_write({Addr, _} = Ptr, Data) ->
    {Addr, _} = case is_binary(Data) of
                    true ->
                        mem_write_binary(Data, Ptr);
                    false ->
                        mem_write_list(Data, Ptr)
                end,
    Ptr.

%% @doc Writes the <code>Data</code> to memory and returns a nifty pointer to it; the list elements are interpreted as byte values
-spec mem_write(binary() | list()) -> ptr().
mem_write(Data) ->
    case is_binary(Data) of
        true ->
            mem_write_binary(Data, mem_alloc(byte_size(Data)));
        false ->
            mem_write_list(Data, mem_alloc(length(Data)))
    end.

-spec mem_write_list(list(), ptr()) -> ptr().
mem_write_list(_, _) ->
    erlang:nif_error(nif_library_not_loaded).

-spec mem_write_binary(binary(), ptr()) -> ptr().
mem_write_binary(_, _) ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Reads <code>X2</code> bytes from the pointer <code>X1</code> and returns it as list
-spec mem_read(ptr(), integer()) -> list().
mem_read(_, _) ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Allocates <code>X1</code> bytes and returns a pointer to it
-spec mem_alloc(non_neg_integer()) -> ptr().
mem_alloc(_) ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Copies <code>Size</code> bytes from <code>Ptr1</code> to <code>Ptr2</code>
-spec mem_copy(ptr(), ptr(), non_neg_integer()) -> ok.
mem_copy(_, _, _) ->
    erlang:nif_error(nif_library_not_loaded).

%% config
%% @doc Returns the platform specific configuration of nifty
-spec get_config() -> proplists:proplist().
get_config() ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Returns erlangs NIF environment
-spec get_env() -> {integer(), nonempty_string()}.
get_env() ->
    erlang:nif_error(nif_library_not_loaded).

%% @doc Casts a pointer to <code>Type</code>; returns <code>undef</code>
%%  if the specified type is invalid
-spec as_type(ptr(), nonempty_string()) -> ptr() | undef.
as_type({Address, _} = Ptr, Type) ->
    BaseType = case string:tokens(Type, "*") of
                   [T] ->
                       string:strip(T);
                   _ ->
                       []
               end,
    Types = get_types(),
    case dict:is_key(BaseType, Types) of
        true ->
            {Address, "nifty."++Type};
        false ->
            case string:tokens(Type, ".") of
                ["nifty", TypeName] ->
                    %% builtin type
                    as_type(Ptr, TypeName);
                [ModuleName, TypeName] ->
                    Mod = list_to_atom(ModuleName),
                    case {module, Mod}=:=code:ensure_loaded(Mod) andalso
                        proplists:is_defined(get_types, Mod:module_info(exports)) of
                        true ->
                            %% resolve and build but we are looking for the basetype
                            %% if the base type is defined or basetype * we are allowing
                            %% casting
                            [RBUType] = string:tokens(TypeName, "*"),
                            RBType = string:strip(RBUType),
                            case nifty_types:resolve_type(RBType, Mod:get_types()) of
                                undef ->
                                    case nifty_types:resolve_type(RBType++" *", Mod:get_types()) of
                                        undef ->
                                            %% unknown type
                                            undef;
                                        _ ->
                                            %% pointer to incomplete type
                                            {Address, Type}
                                    end;
                                _ ->
                                    %% pointer to complete type
                                    {Address, Type}
                            end;
                        _ ->
                            %% module part of the type is not a nifty module
                            undef
                    end;
                _ ->
                    %% malformed type
                    undef
            end
    end.

%% @doc Allocates an array with <code>Size</code> elements of type <code>Type</code>
-spec array_new(nonempty_string(), non_neg_integer()) -> ptr().
array_new(Type, Size) ->
    {Addr, _} = malloc(size_of(Type)*Size),
    {Addr, referred_type(Type)}.

array_element_type({_, Type}) ->
    string:strip(lists:droplast(Type)).

%% @doc returns a pointer to the element at position <code>Index</code> of the array
-spec array_ith(ptr(), integer()) -> ptr().
array_ith({Addr, Type} = Array, Index) ->
    %% Type must be a pointer of the stored type
    Offset = size_of(array_element_type(Array)),
    {Addr + (Index * Offset), Type}.

%% @doc returns the element at position <code>Index</code> of the array
-spec array_element(ptr(), integer()) -> cvalue().
array_element(Array, Index) ->
    dereference(array_ith(Array, Index)).

%% @doc updates the element at position <code>Index</code> of the array
-spec array_set(ptr(), term(), integer()) -> ok.
array_set(Array, Value, Index) ->
    ElementPtr = array_ith(Array, Index),
    NewElement = pointer_of(Value, array_element_type(Array)),
    Size = size_of(array_element_type(Array)),
    mem_copy(NewElement, ElementPtr, Size),
    free(NewElement).

-spec array_to_list(ptr(), non_neg_integer()) -> list(cvalue()).
array_to_list(Array, N) ->
    [array_element(Array, I) || I <- lists:seq(0,N)].

-spec list_to_array(list(), nonempty_string()) -> ptr().
list_to_array(List, Type) ->
    N = length(List),
    A = array_new(Type, N),
    _ = [array_set(A, E, I) || { I, E} <- lists:zip(lists:seq(0,N-1), List) ],
    A.
