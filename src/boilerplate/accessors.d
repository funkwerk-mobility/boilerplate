module boilerplate.accessors;

import boilerplate.conditions : generateChecksForAttributes, IsConditionAttribute;
import boilerplate.util: DeepConst, isStatic;
import std.meta : StdMetaFilter = Filter;
import std.traits;
import std.typecons: Nullable;

struct Read
{
    string visibility = "public";
}

// Deprecated! See below.
// RefRead can not check invariants on change, so there's no point.
// ref property functions where the value being returned is a field of the class
// are entirely equivalent to public fields.
struct RefRead
{
    string visibility = "public";
}

struct ConstRead
{
    string visibility = "public";
}

struct Write
{
    string visibility = "public";
}

immutable string GenerateFieldAccessors = `
    import boilerplate.accessors : GenerateFieldAccessorMethods;
    mixin GenerateFieldAccessorMethods;
    mixin(GenerateFieldAccessorMethodsImpl);
    `;

public static string GenerateFieldDecls_(FieldType, Attributes...)
    (string name, bool synchronize, bool fieldIsStatic, bool fieldIsUnsafe)
{
    if (!__ctfe)
    {
        return null;
    }

    string result;

    import boilerplate.accessors :
        ConstRead,
        GenerateConstReader, GenerateReader, GenerateRefReader, GenerateWriter,
        Read, RefRead, Write;
    import boilerplate.util : udaIndex;

    static if (udaIndex!(Read, Attributes) != -1)
    {
        string readerDecl = GenerateReader!(FieldType, Attributes)(
            name, fieldIsStatic, fieldIsUnsafe, synchronize);

        debug (accessors) pragma(msg, readerDecl);
        result ~= readerDecl;
    }

    static if (udaIndex!(RefRead, Attributes) != -1)
    {
        result ~= `pragma(msg, "Deprecation! RefRead on " ~ typeof(this).stringof ~ ".` ~ name
            ~ ` makes a private field effectively public, defeating the point.");`;

        string refReaderDecl = GenerateRefReader!(FieldType)(name, fieldIsStatic);

        debug (accessors) pragma(msg, refReaderDecl);
        result ~= refReaderDecl;
    }

    static if (udaIndex!(ConstRead, Attributes) != -1)
    {
        string constReaderDecl = GenerateConstReader!(const(FieldType), Attributes)
            (name, fieldIsStatic, fieldIsUnsafe, synchronize);

        debug (accessors) pragma(msg, constReaderDecl);
        result ~= constReaderDecl;
    }

    static if (udaIndex!(Write, Attributes) != -1)
    {
        string writerDecl = GenerateWriter!(FieldType, Attributes)
            (name, `this.` ~ name, fieldIsStatic, fieldIsUnsafe, synchronize);

        debug (accessors) pragma(msg, writerDecl);
        result ~= writerDecl;
    }

    return result;
}

mixin template GenerateFieldAccessorMethods()
{
    private static string GenerateFieldAccessorMethodsImpl()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.accessors : GenerateFieldDecls_;
        import boilerplate.util : GenNormalMemberTuple, isStatic, isUnsafe;

        string result = "";

        mixin GenNormalMemberTuple;

        foreach (name; NormalMemberTuple)
        {
            // synchronized without lock contention is basically free, so always do it
            // TODO enable when https://issues.dlang.org/show_bug.cgi?id=18504 is fixed
            // enum synchronize = is(typeof(__traits(getMember, typeof(this), name)) == class);
            enum fieldIsStatic = mixin(name.isStatic);
            enum fieldIsUnsafe = mixin(name.isUnsafe);

            result ~= GenerateFieldDecls_!(
                typeof(__traits(getMember, typeof(this), name)),
                __traits(getAttributes, __traits(getMember, typeof(this), name))
            ) (name, /*synchronize*/false, fieldIsStatic, fieldIsUnsafe);
        }

        return result;
    }
}

string getModifiers(bool isStatic)
{
    return isStatic ? " static" : "";
}

