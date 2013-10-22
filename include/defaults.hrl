-define(DEFAULT_LOG_LEVEL, info).
-define(DEFAULT_FORMATTER, lager_default_formatter).
-define(DEFAULT_FORMATTER_CONFIG,["[", severity, "] ",
        {pid, ""},
        {module, [
                {pid, ["@"], ""},
                module,
                {function, [":", function], ""},
                {line, [":",line], ""}], ""},
        " ", message]).