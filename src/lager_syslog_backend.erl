%% Copyright (c) 2011-2012 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

%% @doc Syslog backend for lager.

-module(lager_syslog_backend).

-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
        code_change/3]).

-export([config_to_id/1, ensure_new_config_format/1]).

-ifdef(TEST).
-export([parse_level/1, validate_config/1]).
-endif.

-record(state, {level, handle, id, formatter,formatter_config}).

-include_lib("lager/include/lager.hrl").
-include("defaults.hrl").


%% convert the configuration into a hopefully unique gen_event ID
config_to_id(Config) ->
    case validate_config(Config) of
        {ok, ValidatedConfig} ->
            config_to_id_impl(ValidatedConfig);
        Error ->
            throw(Error)
    end.

%% make sure the config is in the new format (proplists)q
ensure_new_config_format([Ident, Facility, Level]) when is_list(Ident),
                                                    is_atom(Facility),
                                                    is_atom(Level) ->
    ?INT_LOG(warning, "Old config format, consider switching to proplists", []),
    [
        {identity, Ident}, {facility, Facility},
        {level, Level}
    ];
ensure_new_config_format([Ident, Facility, Level, {Formatter, FormatterConfig}]) when is_list(Ident),
                                                                is_atom(Facility),
                                                                is_atom(Level),
                                                                is_atom(Formatter) ->
    ?INT_LOG(warning, "Old config format, consider switching to proplists", []),
    [
        {identity, Ident}, {facility, Facility}, {level, Level}, 
        {formatter, Formatter}, {formatter_config, FormatterConfig}
    ];
ensure_new_config_format(Config) when is_list(Config) ->
    case lists:all(fun
            ({K,_V}) -> is_atom(K);
            (_) -> false
        end, Config) of
        true ->
            Config;
        false ->
            ?INT_LOG(error, "Config is not a proplist", []),
            throw({error, invalid_config})
    end;
ensure_new_config_format(_Config) ->
    ?INT_LOG(error, "Config is not a proplist", []),
    throw({error, invalid_config}).

%% @private
init(Config) ->
    case validate_config(Config) of
        {ok, ValidatedConfig} ->
            init_syslog_backend(ValidatedConfig);
        Error ->
            Error
    end.

