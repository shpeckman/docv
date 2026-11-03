<!-- AGENTS.md -->
# AGENTS.md

Orientation for AI agents working on docv: a Crystal shard that parses manual pages (roff with man(7), mdoc(7), tbl(1)) and Markdown documents (through markd), lays them out wrapped or unwrapped, and shows them in a terminal viewer. It also generates man pages for Crystal shards (`docv gen-cr`). Namespace `Docv`. Its dependencies are markd and treesitter (`shards install`; treesitter links libtree-sitter through pkg-config); everything else is the standard library.

## Layout

```
shard.yml                   name docv, target docv (src/cli.cr), dependencies markd ~> 0.6.0, treesitter (main)
makefile                    spec, build, release, docs, format, install, clean
src/docv.cr                 entry "docv": parser + layout; Docv.parse/load (Markdown by name)/find/open
src/docv/style.cr           Attr (incl. Strike), Markup (Code, CodeBlock, Quote, Rule, Image, Syntax*), ColorDepth,
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
src/docv/config.cr          Docv.base_directory, Docv.user_directory (XDG base dirs), Options (unsafe,
                            stdin, highlight, indent), DockStyle (Regular, Overlay), PickerSettings (dock,
                            dock_width, dock_open, min_group, search_threads), Config
                            ($XDG_CONFIG_HOME/docv/config.ini: [man] roff-unsafe, indent; [viewer]
                            start-wrapped, syntax-highlighting; [picker] dock, dock-width, dock-open,
                            min-group, search-threads; [colors]; load creates DEFAULT, parse validates
                            KEYS, BOOLEANS, RANGES and DockStyle names; [colors] keys and defaults come
                            from Theme)
src/docv/fuzzy.cr           Fuzzy: fzf-style scoring (BONUS table, ASCII classes), DP alignment, positions,
                            match? (subsequence test on raw bytes, ASCII fold table)
src/docv/index.cr           Index: pages along a Manpath and its project's documents (project first),
                            NAME descriptions (engine on the page prefix up to the heading after NAME;
                            NAMES, .so aliases), document descriptions (Markdown.description, not cached),
                            cache index.tsv per directory
src/docv/markdown.cr        Markdown: EXTENSIONS, file?, parse, tree (markd with GFM, autolink fallback),
                            slug, alert_title, description; Converter: markd tree into Blocks (lists,
                            quotes, code, expand tables, HTML stripped), inline spans (ATTRIBUTES, markup,
                            link targets), anchors
src/docv/syntax.cr          Syntax: tree-sitter highlighting; ALIASES (labels), SECTION_LANGUAGES (3cr),
                            CAPTURES (capture prefixes to Markup), grammar_directories, query_directories
                            (QueryDirectory first_wins: docv's, $XDG_DATA_HOME/tree-sitter/queries, nvim,
                            helix), grammar cache (parser + query), inherits,
                            highlight (runs per line), apply (blocks of one example), clear
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
src/docv/macros/man.cr      Man package (TH SH SS PP TP IP HP RS RE fonts EX UR MT SY OP MR ...); EX..EE
                            highlighted for pages with a section language; body indent IN or
                            Options#indent, subsection indent SN scaled with it (Mdoc: INDENT and SUB_INDENT)
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
                            paths from src/<name>.cr, src/<name>/*.cr, other src/*.cr minus the
                            shard.yml targets' mains), Types (in nesting order)
src/docv/crystal_pages/roff.cr   Roff (escape, quote, bold, line, lines), Inline (markd inlines to roff:
                            FONTS, code, links), Renderer (markd blocks to roff: SECTIONS, FLAG, item)
src/docv/crystal_pages/pages.cr  Literal (constant values), Page (render with date), Pages (overview and API
                            page: a .SH per type, .SS per MEMBER_SECTIONS entry), Generator (gzipped
                            pages, unchanged-aware, remove stale)
src/docv/corpus.cr          entry "docv/corpus": Corpus (text of all pages at WIDTH: extract, cache text.bin
                            mapped with mmap, records by path and mtime; build parses missing pages in
                            worker processes (Corpus.worker, serve, PAGE_TIMEOUT) or in this process;
                            count on isolated searcher threads fed through a channel, Search, CHUNK)
src/docv/viewer.cr          entry "docv/viewer": terminal layer + viewer (requires docv/corpus)
src/docv/term/events.cr     Key numbers, Mods, KeyAction, raw event records (ColorsReport), Event alias
src/docv/term/decoder.cr    Decoder: bytes into raw events (kitty CSI u, legacy, SGR mouse, notifications,
                            OSC 21 reports; unterminated ESC ] is Alt-])
src/docv/term/input.cr      Input: derived events (pressed-set, text/command, click, drag, scroll, pointer
                            enter/move/leave)
src/docv/term/tty.cr        LibDocvTty (ioctl), Sequences (COLORS_QUERY, CLIPBOARD, HYPERLINK, POINTER), Tty
                            (raw mode, size, enter/leave, query_colors, copy, pointer, color_depth)
src/docv/screen.cr          Screen: front/back cell buffers and per-cell hyperlink ids (interned URIs),
                            row-diff render in synchronized updates, OSC 8, SGR cache per style id with
                            colors reduced to the depth
src/docv/viewer/bindings.cr Action, FieldAction, TreeAction, DEFAULT_BINDINGS, FIELD_BINDINGS and
                            TREE_BINDINGS (data), ACTION_HELP, FIELD_HELP, TREE_HELP, Keymap(T) (lookup
                            order, keys), Bindings, FieldBindings, TreeBindings
src/docv/viewer/field.cr    Field: the search field text
src/docv/viewer/frame.cr    Frame: title row (NAME, VERSION: Region::Name; heading_bounds, heading_col; CLOSE
                            mark), title line, padded content after
                            a regular dock's columns (dock, inner, left), thumb-only vertical scrollbar,
                            horizontal scrollbar line, status row, regions, thumbs, rule
src/docv/viewer/dock.cr     Dock: search field (◖ ◗ inside FIELD_MARGIN, PLACEHOLDER, MANUAL_PREFIX, manual?,
                            query; HEAD_ROWS), divider joining the lines with ┬ ┴, group and
                            pages (nested Pickers; tree is the one shown), style, width (MIN_WIDTH, MIN_PAGE, span, offset), parts
                            (Field, Tree, Divider), tree_row/rows/cols, draw
src/docv/viewer/help.cr     Help: help built from the bindings, drawn in the page area (TITLE heads the title row) (ACTION_HELP, FIELD_HELP, TREE_HELP,
                            MOUSE)
src/docv/viewer/picker.cr   Picker: fuzzy-ranked Items (label, detail, target, role, group, key), rows,
                            selection, hover row, drawing scrolled sideways (left, scroll_x, width), hit
                            counts (hits=, groups count items with hits); nested: outline rows,
                            open/folded groups, ranked levels (rank), toggle/expand/collapse, reveal, unfold
                            (levels while they fit)
src/docv/viewer/outline.cr  Picker::Outline: key token trie (SEPARATORS, min_group (MIN_GROUP default),
                            Item#folder groups after the others, single-child groups
                            take the child's prefix) into Nodes (prefix, item, parent, depth, size,
                            children, text/skip: name relative to the group, relative), roots per item
                            group, leaf, items under a node
src/docv/viewer/viewer.cr   Viewer: Focus (page, tree, field), Hover and POINTER_SHAPES (OSC 22),
                            START_HINT, HEADING_SEPARATOR (draw_title, page_heading, page_detail), TEXT_ROLES, MARKUP_ROLES, HEADING_ROLES, PROJECT_GROUP/OTHER_GROUP,
                            PROJECT_KEY, group_of/group_tree/all_pages, palette/theme (apply_colors, page_style), layouts
                            cache, anchors, actions, dock (refit, tree, field, finder), corpus fiber and
                            hit searches (hit_generation), index fiber, links (open_link by TargetKind,
                            anchor_block, history), text selection (OSC 52 copy), mouse, drawing (OSC 8
                            for URL links), run loop
src/cli.cr                  docv command (path-add, path-rm, path-list, gen-cr, text-worker, viewer, plain
                            output; sets Corpus.worker)
man/man1/docv.1             manual page of the command (man(7)): keys, dock, mouse, search path, links,
                            Markdown, environment, files
man/man5/docv-config.5      manual page of config.ini: [man], [viewer], [picker], [colors] roles and defaults
spec/                       specs per component (spec_helper: parse, render, blocks; markdown_spec: md;
                            manual_spec: hand-written pages strictly, generated API pages parse cleanly;
                            crystal_pages_spec: roff of Markdown, pages from a JSON fixture, generator;
                            corpus_spec: pages in a temp directory, in-process parsing, serve)
```

