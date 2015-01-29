module sassed.test;

private
{
    import sassed.sass;
    import sassed.console;
    
    import std.file : readText, remove, exists;
    import std.stdio : writeln;
}

enum success = "SUCCESS: ";
enum fail = "FAIL: ";

unittest
{
    auto sass = new shared Sass;

    /*
     * String compilation. Conditions:
     * 1) Source map emitted.
     * 2) Nested style.
     */
    auto titleFirst = "String compilation with source map";

    sass.options.sourcemap.enable();

    string sourcemap;
    auto source = "tests/input/single.scss".readText();

    assert( sass.compile( source, sourcemap ).length > 0, fail ~ titleFirst );
    assert( sourcemap.length > 0, fail ~ titleFirst );
    writeln( success ~ titleFirst );

    /*
     * String compilations.
     * 1) No source map;
     * 2) Compressed style
     */
    auto titleSecond = "String compilation, compressed style";

    sass.options.sourcemap.disable();
    sass.options.style = SassStyle.COMPRESSED;

    assert( sass.compile( source ).length > 0, fail ~ titleSecond);
    writeln( success ~ titleSecond );
}

unittest
{
    auto sass = new shared Sass;

    /*
     * File compilation. Conditions:
     * 1) Source map emitted.
     * 2) Nested style
     */
    auto titleFirst = "File compilation with source map";

    sass.options.sourcemap.enable();
    
    sass.compileFile( "tests/input/single.scss", "tests/output/single.css" );

    assert( "tests/output/single.css".exists(), fail ~ titleFirst );
    assert( "tests/output/single.css.map".exists(), fail ~ titleFirst );

    auto result = "tests/output/single.css".readText();
    auto resultMap = "tests/output/single.css.map".readText();

    assert( result.length > 0, fail ~ titleFirst );
    assert( resultMap.length > 0, fail ~ titleFirst );
    writeln( success ~ titleFirst );

    "tests/output/single.css".remove();
    "tests/output/single.css.map".remove();

    /*
     * File compilation. Conditions:
     * 1) No source map.
     * 2) Compressed style
     */
    auto titleSecond = "File compilation, compressed style";

    sass.options.sourcemap.disable();
    sass.options.style = SassStyle.COMPRESSED;

    sass.compileFile( "tests/input/single.scss", "tests/output/single.css" );

    assert( "tests/output/single.css".exists(), fail ~ titleSecond );

    result = "tests/output/single.css".readText();

    assert( result.length > 0, fail ~ titleSecond );
    writeln( success ~ titleSecond );

    "tests/output/single.css".remove();
}

unittest
{
    auto sass = new shared Sass;

    /*
     * Folder compilation. Conditions:
     * 1) Source map emitted.
     * 2) Nested style
     * 3) Multiple files
     */
    auto titleFirst = "Folder compilation with source map, multiple files";

    sass.options.sourcemap.enable();

    sass.compileFolder( "tests/input/folder", "tests/output/folder" );

    assert( "tests/output/folder/folder-first.css".exists(), fail ~ titleFirst );
    assert( "tests/output/folder/folder-second.css".exists(), fail ~ titleFirst );
    assert( "tests/output/folder/folder-first.css.map".exists(), fail ~ titleFirst );
    assert( "tests/output/folder/folder-second.css.map".exists(), fail ~ titleFirst );

    auto resultFirst = "tests/output/folder/folder-first.css".readText();
    auto resultSecond = "tests/output/folder/folder-second.css".readText();

    auto resultMapFirst = "tests/output/folder/folder-first.css.map".readText();
    auto resultMapSecond = "tests/output/folder/folder-second.css.map".readText();

    assert( resultFirst.length > 0, fail ~ titleFirst );
    assert( resultSecond.length > 0, fail ~ titleFirst );
    assert( resultMapFirst.length > 0, fail ~ titleFirst );
    assert( resultMapSecond.length > 0, fail ~ titleFirst );
    writeln( success ~ titleFirst );

    "tests/output/folder/folder-first.css".remove();
    "tests/output/folder/folder-second.css".remove();
    "tests/output/folder/folder-first.css.map".remove();
    "tests/output/folder/folder-second.css.map".remove();

    /*
     * Folder compilation. Conditions:
     * 1) No source map.
     * 2) Compressed style
     * 3) Single file.
     */
    auto titleSecond = "Folder compilation, single file";

    sass.options.sourcemap.disable();
    sass.options.style = SassStyle.COMPRESSED;
    sass.options.singleFile.enable();
    sass.options.singleFile.name = "folder-all";

    sass.compileFolder( "tests/input/folder", "tests/output/folder" );

    assert( "tests/output/folder/folder-all.css".exists(), fail ~ titleSecond );

    auto result = "tests/output/folder/folder-all.css".readText();

    assert( result.length > 0, fail ~ titleSecond );
    writeln( success ~ titleSecond );

    "tests/output/folder/folder-all.css".remove();
}