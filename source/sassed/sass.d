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

enum SassStyle : int
{
    NESTED = 0,
    EXPANDED = 1,
    COMPACT = 2,
    COMPRESSED = 3,
}

enum PrettifyLevel
{
    ZERO = SASS2SCSS_PRETTIFY_0,
    FIRST = SASS2SCSS_PRETTIFY_1,
    SECOND = SASS2SCSS_PRETTIFY_2,
    THIRD = SASS2SCSS_PRETTIFY_3
}

shared class Sass
{
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

    immutable(string) compile( in string source )
    {
        string sourcemap;

        if( options.sourcemap.enabled )
            return compileImpl!true( source, sourcemap );
        else
            return compileImpl!false( source, sourcemap );
    }

    immutable(string) compile( in string source, out string sourcemap )
    {
        if( options.sourcemap.enabled )
            return compileImpl!true( source, sourcemap );
        else
            return compileImpl!false( source, sourcemap );
    }

    immutable(string) compileFile( in string input, in string output = "" )
    {
        string sourcemap;

        if( options.sourcemap.enabled )
            return compileFileImpl!true( input, output, sourcemap );
        else
            return compileFileImpl!false( input, output, sourcemap );
    } 

    immutable(string) compileFile( in string input, in string output, out string sourcemap )
    {
        if( options.sourcemap.enabled )
            return compileFileImpl!true( input, output, sourcemap );
        else
            return compileFileImpl!false( input, output, sourcemap );
    } 

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

    Tid watchDir( in string input, in string output )
    {
        testDirs( input, output );
        return spawn( &watchDirImpl, input, output );
    }

    void unwatchDir( scope Tid id )
    {
        send( id, true );
    }

    void createResultFile( string outpath, string source )
    {
        auto file = File( outpath, "w+" );
        file.write( source );
        file.close();
    }

    void createMapFile( string outpath, string source )
    {
        createResultFile( outpath ~ options.sourcemap.extension, source );
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

class SassException : Exception
{
    this( string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null )
    {
        super( msg, file, line, next );
    }
}

private:

shared struct SassOptions
{
    SourceMap sourcemap;
    LogSettings log;
    ExtensionSettings extension;
    Sass2ScssSettings sass2scss;
    SingleFile singleFile;
    SassStyle style = SassStyle.NESTED;
    string includePaths;
    string imagePath;
    int precision;

    private
    {
        bool _isCommentsEmitted;
        bool _isSyntaxIndented;
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