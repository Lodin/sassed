﻿// Written in the D Programming Language
/**
 * Thin wrapper for libsass in D Programming Language.
 * It can:
 * $(OL
 *      $(LI Compile received string to css and return resulting css code)
 *      $(LI Compile single file and put it to a specified folder)
 *      $(LI Compile whole folder to multiple files and put it to another folder)
 *      $(LI Compile whole folder to a single file)
 *      $(LI Compile from `.sass` and `.scss` files)
 *      $(LI Watch input folder and recompile files within output when user changing some of them)
 * )
 * 
 * Usage:
 * ----
 * // Creating new Sass object
 * auto sass = new shared Sass;
 * 
 * // Setting some options
 * sass.options.style = SassStyle.COMPRESSED;
 * sass.options.sourcemap.enable();
 * 
 * // Using one of compiling methods
 * sass.compileFile( "path/to/file.scss", "path/to/result.css" );
 * ----
 * 
 * Copyright:
 *      Copyright Vlad Rindevich, 2015.
 * 
 * License:
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * 
 * Authors:
 *      Vlad Rindevich (rindevich.vs@gmail.com).
 */
module sassed.sass;

private
{
    import derelict.sass.sass;

    import libasync.watcher : AsyncDirectoryWatcher, DWChangeInfo;
    import libasync.events : getThreadEventLoop;
    import libasync.threads : destroyAsyncThreads;

    import std.string : toStringz, format;
    import std.conv : to;
    import std.stdio : File, stderr;
    import std.file : exists, isFile, isDir, dirEntries, SpanMode, readText,
        extension, mkdir;
    import std.path : setExtension, baseName, buildPath;
    import std.concurrency : spawn, receive, send, Tid, OwnerTerminated;
    import std.datetime : Clock;
    import std.array : Appender, replace;
    import std.algorithm : canFind;
    import std.typecons : Tuple;
    import std.traits : Unqual;
    import std.c.stdlib : free;
}

shared static ~this()
{
    destroyAsyncThreads();
}

/**
 * Style options specifier. All styles are defined at
 * $(LINK http://sass-lang.com/documentation/file.SASS_REFERENCE.html#output_style, Sass Documentation).
 * By now libsass implements only `nested` and `compressed` styles.
 */
enum SassStyle : int
{
    NESTED = 0,
    EXPANDED = 1,
    COMPACT = 2,
    COMPRESSED = 3,
}

/**
 * Sass2scss libsass plugin option specifier. It consists of:
 * $(OL
 *     $(LI Write everything on one line (`minimized`))
 *     $(LI Add lf after opening bracket (`lisp style`))
 *     $(LI Add lf after opening and before closing bracket (`1TBS style`))
 *     $(LI Add lf before/after opening and before closing (`allman style`))
 * )
 * More information can be found in the
 * $(LINK https://github.com/mgreter/sass2scss, official documentation).
 */
enum PrettifyLevel
{
    ZERO = SASS2SCSS_PRETTIFY_0,
    FIRST = SASS2SCSS_PRETTIFY_1,
    SECOND = SASS2SCSS_PRETTIFY_2,
    THIRD = SASS2SCSS_PRETTIFY_3
}

/// Watcher inner compile error handler type
alias bool delegate(SassCompileException) CompileErrorHandler;
alias void delegate(string input, string output) CompileSuccessHandler;

/**
 * SASS main implementation. Contains:
 * $(OL
 *     $(LI Different compiling methods: 
 *          $(OL
 *              $(LI `compile`. Simple string-to-string method)
 *              $(LI `compileFile`. File compiling method)
 *              $(LI `compileFolder`. Folder compiling method)
 *              $(LI `watchDir`. Recompiling on change method)
 *          ) 
 *     )
 *     $(LI Option specifier. It allows configuring SASS as needed)
 *     $(LI SASS to SCSS converter. It allows implicit conversion from SASS code
 *          to CSS through the interjacent conversion to SCSS)
 * )
 */
