-module(lager_syslog_backend_eunit).

-include_lib("eunit/include/eunit.hrl").
-include("defaults.hrl").

-compile([{parse_transform, lager_transform}]).

config_conversion_test_() ->
    {foreach,
        fun() ->
                ok
        end,
        fun(_) ->
                ok
        end,
        [
            {"Old style 3 element config",
                fun() ->
                        Config = ["foobar", local6, debug],
                        Expected = [
                            {identity, "foobar"},
                            {facility, local6},
                            {level, debug}
                        ],
                        ?assertEqual(Expected, lager_syslog_backend:ensure_new_config_format(Config))
                end
            },
            {"Old style 4 element config",
                fun() ->
                        Config = ["foobar", local6, debug, {test_formatter, test_format_config}],
                        Expected = [
                            {identity, "foobar"},
                            {facility, local6},
                            {level, debug},
                            {formatter, test_formatter},
                            {formatter_config, test_format_config}
                        ],
                        ?assertEqual(Expected, lager_syslog_backend:ensure_new_config_format(Config))
                end
            },
            {"Proplist config (non-validated)",
                fun() ->
                        Config = [{foo, bar}, {foz, baz}],
                        Expected = [
                            {foo, bar},
                            {foz, baz}
                        ],
                        ?assertEqual(Expected, lager_syslog_backend:ensure_new_config_format(Config))
                end
            },
            {"non-valid proplist config (non-validated)",
                fun() ->
                        Config = [{"foo", bar}, {1, baz}],
                        Expected = {error, invalid_config},
                        ?assertThrow(Expected, lager_syslog_backend:ensure_new_config_format(Config))
                end
            },
            {"non-valid config",
                fun() ->
                        Config = [asd],
                        Expected = {error, invalid_config},
                        ?assertThrow(Expected, lager_syslog_backend:ensure_new_config_format(Config))
                end
            }
        ]}.

    validate_config_test_() ->
    {foreach,
        fun() ->
                ok
        end,
        fun(_) ->
                ok
        end,
        [
            {"Minimal config",
                fun() ->
                        Config = [{identity, "foobar"}, {facility, local6}],
                        {ok, ExpectedLevel} = lager_syslog_backend:parse_level(?DEFAULT_LOG_LEVEL),
                        Expected = {ok, [
                            {facility, local6},
                            {formatter, ?DEFAULT_FORMATTER},
                            {formatter_config, ?DEFAULT_FORMATTER_CONFIG},
                            {handler_id, undefined},
                            {identity, "foobar"},
                            {level, ExpectedLevel}
                        ]},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Full config",
                fun() ->
                        Config = [
                            {identity, "foobar"}, {facility, local6}, {formatter, foobar},
                            {formatter_config, [identity]}, {handler_id, foobaz},
                            {level, error}
                        ],
                        {ok, ExpectedLevel} = lager_syslog_backend:parse_level(error),
                        Expected = {ok, [
                            {facility, local6},
                            {formatter, foobar},
                            {formatter_config, [identity]},
                            {handler_id, foobaz},
                            {identity, "foobar"},
                            {level, ExpectedLevel}
                        ]},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"string handler id",
                fun() ->
                        Config = [
                            {identity, "foobar"}, {facility, local6}, {formatter, foobar},
                            {formatter_config, [identity]}, {handler_id, "foobaz"},
                            {level, error}
                        ],
                        {ok, ExpectedLevel} = lager_syslog_backend:parse_level(error),
                        Expected = {ok, [
                            {facility, local6},
                            {formatter, foobar},
                            {formatter_config, [identity]},
                            {handler_id, "foobaz"},
                            {identity, "foobar"},
                            {level, ExpectedLevel}
                        ]},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Missing identity",
                fun() ->
                        Config = [{facility, local6}],
                        Expected = {error, {missing_field, identity}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Missing facility",
                fun() ->
                        Config = [{identity, "foobar"}],
                        Expected = {error, {missing_field, facility}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Invalid level",
                fun() ->
                        Config = [{identity, "foobar"}, {facility, local6}, {level, foobar}],
                        Expected = {error, {bad_config, "Invalid loglevel", foobar}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Invalid formatter",
                fun() ->
                        Config = [{identity, "foobar"}, {facility, local6}, {formatter, "foobar"}],
                        Expected = {error, {bad_config, "Invalid formatter", "foobar"}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Invalid formatter_config",
                fun() ->
                        Config = [{identity, "foobar"}, {facility, local6}, {formatter_config, foobar}],
                        Expected = {error, {bad_config, "Invalid formatter config", foobar}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Invalid handler_id",
                fun() ->
                        Config = [{identity, "foobar"}, {facility, local6}, {handler_id, {foobar}}],
                        Expected = {error, {bad_config, "Invalid handler_id", {foobar}}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            },
            {"Invalid option",
                fun() ->
                        Config = [{identity, "foobar"}, {facility, local6}, {foo, bar}],
                        Expected = {error, {bad_config, "Unknown option", {foo, bar  }}},
                        ?assertEqual(Expected, lager_syslog_backend:validate_config(Config))
                end
            }
        ]}.

log_test_() ->
    {foreach,
        fun() ->
                error_logger:tty(false),
                application:load(syslog),
                application:load(lager),
                application:set_env(lager, handlers, [
                    {lager_syslog_backend, [{identity, "foobar"},
                    {facility, local6}, {level, debug}]}
                ]),
                %application:set_env(lager, error_logger_redirect, false),
                %application:set_env(lager, async_threshold, undefined),
                application:start(syslog),
                application:start(lager)
        end,
        fun(_) ->
                application:stop(lager),
                application:stop(syslog),
                error_logger:tty(true)
        end,
        [
            {"simple log",
                fun() ->
                        lager:log(error, self(), "Test message"),
                        ?assertEqual(true, true)
                end
            }
        ]}.
