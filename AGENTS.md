<!-- AGENTS.md -->
# AGENTS.md

Orientation for AI agents working on docv: a Crystal shard that parses manual pages (roff with man(7), mdoc(7), tbl(1)) and Markdown documents (through markd), lays them out wrapped or unwrapped, and shows them in a terminal viewer. It also generates man pages for Crystal shards (`docv gen-cr`). Namespace `Docv`. Its one dependency is markd (`shards install`); everything else is the standard library.

## Layout

```
shard.yml                   name docv, target docv (src/cli.cr), dependency markd ~> 0.6.0
makefile                    spec, build, release, docs, format, install, clean
src/docv.cr                 entry "docv": parser + layout; Docv.parse/load (Markdown by name)/find/open
src/docv/style.cr           Attr (incl. Strike), Markup (Code, CodeBlock, Quote, Rule, Image), ColorDepth,
                            Color (default/palette/RGB in 32 bits), Style (attr, colors, markup; merge,
                            to_sgr), Styles (16-bit id interning, merge), Colors (roff names, defcolor)
src/docv/palette.cr         Palette: terminal theme as RGB (OSC 21 values, xterm fallback), ramp, reduce
src/docv/cell.cr            Unicode (widths, cluster interning), Cell (12-byte value, memcmp-safe)
src/docv/ast.cr             Span (text, style, link), Format, BlockKind, TargetKind, Target, Align, Tabs,
                            Block (level, bars), Document (links, anchors), Table (Cell, Row, kinds)
src/docv/source.cr          Source (read: gzip + Latin-1 fallback; .so resolution)
src/docv/manpath.cr         Manpath: roots (trees and flat dirs, project flag), find, man-db system path
                            (MANPATH, PATH neighbors, MANPATH_MAP, MANDATORY_MANPATH), Project (root, pages,
                            documents) from one walk (MARKERS, SKIP), added directories file (paths),
                            SECTION, split, rank
src/docv/theme.cr           Theme: Role enum (Heading1-6, markup roles), spec grammar (parse), DEFAULT and
                            MONOCHROME tables, KEYS, styles(palette, depth)
src/docv/config.cr          Docv.user_directory (XDG base dirs), Options (unsafe, stdin), Config
                            ($XDG_CONFIG_HOME/docv/config.ini: load creates DEFAULT, parse validates
                            KEYS and BOOLEANS; [colors] keys and defaults come from Theme)
src/docv/fuzzy.cr           Fuzzy: fzf-style scoring (BONUS table, ASCII classes), DP alignment, positions
src/docv/index.cr           Index: pages along a Manpath and its project's documents (project first),
                            NAME descriptions (engine on the page prefix up to the heading after NAME;
                            NAMES, .so aliases), document descriptions (Markdown.description, not cached),
                            cache index.tsv per directory
src/docv/markdown.cr        Markdown: EXTENSIONS, file?, parse, tree (markd with GFM, autolink fallback),
                            slug, alert_title, description; Converter: markd tree into Blocks (lists,
                            quotes, code, expand tables, HTML stripped), inline spans (ATTRIBUTES, markup,
                            link targets), anchors
src/docv/roff/cursor.cr     Cursor: char reader passed by reference between scanners
src/docv/roff/numeric.cr    expressions in terminal units (24u per column, 40u per line), MAX_EXTENT clamp
src/docv/roff/registers.cr  number registers, .af formats
src/docv/roff/chars.cr      special character table, uXXXX, charNNN, accent composition
src/docv/roff/env.cr        Font, Env (formatting environment: font, colors, fill, indents, tabs)
src/docv/roff/builder.cr    Builder: output into Blocks, captures (tags, headings, cells), soft/hard space
src/docv/roff/engine.cr     Package (abstract), Frame, Engine: input stack, dispatch, conditionals, loops,
                            definitions, diversions, environments, built-in registers
src/docv/roff/interpolate.cr  copy-mode/normal interpolation: \* \n \$ \g \w \B \A \R \V, comments
src/docv/roff/inline.cr     Inline: escapes into text, font/color changes, motions, \c
src/docv/roff/requests.cr   every roff request (NO_OP set, BREAKING set; UNSAFE gated by Options#unsafe)
src/docv/roff/tbl.cr        Tbl: .TS/.TE options, format rows, data, T{ T} blocks
src/docv/roff/unsafe.cr     UNSAFE set and its requests (sy pso pi open opena write writec writem close
                            cf trf rd), shell helper (null stdio), streams, pi at end of run
src/docv/macros/man.cr      Man package (TH SH SS PP TP IP HP RS RE fonts EX UR MT SY OP MR ...)
src/docv/macros/mdoc_data.cr  MdocData: indents, fonts, enclosures, standards, libraries, callable set
src/docv/macros/mdoc.cr     Mdoc package: tokens, delimiters, inline macros, lists, displays, synopsis
src/docv/layout.cr          Layout (lines with or without header and footer, header_line, footer_line; none
                            for Markdown), Line, Link (col, width, Target), Piece (cell links), Row,
                            Tokenizer, flow (wrap/unwrapped), span links and LINK cross-references, tags,
                            align, quote bars, rules
src/docv/layout/table.cr    TableLayout: widths, text blocks, spans, numeric alignment, expand (spare width
                            by column width), rules and frames, cell links
src/docv/crystal_pages.cr   entry "docv/crystal_pages": CrystalPages (gen-cr): GENERATOR, MARKER, GENERATED,
                            SUFFIX, sections, OUTPUT, base_name, clean_type, summary, blocks (markd blocks,
                            text merged, empty HTML dropped), children, plain, code_block, generate
src/docv/crystal_pages/model.cr  JSON model of crystal docs (Location, TypeRef, Arg, Definition, Constant,
                            Member, TypeDoc, Project), DocTool (runs crystal docs), Shard (root, require
                            paths), Types (pages, lookup, referenced)
src/docv/crystal_pages/roff.cr   Roff (escape, quote, bold, line, lines), Inline (markd inlines to roff:
                            FONTS, code, links), Renderer (markd blocks to roff: SECTIONS, FLAG, item)
src/docv/crystal_pages/pages.cr  Literal (constant values), Page (render with date), Pages (overview, type
                            pages, MEMBER_SECTIONS), Generator (write unchanged-aware, remove stale)
src/docv/viewer.cr          entry "docv/viewer": terminal layer + viewer
src/docv/term/events.cr     Key numbers, Mods, KeyAction, raw event records (ColorsReport), Event alias
src/docv/term/decoder.cr    Decoder: bytes into raw events (kitty CSI u, legacy, SGR mouse, notifications,
                            OSC 21 reports; unterminated ESC ] is Alt-])
src/docv/term/input.cr      Input: derived events (pressed-set, text/command, click, drag, scroll, pointer
                            enter/move/leave)
src/docv/term/tty.cr        LibDocvTty (ioctl), Sequences (COLORS_QUERY, CLIPBOARD, HYPERLINK), Tty (raw
                            mode, size, enter/leave, query_colors, copy, color_depth)
src/docv/screen.cr          Screen: front/back cell buffers and per-cell hyperlink ids (interned URIs),
                            row-diff render in synchronized updates, OSC 8, SGR cache per style id with
                            colors reduced to the depth
src/docv/viewer/bindings.cr Action, FieldAction, DEFAULT_BINDINGS and FIELD_BINDINGS (data), ACTION_HELP,
                            FIELD_HELP, Keymap(T) (lookup order, keys), Bindings, FieldBindings
src/docv/viewer/field.cr    Field: the search bar text
src/docv/viewer/frame.cr    Frame: title row (NAME, VERSION, search bar ◖ ◗, CLOSE mark), title line,
                            padded content, thumb-only vertical scrollbar, horizontal scrollbar line, status
                            row, regions, thumbs, rule, box
src/docv/viewer/help.cr     Help: floating help built from the bindings (ACTION_HELP, FIELD_HELP, MOUSE)
src/docv/viewer/picker.cr   Picker: fuzzy-ranked Items (label, detail, target, role, group), selection,
                            hover row, drawing
src/docv/viewer/viewer.cr   Viewer: Mode (view, search), Scope (page, manual), TEXT_ROLES, MARKUP_ROLES,
                            HEADING_ROLES, PROJECT_GROUP/OTHER_GROUP, palette/theme (apply_colors,
                            page_style), layouts cache, anchors, actions, search bar, index fiber, links
                            (open_link by TargetKind, anchor_block, history), text selection (OSC 52
                            copy), mouse, drawing (OSC 8 for URL links), run loop
src/cli.cr                  docv command (path-add, path-rm, path-list, gen-cr, viewer, plain output)
man/man1/docv.1             manual page of the command (man(7)): keys, mouse, search path, links,
                            Markdown, environment, files
man/man5/docv-config.5      manual page of config.ini: [roff], [colors] roles and defaults
spec/                       specs per component (spec_helper: parse, render, blocks; markdown_spec: md;
                            crystal_pages_spec: roff of Markdown, pages from a JSON fixture, generator)
```

