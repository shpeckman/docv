<!-- README.md -->
# docv

Parses manual pages and Markdown documents and shows them in a terminal viewer. Written in Crystal; besides the standard library it uses [markd](https://github.com/icyleaf/markd) for Markdown and [treesitter](https://github.com/shpeckman/treesitter) for syntax highlighting.

- **Parser.** A roff interpreter with the man(7) and mdoc(7) macro packages and the tbl(1) preprocessor built in natively. It reads plain and gzip page files and follows `.so` includes. Markdown files (CommonMark with the GitHub extensions) go through markd into the same model (see [Markdown](#markdown)). The result is a document model of blocks and styled spans, with link targets and heading anchors.
- **Layout.** Turns a document into lines of cells. The *wrapped* layout fills paragraphs to the width. The *unwrapped* layout puts each paragraph on one line. Unfilled text and tables never wrap. Lines carry their links: the span links of a document, and cross-references such as `ls(1)` detected in the text.
- **Viewer.** Uses a cell-grid renderer that diffs the screen row by row. Keyboard input uses the kitty protocol, with all enhancements pushed and legacy encodings understood. Mouse input uses SGR-pixel reports. The viewer also handles in-band resize, focus, visibility and color-scheme notifications. The screen is a title row (`ＤＯＣＶ` and the version, which opens the help on a click, the page's heading centered, and a 🞪 close mark), a line, a dock on the left that toggles (`p`), the page with a draggable vertical scrollbar in the last column (only its thumb is drawn), a horizontal scrollbar line (thumb `━`, track `─`) and a status row. The heading of a manual page is its manual and reference (`ABRT Manual - ABRT(1)`; pointing at it shows the footer's source and date beside it, dimmed), of a Markdown document its file name and first heading (`README.md - docv`); the page itself scrolls under it, vertically and horizontally. The dock holds the search field and a tree of the current page's group (or of the current folder's pages and Markdown documents), names that share a prefix folded into nested groups and the current page selected. The field fuzzy-finds in the displayed page, highlighting matches in place, while the tree counts the matching lines of each page; after a leading `/` the tree holds every page of the manual and ranks them instead. The mouse pointer takes the shape of what it is over (OSC 22). It also has links with back navigation (cross-references, files, heading anchors; URLs as OSC 8 hyperlinks), mouse text selection copied to the clipboard, and a help (`h`, or a click on `ＤＯＣＶ`) listing the keys as they are bound, shown in place of the page with `HELP` as the title row's heading. Everything is colored by role from the terminal's own theme, which it queries with OSC 21 (see [Colors](#colors)).

## Requirements

- Crystal 1.21 or newer
- Linux (the viewer uses `termios` and `TIOCGWINSZ`)
- [markd](https://github.com/icyleaf/markd) 0.6 and [treesitter](https://github.com/shpeckman/treesitter) (installed by `shards install`)
- libtree-sitter 0.25 or newer, found through `pkg-config` (Fedora: `libtree-sitter-devel`); it is linked in always
- for syntax highlighting: tree-sitter grammars and their `highlights.scm` queries (see [Syntax highlighting](#syntax-highlighting))

## Installation

```yaml
dependencies:
  docv:
    github: shpeckman/docv
```

The command-line viewer:

    shards install
    make release        # bin/docv
    make install        # ~/.local/bin/docv, man pages in ~/.local/share/man

The manual pages are `man/man1/docv.1` (the command, its keys, mouse, search path, environment and files) and `man/man5/docv-config.5` (`config.ini`). Inside this repository `docv docv` finds them as project pages; after `make install`, `man docv` and `man docv-config` work too.

## Command line

    docv [-u]
    docv [-u] [section] name
    docv [-u] name(section)
    docv [-u] file
    docv path-add dir...
    docv path-rm dir...
    docv path-list
    docv gen-cr [-o dir] [shard]

A `file` is a manual page, or a Markdown document when its name ends in `.md`, `.markdown`, `.mdown`, `.mkd` or `.mkdn` (optionally followed by `.gz`): `docv README.md`. Without a page, the viewer opens on an empty page with the dock closed and a hint in the status row; `p` opens the dock on the pages and documents of the current folder's project, `/` searches every page (this needs a terminal). The viewer starts in the wrapped layout unless `[viewer] start-wrapped = false` is set in `config.ini`; `-u` (`--unwrapped`) starts in the unwrapped layout either way. When standard output is not a terminal, the page is printed as plain text at `MANWIDTH` columns (default 80).

### Search path

Pages are looked up, and listed by the page search, along this path, earlier entries first:

1. **The project around the current directory.** The project root is the nearest directory upward that holds a marker: `.git`, `.hg`, `.svn`, `.jj`, `shard.yml`, `Cargo.toml`, `package.json`, `go.mod`, `pyproject.toml`, `setup.py`, `Gemfile`, `pom.xml`, `build.gradle`, `CMakeLists.txt`, `meson.build`, `configure.ac`, or a `Makefile`. The search stops below the home directory. Without a marker, the current directory itself is the root, unless it is the home directory or `/`. The root and its subfolders are searched up to 4 levels deep, skipping hidden folders, `node_modules`, `vendor`, `lib`, `target`, `__pycache__` and symbolic links. Two kinds of directory count: trees with section directories (`man/man1/tool.1`), and directories with pages in them (`doc/tool.1`, or the root itself). A page there is a file named `name.section` (optionally `.gz`) whose text starts with a roff control character. The Markdown documents found along the way (not hidden ones) are listed by the page search, by their path from the project root.
2. **The added directories**, from `docv path-add`.
3. **The system path**, built as man-db does (manpath(5)):
   - `MANPATH`, where each empty component stands for the default path;
   - otherwise the default path: for each `PATH` element, its `MANPATH_MAP` directories from `/etc/man_db.conf` (or `/etc/manpath.config`), or else whichever of `../man`, `man`, `../share/man` and `share/man` exist next to it;
   - then the `MANDATORY_MANPATH` directories.

Locale subdirectories of a tree come before it (`LC_ALL`, `LC_MESSAGES`, `LANG`), and sections are searched in man-db's order.

| Command                 | Does |
|-------------------------|------|
| `docv path-add dir…` | adds directories (made absolute) to `$XDG_CONFIG_HOME/docv/paths`; each must exist; a directory without man pages gets a warning |
| `docv path-rm dir…`  | removes them; fails for a directory that was not added |
| `docv path-list`     | prints the search path, each entry with its source (`project`, `added`, `system`); `(pages)` marks a directory with pages in it |

`paths` holds one directory per line, and lines starting with `#` are comments. `path-add` and `path-rm` rewrite the file, so comments you add by hand are not kept.

### Man pages of a Crystal shard

`docv gen-cr` generates man pages for a Crystal shard: the nearest directory from `shard` (default: the current directory) upward that holds a `shard.yml`. It runs `crystal docs --format json` there and renders, into `dir` (default `man`, relative to the shard root):

| Page                       | From                                                                     |
|----------------------------|--------------------------------------------------------------------------|
| `man7/name.7cr`            | `README.md`: NAME from its first sentence, its sections, then the list of types |
| `man3/Type.3cr`            | each documented type: synopsis with its `require`, description, inheritance, related types, constants or enum members, constructors, class and instance methods, macros, source files, see also |
| `man3/name-toplevel.3cr`   | the top level methods, macros and constants, when there are any          |

The `cr` suffix keeps the pages from shadowing C library pages. Being under `man/` in the project, they show up right away in `docv`'s page search (`/Bar`) and as `docv Foo::Bar`. Doc comments are Markdown (read with markd): code spans and bold, italic, lists, code blocks, quotes and tables become roff, external links get their URL in angle brackets, and paragraphs starting with `NOTE:`, `TODO:`, `DEPRECATED:` and the other Crystal flags get a bold label. Generated members (`record`'s `clone` and `copy_with`, serializer constructors, enum predicates) are left out.

A page whose content is unchanged keeps its file and date, and generated pages that are no longer produced are removed. Every page carries the comment `Generated by docv gen-cr from README.md and the doc comments; regenerate instead of editing.`; a file in the way without it stops the run. `SOURCE_DATE_EPOCH` sets the date for reproducible builds.

### Configuration

The configuration file is `$XDG_CONFIG_HOME/docv/config.ini`. When `XDG_CONFIG_HOME` is unset or not an absolute path, `~/.config/docv/config.ini` is used. The first run writes a commented default file there. Unknown sections or keys and invalid values are reported as errors.

```ini
[roff]
; run sy, pso, pi, open, opena, write, writec, writem, close, cf, trf, rd and \V
unsafe = false

[viewer]
start-wrapped = true
syntax-highlighting = true
dock = regular
dock-width = 36
dock-open = false
search-threads = 0
```

| Key                     | Default | Meaning                                                                    |
|-------------------------|---------|----------------------------------------------------------------------------|
| `roff.unsafe`           | `false` | run the requests that execute commands or access files (see [roff coverage](#roff-coverage)); booleans accept `true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0` |
| `viewer.start-wrapped`  | `true`  | start in the wrapped layout; `false` starts unwrapped (`w` switches, `-u` starts unwrapped either way) |
| `viewer.syntax-highlighting` | `true` | color code examples by their syntax (see [Syntax highlighting](#syntax-highlighting)) |
| `viewer.dock`           | `regular` | `regular`: the page narrows to make room for the dock; `overlay`: the dock covers the left of the page |
| `viewer.dock-width`     | `36`    | width of the dock in columns (16 to 400); dragging its right edge changes it until the viewer quits |
| `viewer.dock-open`      | `false` | open the dock at start                                                     |
| `viewer.search-threads` | `0`     | processes that read the text of every page and threads that search it (see [Dock](#dock)); `0` is one less than the number of processors |

### Colors

The viewer draws every element in a *role*, and `[colors]` in `config.ini` restyles roles. The default file lists every role with its default, commented out.

```ini
[colors]
heading = bold #ff8800
field = on background+8
selection = black on bright-cyan
```

A style is attribute words (`bold`, `italic`, `underline`, `reverse`, `dim`), a foreground color, and `on` followed by a background color. A color is one of:

- `default`, `foreground` or `background`;
- an ANSI name: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, or `bright-` followed by one of them;
- a palette number `0`-`255`;
- `#rrggbb`.

Named and numbered colors are the terminal theme's own, so the defaults fit any theme. A `+N` or `-N` suffix ramps a color N percent toward the theme's foreground or background. For example, `on background+12` is a bar a shade off the background in a dark and a light theme alike, and `foreground-40` is text dimmed toward the background. Comments go on their own lines.

On entering, the viewer asks the terminal for its theme with OSC 21 (kitty's color control protocol: foreground, background and the 16 ANSI colors), and asks again when the color scheme changes. Once the terminal answers, ramped colors are exact and written as 24-bit color. Without an answer, xterm's colors on a black or white background (by the reported color scheme) stand in. The color depth then comes from the environment: 24-bit with `COLORTERM=truecolor` or `24bit` or a `*-direct` `TERM`, 256 colors with a `256color` `TERM`, the 16 ANSI colors otherwise. Colors past the depth are mapped to the nearest color the terminal shows. With `NO_COLOR` set (and not empty), the viewer shows no colors at all and uses attributes only: bold headings, underlined arguments and links, reverse video for selections. Colors a page sets itself with roff color requests are kept, and are dropped with `NO_COLOR`.

| Key                         | Default                  | Styles |
|-----------------------------|--------------------------|--------|
| `colors.text`                    | (plain)                   | plain page text |
| `colors.heading1`                | `bold bright-blue`        | section headings (`NAME`, `SYNOPSIS`), level 1 document headings |
| `colors.heading2`                | `bold blue`               | subsection headings, level 2 document headings |
| `colors.heading3`                | `bold bright-magenta`     | level 3 headings |
| `colors.heading4`                | `bold magenta`            | level 4 headings |
| `colors.heading5`                | `bold`                    | level 5 headings |
| `colors.heading6`                | `bold foreground-40`      | level 6 headings |
| `colors.bold`                    | `bold cyan`               | bold page text: commands, options |
| `colors.italic`                  | `underline green`         | italic page text: arguments |
| `colors.bold-italic`             | `bold underline green`    | bold italic page text |
| `colors.underline`               | `underline`               | underlined page text (`.ul`) |
| `colors.code`                    | `yellow on background+8`  | inline code in documents |
| `colors.code-block`              | `yellow`                  | code blocks in documents |
| `colors.quote`                   | `foreground-60`           | the `│` bars of block quotes |
| `colors.image`                   | `italic foreground-40`    | the description standing for an image |
| `colors.syntax-keyword`          | `bold magenta`            | keywords in highlighted code (`keyword`, `conditional`, `repeat`, `include`, `exception`, …) |
| `colors.syntax-string`           | `green`                   | strings and characters |
| `colors.syntax-comment`          | `italic foreground-45`    | comments |
| `colors.syntax-function`         | `blue`                    | functions, methods, constructors |
| `colors.syntax-type`             | `cyan`                    | types, namespaces, modules |
| `colors.syntax-constant`         | `red`                     | constants, numbers, booleans, built-in variables |
| `colors.syntax-operator`         | `foreground-15`           | operators |
| `colors.syntax-punctuation`      | `foreground-35`           | brackets, delimiters |
| `colors.syntax-property`         | `bright-cyan`             | properties, fields, attributes |
| `colors.syntax-tag`              | `bright-blue`             | markup tags |
| `colors.link`                    | `underline magenta`       | links: cross-references such as `ls(1)`, files, headings, URLs |
| `colors.link-focus`              | `reverse magenta`         | the focused link |
| `colors.text-selection`          | `on blue-50`              | text selected with the mouse |
| `colors.page-header`             | `bold`                    | the page's heading in the title row (its source and date beside it take `detail`) |
| `colors.title`                   | `bold`                    | `ＤＯＣＶ` |
| `colors.version`                 | `foreground-50`           | the version after the title |
| `colors.close`                   | `red`                     | the 🞪 close mark |
| `colors.border`                  | `foreground-60`           | the line under the title row, the horizontal scrollbar track, the dock's divider |
| `colors.thumb`                   | `bold blue`               | scrollbar thumbs |
| `colors.rule`                    | `foreground-70`           | the rules under the header and above the footer, horizontal rules in documents |
| `colors.field`                   | `on background+12`        | the search field; its `◖` `◗` ends take its background as their color |
| `colors.prompt`                  | `bold blue`               | the leading `/` of a page search |
| `colors.placeholder`             | `foreground-50`           | the hint in the empty search field |
| `colors.cursor`                  | `reverse`                 | the input cursor |
| `colors.message`                 | `yellow`                  | messages such as `Copied 29 characters` |
| `colors.status`                  | `foreground-30`           | status row text |
| `colors.status-separator`        | `foreground-60`           | the `│` between status parts |
| `colors.name`                    | `bold cyan`               | page and document names in the dock's tree |
| `colors.detail`                  | `foreground-35`           | descriptions in the dock's tree |
| `colors.selection`               | `on background+22`        | the selected row of the tree; the line of the selected match in the page |
| `colors.hover`                   | `on background+10`        | the row of the tree under the pointer |
| `colors.mark`                    | `bold underline yellow`   | fuzzy-matched characters, in the list and in the page |
| `colors.hit`                     | `bold green`              | pages in the dock's tree with lines the search in the page matches, and their counts |
| `colors.popup`                   | `on background+6`         | the overlay dock |

### Keys

| Keys                                   | Action                                   |
|----------------------------------------|------------------------------------------|
| `j` `↓` `Ctrl-n` `Ctrl-e`              | line down                                |
| `k` `↑` `Ctrl-p` `Ctrl-y`              | line up                                  |
| `Space` `Ctrl-f` `PgDn`                | page down                                |
| `b` `Ctrl-b` `Shift-Space` `PgUp`      | page up                                  |
| `d` `Ctrl-d` / `u` `Ctrl-u`            | half page down / up                      |
| `g` `<` `Home` / `G` `>` `End`         | top / bottom                             |
| `l`                                    | scroll right 8 columns                   |
| `H` / `L`                              | scroll left / right half a screen        |
| `0` / `$`                              | line start / line end                    |
| `w`                                    | toggle wrapped and unwrapped layout      |
| `f` `t`                                | open the dock with the keyboard in its search field: find in the page |
| `/` `o`                                | the same with `/` typed: find a page or project document |
| `p`                                    | open the dock with the keyboard in its tree, or close it (see [Dock](#dock)) |
| `Tab` / `Shift-Tab`                    | focus next / previous link               |
| `Enter`                                | follow the focused link (see [Links](#links)) |
| `Backspace` `Alt-←`                    | back to the previous page                |
| `h`                                    | help in place of the page (`HELP` in the title row): the keys as bound and the mouse gestures; `j`/`k` and the other scrolling keys scroll it, `l`, `H`, `L`, `0`, `$` and `Shift`-wheel sideways, any other key or a click closes it |
| `Esc`                                  | clear link focus, selection and message  |
| `Ctrl-l`                               | redraw                                   |
| `q` `Q` `Ctrl-c`                       | quit                                     |

Bindings are looked up by physical key first (the kitty base-layout code), then by the reported key, then by the shifted symbol without its shift. That makes `G` and `$` work on any layout.

The status row shows messages such as `Copied 29 characters` on the left. On the right it shows the layout, the visible lines of the body and the first column: `[wrap] │ 1-56/801 │ col 1`. While finding in the page it starts with the selected match and the match count, during a `/` search with the result count; then the progress of indexing (`indexing 40%`, while page descriptions load) and of reading the text of all pages (`reading pages 40%`). While the help is shown it shows the help's visible lines and first column instead of the page's.

### Dock

The dock sits left of the page: the search field between `◖` and `◗` on its first row (`find` while empty), then the tree of pages, with a divider on its right edge that joins the lines above and below (`┬`, `┴`). `p` opens it with the keyboard in the tree and closes it; `f`, `t` or a click on the field opens it with the keyboard in the field, `/` and `o` with `/` already typed. A regular dock narrows the page; an overlay dock (`dock = overlay`) covers the left of the page on the popup background. Dragging the divider resizes it. Keys the tree does not bind go to the page, so `Space`, `b`, `d` and `u` scroll the page with the keyboard in the tree.

- **The tree** shows the pages around the current one: for a page of the project, or without a page, the project's pages (`name(section)`) and Markdown documents (by their path from the project root: `README.md`, `docs/guide.md`); for another page, the outermost group it is in (all of `abrt` for `abrt-dump-oops(1)`), or the page alone when it is in none. Names that share a prefix fold into nested groups: `abrt-cli` and `abrt-dump-oops` go under `▸ abrt`, and `abrt-dump-oops` and `abrt-dump-xorg` under `▸ abrt-dump` within it. A prefix is made of whole tokens of the name, split at `-`, `_`, `.`, `:` and `/` (so `File::Spec`, `systemd.unit` and the project's `docs/guide.md` group too), and it takes at least 3 entries to make a group. Groups cross sections (`abrt(1)`, `abrt.conf(5)`) and are case-sensitive; a page named like its group (`git(1)` in `git`) is listed inside it. Rows are named relative to their group, so `abrt-action-analyze-c(1)` reads `c(1)` under `▾ analyze` under `▾ action` under `▾ abrt`; a page named like its group is named relative to the group above (`abrt(1)` in `abrt`, `dump(1)` in `abrt-dump`). The groups are folded and listed by name, except those around the current page, which is selected; the tree follows the page through links, `Backspace` and pages opened from the tree, switching to the group of a page in another one.
- **Text without a leading `/`** fuzzy-finds in the lines of the displayed page, in its current layout. The page stays in the frame: matched characters are highlighted where they are, the selected match's line is shaded, and the page scrolls to the best match as you type. `↓`/`↑` step through the matches, best first, and the status row shows `match 2/8`. `Enter` gives the page the keyboard at the match. Meanwhile the lines that every term matches are counted for every page of the manual, and the tree shows each of its pages' count at the right of the row with the name in the `hit` color; a group shows how many of its pages have hits. The text of all pages is read once, in the background, by worker processes (`search-threads`, `docv text-worker`), with progress in the status row, and cached in `$XDG_CACHE_HOME/docv/text.bin` (about 200 MB for 27,000 pages) with each page's modification time; later sessions read only changed pages. Searching it takes threads of their own, tens of milliseconds for a full manual. Fuzzy terms are lenient, so short ones match a line of most pages.
- **Text after a leading `/`** fills the tree with every page along the manual path and every document of the project, the project's first, and ranks them, each row with its description (from the NAME section; for a document its first heading and paragraph) after the name. A term matches the reference or the description and counts with the better of the two; a reference match counts half a character more than an equal description match. So `/printf 3` finds `printf(3)`, and `/list dir` finds `dir(1)` and `ls(1)` by their descriptions. The project's entries still come first, ahead of better matches elsewhere; ties go to the shorter reference, then to section order. Groups without a match are left out and the others are open and ranked by their best match, each level on its own; folding one keeps it folded until the text changes. `Enter` (in the field or the tree) or a click opens the selected page or document and ends the search: the field empties, the tree shows the page's group and the page gets the keyboard; `Backspace` in the page view comes back. Without a page on the command line the viewer starts here.

Both are fuzzy: the characters of each space-separated term must appear in order, and matches score higher at word starts, in runs of consecutive characters and with short gaps (scored like fzf). Every term must match. Lower-case terms ignore case; a term with an upper-case letter matches exactly. Matched characters are underlined in the results. Rows wider than the dock scroll sideways.

| Search field keys                      | Action                                   |
|----------------------------------------|------------------------------------------|
| text                                   | type into the field                      |
| `Enter`                                | back to the page at the match / open the selected page / fold or unfold the selected group |
| `Esc` `Ctrl-c` `Ctrl-g` `Tab`          | to the tree                              |
| `Backspace`                            | delete the last character                |
| `Ctrl-u`                               | clear the field                          |
| `↓` `Ctrl-n` / `↑` `Ctrl-p` `Shift-Tab` | next / previous match, or row of the tree |
| `PgDn` / `PgUp`                        | a screenful of matches or rows down / up |
| `→` / `←`                              | unfold the selected group or step into it / fold it or step out to its group |
| `Shift-→` / `Shift-←`                  | scroll the tree right / left             |

| Tree keys                              | Action                                   |
|----------------------------------------|------------------------------------------|
| `j` `↓` `Ctrl-n` / `k` `↑` `Ctrl-p`    | next / previous page or group            |
| `PgDn` / `PgUp`                        | a screenful down / up                    |
| `g` `Home` / `G` `End`                 | first / last row                         |
| `Enter`                                | open the page / fold or unfold the group |
| `l` `→` / `←`                          | unfold the group or step into it / fold it or step out to its group |
| `L` `Shift-→` / `H` `Shift-←`          | scroll the tree right / left             |
| `Tab`                                  | to the search field                      |
| `Esc`                                  | back to the page                         |

Page names are listed on the spot. Descriptions come from parsing the start of each page, which takes a few seconds for a full manual. That work runs in the background while the dock is open, with progress shown in the status row; the project's documents are described first. The page descriptions are cached in `$XDG_CACHE_HOME/docv/index.tsv` (`~/.cache/docv/index.tsv` when the variable is unset or not absolute). A directory whose modification time is unchanged comes from the cache; in a changed directory only files with a new modification time are read again. Document descriptions are read on every start. Quitting early keeps the descriptions done so far.

### Links

`Tab` focuses the links on the page in turn, the status row shows where the focused one leads, and `Enter` or a click follows it. `Backspace` comes back to the place it was followed from.

| Link                         | Following it                                                         |
|------------------------------|----------------------------------------------------------------------|
| `name(section)` in the text  | opens the page from the search path                                  |
| `[text](other.md#usage)`     | opens the file relative to the current one, at the heading `usage`   |
| `[text](#usage)`             | goes to the heading `usage` of the current document                  |
| `[text](https://…)`, `mailto:` … | shows the URL; the terminal opens it (OSC 8)                     |

Anchors are GitHub's: the heading in lower case, punctuation dropped, spaces as dashes, `-1`, `-2`… appended to repeated headings. Links with a scheme are written to the terminal as OSC 8 hyperlinks. Most terminals open them on a click with a modifier (kitty: `Ctrl-Shift`-click), because the viewer takes plain clicks itself.

### Mouse

| Gesture                                   | Action                                  |
|-------------------------------------------|-----------------------------------------|
| wheel                                     | scroll 3 lines                          |
| `Shift`-wheel, horizontal wheel           | scroll 8 columns                        |
| drag in the text                          | select text; copied to the clipboard on release (OSC 52) |
| double-click                              | select the word (letters, digits, `_` and `-`, so `--color` whole) or the run of punctuation, and copy it |
| triple-click                              | select the paragraph (the lines with text around it in blocks of the same kind; a heading alone) and copy it |
| drag a scrollbar thumb (right and bottom border) | scroll                           |
| click a scrollbar track                   | page in that direction                  |
| click a link                              | follow it                               |
| click the search field                    | give it the keyboard                    |
| hover over a row of the tree              | highlight it                            |
| click a page in the tree                  | open it                                 |
| click a group in the tree                 | fold or unfold it                       |
| wheel / `Shift`-wheel over the dock       | scroll the tree / scroll it sideways    |
| drag the dock's right edge                | resize the dock                         |
| back button (Aux8)                        | back to the previous page               |
| click `ＤＯＣＶ v0.1.0` (start of the title row) | open the help                      |
| point at the page's heading               | show the page's source and date beside it |
| click 🞪 (end of the title row)            | quit                                    |

A selection stays highlighted until the next click or key. Selections follow the indentation: a line's indentation and trailing blanks are never highlighted, and the copied lines lose the indentation they share, so a paragraph comes out flush left and code keeps its relative indentation.

The arrow keys `←` and `→` do not scroll sideways; `l`, `H`, `L`, `0`, `$`, `Shift`-wheel and the horizontal scrollbar do. Code never wraps, also in the wrapped layout: code blocks (`.EX`, `.nf`, `.Bd -literal`, `.Dl`, fenced and indented Markdown code) keep their lines, and Markdown code spans are not broken across lines; the page scrolls sideways to show long ones. The clipboard write first sends an invalid payload, which clears the clipboard in terminals that append successive OSC 52 writes (kitty) and is ignored elsewhere.

## Markdown

Markdown is read as CommonMark with the GitHub extensions: tables, task lists, strikethrough, bare URLs as links (`www.`, `https://`, e-mail addresses) and alerts (`> [!NOTE]`).

| Element                  | Shown as                                                           |
|--------------------------|--------------------------------------------------------------------|
| paragraph                | filled to the width; a hard line break (two spaces, `\`) starts a new line |
| heading `#` … `######`   | its own line in the role of its level (`heading1` … `heading6`), with a blank line after |
| `**bold**`, `*italic*`   | the `bold` and `italic` roles                                      |
| `~~strikethrough~~`      | struck through (SGR 9)                                             |
| `` `code` ``             | the `code` role                                                    |
| code block               | its lines unwrapped, indented by 4, in `code-block`; tabs every 8 columns |
| list                     | items hanging on `•` `◦` `▪` by depth, `1.` (widest number), `☐` / `☑` for tasks; loose lists keep a blank line between items |
| block quote              | a `│` bar per level, in `quote`; an alert starts with its title (`Note`) in bold |
| table                    | boxed as wide as the terminal (spare width spread over the columns by their widths), the header row bold and ruled off, cells aligned and filled to their column |
| `---`                    | a rule across the width, in `rule`                                 |
| image                    | its description, in `image` (the file name without one)            |
| raw HTML                 | dropped, keeping the text between the tags                         |

Markdown documents have no page header and footer; the title row shows the file name and first heading.

## Syntax highlighting

With `syntax-highlighting = true` (the default), code examples are colored by their syntax through tree-sitter:

- Markdown code blocks labeled with a language: ` ```crystal `. The first word of the label names the grammar, or an alias of it (`cr` → `crystal`, `sh`/`shell` → `bash`, `js` → `javascript`, `py` → `python`, `yml` → `yaml`, …). Unlabeled and indented code blocks and code spans stay plain.
- The `.EX` examples of manual pages whose section names a language: `Foo.3cr` and `name.7cr`, the pages `docv gen-cr` makes, are Crystal.

A language takes two things, and docv ships neither: its grammar, a shared library `libtree-sitter-<name>.so` or `<name>.so`, and its highlight query, `<name>/highlights.scm`. They are looked for where tree-sitter and editors install them, for example grammars in `~/.local/lib` with queries in `~/.local/share/tree-sitter/queries/<name>/highlights.scm`:

| Grammars (after `~/.local/lib`, `/usr/local/lib`, `/usr/local/lib64`, `/usr/lib`, `/usr/lib64`) | Queries |
|---|---|
| `$XDG_DATA_HOME/docv/grammars` | `$XDG_DATA_HOME/docv/queries`, `$XDG_DATA_HOME/tree-sitter/queries` |
| `$XDG_DATA_HOME/nvim/site/parser` | `$XDG_DATA_HOME/nvim/site/queries` |
| `$XDG_DATA_HOME/nvim/lazy/nvim-treesitter/parser` | `$XDG_DATA_HOME/nvim/lazy/nvim-treesitter/queries`, `/usr/share/nvim/runtime/queries` |
| `$XDG_CONFIG_HOME/helix/runtime/grammars`, `/usr/lib64`, `/usr/lib` and `/usr/share` `helix/runtime/grammars` | the same `helix/runtime/queries` directories |

(`XDG_DATA_HOME` defaults to `~/.local/share`, `XDG_CONFIG_HOME` to `~/.config`.) A grammar can be built from its repository with `tree-sitter build`, whose `queries/highlights.scm` is the query. A query's `; inherits: a,b` line puts those languages' queries first. A language without a grammar or query, or whose query the grammar rejects, stays plain.

Capture names map to the `syntax-*` roles by their longest known dotted prefix (`keyword.function` is a keyword; nvim's and helix's names both work); `variable` and unknown names stay in the code's own color (`code-block` in documents, plain in manual pages). An inner capture overrides the one around it. Of two captures of the same node, the later pattern wins, as in nvim; for helix's query directories the earlier one does.

## Library

```crystal
require "docv"

doc = Docv.open("ls", "1") || abort "no page"   # find + load (added directories and system path)
manpath = Docv::Manpath.default(Dir.current)    # with the man pages of the project around the current directory
path = manpath.find("tool", "1")
doc = Docv.load("/usr/share/man/man1/ls.1.gz")  # file, plain or gzip
doc = Docv.load("README.md")                    # Markdown by file name (Markdown.file?)
doc = Docv.parse(source, path)                  # roff text; path resolves .so
doc = Docv::Markdown.parse(text)                # Markdown text
doc = Docv.load(path, Docv::Options.new(unsafe: true, stdin: STDIN))
doc = Docv.load(path, Docv::Config.load.options) # options from config.ini
doc = Docv.load("README.md", Docv::Options.new(highlight: true))  # with syntax highlighting

doc.format     # Docv::Format::Man | Mdoc | Roff | Markdown
doc.reference  # "LS(1)"; a document's first level 1 heading
doc.title, doc.section, doc.date, doc.source, doc.manual
doc.blocks     # Array(Docv::Block)
doc.links      # Array(Docv::Target): the targets of Span#link (from 1)
doc.anchors    # heading anchor => block index ("installation" => 12)
doc.messages   # .tm output and unknown requests or macros

Docv::Layout.new(doc).header_line(80)          # the page header line, nil without .TH/.Dt and for Markdown
Docv::Layout.new(doc).footer_line(80)          # the page footer line, nil without .TH/.Dt and for Markdown
Docv::Layout.new(doc).lines(80, header: false, footer: false)  # the body only
Docv::Layout.new(doc).lines(80, wrap: true).each do |line|
  puts line.text                       # cells as text
  line.links.each { |link| p link }    # Layout::Link: col, width, target (Target: kind, location, part)
end

index = Docv::Index.new(manpath)        # pages along the manpath and its project's documents
index.describe unless index.complete?      # parse the descriptions still missing; saves the cache
index.entries.each { |entry| puts "#{entry.reference}  #{entry.description}" }
Docv::Index.description(path)           # one page's NAME description, one document's heading and paragraph

project = Docv::Manpath.project(Dir.current)  # root, man page directories, Markdown documents

fuzzy = Docv::Fuzzy.new("prf")
fuzzy.score("printf")                      # => 73 (nil when not a subsequence)
fuzzy.positions("printf")                  # => [0, 1, 5]
```

| Type                     | Holds                                                                         |
|--------------------------|-------------------------------------------------------------------------------|
| `Document`               | metadata, blocks, link targets (`links`) and heading anchors (`anchors`) of a page or document |
| `Block`                  | `kind` (`Text`, `Heading`, `Blank`, `Table`, `Rule`), heading `level` (1-6), `indent`, first-line `offset`, `tag`/`tag_indent`, `fill?`, `align`, `tabs`, `spans`, `lines`, `table`, quote `bars` (columns) |
| `Span`                   | text, a style id (`Styles[id]` is a `Style`: `attr` (`Attr`: `Bold`, `Italic`, `Underline`, `Reverse`, `Dim`, `Strike`), `fg`, `bg`, `markup`; `merge(over)`) and a `link` (index into `Document#links` from 1, `0` for none) |
| `Markup`                 | what text is for the viewer's roles: `None`, `Code`, `CodeBlock`, `Quote`, `Rule`, `Image`, and `SyntaxKeyword` … `SyntaxTag` for highlighted code |
| `Target`                 | where a link leads: `kind` (`TargetKind`: `Page`, `Url`, `File`, `Anchor`), `location` (page name, URL, path), `part` (section, anchor), `label` |
| `Syntax`                 | `Syntax.highlight(code, language)` (lines of `{text, Markup}` runs, `nil` without grammar or query), `apply(blocks, language)`, `language(label)` (`ALIASES`), `page_language(path)` (`SECTION_LANGUAGES`), `markup(capture)` (`CAPTURES`), `grammar_directories`, `query_directories` (`Syntax::QueryDirectory`: `path`, `first_wins`), `clear` |
| `Markdown`               | `Markdown.parse(text, highlight = false)`, `Markdown.file?(path)` (`EXTENSIONS`), `Markdown.slug(heading)`, `Markdown.description(text)` |
| `Color`                  | `Color::DEFAULT`, `Color.palette(index)` (0-255), `Color.rgb(r, g, b)`; `default?`, `palette?`, `rgb?` |
| `Palette`                | the terminal theme as RGB: `foreground`, `background`, `set(key, value)` (OSC 21 values), `reported?`, `dark?`, `rgb(color, foreground)`, `ramp(rgb, percent)`, `reduce(color, depth)`; `Palette.parse(value)` |
| `Theme`                  | role styles: `Theme.new(overrides)`, `Theme.parse(spec)`, `styles(palette, depth)` (a style id per `Theme::Role`), `Theme::DEFAULT`, `Theme::MONOCHROME`, `Theme::KEYS`; `Theme::Error` |
| `Table`                  | tbl rows of cells (`Text`, `HSpan`, `VSpan`, `Rule`, `DoubleRule`), alignments, minimum widths, vertical rules, gaps, frame |
| `Layout::Line`           | `cells : Array(Cell)`, `text`, `links`, `block`/`offset` (reading position)   |
| `Cell`                   | grapheme, style id, width (2 for wide characters, 0 for their continuation)  |
| `Manpath`                | `Manpath.new(dirs, locale, project = nil)` (each dir a tree or a flat directory), `find(name, section)`, `roots` (`Manpath::Root`: `path`, `flat`, `project`), `project`, `all_sections`; `Manpath.default(dir = nil)` (project directories, added directories, system path, with the project around *dir*), `Manpath.system(manpath, path, config)`, `Manpath.man_db`/`parse_man_db`, `Manpath.project_root(dir)`, `Manpath.project(dir)` (`Manpath::Project`: `root`, `pages`, `documents`), `Manpath.discover(dir)`, `Manpath.flat?`/`pages?`/`page?`, `Manpath.split(file, section)`, `Manpath.read_paths`/`add_paths`/`remove_paths`/`paths_file`, `Manpath.parse_reference`, `Manpath.rank(section)` |
| `Index`                  | `Index.new(manpath = Manpath.default, cache = Index.cache_path)` (`nil` cache disables it), `entries` (the project's pages, its documents, the other pages), `pending`, `complete?`, `describe` (optionally with a block receiving done and total after each entry; `break` stops early), `save`, `Index.description(path)` |
| `Index::Entry`           | `name` (a document's path from the project root), `section` (empty for a document), `path`, `description`, `reference`, `project?`, `document?` |
| `Fuzzy`                  | `Fuzzy.new(query)`, `score(text)`, `positions(text)` (character indices), `exact?` (query has upper case) |
| `Source`                 | `Source.read(path)`: gzip inflating and Latin-1 fallback; `.so` resolution    |
| `Options`                | `unsafe` (run `Roff::Engine::UNSAFE` requests and `\V`), `stdin` (input of `.rd`; `nil` reads nothing), `highlight` (syntax highlighting, default `false`; `Config#options` sets it from `syntax-highlighting`) |
| `Config`                 | `Config.load(path = Config.path, create = true)`, `Config.parse(text)`, `unsafe?`, `start_wrapped?`, `syntax_highlighting?`, `colors`, `theme`, `options(stdin)`, `viewer` (`ViewerSettings`: `dock` (`DockStyle::Regular`, `Overlay`), `dock_width`, `dock_open`, `search_threads`); `Config::Error` |

The man page generator is a separate require too:

```crystal
require "docv/crystal_pages"

root = Docv::CrystalPages::Shard.root(Dir.current) || abort "not in a shard"
puts Docv::CrystalPages.generate(root, File.join(root, "man"))  # "man: 12 written, 3 unchanged, 0 removed"
```

| Type                         | Does                                                                  |
|------------------------------|-----------------------------------------------------------------------|
| `CrystalPages`               | `generate(root, output)`, `blocks(markdown)` (markd nodes), `summary`, `base_name`, `clean_type`, `plain`; `GENERATOR`, `MARKER`, `GENERATED`, `SUFFIX`; `CrystalPages::Error` |
| `CrystalPages::DocTool`      | `load(root)`: runs `crystal docs --format json` into a `Project` (`repository_name`, `body`, `program`) |
| `CrystalPages::TypeDoc`      | a documented type: kind, names, superclass and relations, constants, constructors, methods, macros, nested types (generated members dropped) |
| `CrystalPages::Shard`        | `Shard.root(dir)`, `name`, `version`, `require_path(type)`, `relative(text)` |
| `CrystalPages::Types`        | the types with pages, `[]?(name)`, `lookup(context, name)`, `referenced(type)` |
| `CrystalPages::Renderer`     | markd blocks to roff: `render(blocks)`, `item(head, blocks)`, `tables?` |
| `CrystalPages::Inline`       | `render(node, bold:, urls:, upcase:)`, `markdown(text, urls:)`        |
| `CrystalPages::Pages`        | `all`: the overview and type `Page`s (`path`, `name`, `section`, `body`, `render(date)`) |
| `CrystalPages::Generator`    | `run(pages)`: written, unchanged, removed; `Generator.today` (`SOURCE_DATE_EPOCH`) |

The viewer and its terminal layer are a separate require:

```crystal
require "docv/viewer"

config = Docv::Config.load
viewer = Docv::Viewer.new(doc, path, wrap: true, options: config.options, theme: config.theme,
  settings: config.viewer)
viewer.bindings[{Docv::Term::Mods::None, 'x'.ord}] = Docv::Viewer::Action::Quit
viewer.field_bindings[{Docv::Term::Mods::Ctrl, 'j'.ord}] = Docv::Viewer::FieldAction::Next
viewer.run

start = Docv::Viewer.new                        # empty page, dock closed
start.perform(Docv::Viewer::Action::OpenPage)   # start in a search of every page
start.run
```

| Type                     | Does                                                                      |
|--------------------------|---------------------------------------------------------------------------|
| `Viewer`                 | the full-screen viewer; `run`, `perform(action)`, `bindings`, `field_bindings`, `tree_bindings`, `focus` (`Page`, `Tree`, `Field`); the document is optional (empty page); `options` apply to pages opened through links and the page search (`.rd` never reads there); `theme` (default `Theme.new`), `depth` (default `Term::Tty.color_depth`) and `settings` (`ViewerSettings`: `dock` style, `dock_width`, `dock_open`, `search_threads`; `Config#viewer`) |
| `Viewer::Keymap(T)`      | key table, `lookup(event)` with physical/key/shifted matching             |
| `Viewer::Bindings`       | `Keymap(Action)` for the page view, from `DEFAULT_BINDINGS`               |
| `Viewer::FieldBindings`  | `Keymap(FieldAction)` for the search field, from `FIELD_BINDINGS`         |
| `Viewer::TreeBindings`   | `Keymap(TreeAction)` for the dock's tree, from `TREE_BINDINGS`            |
| `Viewer::Picker`         | fuzzy-ranked list of `Item`s (label, detail, target, role, group; lower groups first; key): `query=`, `results`, `rows`, `current`, `group?`, `toggle`, `expand`, `collapse`, `reveal(target)`, `move`, `scroll_to`, `scroll_x`/`left`/`width` (sideways), `hits=` (counts per item, groups count items with hits), `marks`, `label_width`, `draw` (with the role style ids, a fill, labels only without details); `nested: true` folds the items into an `Outline` by their keys |
| `Viewer::Picker::Outline` | items grouped by shared key prefixes (`SEPARATORS`, `MIN_GROUP`): `nodes` (`Node`: prefix, item, parent, depth, size, children, text and skip of the relative name), `roots`, `leaf`, `items(id)`, `Outline.each_token`, `Outline.relative` |
| `Viewer::Dock`           | the dock: `field`, `group` and `pages` (nested `Picker`s: the current page's group, every page), `tree` (the one shown), `style`, `width`, `open?`, `span(cols)`, `offset(cols)`, `manual?`, `query`, `part(frame, row, col)` (`Field`, `Rule`, `Tree`, `Divider`), `tree_row`, `tree_rows`, `tree_cols`, `draw` |
| `Viewer::Frame`          | title row with name, page heading and close mark, title line, content area (after a regular dock's columns, `dock`) with the scrollbars, status row: geometry (`inner`, `left`, `inner_cols`, `content_cols`), `name_width`, `heading_bounds`, `heading_col(width)`, `region(row, col)` (`Name`, `Title`, `Close`, `Border`, `Content`, `VerticalBar`, `HorizontalBar`, `Status`), `Frame.thumb`, `draw`, `title`, `rule` |
| `Viewer::Help`           | the help from the bindings, drawn in the page area (`Help::TITLE` heads the title row) (`ACTION_HELP`, `FIELD_HELP`, `TREE_HELP`, `Help::MOUSE`): `lines`, `top`, `left`, `width`, `keys_width`, `scroll`, `scroll_x`, `rows`, `max_top`, `max_left`, `draw`, `Help.key_name(mods, key)` |
| `Viewer::Field`          | the search field text: `insert`, `delete_back`, `clear`                   |
| `Corpus`                 | the text of many pages (`require "docv/corpus"`): `build(sources)` from its mapped cache file (`text.bin`) or by parsing, in `threads` worker processes when `Corpus.worker` is set (`Corpus.serve`, `docv text-worker`); `text(index)`, `count(query, cancelled)` (lines every term matches per page, on isolated searcher threads), `Corpus.extract(path)`, `close` |
| `Screen`            | front and back cell buffers with hyperlinks; `write`, `blit`, `fill`, `restyle`, `link(row, col, count, uri)` (OSC 8), `colors(palette, depth)`, `render(io)` rewrites changed rows only, with colors reduced to the depth |
| `Term::Tty`         | raw mode, window size in cells and pixels, `enter`/`leave` of the full-screen state, `query_colors` (OSC 21), `copy(text)` (OSC 52 clipboard), `pointer(shape)` (OSC 22), `Tty.color_depth` (`NO_COLOR`, `COLORTERM`, `TERM`) |
| `Term::Decoder`     | bytes into raw events: `KeyEvent`, `MouseEvent`, `ResizeEvent`, `FocusEvent`, `VisibilityEvent`, `ColorSchemeEvent`, `ModeReport`, `CellSizeReport`, `KeyboardFlagsReport`, `ColorsReport` (OSC 21) |
| `Term::Input`       | derived events: pressed-set, `TextInput`/`KeyCommand`, `MousePress`, `Click` (with multi-click count), `Drag` (start/move/end), `Scroll` (accumulated), `PointerEnter`/`PointerMove`/`PointerLeave`; pixel-to-cell conversion |

### Terminal modes

On entering, the viewer switches to the alternate screen and pushes kitty keyboard flags `31` inside it (`CSI > 31 u`). It enables mouse modes 1003, 1006 and 1016 and notification modes 2048, 1004, 2033 and 2031, then queries mode 1016, the cell size, the keyboard flags, visibility and the color scheme, and the theme colors with OSC 21 (again when the color scheme changes). On leaving it undoes all of this in reverse order. Mouse coordinates are read as pixels once the terminal confirms mode 1016; otherwise they are read as SGR cell coordinates. Frames are written inside synchronized-update brackets (mode 2026). URL links are written as OSC 8 hyperlinks, ended before the end of each row. The mouse pointer is shaped with OSC 22 (kitty's pointer shapes, CSS cursor names) after each frame when what lies under it changed: `text` over page text and the search field, `pointer` over links, rows of the tree and the close mark, `ew-resize` over the dock's edge, `grab` over a scrollbar thumb and `grabbing` while dragging one, `default` elsewhere; leaving resets it.

## roff coverage

Every groff request is recognized.

- **Interpreted:** definitions and strings (`de` `am` `ds` `as` and their `1`/`i` variants, `rm` `rn` `als` `chop` `length` `substring` `stringup` `stringdown`); registers (`nr` `rr` `rnn` `aln` `af`); conditionals and loops (`if` `ie` `el` `while` `break` `continue`); `return` `shift` `nop` `do` `ig`; input (`so` `nx`); `ex` `ab` `tm` `tm1` `tmc`; traps on input lines and at the end (`it` `itc` `em`), plus `blm` `lsm`; diversions (`di` `da` `box` `boxa`); environments (`ev` `evc`).
- **Character requests:** `cc` `c2` `ec` `eo` `ecs` `ecr` `tr` `trin` `trnt` `char` `fchar` `fschar` `schar` `rchar` `rfschar`.
- **Fonts and colors:** `ft` `fp` `ftr` `ul` `cu` `gcolor` `fcolor` `defcolor`.
- **Filling and spacing:** `br` `brp` `fi` `nf` `ad` `na` `ce` `rj` `sp` `bp` `ns` `rs` `in` `ti` `ll` `lt` `ta` `tl`.
- **Escapes:** all of them, including `\*`, `\n` (with auto-increment), `\$`, `\g`, `\w`, `\B`, `\A`, `\R`, `\f`, `\m`, `\M`, `\h`, `\l`, `\(xx`, `\[name]` (groff names, `uXXXX`, accented letters), `\C`, `\N`, `\c`, `\p`, `\Z`, `\o` and `\b`.

Some requests are accepted but do nothing, because they are pointless on a reflowing terminal view: page geometry and page traps (`pl` `po` `pn` `wh` `ch` `dt` `vpt` `mk` `rt` `ne` `os` `sv`), sizes and spacing (`ps` `vs` `ls` `ss` `cs` `bd` `sizes` `fzoom`), hyphenation (`hy` `nh` `hc` `hw` `hla` `hlm` `hpf*` `hym` `hys` `shc` `hcode`), kerning and ligatures, line numbering and margin characters (`nm` `nn` `mc`), device and debugging output (`device` `devicem` `output` `pm` `pnr` `ptr` `pev` `pline` `pvs` `backtrace`), warnings, `fam` `fc` `lc` `tc` `uf` `linetabs`, and macro package loading (`mso` `msoh`, since the packages are built in).

The unsafe requests run only with `roff.unsafe = true` (`Options#unsafe`). Otherwise they are accepted and ignored:

| Request                         | With `unsafe`                                                                     |
|---------------------------------|-----------------------------------------------------------------------------------|
| `sy cmd`                        | runs `/bin/sh -c cmd`; the raw wait status goes to register `systat`              |
| `pso cmd`                       | runs the command and reads its output as input                                     |
| `pi cmd`                        | after parsing, pipes the page formatted as text at 78 columns into the command     |
| `open s file` / `opena s file`  | opens stream `s` for writing / appending                                           |
| `write s text` / `writec s text`| writes text (copy mode, leading `"` removed) with / without a newline              |
| `writem s macro`                | writes the macro body uninterpreted                                                |
| `close s`                       | closes the stream (all streams close at the end of parsing)                        |
| `cf file` / `trf file`          | sets the file's lines unprocessed as unfilled text, dropping control characters other than tab |
| `rd [prompt]`                   | prints the prompt (or a bell) on standard error, then reads input lines from `Options#stdin` up to an empty line |
| `\V[name]`                      | interpolates the environment variable                                              |

Commands run with standard input and output on the null device, so they never draw over the viewer; `pso` captures the output. The CLI gives `.rd` the terminal only for the page named on the command line, before the viewer starts.

Lines are left-aligned (ragged right) and never hyphenated. `.ad b` is treated as left; `.ad c` and `.ad r` work, as do `.ce` and `.rj`.

## Development

| Target         | Does                                    |
|----------------|-----------------------------------------|
| `make spec`    | spec suite                              |
| `make build`   | debug `bin/docv`                     |
| `make release` | release `bin/docv`                   |
| `make docs`    | API documentation in `docs/`            |
| `make format`  | `crystal tool format`                   |
| `make install` | release build into `~/.local/bin`, man pages into `~/.local/share/man` |
