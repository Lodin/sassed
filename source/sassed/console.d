module sassed.console;

private
{
    import sassed.sass : SassStyle, Sass;

    import std.string : format;
    import std.array : Appender, join;
    import std.stdio : writeln, writefln, readf, File;
    import std.getopt : getopt, config;
    import std.algorithm : canFind;
}

class SassConsole
{
    protected
    {
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
            "h|help",                       &isHelpNeeding,
        );

        executableName = args[0];

        if( args.length == 1 )
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

    void run ()
    {
        if( isHelpNeeding )
        {
            help();
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
            sass.options.emitComments();

        if( loadPath != "" )
            sass.options.includePaths = loadPath;

        if( isMapCommentOmitting )
            sass.options.sourcemap.omitSourceUrl();

        if( precision > 0 )
            sass.options.precision = precision;

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

    void help() const
    {
        writefln( "Usage: %s [options] [INPUT] [OUTPUT]", executableName );
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

protected:

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
                shortCommand != ""? "-" ~ shortCommand : "",
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