## Flow

The CLI handles `path-add`/`path-rm`/`path-list` (they only touch `Manpath.paths_file`) and `gen-cr` before anything else. `gen-cr` finds the shard root (`Shard.root`), runs `crystal docs --format json` there (`DocTool`), and `Pages` renders the overview from the project body and a page per type from `Types`; Markdown goes through `Markdown.tree` into `Renderer`/`Inline`, which write roff. `Generator` writes into the output directory, keeping unchanged pages with their date, removing stale generated pages and refusing files without `GENERATED`. Its output for a shard is byte-identical to treesitter's `scripts/man.cr` (the code it came from) apart from the comment lines and the date. Otherwise it reads `Config` first; `Config#options` becomes the `Options` the engine gets (`.rd` reads `STDIN` only for the page named on the command line). It builds one `Manpath.default(Dir.current)` (project directories, added directories, system path, plus the `Manpath::Project` with its Markdown documents) and hands it to the lookup, the viewer and the `Index`. `Docv.load` reads the file with `Source.read` and picks the parser by name: `Markdown.file?` goes to `Markdown.parse`, everything else to the roff `Engine`.

roff: `Engine#run` pushes the file onto the input stack. Each line is a control line (request, user macro, or package macro, looked up in that order; `.TS` goes to `Tbl` first) or a text line (interpolated, then formatted by `Inline` into the `Builder`). User macros take precedence over package macros, and package macros over requests. The package (`Man` or `Mdoc`) is chosen by the first macro either one knows. `.SH`/`.Sh` are headings of level 1, `.SS`/`.Ss` of level 2.

