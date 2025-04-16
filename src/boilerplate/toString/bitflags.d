module boilerplate.toString.bitflags;

import std.typecons : BitFlags;

void toString(T: const BitFlags!Enum, Enum, Writer)(ref Writer writer, const T field)
{
    import std.conv : to;
    import std.traits : EnumMembers;

    bool firstMember = true;

    writer(Enum.stringof);
    writer("(");

    static foreach (member; EnumMembers!Enum)
    {
        if (field & member)
        {
            if (firstMember)
            {
                firstMember = false;
            }
            else
            {
                writer(", ");
            }

            enum name = to!string(member);

            writer(name);
        }
    }
    writer(")");
}

@("can format bitflags")
unittest
{
    import unit_threaded.should : shouldEqual;

    string generatedString;

    scope sink = (const(char)[] fragment) {
        generatedString ~= fragment;
    };

    enum Enum
    {
        A = 1,
        B = 2,
    }

    const BitFlags!Enum flags = BitFlags!Enum(Enum.A, Enum.B);

    toString(sink, flags);

    generatedString.shouldEqual("Enum(A, B)");
}
