# sassed
Thin wrapper for libsass written in D Programming Language.

### It can
 * Compile received string to css and return resulting css code
 * Compile single file and put it to a specified folder
 * Compile whole folder to multiple files and put it to another folder
 * Compile whole folder to a single file
 * Compile from `.sass` and `.scss` files
 * Watch input folder and recompile files within output when user changing some of them

### Library usage

First of all you should create new Sass object
```d
auto sass = new shared Sass;
```

Then you should set options you need.
Sassed has next configurators:
* Source map - configurates source map generation.
```d
// Enabling source map generaion
sass.options.sourcemap.enable();

// Defining source map file extension (`.map` by default)
sass.options.sourcemap.extension = "newmap" // without a point before extension

// Disabling source mapping url (`true` by default)
sass.options.sourcemap.sourceMappingUrl.disable();

// Embedding source mapping url
sass.options.sourcemap.sourceMappingUrl.embedding.enable();
```
* Extensions - configurates SASS and SCSS file extensions.
```d
// Defining new SASS extension (`.sass` by default)
sass.options.extensions.sass = "sassmap" // without a point before extension
```
* SASS to SCSS - configurate SASS to SCSS compilation (only for method `convertSass2Scss`).
```d
// Setting sass2scss prettify level
sass.options.sass2scss.prettifyLevel = PrettifyLevel.ZERO;

// Setting comment conversion
sass.options.sass2scss.stripComments();
```
* Single file - configurate folder-to-file compilation
```d
// Setting single file name (`style` by default)
sass.options.singleFile.name = "mystyle";

// Enabling single file source comments splitting compiled code blocks from
// different files
sass.options.singleFile.comments.enable();

// Setting placeholder for source comments (`%{filename}` by default)
sass.options.singleFile.comments.placeholder = "%{file}";

// Setting new comment template. Changing placeholder you should always change
// template
sass.options.singleFile.comments.templ = "This code came from: %{file}";

```
Sassed options:
* Source comments - enables inline source comments
```d
sass.options.sourceComments.enable();
```
* Indented syntax - enables compiling from SASS instead of SCSS
```d
sass.options.indentedSyntax.enable();
```
* Style - defines output CSS style. By now libsass supports only `nested` and `compressed` styles.
```d
sass.options.style = SassStyle.COMPRESSED;
```
* Include path - defines `@import` directive search location
```d
sass.options.includePaths = "path/to/import";
```
* Image path - defines optional path to find images
```d
sass.options.imagePath = "path/to/images";
```
* Precision - defines number precision of computed values
```d
sass.options.precision = 2;
```

After setting options you can compile your files by next methods:
* String-to-string compilation (also you can get source map string by `out` parameter in overloaded method signature)
* File-to-file / file-to-string compilation (source map string available)
* Folder-to-folder / folder-to-file compilation
* Folder watching. This method creates thread watching some directory and compiling changed file (or all folder if `singleFile` is enabled). Be careful: if you change sass options, it will change in watching thread too.

```d
// String-to-string compilation method with getting source map string
string sourcemap;
auto code = "#map{ & .inner-map {} }"
auto result = sass.compile( code, sourcemap );
```

### Console usage
Simple compiling file to file
```bash
$ ./sassed some.scss some.css -m
```

Compiling folder to folder
```bash
$ ./sassed folder path/to/input path/to/output
```

Compiling folder to single file. Folder will be compiled in path/to/output/style.css.
```bash
$ ./sassed folder path/to/input path/to/output -u
```

Watching folder
```bash
$ ./sassed watch path/to/input path/to/output
```

More about options can be find in `help`
```bash
$ ./sassed -h
```