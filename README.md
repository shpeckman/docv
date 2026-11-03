<!-- README.md -->
# docv

A manual page and Markdown viewer for the terminal, and a Crystal library to parse and lay out those pages.

- Reads roff with the man(7) and mdoc(7) macros and tbl(1) tables, plain or gzipped, and Markdown (CommonMark with the GitHub extensions).
- Shows them in a full-screen viewer: wrapped or unwrapped layout, links and back navigation, mouse selection, syntax-highlighted code, colors from the terminal's own theme.
- A dock with the page's group of related pages and a fuzzy search over the page, every page of the manual, and the text of all pages.
- Generates man pages for a Crystal shard from its README and doc comments (`docv gen-cr`).

## Requirements

- Crystal 1.21 or newer, on Linux
- libtree-sitter 0.25 or newer, found through `pkg-config` (Fedora: `libtree-sitter-devel`)
- for syntax highlighting: tree-sitter grammars and their `highlights.scm` queries (see docv(1))

## Installation

The command:

    shards install
    make release        # bin/docv
    make install        # ~/.local/bin/docv, man pages in ~/.local/share/man

The library, in `shard.yml`:

```yaml
dependencies:
  docv:
    github: shpeckman/docv
```

## Usage

    docv [-u] [section] name      # a page along the man path: docv ls, docv 3 printf, docv 'ls(1)'
    docv [-u] file                # a page file or a Markdown document
    docv                          # the viewer on an empty page; p opens this folder's pages
    docv path-add dir...          # add man page directories (path-rm, path-list)
    docv gen-cr [-o dir] [shard]  # man pages for a Crystal shard

In the viewer, `h` lists the keys, `p` opens the dock, `f` finds in the page and `/` searches every page. When standard output is not a terminal, the page is printed as text.

The manual pages document the rest: docv(1) for the command, keys, mouse and search path, docv-config(5) for `config.ini`. Inside this repository `docv docv` opens docv(1).

## Library

```crystal
require "docv"

doc = Docv.open("ls", "1") || abort "no page"   # look up and parse
doc = Docv.load("README.md")                    # a file: roff, or Markdown by name
Docv::Layout.new(doc).lines(80).each { |line| puts line.text }
```

```crystal
require "docv/viewer"

Docv::Viewer.new(Docv.load("README.md"), "README.md").run
```

```crystal
require "docv/crystal_pages"

root = Docv::CrystalPages::Shard.root(Dir.current) || abort "not in a shard"
puts Docv::CrystalPages.generate(root, File.join(root, "man"))
```

The API reference is docv(3cr), with docv(7cr) as its overview, in `man/` (`docv 3cr docv` inside this repository), or `make docs`.

## Development

| Target         | Does                                                  |
|----------------|-------------------------------------------------------|
| `make spec`    | spec suite                                            |
| `make build`   | debug `bin/docv`                                      |
| `make release` | release `bin/docv`                                    |
| `make docs`    | API documentation in `docs/`                          |
| `make format`  | `crystal tool format`                                 |
| `make install` | release build into `~/.local/bin`, man pages into `~/.local/share/man` |

After changing doc comments or this file, run `docv gen-cr` to regenerate the two gzipped API pages in `man/`.
