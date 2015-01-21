/**
 * Console implementation for SASS compiler.
 */

module sassed.console;

private
{
    import sassed.sass : SassStyle, Sass, SassCompileException;

    import std.string : format;
    import std.array : Appender, join;
    import std.stdio : writeln, writefln, readf, File;
    import std.getopt : getopt, config;
    import std.algorithm : canFind;
    import std.datetime : DateTime, Clock;
}

/**
 * SASS console compiler main implementation
 */
class SassConsole
{
    protected
    {
        enum Version = "0.1.0";

        shared(Sass) sass;
        SassStyle[string] styles;

        string executableName;
        Command command;
        string input;
        string output;

        bool isStdinUsing;
        bool isSingleFile;
        string style;
        bool isLineNumberUsing;
        string loadPath;
        bool isSourceMapEmitting;
        bool isMapCommentOmitting;
        int precision;

        bool isVersionNeeding;
        bool isHelpNeeding;
    }

    this( string[] args )
    {
        sass = new shared Sass;

        styles = [
            "nested" : SassStyle.NESTED,
//            "expanded" : SassStyle.EXPANDED,  // not allowed in libsass by now
//            "compact" : SassStyle.COMPACT,    // not allowed in libsass by now
            "compressed" : SassStyle.COMPRESSED
        ];

        auto commands = [
            "folder" : Command.FOLDER,
            "watch" : Command.WATCH
        ];

        getopt(
            args,
            config.passThrough,
            config.caseSensitive,
            "s|stdin",                      &isStdinUsing,
            "u|single-file",                &isSingleFile,
            "t|style",                      &style,
            "l|line-numbers|line-comments", &isLineNumberUsing,
            "I|load-path",                  &loadPath,
            "m|sourcemap",                  &isSourceMapEmitting,
            "M|omit-map-comment",           &isMapCommentOmitting,
            "p|precision",                  &precision,
            "v|version",                    &isVersionNeeding,
            "h|help",                       &isHelpNeeding,
        );

        executableName = args[0];

        if( args.length == 1 && !isVersionNeeding)
        {
            isHelpNeeding = true;
            return;
        }

        if( commands.keys.canFind( args[1] ))
        {
            command = commands[args[1]];

            isStdinUsing = false;
            
            if( args.length > 3 )
            {
                input = args[2];
                output = args[3];
            }
            else
                throw new SassConsoleException( format( "If command `%s` is used,"
                    ~ " both input and output should be defined", args[1] ));
        }
        else
        {
            if( isStdinUsing )
                output = args[1];
            else
                input = args[1];
            
            if( args.length > 2 && !isStdinUsing )
                output = args[2];
        }
    }

    ~this()
    {
        sass.destroy();
    }

    /**
     * Starts the compilation
     */
    void run ()
    {
        if( isHelpNeeding )
        {
            help();
            return;
        }

        if( isVersionNeeding )
        {
            getVersion();
            return;
        }

        if( isSingleFile )
        {
            if( command == Command.NONE )
                throw new SassConsoleException( format( "Option `single-file` can"
                    ~ " be applied only for `folder` and `watch` commands" ));

            sass.options.singleFile.enable();
        }

        if( style != "" )
        {
            if( !styles.keys.canFind( style ))
                throw new SassConsoleException( format( "Style `%s` does not"
                    ~ " allowed here. Allowed styles: %s", style, styles.keys.join( ", " )));
            
            sass.options.style = styles[style];
        }

        if( isLineNumberUsing )
            sass.options.sourceComments.enable();

        if( loadPath != "" )
            sass.options.includePaths = loadPath;

        if( isMapCommentOmitting )
            sass.options.sourcemap.sourceMappingUrl.disable();

        if( precision > 0 )
            sass.options.precision = precision;

        try
        {
            switch( command ) with( Command )
            {
                case FOLDER:
                    folderRun();
                    break;
                    
                case WATCH:
                    watchRun();
                    break;
                    
                default:
                    defaultRun();
                    break;
            }
        }
        catch( SassCompileException e )
        {
            writefln( "[%s] %s", currentTime,  e.msg );
        }
    }

protected:
    