shared class Sass
{
    /// Contains SASS compiler options list
    SassOptions options;
    Version versions;

    this()
    {
        if( !DerelictSass.isLoaded )
            DerelictSass.load();

        options.sourcemap.sourceMappingUrl.enable();
    }

    /**
     * Compiles SASS string to CSS string.
     * 
     * Params: source = SASS code to compile
     * 
     * Returns: compiled CSS code
     */
    string compile( in string source ) const
    {
        string sourcemap;

        if( options.sourcemap.enabled )
            return compileImpl!true( source, sourcemap );
        else
            return compileImpl!false( source, sourcemap );
    }

    /**
     * Compiles SASS string to CSS string and generates source map.
     * 
     * Params:
     *         source = SASS code to compile
     *         sourcemap = returns SASS source map string
     * 
     * Returns: compiled CSS code.
     */
    string compile( in string source, out string sourcemap ) const
    {
        if( options.sourcemap.enabled )
            return compileImpl!true( source, sourcemap );
        else
            return compileImpl!false( source, sourcemap );
    }

    /**
     * Compiles SASS file.
     * 
     * Params:
     *         input = path to compiling SASS file
     *         output = path to result CSS file. If null, returns compiled code
     *                  as string
     * 
     * Returns: compiled CSS code, if `output` parameter is empty. Otherwise
     *          null
     */
    string compileFile( in string input, in string output = null ) const
    {
        string sourcemap;

        if( options.sourcemap.enabled )
            return compileFileImpl!true( input, output, sourcemap );
        else
            return compileFileImpl!false( input, output, sourcemap );
    } 

    /**
     * Compiles SASS file.
     * 
     * Params:
     *         input = path to compiling SASS file
     *         output = path to result CSS file. If null, returns compiled code
     *                  as string
     *         sourcemap = returns SASS source map string
     * 
     * Returns: compiled CSS code, if `output` parameter is empty. Otherwise
     *          null
     */
    string compileFile( in string input, in string output, out string sourcemap ) const
    {
        if( options.sourcemap.enabled )
            return compileFileImpl!true( input, output, sourcemap );
        else
            return compileFileImpl!false( input, output, sourcemap );
    } 

    /**
     * Compiles folder with SASS files. There are two compiling variants:
     * 1) If `singleFile` option is enabled, method compiles all folder SASS
     * files to the `output` to a single file with name defined in
     * `singleFile.name`. By now it is impossible to create source map to that
     * file. 
     * 2) Otherwise, method compiles SASS files name-by-name to the folder
     * `output`. Source maps will be created too. 
     * 
     * Params:
     *         input = path to folder contains SASS files
     *         output = path to result folder
     */
    void compileFolder( in string input, in string output )
    {
        void each( void delegate( in string name ) action ) const
        {
            foreach( string name; dirEntries( input, SpanMode.shallow ))
            {
                if( isDir( name ))
                    continue;

                action( name );
            }
        }

        void writeCommentedFile( ref File file, in string name, in string source ) const
        {
            if( options.singleFile.comments.enabled )
            {
                file.writeln(
                    "\n/* " 
                    ~ options.singleFile.comments.templ.replace(
                        options.singleFile.comments.placeholder,
                        name
                    ) ~ " */"
                );
            }
            
            file.writeln( source.to!string() );
        }

        string buildOutputPath( in string filename ) const
        {
            return buildPath(
                output,
                baseName( filename.setExtension( "css" ))
            );
        }

        testDirs( input, output );

        if( options.singleFile.enabled )
        {
            auto outputPath = buildOutputPath( options.singleFile.name );
            auto file = File( outputPath, "w+" );

            each(( name )
            {
                if( name.extension[1..$] == options.extension.sass )
                    options.indentedSyntax.enable();

                auto result = compileFile( name );
                writeCommentedFile( file, name, result );
            });
        }
        else
        {
            each(( name )
            {
                if( name.extension[1..$] == options.extension.sass )
                    options.indentedSyntax.enable();

                compileFile( name, buildOutputPath( name ));
            });
        }
    }

    /**
     * Activates directory watching and recompiles any file every time it
     * changes.
     * Watching works on two scenarios. If `singleFile` option is enabled, 
     * recompiling affects all files in folder. Otherwise, only changed file
     * will be recompiled. 
     * Any watching process creates own thread and returns it Tid. To stop the
     * process `unwatchDir` method should be used.
     * 
     * Params:
     *         input = path to folder contains SASS files
     *         output = path to result folder
     * 
     * Returns: Tid of watching thread
     */
    Tid watchDir( in string input, in string output )
    {
        testDirs( input, output );
        return spawn( &watchDirImpl, input, output );
    }

    /**
     * Stops directory watching.
     * 
     * Params: tid = watching thread id
     */
    void unwatchDir( scope Tid tid )
    {
        send( tid, true );
    }

    /**
     * Converts SASS code to SCSS code
     * 
     * Params: source = SASS code
     * Returns: converted SCSS code
     */
    string convertSass2Scss( in string source ) const
    {
        return sass2scss(source.toStringz(), options.sass2scss.get()).to!string();
    }

    /**
     * Creates result CSS file in `output` path from `source` string
     * 
     * Params: 
     *         output = result file name with path
     *         source = source code to write
     */
    void createResultFile( string output, string source ) const
    {
        auto file = File( output, "w+" );
        file.write( source );
        file.close();
    }

    /**
     * Creates source map file in `output` path from `source` string
     * 
     * Params: 
     *         output = result file name with path
     *         source = source code to write
     */
    void createMapFile( string output, string source ) const
    {
        createResultFile( output ~ options.sourcemap.extension, source );
    }

protected:

    void testDirs( in string input, in string output )
    {
        if( !input.exists() )
            throw new SassRuntimeException( format( "Directory `%s` does not exist", input ));

        if( !input.isDir() )
            throw new SassRuntimeException( format( "`%s` is not a directory", input ));
        
        if( !output.exists() )
            mkdir( output );
    }

    string compileImpl( bool isMapUsing )(
        in string source,
        out string sourcemap
    ) const
    {
        string result;

        auto ctx = sass_make_data_context( cast(char*)source.toStringz() );
        auto ctx_out = sass_data_context_get_context( ctx );

        auto opts = options.get();

        static if( isMapUsing )
            sass_option_set_source_map_file( opts, toStringz( "temp" ~ options.sourcemap.extension ) );

        sass_data_context_set_options( ctx, opts );
        free( opts );

        sass_compile_data_context( ctx );

        if( sass_context_get_error_status( ctx_out ) > 0 )
        {
            auto error = sass_context_get_error_message( ctx_out ).to!string();
            sass_delete_data_context( ctx );
            throw new SassCompileException( error );
        }

        static if( isMapUsing )
            sourcemap = sass_context_get_source_map_string( ctx_out ).to!string();

        result = sass_context_get_output_string( ctx_out ).to!string();
        sass_delete_data_context( ctx );

        return result;
    }

    string compileFileImpl( bool isMapUsing )(
        in string input,
        in string output,
        out string sourcemap
    ) const
    {
        if( !input.exists() )
            throw new SassRuntimeException( format( "File `%s` does not exist", input ));
        
        if( !input.isFile() )
            throw new SassRuntimeException( format( "`%s` is not a file", input ));

        auto inputPtr = input.toStringz();

        auto ctx = sass_make_file_context( inputPtr );
        auto ctx_out = sass_file_context_get_context( ctx );

        auto opts = options.get();

        sass_option_set_input_path( opts, inputPtr );

        if( output != "" )
            sass_option_set_output_path( opts, output.toStringz() );

        static if( isMapUsing )
            sass_option_set_source_map_file( opts, toStringz( output ~ options.sourcemap.extension ) );

        sass_file_context_set_options( ctx, opts );
        free( opts );

        sass_compile_file_context( ctx );

        if( sass_context_get_error_status( ctx_out ) > 0 )
        {
            auto error = sass_context_get_error_message( ctx_out ).to!string();
            sass_delete_file_context( ctx );
            throw new SassCompileException( error );
        }

        auto result = sass_context_get_output_string( ctx_out ).to!string();

        if( output != "" )
        {
            createResultFile( output, result );

            if( options.sourcemap.enabled )
                createMapFile( output, sass_context_get_source_map_string( ctx_out ).to!string() );

            sass_delete_file_context( ctx );

            return null;
        }

        static if( isMapUsing )
            sourcemap = sass_context_get_source_map_string( ctx_out ).to!string();

        sass_delete_file_context( ctx );

        return result;
    }

    void watchDirImpl( in string input, in string output )
    {
        auto event = getThreadEventLoop();
        auto watcher = new AsyncDirectoryWatcher( event );
        bool isStoppableError;
        
        if( options.singleFile.enabled )
        {
            watcher.run({
                bool isFailed;

                try
                    compileFolder( input, output );
                catch( SassCompileException e )
                {
                    isFailed = true;

                    if( options.compileError != null )
                        isStoppableError = options.compileError( e );
                }

                if( options.compileSuccess != null && !isFailed )
                    options.compileSuccess( input, output );
            });
        }
        else
        {
            DWChangeInfo[1] change;
            DWChangeInfo[] changeRef = change.ptr[0..1];

            watcher.run({
                auto isCompiled = false;
                while(watcher.readChanges( changeRef ))
                {
                    if(!isCompiled)
                    {
                        bool isFailed;
                        auto inputName = change[0].path;
                        auto outputName = buildPath(
                            output,
                            baseName( inputName.setExtension( "css" ) )
                        );

                        try
                            compileFile( inputName, outputName );
                        catch( SassCompileException e )
                        {
                            isFailed = true;
                             
                            if( options.compileError != null )
                                isStoppableError = options.compileError( e );
                        }

                        if( options.compileSuccess != null && !isFailed )
                            options.compileSuccess( inputName, outputName );
                        
                        isCompiled = true;
                    }
                }
            });
        }
        
        watcher.watchDir( input );
        
        bool isOwnerTerminated;
        
        while( event.loop() )
        {
            if( !isOwnerTerminated )
            {
                bool isStopped;
                receive(
                    ( bool stop ) { isStopped = stop; },
                    ( OwnerTerminated e ) { isOwnerTerminated = true; }
                );
                
                if( isStopped )
                    break;
            }

            if( isStoppableError )
                break;

            continue;
        }
    }
}