## Flow

The CLI handles `path-add`/`path-rm`/`path-list` (they only touch `Manpath.paths_file`) and `gen-cr` before anything else. `gen-cr` finds the shard root (`Shard.root`), runs `crystal docs --format json` there (`DocTool`), and `Pages` renders two pages named after the shard: the overview `name.7cr` from the project body (with a list of the types) and the API page `name.3cr` with one `.SH` section per type from `Types` (declaration with its `require`, description, then `.SS` subsections for relations, constants and `MEMBER_SECTIONS`). `:nodoc:` types never reach the JSON. `Generator` gzips them (`COMPRESSION`, header time fixed at the epoch). Markdown goes through `Markdown.tree` into `Renderer`/`Inline`, which write roff. `Generator` writes into the output directory, keeping unchanged pages (compared decompressed) with their date, removing stale generated pages, gzipped or not, and refusing files without `GENERATED`. Otherwise it reads `Config` first; `Config#options` becomes the `Options` the engine gets (`.rd` reads `STDIN` only for the page named on the command line). It builds one `Manpath.default(Dir.current)` (project directories, added directories, system path, plus the `Manpath::Project` with its Markdown documents) and hands it to the lookup, the viewer and the `Index`. `Docv.load` reads the file with `Source.read` and picks the parser by name: `Markdown.file?` goes to `Markdown.parse`, everything else to the roff `Engine`.