    void help()
    {
        writefln( "Usage: %s [command] [options] [INPUT] [OUTPUT]", executableName );
        writeln( "Commands:" );
        writefln( "%10s - %s", "folder", "Compiles INPUT folder files to OUTPUT folder." );
        writefln( "%10s - %s", "watch ", "Watching INPUT folder, and if any file changes, recompile it to OUTPUT" );

        writeln( "Options:" );

        writeln( formatHelp("s", "stdin", "Read input from standard input instead of an input file."));
        writeln( formatHelp("u", "single-file", "Compiling directory to single css-file."));
        writeln( formatHelp("t", "style NAME", "Output style. Can be:"));

        foreach( name, ref style; styles )
            writeln( formatHelp( "", "", "- " ~ name ));

        writeln( formatHelp( "l", "line-numbers", "Emit comments showing original line numbers." ));
        writeln( formatHelp( "", "line-comments", "" ));
        writeln( formatHelp( "I", "load-path PATH", "Set Sass import path." ));
        writeln( formatHelp( "m", "sourcemap", "Emit source map." ));
        writeln( formatHelp( "M", "omit-map-comment", "Omits the source map url comment." ));
        writeln( formatHelp( "p", "precision", "Set the precision for numbers." ));
        writeln( formatHelp( "v", "version", "Display compiled versions." ));
        writeln( formatHelp( "h", "help", "Display this help message." ));
        writeln( "" );
    }

    void getVersion()
    {
        writeln( "Current sassed version: " ~ Version );
    }

    string formatHelp( in string shortCommand, in string longCommand, in string description ) const
    {
        Appender!string result;

        if( shortCommand != "" )
        {
            result ~= format(
                "%6s, %-22s %s",
                shortCommand != ""? "-" ~ shortCommand : "",
                longCommand != ""? "--" ~ longCommand : "",
                description
            );
        }
        else
        {
            result ~= format(
                "%7s %-22s %s",
                "",
                longCommand != ""? "--" ~ longCommand : "",
                description
            );
        }
        
        return result.data;
    }

    void defaultRun()
    {
        if( !isStdinUsing )
        {
            if( output != "" )
            {
                if( isSourceMapEmitting )
                    sass.options.sourcemap.enable();
                
                sass.compileFile( input, output );
            }
            else
                writeln( sass.compileFile( input ));
        }
        else
        {
            string contents;
            writeln( "Enter your code:" );
            readf( "%s", &contents );
            
            if( output != "" )
            {
                string result;

                if( isSourceMapEmitting )
                {
                    string sourcemap;

                    sass.options.sourcemap.enable();
                    result = sass.compile( contents, sourcemap );

                    sass.createMapFile( output, sourcemap );
                }
                else
                    result = sass.compile( contents );

                auto file = File( output, "w+" );
                file.write( result );
                file.close();
            }
            else
                writeln( sass.compile( contents ));
        }
    }

    void folderRun()
    {
        if( isSourceMapEmitting )
        {
            if( isSingleFile )
                throw new SassConsoleException( "By now source map does not"
                    ~ " implemented for single file compilation" );

            sass.options.sourcemap.enable();
        }

        sass.compileFolder( input, output );
    }

    void watchRun()
    {
        if( isSourceMapEmitting )
        {
            if( isSingleFile )
                throw new SassConsoleException( "By now source map does not"
                    ~ " implemented for single file compilation" );
            
            sass.options.sourcemap.enable();
        }

        sass.watchDir( input, output );
    }

    @property string currentTime()
    {
        auto date = cast(DateTime) Clock.currTime;
        return format(
            "%s.%s.%s %s:%s:%s",
            date.day,
            cast(ubyte) date.month,
            date.year,
            date.hour,
            date.minute,
            date.second
        );
    }
}

class SassConsoleException : Exception
{
    this( string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null )
    {
        super( msg, file, line, next );
    }
}

private:

enum Command : byte
{
    NONE,
    FOLDER,
    WATCH
}