uint filterAttributes(T)(bool isStatic, bool isUnsafe, FilterMode mode)
{
    import boilerplate.util : needToDup;

    uint attributes = uint.max;

    if (needToDup!T)
    {
        attributes &= ~FunctionAttribute.nogc;
        static if (isAssociativeArray!T)
        {
            // int[int].dup can throw apparently
            attributes &= ~FunctionAttribute.nothrow_;
        }
    }
    // Nullable.opAssign is not nogc
    if (mode == FilterMode.Writer && isInstanceOf!(Nullable, T))
    {
        attributes &= ~FunctionAttribute.nogc;
    }
    // TODO remove once synchronized (this) is nothrow
    // see https://github.com/dlang/druntime/pull/2105 , https://github.com/dlang/dmd/pull/7942
    if (is(T == class))
    {
        attributes &= ~FunctionAttribute.nothrow_;
    }
    if (isStatic)
    {
        attributes &= ~FunctionAttribute.pure_;
    }
    if (isUnsafe)
    {
        attributes &= ~FunctionAttribute.safe;
    }
    return attributes;
}

enum FilterMode
{
    Reader,
    Writer,
}

string GenerateReader(T, Attributes...)(string name, bool fieldIsStatic, bool fieldIsUnsafe, bool synchronize)
{
    import boilerplate.util : needToDup;
    import std.string : format;

    auto example = T.init;
    auto accessorName = accessor(name);
    enum visibility = getVisibility!(Read, __traits(getAttributes, example));
    enum needToDupField = needToDup!T;

    static if (isAssociativeArray!T)
    {
        fieldIsUnsafe = true;
    }

    uint attributes = inferAttributes!(T, "__postblit") &
        filterAttributes!T(fieldIsStatic, fieldIsUnsafe, FilterMode.Reader);

    string attributesString = generateAttributeString(attributes);
    string accessorBody;
    string type;

    if (fieldIsStatic)
    {
        type = format!`typeof(this.%s)`(name);
    }
    else
    {
        type = format!`inout(typeof(this.%s))`(name);
    }

    // for types like string where the contents are already const or value,
    // so we can safely reassign to a non-const type
    static if (needToDupField)
    {
        static if (isArray!T)
        {
            accessorBody = format!`return typeof(this.%s).init ~ this.%s;`(name, name);
        }
        else static if (isAssociativeArray!T)
        {
            accessorBody = format!`return cast(typeof(this.%s)) this.%s.dup;`(name, name);
        }
        else
        {
            static assert(false, "logic error: need to dup but don't know how");
        }
    }
    else static if (DeepConst!(Unqual!T) && !is(Unqual!T == T))
    {
        // necessitated by DMD bug https://issues.dlang.org/show_bug.cgi?id=18545
        accessorBody = format!`typeof(cast() this.%s) var = this.%s; return var;`(name, name);
        type = format!`typeof(cast() this.%s)`(name);
    }
    else
    {
        accessorBody = format!`return this.%s;`(name);
    }

    if (synchronize)
    {
        accessorBody = format!`synchronized (this) { %s} `(accessorBody);
    }

    auto modifiers = getModifiers(fieldIsStatic);

    if (!fieldIsStatic)
    {
        attributesString ~= " inout";
    }

    string outCondition = "";

    if (fieldIsStatic)
    {
        if (auto checks = generateChecksForAttributes!(T, StdMetaFilter!(IsConditionAttribute, Attributes))
            ("result", " in postcondition of @Read"))
        {
            outCondition = format!` out(result) { %s } body`(checks);
        }
    }

    return format!("%s%s final @property %s %s()%s%s { %s }")
                (visibility, modifiers, type, accessorName, attributesString, outCondition, accessorBody);
}

@("generates readers as expected")
@nogc nothrow pure @safe unittest
{
    int integerValue;
    string stringValue;
    int[] intArrayValue;
    const string constStringValue;

    static assert(GenerateReader!int("foo", true, false, false) ==
        "public static final @property typeof(this.foo) foo() " ~
        "@nogc nothrow @safe { return this.foo; }");
    static assert(GenerateReader!string("foo", true, false, false) ==
        "public static final @property typeof(this.foo) foo() " ~
        "@nogc nothrow @safe { return this.foo; }");
    static assert(GenerateReader!(int[])("foo", true, false, false) ==
        "public static final @property typeof(this.foo) foo() nothrow @safe "
      ~ "{ return typeof(this.foo).init ~ this.foo; }");
    static assert(GenerateReader!(const string)("foo", true, false, false) ==
        "public static final @property typeof(cast() this.foo) foo() @nogc nothrow @safe "
      ~ "{ typeof(cast() this.foo) var = this.foo; return var; }");
}

