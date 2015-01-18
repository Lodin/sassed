module sassed.test;

private
{
    import sassed.sass;
    import sassed.console;
    
    import std.file : readText, remove, exists;
    import std.stdio : writeln;
}

unittest
{
    auto sass = new shared Sass;

    /*
     * String compilation. Conditions:
     * 1) Source map emitted.
     * 2) Nested style.
     */
    sass.options.sourcemap.enable();

    string sourcemap;
    auto source = "tests/input/single.scss".readText();
    auto comparingSourceNested = "tests/comparing/string-compilation/single-nested.css".readText();
    auto comparingSourcemap = "tests/comparing/string-compilation/single.css.map".readText();

    assert( sass.compile( source, sourcemap ) == comparingSourceNested );
    assert( sourcemap == comparingSourcemap );
    writeln( "SUCCESS: String compilation with source map" );

    /*
     * String compilations.
     * 1) No source map;
     * 2) Compressed style
     */
    sass.options.sourcemap.disable();
    sass.options.style = SassStyle.COMPRESSED;

    auto comparingSourceCompressed = "tests/comparing/string-compilation/single-compressed.css".readText();

    assert( sass.compile( source ) == comparingSourceCompressed );
    writeln( "SUCCESS: String compilation, compressed style" );
}

unittest
{
    auto sass = new shared Sass;

    /*
     * File compilation. Conditions:
     * 1) Source map emitted.
     * 2) Nested style
     */
    sass.options.sourcemap.enable();
    
    auto comparingSourceNested = "tests/comparing/file-compilation/single-nested.css".readText();
    auto comparingSourcemap = "tests/comparing/file-compilation/single.css.map".readText();

    sass.compileFile( "tests/input/single.scss", "tests/output/single.css" );

    assert( "tests/output/single.css".exists() );
    assert( "tests/output/single.css.map".exists() );

    auto result = "tests/output/single.css".readText();
    auto resultMap = "tests/output/single.css.map".readText();

    assert( result == comparingSourceNested );
    assert( resultMap == comparingSourcemap );
    writeln( "SUCCESS: File compilation with source map" );

    "tests/output/single.css".remove();
    "tests/output/single.css.map".remove();

    /*
     * File compilation. Conditions:
     * 1) No source map.
     * 2) Compressed style
     */
    sass.options.sourcemap.disable();
    sass.options.style = SassStyle.COMPRESSED;

    auto comparingSourceCompressed = "tests/comparing/file-compilation/single-compressed.css".readText();

    sass.compileFile( "tests/input/single.scss", "tests/output/single.css" );

    assert( "tests/output/single.css".exists() );

    result = "tests/output/single.css".readText();

    assert( result == comparingSourceCompressed );
    writeln( "SUCCESS: File compilation, compressed style" );

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
    sass.options.sourcemap.enable();

    auto comparingFileFirst = "tests/comparing/folder-compilation/folder-first.css".readText();
    auto comparingFileSecond = "tests/comparing/folder-compilation/folder-second.css".readText();

    auto comparingMapFirst = "tests/comparing/folder-compilation/folder-first.css.map".readText();
    auto comparingMapSecond = "tests/comparing/folder-compilation/folder-second.css.map".readText();

    sass.compileFolder( "tests/input/folder", "tests/output/folder" );

    assert( "tests/output/folder/folder-first.css".exists() );
    assert( "tests/output/folder/folder-second.css".exists() );
    assert( "tests/output/folder/folder-first.css.map".exists() );
    assert( "tests/output/folder/folder-second.css.map".exists() );

    auto resultFirst = "tests/output/folder/folder-first.css".readText();
    auto resultSecond = "tests/output/folder/folder-second.css".readText();

    auto resultMapFirst = "tests/output/folder/folder-first.css.map".readText();
    auto resultMapSecond = "tests/output/folder/folder-second.css.map".readText();

    assert( resultFirst == comparingFileFirst );
    assert( resultSecond == comparingFileSecond );
    assert( resultMapFirst == comparingMapFirst );
    assert( resultMapSecond == comparingMapSecond );
    writeln( "SUCCESS: Folder compilation with source map, multiple files" );

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
    sass.options.sourcemap.disable();
    sass.options.style = SassStyle.COMPRESSED;
    sass.options.singleFile.enable();
    sass.options.singleFile.name = "folder-all";

    auto comparingFile = "tests/comparing/folder-compilation/folder-all.css".readText();

    sass.compileFolder( "tests/input/folder", "tests/output/folder" );

    assert( "tests/output/folder/folder-all.css".exists() );

    auto result = "tests/output/folder/folder-all.css".readText();

    assert( result == comparingFile );
    writeln( "SUCCESS: Folder compilation, single file" );

    "tests/output/folder/folder-all.css".remove();
}