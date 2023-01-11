module boilerplate;

public import boilerplate.accessors;

public import boilerplate.autostring;

public import boilerplate.conditions;

public import boilerplate.constructor;

enum GenerateAll = GenerateThis ~ GenerateToString ~ GenerateFieldAccessors ~ GenerateInvariants;

/**
 * Used to indicate that a field should be treated as if aliased to this as much as practical.
 * At the moment this has no effect in boilerplate, but it is used in serialized to treat the
 * field as aliased to this for purpose of encode/decode.
 */
struct AliasThis
{
}

@("can use all four generators at once")
unittest
{
    import core.exception : AssertError;
    import std.conv : to;
    import unit_threaded.should : shouldEqual, shouldThrow;

    class Class
    {
        @ConstRead @Write @NonInit
        int i_;

        mixin(GenerateAll);
    }

    auto obj = new Class(5);

    obj.i.shouldEqual(5);
    obj.to!string.shouldEqual("Class(i=5)");
    obj.i(0).shouldThrow!AssertError;
}

// regression test for workaround for https://issues.dlang.org/show_bug.cgi?id=19731
@("accessor on field in struct with invariant and constructor")
unittest
{
    import core.exception : AssertError;
    import unit_threaded.should : shouldThrow;

    struct Struct
    {
        @NonNull
        @ConstRead
        Object constObject_;

        @NonNull
        @Read
        Object object_;

        mixin(GenerateAll);
    }

    Struct().constObject.shouldThrow!AssertError;
    Struct().object.shouldThrow!AssertError;
}

@("field with reserved name")
unittest
{
    struct Struct
    {
        int version_;

        mixin(GenerateAll);
    }

    with (Struct.Builder())
    {
        version_ = 5;

        assert(value.version_ == 5);
        assert(value.BuilderFrom().value.version_ == 5);
    }
}

@("class with no members")
unittest
{
    static class Class
    {
        mixin(GenerateAll);
    }

    auto instance = Class.Builder().value;
}

@("underscore property is aliased to this")
unittest
{
    struct Foo
    {
        @ConstRead
        int i_;

        alias i_ this;

        mixin(GenerateAll);
    }

    auto builder = Foo.Builder();

    cast(void) builder;
}

@("const sumtype with non-const subtype")
unittest
{
    import std.sumtype : SumType;

    struct Foo
    {
        int[] array;
    }

    struct Bar
    {
        const SumType!Foo foo;

        mixin(GenerateAll);
    }
}