string GenerateRefReader(T)(string name, bool isStatic)
{
    import std.string : format;

    auto example = T.init;
    auto accessorName = accessor(name);
    enum visibility = getVisibility!(RefRead, __traits(getAttributes, example));

    string attributesString;
    if (isStatic)
    {
        attributesString = "@nogc nothrow @safe ";
    }
    else
    {
        attributesString = "@nogc nothrow pure @safe ";
    }

    auto modifiers = getModifiers(isStatic);

    // no need to synchronize a reference read
    return format("%s%s final @property ref typeof(this.%s) %s() " ~
        "%s{ return this.%s; }",
        visibility, modifiers, name, accessorName, attributesString, name);
}

@("generates ref readers as expected")
@nogc nothrow pure @safe unittest
{
    static assert(GenerateRefReader!int("foo", true) ==
        "public static final @property ref typeof(this.foo) foo() " ~
        "@nogc nothrow @safe { return this.foo; }");
    static assert(GenerateRefReader!string("foo", true) ==
        "public static final @property ref typeof(this.foo) foo() " ~
        "@nogc nothrow @safe { return this.foo; }");
    static assert(GenerateRefReader!(int[])("foo", true) ==
        "public static final @property ref typeof(this.foo) foo() " ~
        "@nogc nothrow @safe { return this.foo; }");
}

string GenerateConstReader(T, Attributes...)(string name, bool isStatic, bool isUnsafe, bool synchronize)
{
    import std.string : format;

    auto example = T.init;
    auto accessorName = accessor(name);
    enum visibility = getVisibility!(ConstRead, __traits(getAttributes, example));

    uint attributes = inferAttributes!(T, "__postblit") &
        filterAttributes!T(isStatic, isUnsafe, FilterMode.Reader);

    string attributesString = generateAttributeString(attributes);

    static if (DeepConst!(Unqual!T) && !is(Unqual!T == T))
    {
        // necessitated by DMD bug https://issues.dlang.org/show_bug.cgi?id=18545
        string accessorBody = format!`typeof(cast() this.%s) var = this.%s; return var;`(name, name);
        string type = format!`typeof(cast() const(typeof(this)).init.%s)`(name);
    }
    else
    {
        string accessorBody = format!`return this.%s; `(name);
        string type = format!`const(typeof(this.%s))`(name);
    }

    if (synchronize)
    {
        accessorBody = format!`synchronized (this) { %s} `(accessorBody);
    }

    auto modifiers = getModifiers(isStatic);

    if (isStatic)
    {
        string outCondition = "";

        if (auto checks = generateChecksForAttributes!(T, StdMetaFilter!(IsConditionAttribute, Attributes))
            ("result", " in postcondition of @ConstRead"))
        {
            outCondition = format!` out(result) { %s } body`(checks);
        }

        return format("%s%s final @property %s %s()%s%s { %s}",
            visibility, modifiers, type, accessorName, attributesString, outCondition, accessorBody);
    }

    return format("%s%s final @property %s %s() const%s { %s}",
        visibility, modifiers, type, accessorName, attributesString, accessorBody);
}

