import sassed.console : SassConsole;
import std.stdio : writeln;
import std.c.stdlib : exit;

void main (string[] args)
{
    try
    {
        auto sassConsole = new SassConsole (args);
        sassConsole.run ();
    }
    catch (Exception e)
    {
        writeln (e);
        exit (-1);
    }
}