%% @private
handle_call(get_loglevel, #state{level=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    try parse_level(Level) of
        {ok, Lvl} ->
            {ok, ok, State#state{level=Lvl}}
    catch
        _:_ ->
            {ok, {error, bad_log_level}, State}
    end;
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event({log, Level, {_Date, _Time}, [_LevelStr, Location, Message]},
        #state{level=LogLevel} = State) when Level =< LogLevel ->
    syslog:log(State#state.handle, convert_to_syslog_level(Level), [Location, Message]),
    {ok, State};
handle_event({log, Message}, #state{level=Level,formatter=Formatter,formatter_config=FormatConfig} = State) ->
    case lager_util:is_loggable(Message, Level, State#state.id) of
        true ->
            syslog:log(State#state.handle, convert_to_syslog_level(lager_msg:severity_as_int(Message)), [Formatter:format(Message, FormatConfig)]),
            {ok, State};
        false ->
            {ok, State}
    end;
handle_event(_Event, State) ->
    {ok, State}.

%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


validate_config(Config) ->
    CorrectFormat = ensure_new_config_format(Config),
    validate_config_impl(CorrectFormat, []).

validate_config_impl([], Acc) ->
    check_mandatory_fields([identity, facility], Acc);
validate_config_impl([{identity, Identity}|Tail], Acc) ->
    case is_list(Identity) of
        false ->
            {error, {bad_config, "Invalid identity", Identity}};
        true ->
             validate_config_impl(Tail, [{identity, Identity}|Acc])
    end;
validate_config_impl([{level, Level}|Tail], Acc) ->
    case parse_level(Level) of
        {ok, Mask} ->
            validate_config_impl(Tail, [{level, Mask}|Acc]);
        _ ->
            {error, {bad_config, "Invalid loglevel", Level}}
    end;
validate_config_impl([{facility, Facility}|Tail], Acc) ->
    case is_atom(Facility) of
        false ->
            {error, {bad_config, "Invalid facility", Facility}};
        true ->
            validate_config_impl(Tail, [{facility, Facility}|Acc])
    end;
validate_config_impl([{formatter, Formatter}|Tail], Acc) ->
    case is_atom(Formatter) of
        false ->
            {error, {bad_config, "Invalid formatter", Formatter}};
        true ->
            validate_config_impl(Tail, [{formatter, Formatter}|Acc])
    end;
validate_config_impl([{formatter_config, FormatterConfig}|Tail], Acc) ->
    case is_list(FormatterConfig) of
        false ->
            {error, {bad_config, "Invalid formatter config", FormatterConfig}};
        true ->
            validate_config_impl(Tail, [{formatter_config, FormatterConfig}|Acc])
    end;
validate_config_impl([{handler_id, HandlerId}|Tail], Acc) ->
    case is_atom(HandlerId) or is_list(HandlerId) of
        false ->
            {error, {bad_config, "Invalid handler_id", HandlerId}};
        true ->
            validate_config_impl(Tail, [{handler_id, HandlerId}|Acc])
    end;
validate_config_impl([Other|_Tail], _Acc) ->
    {error, {bad_config, "Unknown option", Other}}.

check_mandatory_fields([], Acc) ->
    {ok, add_default_fields(Acc)};
check_mandatory_fields([Field|Tail], Acc) ->
    case proplists:get_value(Field, Acc) of
        undefined ->
            {error, {missing_field, Field}};
        _ ->
            check_mandatory_fields(Tail, Acc)
    end.

add_default_fields(Config) ->
    %% merge with the default options
    {ok, DefaultLevel} = parse_level(?DEFAULT_LOG_LEVEL),
    lists:ukeymerge(1, lists:sort(Config), lists:sort([
        {level, DefaultLevel}, {handler_id, undefined},
        {formatter, ?DEFAULT_FORMATTER}, {formatter_config, ?DEFAULT_FORMATTER_CONFIG}
    ])).

config_to_id_impl(ValidatedConfig) ->
    case proplists:get_value(handler_id, ValidatedConfig) of
        undefined ->
            Identity = proplists:get_value(identity, ValidatedConfig),
            Facility = proplists:get_value(facility, ValidatedConfig),
            {?MODULE, {Identity, Facility}};
        HandlerId ->
            {?MODULE, HandlerId}
    end.

init_syslog_backend(ValidatedConfig) ->
    case ensure_started(syslog) of
        ok ->
            Identity = proplists:get_value(identity, ValidatedConfig),
            Facility = proplists:get_value(facility, ValidatedConfig),
            case syslog:open(Identity, [pid], Facility) of
                {ok, SyslogHandle} ->
                    Level = proplists:get_value(level, ValidatedConfig),
                    Id = config_to_id_impl(ValidatedConfig),
                    Formatter = proplists:get_value(formatter, ValidatedConfig),
                    FormatterConfig = proplists:get_value(formatter_config, ValidatedConfig),
                    {ok, #state{level=Level,
                            id=Id,
                            handle=SyslogHandle,
                            formatter=Formatter,
                            formatter_config=FormatterConfig}};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

ensure_started(Application) ->
    case application:start(Application) of
        ok ->
            ok;
        {error, {already_started, _}} ->
            ok;
        Error ->
            Error
    end.

parse_level(Level) ->
    try lager_util:config_to_mask(Level) of
        LevelMask ->
            {ok, LevelMask}
    catch
        error:undef ->
            %% must be lager < 2.0
            try lager_util:level_to_num(Level) of
                LevelMask ->
                    {ok, LevelMask}
            catch
                _:_ ->
                    {error, invalid_level}
            end;
        _:_ ->
            {error, invalid_level}
    end.

convert_to_syslog_level(?DEBUG) -> debug;
convert_to_syslog_level(?INFO) -> info;
convert_to_syslog_level(?NOTICE) -> notice;
convert_to_syslog_level(?WARNING) -> warning;
convert_to_syslog_level(?ERROR) -> err;
convert_to_syslog_level(?CRITICAL) -> crit;
convert_to_syslog_level(?ALERT) -> alert;
convert_to_syslog_level(?EMERGENCY) -> emerg.