string GenerateWriter(T, Attributes...)(string name, string fieldCode, bool isStatic, bool isUnsafe, bool synchronize)
{
    import boilerplate.util : needToDup;
    import std.algorithm : canFind;
    import std.string : format;

    auto example = T.init;
    auto accessorName = accessor(name);
    auto inputName = accessorName;
    enum needToDupField = needToDup!T;
    enum visibility = getVisibility!(Write, __traits(getAttributes, example));

    uint attributes = defaultFunctionAttributes &
        filterAttributes!T(isStatic, isUnsafe, FilterMode.Writer) &
        inferAssignAttributes!T &
        inferAttributes!(T, "__postblit") &
        inferAttributes!(T, "__dtor");

    string precondition = ``;

    if (auto checks = generateChecksForAttributes!(T, StdMetaFilter!(IsConditionAttribute, Attributes))
        (inputName, " in precondition of @Write"))
    {
        precondition = format!` in { import std.format : format; import std.array : empty; %s } body`(checks);
        attributes &= ~FunctionAttribute.nogc;
        attributes &= ~FunctionAttribute.nothrow_;
        // format() is neither pure nor safe
        if (checks.canFind("format"))
        {
            attributes &= ~FunctionAttribute.pure_;
            attributes &= ~FunctionAttribute.safe;
        }
    }

    auto attributesString = generateAttributeString(attributes);
    auto modifiers = getModifiers(isStatic);

    string accessorBody = format!`this.%s = %s%s; `(name, inputName, needToDupField ? ".dup" : "");

    if (synchronize)
    {
        accessorBody = format!`synchronized (this) { %s} `(accessorBody);
    }

    string result = format("%s%s final @property void %s(typeof(%s) %s)%s%s { %s}",
        visibility, modifiers, accessorName, fieldCode, inputName,
        attributesString, precondition, accessorBody);

    static if (is(T : Nullable!Arg, Arg))
    {
        result ~= format("%s%s final @property void %s(typeof(%s.get) %s)%s%s { %s}",
        visibility, modifiers, accessorName, fieldCode, inputName,
        attributesString, precondition, accessorBody);
    }
    return result;
}

@("generates writers as expected")
@nogc nothrow pure @safe unittest
{
    static assert(GenerateWriter!int("foo", "integerValue", true, false, false) ==
        "public static final @property void foo(typeof(integerValue) foo) " ~
        "@nogc nothrow @safe { this.foo = foo; }");
    static assert(GenerateWriter!string("foo", "stringValue", true, false, false) ==
        "public static final @property void foo(typeof(stringValue) foo) " ~
        "@nogc nothrow @safe { this.foo = foo; }");
    static assert(GenerateWriter!(int[])("foo", "intArrayValue", true, false, false) ==
        "public static final @property void foo(typeof(intArrayValue) foo) " ~
        "nothrow @safe { this.foo = foo.dup; }");
}

@("generates same-type writer for Nullable")
pure @safe unittest
{
    import std.typecons : Nullable, nullable;
    import unit_threaded.should : shouldEqual;

    struct Struct
    {
        @Write
        Nullable!int optional_;

        mixin(GenerateFieldAccessors);
    }

    Struct value;

    value.optional = 5;

    value.optional_.shouldEqual(5.nullable);
}

private enum uint defaultFunctionAttributes =
            FunctionAttribute.nogc |
            FunctionAttribute.safe |
            FunctionAttribute.nothrow_ |
            FunctionAttribute.pure_;

private template inferAttributes(T, string M)
{
    uint inferAttributes()
    {
        uint attributes = defaultFunctionAttributes;

        static if (is(T == struct))
        {
            static if (hasMember!(T, M))
            {
                attributes &= functionAttributes!(__traits(getMember, T, M));
            }
            else
            {
                foreach (field; Fields!T)
                {
                    attributes &= inferAttributes!(field, M);
                }
            }
        }
        return attributes;
    }
}

private template inferAssignAttributes(T)
{
    uint inferAssignAttributes()
    {
        uint attributes = defaultFunctionAttributes;

        static if (is(T == struct))
        {
            static if (hasMember!(T, "opAssign"))
            {
                foreach (o; __traits(getOverloads, T, "opAssign"))
                {
                    alias params = Parameters!o;
                    static if (params.length == 1 && is(params[0] == T))
                    {
                        attributes &= functionAttributes!o;
                    }
                }
            }
            else
            {
                foreach (field; Fields!T)
                {
                    attributes &= inferAssignAttributes!field;
                }
            }
        }
        return attributes;
    }
}