roff: `Engine#run` pushes the file onto the input stack. Each line is a control line (request, user macro, or package macro, looked up in that order; `.TS` goes to `Tbl` first) or a text line (interpolated, then formatted by `Inline` into the `Builder`). User macros take precedence over package macros, and package macros over requests. The package (`Man` or `Mdoc`) is chosen by the first macro either one knows. `.SH`/`.Sh` are headings of level 1, `.SS`/`.Ss` of level 2.

Markdown: markd parses with GFM and extended autolinks (`Markdown::OPTIONS`); when markd raises `ArgumentError` (its autolinks can slice into a multibyte character next to an `@`) it parses again without autolinks. `Converter` walks the tree recursively with a state of indent, quote bars, list depth, tightness and a pending list tag. `emit` places a block after a due blank (`@space`), with the pending tag; `add` places continuation blocks. Inline nodes become spans: `ATTRIBUTES` for strong/emphasis/strikethrough, `Markup` on the style for code, code blocks, quote bars, rules and images, and `Span#link` for links (`target_id` interns a `Target` into `Document#links`). Headings record GitHub anchors in `Document#anchors`. Raw HTML loses its tags (`HTML_MARKUP`). With highlighting (`Options#highlight`, from `[viewer] syntax-highlighting`), a fenced block with a language label goes through `Syntax.apply`; so does a man `.EX` example of a page whose section suffix is in `Syntax::SECTION_LANGUAGES`. `Syntax` loads a grammar and its `highlights.scm` once per language (or remembers that it has none), marks each byte of the code with the `Markup` of its captures (inner over outer; same node: later pattern, or earlier for `first_wins` directories) and rewrites the blocks' spans as runs; the viewer styles them through `MARKUP_ROLES`. `Markdown.description` (the index) never highlights.