Markdown: markd parses with GFM and extended autolinks (`Markdown::OPTIONS`); when markd raises `ArgumentError` (its autolinks can slice into a multibyte character next to an `@`) it parses again without autolinks. `Converter` walks the tree recursively with a state of indent, quote bars, list depth, tightness and a pending list tag. `emit` places a block after a due blank (`@space`), with the pending tag; `add` places continuation blocks. Inline nodes become spans: `ATTRIBUTES` for strong/emphasis/strikethrough, `Markup` on the style for code, code blocks, quote bars, rules and images, and `Span#link` for links (`target_id` interns a `Target` into `Document#links`). Headings record GitHub anchors in `Document#anchors`. Raw HTML loses its tags (`HTML_MARKUP`).

Blocks carry only layout intent (indent, offset, tag, fill, align, tabs, level, bars). `Layout` places cells per width (a table with `expand`, which every Markdown table has, takes the full width): the `Tokenizer` keeps each cell's span link when any span has one, `flow_into` turns runs of linked cells into `Layout::Link`s (merged across blanks for one target) and otherwise finds `name(section)` cross-references with `LINK`; `bar` draws the quote bars on every row of a block. `Viewer` caches layouts per `{width, wrap}` and keeps the reading position across layouts through `Line#block`/`Line#offset`.