private string generateAttributeString(uint attributes)
{
    string attributesString;

    if (attributes & FunctionAttribute.nogc)
    {
        attributesString ~= " @nogc";
    }
    if (attributes & FunctionAttribute.nothrow_)
    {
        attributesString ~= " nothrow";
    }
    if (attributes & FunctionAttribute.pure_)
    {
        attributesString ~= " pure";
    }
    if (attributes & FunctionAttribute.safe)
    {
        attributesString ~= " @safe";
    }

    return attributesString;
}

private string accessor(string name) @nogc nothrow pure @safe
{
    import std.string : chomp, chompPrefix;

    return name.chomp("_").chompPrefix("_");
}

@("removes underlines from names")
@nogc nothrow pure @safe unittest
{
    assert(accessor("foo_") == "foo");
    assert(accessor("_foo") == "foo");
}

/**
 * Returns a string with the value of the field "visibility" if the attributes
 * include an UDA of type A. The default visibility is "public".
 */
template getVisibility(A, attributes...)
{
    import std.string : format;

    enum getVisibility = helper;

    private static helper()
    {
        static if (!attributes.length)
        {
            return A.init.visibility;
        }
        else
        {
            foreach (i, uda; attributes)
            {
                static if (is(typeof(uda) == A))
                {
                    return uda.visibility;
                }
                else static if (is(uda == A))
                {
                    return A.init.visibility;
                }
                else static if (i + 1 == attributes.length)
                {
                    return A.init.visibility;
                }
            }
        }
    }
}

@("applies visibility from the uda parameter")
@nogc nothrow pure @safe unittest
{
    @Read("public") int publicInt;
    @Read("package") int packageInt;
    @Read("protected") int protectedInt;
    @Read("private") int privateInt;
    @Read int defaultVisibleInt;
    @Read @Write("protected") int publicReadableProtectedWritableInt;

    static assert(getVisibility!(Read, __traits(getAttributes, publicInt)) == "public");
    static assert(getVisibility!(Read, __traits(getAttributes, packageInt)) == "package");
    static assert(getVisibility!(Read, __traits(getAttributes, protectedInt)) == "protected");
    static assert(getVisibility!(Read, __traits(getAttributes, privateInt)) == "private");
    static assert(getVisibility!(Read, __traits(getAttributes, defaultVisibleInt)) == "public");
    static assert(getVisibility!(Read, __traits(getAttributes, publicReadableProtectedWritableInt)) == "public");
    static assert(getVisibility!(Write, __traits(getAttributes, publicReadableProtectedWritableInt)) == "protected");
}

@("creates accessors for flags")
nothrow pure @safe unittest
{
    import std.typecons : Flag, No, Yes;

    class Test
    {
        @Read
        @Write
        public Flag!"someFlag" test_ = Yes.someFlag;

        mixin(GenerateFieldAccessors);
    }

    with (new Test)
    {
        assert(test == Yes.someFlag);

        test = No.someFlag;

        assert(test == No.someFlag);

        static assert(is(typeof(test) == Flag!"someFlag"));
    }
}

@("creates accessors for nullables")
nothrow pure @safe unittest
{
    import std.typecons : Nullable;

    class Test
    {
        @Read @Write
        public Nullable!string test_ = Nullable!string("X");

        mixin(GenerateFieldAccessors);
    }

    with (new Test)
    {
        assert(!test.isNull);
        assert(test.get == "X");

        static assert(is(typeof(test) == Nullable!string));
    }
}

@("does not break with const Nullable accessor")
nothrow pure @safe unittest
{
    import std.typecons : Nullable;

    class Test
    {
        @Read
        private const Nullable!string test_;

        mixin(GenerateFieldAccessors);
    }

    with (new Test)
    {
        assert(test.isNull);
    }
}

@("creates non-const reader")
nothrow pure @safe unittest
{
    class Test
    {
        @Read
        int i_;

        mixin(GenerateFieldAccessors);
    }

    auto mutableObject = new Test;
    const constObject = mutableObject;

    mutableObject.i_ = 42;

    assert(mutableObject.i == 42);

    static assert(is(typeof(mutableObject.i) == int));
    static assert(is(typeof(constObject.i) == const(int)));
}