/// SASS root exception
class SassException : Exception
{
    this( string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null )
    {
        super( msg, file, line, next );
    }
}

/// SASS runtime exception not connected to code compilation error
class SassRuntimeException : SassException
{
    this( string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null )
    {
        super( msg, file, line, next );
    }
}

/// SASS code compilation exception
class SassCompileException : SassException
{
    this( string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null )
    {
        super( msg, file, line, next );
    }
}

private:

/**
 * SASS option specifier implementation. It allows configuring SASS compiler as
 * you need. This struct is private and available only through `sass.options`
 * call.
 */
shared struct SassOptions
{
    /// Source map configuration tool
    SourceMap sourcemap;

    /// Extension configuration tool
    ExtensionSettings extension;

    /// SASS to SCSS configuration tool 
    Sass2ScssSettings sass2scss;

    /// Single file configuration tool
    SingleFile singleFile;

    /// Controls emitting inline source comments
    Switcher sourceComments;

    /// Controls treating source as SASS (as opposed to SCSS) 
    Switcher indentedSyntax;

    /// Handles compilation error within watcher loop
    CompileErrorHandler compileError;

    /// Handles compilation success within watcher loop
    CompileSuccessHandler compileSuccess;

    private
    {
        SassStyle _style = SassStyle.NESTED;
        string _includePaths;
        string _imagePath;
        int _precision;
    }

    @property
    {
        /// Output style for the generated CSS code
        void style( in SassStyle value ) { _style = value; }
        SassStyle style() const { return _style; }

        /// `@import` directive search locations
        void includePaths( in string path ) { _includePaths = path; }
        string includePaths() const { return _includePaths; }

        /// Optional path to find images
        void imagePath( in string path ) { _imagePath = path; }
        string imagePath() const { return _imagePath; }

        /// Number precision of computed values.
        void precision( in int value ) { _precision = value; }
        int precision() const { return _precision; }
    }

    /// Resets SASS options to its default
    void reset() { this = SassOptions.init; }

    Sass_Options* get() const
    {
        if( style == SassStyle.COMPACT || style == SassStyle.EXPANDED )
            throw new SassRuntimeException( "Only `nested` and `compressed` output"
                ~ " styles are currently supported" );

        auto options = sass_make_options();

        sass_option_set_precision( options, precision );
        sass_option_set_output_style( options, cast(int)style );
        sass_option_set_source_comments( options, sourceComments.enabled );
        sass_option_set_source_map_embed( options, sourcemap.sourceMappingUrl.embedding.enabled );
        sass_option_set_source_map_contents( options, sourcemap.includeContent.enabled );
        sass_option_set_omit_source_map_url( options, !sourcemap.sourceMappingUrl.enabled );
        sass_option_set_is_indented_syntax_src( options, indentedSyntax.enabled );
        sass_option_set_include_path( options, includePaths.toStringz() );
        sass_option_set_image_path( options, imagePath.toStringz() );

        return options;
    }
}