Blocks carry only layout intent (indent, offset, tag, fill, align, tabs, level, bars). `Layout` places cells per width (a table with `expand`, which every Markdown table has, takes the full width): the `Tokenizer` keeps each cell's span link when any span has one, `flow_into` turns runs of linked cells into `Layout::Link`s (merged across blanks for one target) and otherwise finds `name(section)` cross-references with `LINK`; `bar` draws the quote bars on every row of a block. `Viewer` caches layouts per `{width, wrap}` and keeps the reading position across layouts through `Line#block`/`Line#offset`.

Without a page the CLI starts the viewer on an empty `Document` with the dock closed and `START_HINT` as the message. The dock (`Dock`, opened by `p`, `f`/`t`, `/`/`o` or `[viewer] dock-open`) builds an `Index` on first use: names come from directory listings and the project's documents, and descriptions from the cache or from a background fiber that calls `Index#describe` (documents first; they are never cached). The fiber yields every `INDEX_BATCH` entries and sends `:index` on the event channel, which refreshes the tree (`Picker#items=`, keeping open groups, selection and hits while the keys stay the same). The dock has two nested `Picker`s and shows one (`Dock#tree`): `Dock#group` (`group_tree`) holds the pages `group_of` picks around the current page (every project entry for a project page or no page, `PROJECT_KEY`; the outermost group of `@outline`, the outline of every page, for another page; the page alone otherwise), rebuilt when that key changes (revealed at the page, then `Picker#unfold` opens groups level by level while they fit in the dock); `Dock#pages` (`all_pages`) holds every page item for a manual search (project entries in `PROJECT_GROUP`, which `Picker` ranks before any other group), and is the one `:index` refreshes. `Picker::Outline` folds names sharing a prefix of whole tokens into groups of at least `min_group` entries (`[picker] min-group`), and puts items with an `Item#folder` into a top-level group of that name after the others (`page_item` gives Markdown documents `DOCUMENT_FOLDER` and the `Document` role), `Picker#rows` holds outline node ids drawn by their relative `Node#text` (group marks `○`/`●` in `ButtonDim`, group names in `Button`, a page's `(section)` in `Detail`, per enclosing level a `STEM` in `Border` while it continues, else a `GUIDE` in `TreeGuide` while an outer one does, then `BRANCH`/`LAST_BRANCH` in `Border`, from `@stems`, a bitmask per row of the depths that continue, filled backward by `stem_rows`; inside a group `Outline` puts items before subgroups, the top level mixes them by name) (matches still on the whole label, marks shifted by `Node#skip`), an empty query lists the outline with `@opened` groups unfolded, and a query ranks each level by its best result position (`@rank`) with every matching group open unless `@folded`. `reveal_current` selects the current page in the group's tree (`entry_number`: by expanded path, then by name and section; `Picker#reveal` opens the groups around it) whenever the dock opens, on every `show`, and when the field leaves a manual search (`@manual_view`). `Focus` decides where keys go: `Page` to `Bindings`, `Tree` to `TreeBindings` first and the rest to `Bindings`, `Field` to the field through `FieldBindings` (text inserts). `field_changed` reads the field: a leading `Dock::MANUAL_PREFIX` (`/`) sets the tree's query (drawn with details) and drops finding in the page; anything else empties the tree's query (revealing the current page again), finds in the page with `@finder` (one `Picker::Item` per `@lines` entry, item index = line index) and starts `search_hits`. The page stays drawn with `@found` lines' matched columns (`Line#text_columns`) in `Mark` and the selected match's line on `Selection`; `step`/`reveal_match` scroll to matches, and `relayout` re-ranks (`refind`) for a new layout. `search_hits` bumps `@hit_generation` and, once the `Corpus` is ready, spawns a fiber that runs `Corpus#count` (cancelled when the generation moves on) and keeps the counts per index entry (`@hit_counts`); `apply_hits` maps them onto the group's tree (`Picker#hits=` by item target, drawn in `Hit` at the right edge), also when that tree is rebuilt; then it sends `:hits`. The `Corpus` is made on the first search in the page: a fiber (`read_pages`) runs `Corpus#build` over every index entry, reporting `@text_progress` and sending `:text`, then `:corpus`, which searches the field's text. `Corpus#build` maps `text.bin` and reuses records whose mtime matches; missing pages go to `threads` `docv text-worker` processes (`Corpus.worker`, set by the CLI; the GC allocation lock keeps parser threads in one process from scaling), and the new file replaces the old by rename. `Corpus#count` sends one `Search` per searcher thread (`Fiber::ExecutionContext::Isolated`, started on first use) through a channel; they take `CHUNK` pages at a time (`Atomic`) and count lines where every term's `Fuzzy#match?` holds. `tree_open` on a page during a manual search empties the field, gives the page the keyboard and runs `field_changed` after opening it, which returns the dock to the group's tree. `open_link` follows a link by `TargetKind`: `Page` along the manpath, `File` relative to the current page's path (then its anchor), `Anchor` within the page (`anchor_block`), `Url` only shows the location since the terminal opens it; each follow pushes a `Position` on the history (`remember`). Dragging in the page sets `@selection` (page line and column, anchor and head) and copies it with `Tty#copy` on release; a double click selects a `CharClass` run (`word_at`, `WORD_CHARS`) and a triple click the paragraph (`paragraph_at`: lines with text in blocks of one kind), both copied. `selected_cols` keeps highlights within each line's text, and `selected_text` drops the indentation the copied lines share; `PointerMove` feeds the hover row of the tree. Clicks, presses and the wheel on the dock (`Dock#part`) go to it: the field takes the keyboard, a tree row opens or folds (`tree_open`), the wheel scrolls the tree (sideways with `Shift`), and dragging the divider resizes the dock (`DragTarget::Divider`; the page lays out again on release through `refit`). `Frame` owns the page geometry: the page draws from `Frame#left`, after the columns of a regular dock (`Dock#offset`); `refit` rebuilds the frame when the dock opens, closes or resizes. The page body takes the whole content area (`page_rows`, `page_top`), laid out with `lines(header: false, footer: false)`; instead of the page header, `draw_title` centers `page_heading` (`Document#manual` and `#reference` joined by `HEADING_SEPARATOR`, or the file name and first heading block of a document) on the title row through `Frame#heading_col`, in `PageHeader`, and while the pointer is on it writes `page_detail` (the footer's source and date) after it in `Detail`. A click on `Frame::Region::Name` performs `Action::Help`; while `@help` is set, `draw` draws the `Help` in the page area instead of the page (the scrollbar follows `Help#top`), `draw_title` shows `Help::TITLE`, `help_key` scrolls it with the scrolling actions (sideways through `Help#scroll_x`, as do `Shift`-wheel and the horizontal thumb's position) and closes it on any other key, and a click closes it. After each frame `shape_pointer` sets the pointer shape (`Tty#pointer`, OSC 22) from `hover_kind` (drags first, then the dock's parts, the frame's regions, links and text of the page) through `POINTER_SHAPES`, only when it changed. The status row holds the message on the left and the match or result count, indexing and reading progress, then `[wrap] │ lines/total │ col` on the right.

Colors: everything is drawn in a `Theme::Role`. `Viewer#apply_colors` resolves the theme into one style id per role for the current `Palette` and depth, and hands both to the `Screen`. The palette starts as xterm's colors and turns into the terminal's own once an OSC 21 `ColorsReport` arrives, which also switches the depth to 24-bit. A `ColorSchemeEvent` re-queries. Page text keeps the parser's style ids in the layout; at draw time `page_style` maps bold, italic and underlined spans to their roles (`TEXT_ROLES`), then merges the role of the style's `Markup` (`MARKUP_ROLES`); heading lines take `HEADING_ROLES[level - 1]`, and links, matches and focus are merged on top (`Styles.merge`). Spans with their own roff colors keep them. URL links also get `Screen#link`, written as OSC 8 around their cells. `NO_COLOR` gives `ColorDepth::None`: `Theme::MONOCHROME` and no color output at all.

## Commands

    shards install                    # markd into lib/
    make spec                         # crystal spec --threads 2
    make build                        # bin/docv
    crystal tool format src spec

Compile one thing at a time with `--threads 2`; parallel Crystal compiles exhaust memory on this machine.

`docv gen-cr` in the repository regenerates docv's own API pages, `man/man3/docv.3cr.gz` and `man/man7/docv.7cr.gz` (committed); run it after changing doc comments or README.md. `groff -t -man -Tutf8 -ww -z` on generated pages should report nothing but `cannot adjust line` for very wide table rows.

A useful regression check is to parse and lay out every page under `/usr/share/man` and every Markdown file under `/usr/share/doc`, with an ad-hoc program in a scratch directory that calls `Docv.load` and `Layout#lines` (wrapped and unwrapped). It should raise no exceptions (about 30k files); `Document#messages` lists unknown macros. `Index.new(Manpath.default(<repo>), "<scratch>/index.tsv").describe` is a similar check for description extraction: about 3 s in release mode for ~27k pages, with a handful of empty descriptions. Crystal only resolves `require "docv"` from a scratch directory with `CRYSTAL_PATH="$(crystal env CRYSTAL_PATH):<repo>/src:<repo>/lib"`; absolute require paths do not work.

The viewer can be driven headless in tmux: `tmux -L test new-session -d -x 90 -y 20 'bin/docv'`, then `send-keys` and `capture-pane -p` (`-e` shows SGR and OSC 8). Set `XDG_CACHE_HOME` to a scratch directory so the real index and text caches are untouched; send text with `send-keys -l`, and wait about 3 s after start. The first search in the page reads the text of every page: about 8 s with a release build (`make release`, workers are the same binary), minutes with the debug build; `Corpus` can be timed on its own from a scratch program with `Corpus.worker` pointing at a release `docv`.

## Code standards

- Compiler-friendly, performance-focused, idiomatic Crystal. Data-driven: tables (`NO_OP`, `BREAKING`, `MACROS`, `ENCLOSE`, `FONTS`, `DEFAULT_BINDINGS`, `FIELD_BINDINGS`, `TREE_BINDINGS`, `ACTION_HELP`, `FIELD_HELP`, `TREE_HELP`, `Help::MOUSE`, `Help::KEY_NAMES`, `TEXT_ROLES`, `MARKUP_ROLES`, `HEADING_ROLES`, `Theme::DEFAULT`/`MONOCHROME`/`COLORS`/`ATTRIBUTES`, `Markdown::EXTENSIONS`/`ATTRIBUTES`/`ALIGNS`/`BULLETS`/`CHECKBOXES`, `Fuzzy::BONUS`, `Outline::SEPARATORS`, `Viewer::POINTER_SHAPES`, `Index::NAMES`, `Manpath::MARKERS`/`SKIP`/`NEIGHBORS`/`CONFIGS`, `Key::LETTERS`/`TILDE`) over branching where possible.
- Every file starts with a comment holding its path (`# src/docv/...`), then a blank line: a comment directly above the first declaration becomes that type's doc (for `module Docv`, its description in the API pages).
- Comments sparingly and short. Doc comments only for the library API (what a user of the shard calls), one sentence to a few lines, no implementation details; everything else is `:nodoc:` (the first line of its doc comment; a `:nodoc:` namespace hides its contents). Inline comments only for a non-obvious why.
- The user-facing API stays ergonomic (`Docv.open`, `Docv.load`, `Layout#lines`, `Viewer#run`, `CrystalPages.generate`).
- Avoid shotgun surgery: a new request goes in `requests.cr` (plus `NO_OP`/`BREAKING` if relevant; requests that run commands or touch files go in `unsafe.cr` and `UNSAFE`); a new config key goes in `Config::KEYS`, `Config::DEFAULT` (its section text), `Config.parse` and `Options` (parsing) or a `Config` getter used by the CLI (viewer settings such as `start_wrapped?`); a new man macro in `Man::MACROS` and `Man#call`; a new mdoc macro in `MdocData` tables and `Mdoc#inline`; a new Markdown block node in `Converter#block`, an inline node in `Converter#inline` (an emphasis-like one only in `Markdown::ATTRIBUTES`); a new Markdown file extension in `Markdown::EXTENSIONS`; a new Markdown node in generated man pages in `Renderer#render` (block) or `Inline#inline`; a new page section in `Pages#type_page` (member lists in `Pages::MEMBER_SECTIONS`, relations in `TypeDoc#relations`); marked text in a new `Markup` value, its role in `MARKUP_ROLES`; a new link kind in `TargetKind`, `Target#label`, `Converter#target_id` and `Viewer#open_link`; a new key binding in `DEFAULT_BINDINGS` (page view), `FIELD_BINDINGS` (search field) or `TREE_BINDINGS` (dock tree), a new action in `Action`/`FieldAction`/`TreeAction`, its text in `ACTION_HELP`/`FIELD_HELP`/`TREE_HELP` and its `case` in `Viewer#perform`/`Viewer#field_key`/`Viewer#tree_key`; a new kind of field search in `Viewer#field_changed`; a new integer config key also in `Config::RANGES`, a picker setting in `PickerSettings`; a new name separator for page groups in `Outline::SEPARATORS`; a new pointer shape in `Viewer::Hover`, `POINTER_SHAPES` and `Viewer#hover_kind`; a new project marker or skipped folder in `Manpath::MARKERS`/`SKIP`; a new `docv` subcommand in the `case` at the top of `CLI.run` and `USAGE`; a translated NAME heading in `Index::NAMES`; a new color role in `Theme::Role`, `Theme::DEFAULT` and `Theme::MONOCHROME` (config key and default file follow) plus its use site; a change to page description extraction bumps `Index::HEADER`; a change to the text `Corpus.extract` produces or to the cache layout bumps `Corpus::HEADER`.
- Do not change the version in `shard.yml`.
- Keep README.md short (what docv is, install, a usage summary, a library quick start); details belong in the man pages: `man/man1/docv.1` (command, keys, dock, mouse, search path), `man/man5/docv-config.5` (config), and the generated API pages (doc comments and README). Keep those and this file in sync with the code. `spec/manual_spec.cr` parses the man pages and fails on unknown macros; `groff -man -Tutf8 -ww -z` should stay silent on them too.
- Concurrency: the viewer's state belongs to the default execution context (one thread); fibers there (index, corpus, hit searches) touch it between blocking points only. Work on other threads (the corpus searchers) reads only the mapped cache and writes disjoint array elements, and reports back through `@events` or by finishing a `WaitGroup`. Global tables written while parsing (`Styles`, `Unicode` clusters, `Colors`) are not thread-safe, so pages are parsed on one thread or in worker processes (`Corpus#build`); threads would not parse faster anyway (the GC allocation lock), and locking those tables slowed parsing by 40%.
- Crystal gotchas met here: no trailing `while`/`until` modifiers; `macro`, `out`, `lib` are reserved names; `Char::Reader` is a struct (pass a `Cursor`); `String#[]` with a char index is O(n) on non-ASCII strings; `Array#[-1]?` is the last element, so guard 1-based ids before `[id - 1]?`.
- Syntax gotchas: docv ships no grammars or queries, so `spec/syntax_spec.cr` uses treesitter's JSON fixture grammar (compiled with `cc`) and writes its queries to a temp directory; `Syntax.clear` after changing `grammar_directories`/`query_directories`. A new label alias goes in `Syntax::ALIASES`, a capture name in `Syntax::CAPTURES`, a section language in `SECTION_LANGUAGES`, a new syntax color in `Markup`, `Theme::Role`, `DEFAULT`, `MONOCHROME` and `MARKUP_ROLES`.
- markd gotchas: `Node#data` of a list is the same hash as its first item's; table cells hold inline children; text is split into several text nodes at `:` and other characters (`CrystalPages.blocks` merges them); `Renderer` builds strings, so the converters walk `first_child?`/`next?` themselves.