@("creates ref reader")
nothrow pure @safe unittest
{
    class Test
    {
        @RefRead
        int i_;

        mixin(GenerateFieldAccessors);
    }

    auto mutableTestObject = new Test;

    mutableTestObject.i = 42;

    assert(mutableTestObject.i == 42);
    static assert(is(typeof(mutableTestObject.i) == int));
}

@("creates writer")
nothrow pure @safe unittest
{
    class Test
    {
        @Read @Write
        private int i_;

        mixin(GenerateFieldAccessors);
    }

    auto mutableTestObject = new Test;
    mutableTestObject.i = 42;

    assert(mutableTestObject.i == 42);
    static assert(!__traits(compiles, mutableTestObject.i += 1));
    static assert(is(typeof(mutableTestObject.i) == int));
}

@("checks whether hasUDA can be used for each member")
nothrow pure @safe unittest
{
    class Test
    {
        alias Z = int;

        @Read @Write
        private int i_;

        mixin(GenerateFieldAccessors);
    }

    auto mutableTestObject = new Test;
    mutableTestObject.i = 42;

    assert(mutableTestObject.i == 42);
    static assert(!__traits(compiles, mutableTestObject.i += 1));
}

@("returns non const for PODs and structs.")
nothrow pure @safe unittest
{
    import std.algorithm : map, sort;
    import std.array : array;

    class C
    {
        @Read
        string s_;

        mixin(GenerateFieldAccessors);
    }

    C[] a = null;

    static assert(__traits(compiles, a.map!(c => c.s).array.sort()));
}

@("functions with strings")
nothrow pure @safe unittest
{
    class C
    {
        @Read @Write
        string s_;

        mixin(GenerateFieldAccessors);
    }

    with (new C)
    {
        s = "foo";
        assert(s == "foo");
        static assert(is(typeof(s) == string));
    }
}

@("supports user-defined accessors")
nothrow pure @safe unittest
{
    class C
    {
        this()
        {
            str_ = "foo";
        }

        @RefRead
        private string str_;

        public @property const(string) str() const
        {
            return this.str_.dup;
        }

        mixin(GenerateFieldAccessors);
    }

    with (new C)
    {
        str = "bar";
    }
}

@("creates accessor for locally defined types")
@system unittest
{
    class X
    {
    }

    class Test
    {
        @Read
        public X x_;

        mixin(GenerateFieldAccessors);
    }

    with (new Test)
    {
        x_ = new X;

        assert(x == x_);
        static assert(is(typeof(x) == X));
    }
}

@("creates const reader for simple structs")
nothrow pure @safe unittest
{
    class Test
    {
        struct S
        {
            int i;
        }

        @Read
        S s_;

        mixin(GenerateFieldAccessors);
    }

    auto mutableObject = new Test;
    const constObject = mutableObject;

    mutableObject.s_.i = 42;

    assert(constObject.s.i == 42);

    static assert(is(typeof(mutableObject.s) == Test.S));
    static assert(is(typeof(constObject.s) == const(Test.S)));
}

@("returns copies when reading structs")
nothrow pure @safe unittest
{
    class Test
    {
        struct S
        {
            int i;
        }

        @Read
        S s_;

        mixin(GenerateFieldAccessors);
    }

    auto mutableObject = new Test;

    mutableObject.s.i = 42;

    assert(mutableObject.s.i == int.init);
}

@("works with const arrays")
nothrow pure @safe unittest
{
    class X
    {
    }

    class C
    {
        @Read
        private const(X)[] foo_;

        mixin(GenerateFieldAccessors);
    }

    auto x = new X;

    with (new C)
    {
        foo_ = [x];

        auto y = foo;

        static assert(is(typeof(y) == const(X)[]));
        static assert(is(typeof(foo) == const(X)[]));
    }
}

@("has correct type of int")
nothrow pure @safe unittest
{
    class C
    {
        @Read
        private int foo_;

        mixin(GenerateFieldAccessors);
    }

    with (new C)
    {
        static assert(is(typeof(foo) == int));
    }
}

@("works under inheritance (https://github.com/funkwerk/accessors/issues/5)")
@nogc nothrow pure @safe unittest
{
    class A
    {
        @Read
        string foo_;

        mixin(GenerateFieldAccessors);
    }

    class B : A
    {
        @Read
        string bar_;

        mixin(GenerateFieldAccessors);
    }
}