/**
 * SASS version controller. It contains versions of libsass, sass2scss plugin 
 * and sassed itself. Available only through `sass.versions` call.
 */
shared struct Version
{
    private enum _version = "0.2.0";
    
    @property
    {
        /// Libsass version
        string libsass() const { return libsass_version().to!string(); }
        
        /// Sass2scss version
        string sass2scss() const { return sass2scss_version().to!string(); }
        
        /// Sassed version
        string sassed() const { return _version; }
    }
}

/**
 * Source map configurator implementation. Available only through
 * `sass.options.sourcemap` call.
 */
shared struct SourceMap
{
    mixin SwitcherInterface;

    /// SourceMappingUrl configuration tool
    SourceMappingUrl sourceMappingUrl;

    /// Controls embedding include contents in maps
    Switcher includeContent;

    private
    {
        string _extension = ".map";
        bool _enabled;
    }

    @property
    {
        /// Map file exstension. Default is `.map`
        void extension( in string extension_ ) { _extension = "." ~ extension_; }
        string extension() const { return _extension; }
    }
}

/**
 * Exstension configurator. Defines SASS and SCSS extension names. Available
 * only through `sass.options.extension` call.
 */
shared struct ExtensionSettings
{
    private
    {
        string _scss = "scss";
        string _sass = "sass";
    }

    @property
    {
        /// SASS extension name
        void sass( in string ext ) { _sass = ext; }
        string sass() const { return _sass; }

        /// SCSS extension name
        void scss( in string ext ) { _scss = ext; }
        string scss() const { return _scss; }
    }
}

