module boilerplate.toString.datetime;

import std.datetime;

/**
 * Utility functions to format datetime values in generated `toString`.
 *
 * By convention, we use ISO extended strings to represent timestamps.
 */
void toString(Writer)(scope ref Writer writer, SysTime time)
{
    time.toISOExtString(writer);
}

/// Ditto
void toString(Writer)(scope ref Writer writer, Date date)
{
    date.toISOExtString(writer);
}

/// Ditto
void toString(Writer)(scope ref Writer writer, TimeOfDay timeOfDay)
{
    timeOfDay.toISOExtString(writer);
}

/**
 * Format durations as ISO8601.
 */
void toString(Writer)(scope ref Writer writer, Duration duration)
{
    import std.format : formattedWrite;

    if (duration < Duration.zero)
    {
        writer("-");
        duration = -duration;
    }

    auto result = duration.split!("days", "hours", "minutes", "seconds", "msecs");

    with (result)
    {
        writer("P");

        if (days != 0)
        {
            writer.formattedWrite("%sD", days);
        }

        const bool allTimesNull = hours == 0 && minutes == 0 && seconds == 0 && msecs == 0;
        const bool allNull = allTimesNull && days == 0;

        if (!allTimesNull || allNull)
        {
            writer("T");
            if (hours != 0)
            {
                writer.formattedWrite("%sH", hours);
            }
            if (minutes != 0)
            {
                writer.formattedWrite("%sM", minutes);
            }
            if (seconds != 0 || msecs != 0 || allNull)
            {
                writer.formattedWrite("%s", seconds);
                writer.writeMillis(msecs);
                writer("S");
            }
        }
    }
}

/**
 * Converts the specified milliseconds value into a representation with as few digits as possible.
 */
private void writeMillis(Writer)(ref Writer writer, long millis)
in (0 <= millis && millis < 1000)
{
    import std.format : formattedWrite;

    if (millis == 0)
    {
        writer("");
    }
    else if (millis % 100 == 0)
    {
        writer.formattedWrite(".%01d", millis / 100);
    }
    else if (millis % 10 == 0)
    {
        writer.formattedWrite(".%02d", millis / 10);
    }
    else
    {
        writer.formattedWrite(".%03d", millis);
    }
}

@("datetime formatting")
@safe unittest
{
    import unit_threaded.should : shouldEqual;

    SysTime.fromISOExtString("2003-02-01T11:55:00Z").testToString.shouldEqual("2003-02-01T11:55:00Z");
    Date.fromISOExtString("2003-02-01").testToString.shouldEqual("2003-02-01");
    TimeOfDay.fromISOExtString("01:02:03").testToString.shouldEqual("01:02:03");
}

@("duration formatting")
@safe unittest
{
    import unit_threaded.should : shouldEqual;

    (1.days + 2.hours + 3.minutes + 4.seconds + 500.msecs).testToString.shouldEqual("P1DT2H3M4.5S");
    (1.days).testToString.shouldEqual("P1D");
    Duration.zero.testToString.shouldEqual("PT0S");
    1.msecs.testToString.shouldEqual("PT0.001S");
    (-(1.hours + 2.minutes + 3.seconds + 450.msecs)).testToString.shouldEqual("-PT1H2M3.45S");
}

private string testToString(T)(const T value) @safe
{
    string generatedString;

    scope void delegate(const(char)[]) @safe sink = (const(char)[] fragment) @safe {
        generatedString ~= fragment;
    };

    toString(sink, value);
    return generatedString;
}
