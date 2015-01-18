// Written in the D Programming Language
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

public
{
    import dlogg.log : LoggingLevel;
}

private
{
    import derelict.sass.sass;

    import dlogg.log : ILogger;
    import dlogg.strict : StrictLogger;
    import libasync.watcher : AsyncDirectoryWatcher, DWChangeInfo;
    import libasync.events : getThreadEventLoop;

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
 *     $(LI Internal SASS compiling error handler. When compiler detects SASS
 *          code error, it writes info to a log file (default `sass_errors.log`),
 *          and shows it in console if available)
 *     $(LI SASS to SCSS converter. It allows implicit conversion from SASS code
 *          to CSS through the interjacent conversion to SCSS)
 * )
 */
shared class Sass
{
    /// Contains SASS compiler options list
    SassOptions options;
    protected ILogger logger;

    this()
    {
        if( !DerelictSass.isLoaded )
            DerelictSass.load();
    }

    ~this()
    {
        logger.destroy();
    }

    /**
     * Compiles SASS string to CSS string.
     * 
     * Params: source = SASS code to compile
     * 
     * Returns: compiled CSS code
     */
    immutable(string) compile( in string source )
    {
        string sourcemap;

        if( options.sourcemap.enabled )
            return compileImpl!true( source, sourcemap );
        else
            return compileImpl!false( source, sourcemap );
    }

    /**
     * Compiles SASS string to CSS string and generates sourcemap.
     * 
     * Params:
     *         source = SASS code to compile
     *         sourcemap = returns SASS sourcemap string
     * 
     * Returns: compiled CSS code.
     */
    immutable(string) compile( in string source, out string sourcemap )
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
    immutable(string) compileFile( in string input, in string output = null )
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
     *         sourcemap = returns SASS sourcemap string
     * 
     * Returns: compiled CSS code, if `output` parameter is empty. Otherwise
     *          null
     */
    immutable(string) compileFile( in string input, in string output, out string sourcemap )
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
     * `singleFile.name`. By now it is impossible to create sourcemap to that
     * file. 
     * 2) Otherwise, method compiles SASS files name-by-name to the folder
     * `output`. Sourcemaps will be created too. 
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
            if( options.singleFile.isSourceCommentsEmitted )
            {
                file.writeln(
                    "\n/* " 
                    ~ options.singleFile.sourceCommentTemplate.replace(
                        options.singleFile.placeholder,
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
                {
                    auto compiled = compile( sass2scss(
                        name.readText().toStringz(),
                        options.sass2scss.get()
                    ).to!string() );
                    
                    writeCommentedFile( file, name, compiled );
                }
                else
                {
                    auto result = compileFile( name );
                    writeCommentedFile( file, name, result );
                }
            });
        }
        else
        {
            each(( name )
            {
                if( name.extension[1..$] == options.extension.sass )
                {
                    string compiled;

                    auto outputFile = buildOutputPath( name );

                    if( options.sourcemap.enabled )
                    {
                        string sourcemap;

                        compiled = compile( sass2scss(
                            name.readText().toStringz(),
                            options.sass2scss.get(),
                        ).to!string(), sourcemap );

                        createMapFile( output, sourcemap );
                    }
                    else
                    {
                        compiled = compile( sass2scss(
                            name.readText().toStringz(),
                            options.sass2scss.get()
                        ).to!string() );
                    }

                    createResultFile( outputFile, compiled.to!string() );
                }
                else
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
     * Creates result CSS file in `output` path from `source` string
     * 
     * Params: 
     *         output = result file name with path
     *         source = source code to write
     */
    void createResultFile( string output, string source )
    {
        auto file = File( output, "w+" );
        file.write( source );
        file.close();
    }

    /**
     * Creates sourcemap file in `output` path from `source` string
     * 
     * Params: 
     *         output = result file name with path
     *         source = source code to write
     */
    void createMapFile( string output, string source )
    {
        createResultFile( output ~ options.sourcemap.extension, source );
    }

protected:

    void testDirs( in string input, in string output )
    {
        if( !input.exists() )
            throw new SassException( format( "Directory `%s` does not exist", input ));

        if( !input.isDir() )
            throw new SassException( format( "`%s` is not a directory", input ));
        
        if( !output.exists() )
            mkdir( output );
    }

    void log( in string message )
    {
        if ( !logger )
        {
            string file;
            
            if( options.log.file != "" && options.log.file.exists() )
                file = options.log.file;
            else
                file = "sass_errors.log";
            
            logger = new shared StrictLogger( file );
            logger.minOutputLevel = options.log.level;
        }

        logger.log( message, options.log.level );
    }

    immutable(string) compileImpl( bool isMapUsing )(
        in string source,
        out string sourcemap
    )
    {
        string result;
        auto ctx = sass_new_context();
        
        ctx.options = options.get();
        ctx.source_string = source.toStringz();

        static if( isMapUsing )
            ctx.options.source_map_file = toStringz( "temp" ~ options.sourcemap.extension );
        else
            ctx.options.source_map_file = "".toStringz();
        
        sass_compile( ctx );
        
        if( ctx.error_status )
            log( ctx.error_message.to!string() );
        
        static if( isMapUsing )
            sourcemap = ctx.source_map_string.to!string();
        
        result = ctx.output_string.to!string();
        sass_free_context( ctx );
        
        return result;
    }

    immutable(string) compileFileImpl( bool isMapUsing )(
        in string input,
        in string output,
        out string sourcemap
    )
    {
        if( !input.exists() )
            throw new SassException( format( "File `%s` does not exist", input ));
        
        if( !input.isFile() )
            throw new SassException( format( "`%s` is not a file", input ));
        
        auto ctx = sass_new_file_context();
        
        ctx.options = options.get();
        ctx.input_path = input.toStringz();
        ctx.output_path = output.toStringz();

        static if( isMapUsing )
            ctx.options.source_map_file = toStringz( output ~ options.sourcemap.extension );
        else
            ctx.options.source_map_file = "".toStringz();
        
        sass_compile_file( ctx );
        
        if( ctx.error_status )
            log( ctx.error_message.to!string() );
        
        auto result = ctx.output_string.to!string();
        
        if( output != "" )
        {
            auto file = File( output, "w+" );
            file.write( result );
            file.close();
            
            if( options.sourcemap.enabled )
                createMapFile( output, ctx.source_map_string.to!string() );
            
            sass_free_file_context( ctx );
            
            return null;
        }
        
        static if( isMapUsing )
            sourcemap = ctx.source_map_string.to!string();
        
        sass_free_file_context( ctx );
        
        return result;
    }

    void watchDirImpl( in string input, in string output )
    {
        auto event = getThreadEventLoop();
        auto watcher = new AsyncDirectoryWatcher( event );
        
        if( options.singleFile.enabled )
        {
            watcher.run({
                compileFolder( input, output );
            });
        }
        else
        {
            DWChangeInfo[2] change;
            DWChangeInfo[] changeRef = change.ptr[0..2];
            
            watcher.run({
                watcher.readChanges( changeRef );
                compileFile(
                    change[0].path,
                buildPath ( output, baseName( change[0].path.setExtension( "css" )))
                );
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

private:

/**
 * SASS option specifier implementation. It allows configuring SASS compiler as
 * you need. This struct is private and available only through `sass.options`
 * call.
 */
shared struct SassOptions
{
    /// Sourcemap configuration tool
    SourceMap sourcemap;

    /// Log configuration tool
    LogSettings log;

    /// Extension configuration tool
    ExtensionSettings extension;

    /// SASS to SCSS configuration tool 
    Sass2ScssSettings sass2scss;

    /// Single file configuration tool
    SingleFile singleFile;

    private
    {
        bool _isCommentsEmitted;
        bool _isSyntaxIndented;

        SassStyle _style = SassStyle.NESTED;
        string _includePaths;
        string _imagePath;
        int _precision;
    }

    @property
    {
        /// Output CSS style
        void style( in SassStyle value ) { _style = value; }
        SassStyle style() const { return _style; }

        /// Defines `@import` search locations
        void includePaths( in string path ) { _includePaths = path; }
        string includePaths() const { return _includePaths; }

        /// Defines optional path to find images
        void imagePath( in string path ) { _imagePath = path; }
        string imagePath() const { return _imagePath; }

        /// Defines the number precision of computed values.
        void precision( in int value ) { _precision = value; }
        int precision() const { return _precision; }
    }

    void emitComments() { _isCommentsEmitted = true; }
    void enableIndentedSyntax() { _isSyntaxIndented = true; }

    sass_options get() const
    {
        if( style == SassStyle.COMPACT || style == SassStyle.EXPANDED )
            throw new SassException( "Only `nested` and `compressed` output"
                ~ " styles are currently supported" );
        
        sass_options options;
        
        options.output_style = cast(int)style;
        options.source_comments = _isCommentsEmitted;
        options.omit_source_map_url = sourcemap.isSourceUrlOmitted;
        options.source_map_embed = sourcemap.isSourceUrlEmbedded;
        options.source_map_contents = sourcemap.isIncludeContentEmbedded;
        options.is_indented_syntax_src = _isSyntaxIndented;
        options.include_paths = includePaths.toStringz();
        options.image_path = imagePath.toStringz();
        options.precision = precision;

        return options;
    }
}

shared struct SourceMap
{
    private
    {
        string _extension = ".map";
        bool _enabled;

        bool _isSourceUrlOmitted;
        bool _isSourceUrlEmbedded;
        bool _isIncludeContentEmbedded;
    }

    @property
    {
        void extension( in string extension_ ) { _extension = "." ~ extension_; }
        string extension() const { return _extension; }
        bool enabled() const { return _enabled; }

        bool isSourceUrlOmitted() const { return _isSourceUrlOmitted; }
        bool isSourceUrlEmbedded() const { return _isSourceUrlEmbedded; }
        bool isIncludeContentEmbedded() const { return _isIncludeContentEmbedded; }
    }

    void enable() { _enabled = true; }
    void disable() { _enabled = false; }

    void omitSourceUrl() { _isSourceUrlOmitted = true; }
    void embedSourceUrl() { _isSourceUrlEmbedded = true; }
    void embedIncludeContent() { _isIncludeContentEmbedded = true; }
}

shared struct LogSettings
{
    private
    {
        string _file;
        LoggingLevel _level = LoggingLevel.Fatal;
    }

    @property
    {
        void file( in string file_ ) { _file = file_; }
        string file() const { return _file; }

        void level( in LoggingLevel level_ ) { _level = level_; }
        LoggingLevel level() const { return _level; }
    }
}

shared struct ExtensionSettings
{
    private
    {
        string _scss = "scss";
        string _sass = "sass";
    }

    @property
    {
        string sass() const { return _sass; }
        void sass( in string ext ) { _sass = ext; }

        string scss() const { return _scss; }
        void scss( in string ext ) { _scss = ext; }
    }
}

shared struct Sass2ScssSettings
{
    private
    {
        int _prettifyState = PrettifyLevel.ZERO;
        int _commentState = SASS2SCSS_KEEP_COMMENT;
    }

    @property void prettifyLevel( PrettifyLevel level )
    {
        _prettifyState = level;
    }

    void keepComments() { _commentState = SASS2SCSS_KEEP_COMMENT; }
    void stripComments() { _commentState = SASS2SCSS_STRIP_COMMENT; }
    void convertComments() { _commentState = SASS2SCSS_CONVERT_COMMENT; }

    int get() const
    {
        return _prettifyState | _commentState;
    }
}

shared struct SingleFile
{
    private
    {
        string _name = "style";
        string _placeholder = "%{filename}";

        bool _enabled;
        bool _isSourceCommentsEmitted;
        string _sourceCommentTemplate;
    }

    @property
    {
        bool enabled() const { return _enabled; }
        bool isSourceCommentsEmitted() const { return _isSourceCommentsEmitted; }

        void name( in string name_ ) { _name = name_; }
        string name() const { return _name; }

        void placeholder( in string placeholder_ ) { _placeholder = placeholder_; }
        string placeholder() const { return _placeholder; }

        void sourceCommentTemplate( in string template_ )
        {
            if( !template_.canFind( placeholder ))
                throw new SassException( format( "Template should contain"
                    ~ " placeholder `%s` for file name", placeholder ));
            
            _sourceCommentTemplate = template_;
        }

        string sourceCommentTemplate() const
        {
            if( _sourceCommentTemplate == "" )
                return "File " ~ placeholder;
            else
                return _sourceCommentTemplate;
        }
    }

    void enable() { _enabled = true; }
    void disable() { _enabled = false; }
    void emitSourceComments() { _isSourceCommentsEmitted = true; }
}