/**
 * SASS to SCSS converter configurator. Available only through
 * `sass.options.sass2scss` call.
 */
shared struct Sass2ScssSettings
{
    private
    {
        int _prettifyState = PrettifyLevel.ZERO;
        int _commentState;
    }

    /// Converter prettify level
    @property void prettifyLevel( PrettifyLevel level )
    {
        _prettifyState = level;
    }

    /// Removes one-line comment
    void keepComments() { _commentState = SASS2SCSS_KEEP_COMMENT; }

    /// Removes multi-line comments 
    void stripComments() { _commentState = SASS2SCSS_STRIP_COMMENT; }

    /// Converts one-line comments to multi-line
    void convertComments() { _commentState = SASS2SCSS_CONVERT_COMMENT; }

    int get() const
    {
        return _prettifyState | _commentState;
    }
}

/**
 * Single file compilation configurator. Available only through
 * `sass.options.singleFile` call.
 */
shared struct SingleFile
{
    mixin SwitcherInterface; 

    /// Source comments configuration tool
    SourceComments comments;

    private string _name = "style";

    @property
    {
        /// Single file name
        void name( in string name_ ) { _name = name_; }
        string name() const { return _name; }
    }
}

/**
 * Single file source comments configurator. Available only through
 * `sass.options.singleFile.comments` call.
 */
shared struct SourceComments
{
    mixin SwitcherInterface; 

    private
    {
        string _placeholder = "%{filename}";
        string _template = "Source: %{filename}";
    }

    @property
    {
        /// Placeholder string that will be replaced in template
        void placeholder( in string placeholder_ ) { _placeholder = placeholder_; }
        string placeholder() const { return _placeholder; }
        
        /**
         * Source comment template that will be placed as a delimiter between
         * compiled code in result file. It should contain placeholder defined
         * by `placeholder` method, that will be replaced by file name
         */
        void templ( in string template_ )
        {
            if( !template_.canFind( placeholder ))
                throw new SassRuntimeException( format( "Template should contain"
                        ~ " placeholder `%s` for file name", placeholder ));
            
            _template = template_;
        }
        
        string templ() const
        {
            if( _template == "" )
                return "File " ~ placeholder;
            else
                return _template;
        }
    }
}

/**
 * Source mapping url configurator. Available only through
 * `sass.options.sourcemap.sourceMappingUrl` call.
 */
shared struct SourceMappingUrl
{
    /// Controls embedding sourceMappingUrl as data uri
    Switcher embedding;

    mixin SwitcherInterface;
}

/**
 * Structure implementation of $(D SwitcherInterface) 
 */
shared struct Switcher
{
    mixin SwitcherInterface;
}

/**
 * Switcher interface for structures. It implements three methods:
 * $(OL
 *      $(LI Current state)
 *      $(LI Enabling configurator)
 *      $(LI Disabling configurator)
 * )
 */
mixin template SwitcherInterface()
{
    private bool _enabled;

    /// Returns: Configurator current state
    @property bool enabled() const { return _enabled; }

    /// Enables switcher
    void enable() { _enabled = true; }

    /// Disables switcher
    void disable() { _enabled = false; }
}