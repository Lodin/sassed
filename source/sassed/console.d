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
        string input;
        string output;

        bool isStdinUsing;
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

        getopt(
            args,
            config.passThrough,
            config.caseSensitive,
            "s|stdin",                      &isStdinUsing,
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
            isHelpNeeding = true;

        if( args.length > 1 )
        {
            if( isStdinUsing )
                output = args[1];
            else
                input = args[1];
        }

        if( args.length > 2 && !isStdinUsing )
            output = args[2];
    }

    void run ()
    {
        if( isHelpNeeding )
        {
            help();
            return;
        }

        if( style != "" )
        {
            if( !styles.keys.canFind( style ))
                throw new SassConsoleException( format( "Style `%s` does not"
                    ~ "allowed here. Allowed styles: %s", style, styles.keys.join ( ", " )));
            
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

        if( !isStdinUsing )
        {
            if( output != "" )
            {
                if( isSourceMapEmitting )
                    sass.options.sourcemap.file = output ~ ".map";

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
                auto result = sass.compile( contents );
                auto file = File( output, "w+" );
                file.write( result );
                file.close();
            }
            else
                writeln( sass.compile( contents ));
        }
    }

    void help()
    {
        writefln( "Usage: %s [options] [INPUT] [OUTPUT]", executableName );
        writeln( "Options:" );

        writeln( formatHelp("s", "stdin", "Read input from standard input instead of an input file."));
        writeln(formatHelp("t", "style NAME", "Output style. Can be:"));

        foreach (name, ref style; styles)
            writeln(formatHelp("", "", "- " ~ name));

        writeln( formatHelp( "l", "line-numbers", "Emit comments showing original line numbers." ));
        writeln( formatHelp( "", "line-comments" ));
        writeln( formatHelp( "I", "load-path PATH", "Set Sass import path." ));
        writeln( formatHelp( "m", "sourcemap", "Emit source map." ));
        writeln( formatHelp( "M", "omit-map-comment", "Omits the source map url comment." ));
        writeln( formatHelp( "p", "precision", "Set the precision for numbers." ));
        writeln( formatHelp( "v", "version", "Display compiled versions." ));
        writeln( formatHelp( "h", "help", "Display this help message." ));
        writeln( "" );
    }

protected:

    string formatHelp( string shortCommand = "", string longCommand = "", string description = "" )
    {
        Appender!string result = "";

        if( longCommand != "" )
            longCommand = "--" ~ longCommand;

        if( shortCommand != "" )
        {
            shortCommand = "-" ~ shortCommand;
            result ~= format( "%6s, %-22s %s", shortCommand, longCommand, description );
        }
        else
            result ~= format( "%7s %-22s %s", shortCommand, longCommand, description );
        
        return result.data;
    }
}

class SassConsoleException : Exception
{
    this( string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null )
    {
        super( msg, file, line, next );
    }
}