@("transfers struct attributes")
@nogc nothrow pure @safe unittest
{
    struct S
    {
        this(this)
        {
        }

        void opAssign(S s)
        {
        }
    }

    class A
    {
        @Read
        S[] foo_;

        @ConstRead
        S bar_;

        @Write
        S baz_;

        mixin(GenerateFieldAccessors);
    }
}

@("returns array with mutable elements when reading")
nothrow pure @safe unittest
{
    struct Field
    {
    }

    struct S
    {
        @Read
        Field[] foo_;

        mixin(GenerateFieldAccessors);
    }

    with (S())
    {
        Field[] arr = foo;
    }
}

@("ConstRead with tailconst type")
nothrow pure @safe unittest
{
    struct S
    {
        @ConstRead
        string foo_;

        mixin(GenerateFieldAccessors);
    }

    auto var = S().foo;

    static assert(is(typeof(var) == string));
}

@("generates safe static properties for static members")
@safe unittest
{
    class MyStaticTest
    {
        @Read
        static int stuff_ = 8;

        mixin(GenerateFieldAccessors);
    }

    assert(MyStaticTest.stuff == 8);
}

@safe unittest
{
    struct S
    {
        @Read @Write
        static int foo_ = 8;

        @RefRead
        static int bar_ = 6;

        mixin(GenerateFieldAccessors);
    }

    assert(S.foo == 8);
    static assert(is(typeof({ S.foo = 8; })));
    assert(S.bar == 6);
}

@("does not set @safe on accessors for static __gshared members")
unittest
{
    class Test
    {
        @Read
        __gshared int stuff_ = 8;

        mixin(GenerateFieldAccessors);
    }

    assert(Test.stuff == 8);
}

@("does not set inout on accessors for static fields")
unittest
{
    class Test
    {
        @Read
        __gshared Object[] stuff_;

        mixin(GenerateFieldAccessors);
    }
}

unittest
{
    struct Thing
    {
        @Read
        private int[] content_;

        mixin(GenerateFieldAccessors);
    }

    class User
    {
        void helper(const int[])
        {
        }

        void doer(const Thing thing)
        {
            helper(thing.content);
        }
    }
}

@("dups nullable arrays")
unittest
{
    class Class
    {
    }

    struct Thing
    {
        @Read
        private Class[] classes_;

        mixin(GenerateFieldAccessors);
    }

    const Thing thing;

    assert(thing.classes.length == 0);
}

@("dups associative arrays")
unittest
{
    struct Thing
    {
        @Read
        @Write
        private int[int] value_;

        mixin(GenerateFieldAccessors);
    }

    auto thing = Thing([2: 3]);
    auto value = [2: 3];

    thing.value = value;

    // overwrite return value of @Read
    thing.value[2] = 4;
    // overwrite source value of @Write
    value[2] = 4;

    // member value is still unchanged.
    assert(thing.value == [2: 3]);
}

@("generates invariant checks via precondition for writers")
unittest
{
    import boilerplate.conditions : AllNonNull;
    import core.exception : AssertError;
    import std.algorithm : canFind;
    import std.conv : to;
    import unit_threaded.should : shouldThrow;

    class Thing
    {
        @Write @AllNonNull
        Object[] objects_;

        this(Object[] objects)
        {
            this.objects_ = objects.dup;
        }

        mixin(GenerateFieldAccessors);
    }

    auto thing = new Thing([new Object]);

    auto error = ({ thing.objects = [null]; })().shouldThrow!AssertError;

    assert(error.to!string.canFind("in precondition"));
}

@("generates out conditions for invariant tags on static accessors")
unittest
{
    import boilerplate.conditions : NonInit;
    import core.exception : AssertError;
    import unit_threaded.should : shouldThrow;

    struct Struct
    {
        @Read
        @NonInit
        static int test_;

        @ConstRead
        @NonInit
        static int test2_;

        mixin(GenerateFieldAccessors);
    }

    Struct.test.shouldThrow!AssertError;
    Struct.test2.shouldThrow!AssertError;
}