Without a page the CLI starts the viewer on an empty `Document` and performs `Action::OpenPage`. The page search builds an `Index` on first use: names come from directory listings and the project's documents, and descriptions from the cache or from a background fiber that calls `Index#describe` (documents first; they are never cached). The fiber yields every `INDEX_BATCH` entries and sends `:index` on the event channel, which refreshes the open picker. The search bar is one `Field` whose text picks the `Scope`: a leading `MANUAL_PREFIX` (`/`) lists the index entries in the frame (`list` is the picker only then; project entries in `PROJECT_GROUP`, which `Picker` ranks before any other group), anything else ranks the lines of the displayed layout (one `Picker::Item` per `@lines` entry, item index = line index) without listing them. The page stays drawn with `@found` lines' matched columns (`Line#text_columns`) in `Mark` and the selected match's line on `Selection`; `step`/`reveal_match` scroll to matches, `cancel` restores `@origin`, and `relayout` re-ranks (`refind`) for a new layout. `field_changed` rebuilds the `Picker` only when the scope changes. The `Mode` decides whether keys go to `Bindings` or to the bar through `FieldBindings`. `open_link` follows a link by `TargetKind`: `Page` along the manpath, `File` relative to the current page's path (then its anchor), `Anchor` within the page (`anchor_block`), `Url` only shows the location since the terminal opens it; each follow pushes a `Position` on the history (`remember`). Dragging in the page sets `@selection` (page line and column, anchor and head) and copies it with `Tty#copy` on release; `PointerMove` feeds the hover row of the picker. `Frame` owns all screen geometry; the page draws at `Frame::LEFT` and the picker across `Frame#inner_cols`. The page view pins `Layout#header_line` and a `Frame#rule` above the body and a rule and `Layout#footer_line` below it (`PINNED_ROWS` each; none for Markdown), and lays the body out with `lines(header: false, footer: false)`; page geometry (`page_rows`, `page_top`) is the content area minus the pinned rows. The title row holds the title, the search bar and the close mark; the status row holds the message on the left and `[wrap] │ lines/total │ col` or the result count on the right.

Colors: everything is drawn in a `Theme::Role`. `Viewer#apply_colors` resolves the theme into one style id per role for the current `Palette` and depth, and hands both to the `Screen`. The palette starts as xterm's colors and turns into the terminal's own once an OSC 21 `ColorsReport` arrives, which also switches the depth to 24-bit. A `ColorSchemeEvent` re-queries. Page text keeps the parser's style ids in the layout; at draw time `page_style` maps bold, italic and underlined spans to their roles (`TEXT_ROLES`), then merges the role of the style's `Markup` (`MARKUP_ROLES`); heading lines take `HEADING_ROLES[level - 1]`, and links, matches and focus are merged on top (`Styles.merge`). Spans with their own roff colors keep them. URL links also get `Screen#link`, written as OSC 8 around their cells. `NO_COLOR` gives `ColorDepth::None`: `Theme::MONOCHROME` and no color output at all.

## Commands

    shards install                    # markd into lib/
    make spec                         # crystal spec --threads 2
    make build                        # bin/docv
    crystal tool format src spec

Compile one thing at a time with `--threads 2`; parallel Crystal compiles exhaust memory on this machine.

`gen-cr` can be checked against treesitter: `docv gen-cr -o <scratch>` in `../treesitter`, then diff each page past its first four lines with `../treesitter/man`; they should be identical. `groff -t -man -Tutf8 -ww -z` on generated pages should report nothing but `cannot adjust line` for very wide table rows.

A useful regression check is to parse and lay out every page under `/usr/share/man` and every Markdown file under `/usr/share/doc`, with an ad-hoc program in a scratch directory that calls `Docv.load` and `Layout#lines` (wrapped and unwrapped). It should raise no exceptions (about 30k files); `Document#messages` lists unknown macros. `Index.new(Manpath.default(<repo>), "<scratch>/index.tsv").describe` is a similar check for description extraction: about 3 s in release mode for ~27k pages, with a handful of empty descriptions. Crystal only resolves `require "docv"` from a scratch directory with `CRYSTAL_PATH="$(crystal env CRYSTAL_PATH):<repo>/src:<repo>/lib"`; absolute require paths do not work.

The viewer can be driven headless in tmux: `tmux -L test new-session -d -x 90 -y 20 'bin/docv'`, then `send-keys` and `capture-pane -p` (`-e` shows SGR and OSC 8). Set `XDG_CACHE_HOME` to a scratch directory so the real index cache is untouched.

## Code standards

- Compiler-friendly, performance-focused, idiomatic Crystal. Data-driven: tables (`NO_OP`, `BREAKING`, `MACROS`, `ENCLOSE`, `FONTS`, `DEFAULT_BINDINGS`, `FIELD_BINDINGS`, `ACTION_HELP`, `FIELD_HELP`, `Help::MOUSE`, `Help::KEY_NAMES`, `TEXT_ROLES`, `MARKUP_ROLES`, `HEADING_ROLES`, `Theme::DEFAULT`/`MONOCHROME`/`COLORS`/`ATTRIBUTES`, `Markdown::EXTENSIONS`/`ATTRIBUTES`/`ALIGNS`/`BULLETS`/`CHECKBOXES`, `Fuzzy::BONUS`, `Index::NAMES`, `Manpath::MARKERS`/`SKIP`/`NEIGHBORS`/`CONFIGS`, `Key::LETTERS`/`TILDE`) over branching where possible.
- Every file starts with a comment holding its path (`# src/docv/...`).
- Comments sparingly, but document public API for `crystal docs`.
- The user-facing API stays ergonomic (`Docv.open`, `Docv.load`, `Layout#lines`, `Viewer#run`, `CrystalPages.generate`).
- Avoid shotgun surgery: a new request goes in `requests.cr` (plus `NO_OP`/`BREAKING` if relevant; requests that run commands or touch files go in `unsafe.cr` and `UNSAFE`); a new config key goes in `Config::KEYS`, `Config::DEFAULT`, `Config.parse` and `Options`; a new man macro in `Man::MACROS` and `Man#call`; a new mdoc macro in `MdocData` tables and `Mdoc#inline`; a new Markdown block node in `Converter#block`, an inline node in `Converter#inline` (an emphasis-like one only in `Markdown::ATTRIBUTES`); a new Markdown file extension in `Markdown::EXTENSIONS`; a new Markdown node in generated man pages in `Renderer#render` (block) or `Inline#inline`; a new page section in `Pages#type_page` (member lists in `Pages::MEMBER_SECTIONS`, relations in `TypeDoc#relations`); marked text in a new `Markup` value, its role in `MARKUP_ROLES`; a new link kind in `TargetKind`, `Target#label`, `Converter#target_id` and `Viewer#open_link`; a new key binding in `DEFAULT_BINDINGS` (page view) or `FIELD_BINDINGS` (search bar), a new action in `Action`/`FieldAction`, its text in `ACTION_HELP`/`FIELD_HELP` and its `case` in `Viewer#perform`/`Viewer#field_key`; a new search scope in `Viewer::Scope` and `Viewer#field_changed`; a new project marker or skipped folder in `Manpath::MARKERS`/`SKIP`; a new `docv` subcommand in the `case` at the top of `CLI.run` and `USAGE`; a translated NAME heading in `Index::NAMES`; a new color role in `Theme::Role`, `Theme::DEFAULT` and `Theme::MONOCHROME` (config key and default file follow) plus its use site; a change to page description extraction bumps `Index::HEADER`.
- Do not change the version in `shard.yml`.
- Keep README.md (usage and public API), the man pages in `man/` (command, keys, config) and this file in sync with the code. `spec/manual_spec.cr` parses the man pages and fails on unknown macros; `groff -man -Tutf8 -ww -z` should stay silent on them too.
- Crystal gotchas met here: no trailing `while`/`until` modifiers; `macro`, `out`, `lib` are reserved names; `Char::Reader` is a struct (pass a `Cursor`); `String#[]` with a char index is O(n) on non-ASCII strings; `Array#[-1]?` is the last element, so guard 1-based ids before `[id - 1]?`.
- markd gotchas: `Node#data` of a list is the same hash as its first item's; table cells hold inline children; text is split into several text nodes at `:` and other characters (`CrystalPages.blocks` merges them); `Renderer` builds strings, so the converters walk `first_child?`/`next?` themselves.
