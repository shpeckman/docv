# src/docv.cr

require "./docv/style"
require "./docv/cell"
require "./docv/ast"
require "./docv/source"
require "./docv/manpath"
require "./docv/palette"
require "./docv/theme"
require "./docv/config"
require "./docv/roff/cursor"
require "./docv/roff/numeric"
require "./docv/roff/registers"
require "./docv/roff/chars"
require "./docv/roff/env"
require "./docv/roff/builder"
require "./docv/roff/engine"
require "./docv/roff/interpolate"
require "./docv/roff/inline"
require "./docv/roff/requests"
require "./docv/roff/tbl"
require "./docv/roff/unsafe"
require "./docv/macros/man"
require "./docv/macros/mdoc"
require "./docv/markdown"
require "./docv/syntax"
require "./docv/layout"
require "./docv/fuzzy"
require "./docv/index"

# Parses manual pages (roff with man(7), mdoc(7) and tbl(1)) and Markdown
# documents, and lays them out for a terminal.
#
# ```
# doc = Docv.open("ls", "1") || abort "no page"
# doc = Docv.load("README.md")
# lines = Docv::Layout.new(doc).lines(80, wrap: true)
# lines.each { |line| puts line.text }
# ```
module Docv
  # The shard's version.
  VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}

  # Parses roff source *text*; *path* is its file, for resolving `.so` includes.
  def self.parse(text : String, path : String? = nil, options : Options = Options.new) : Document
    Roff::Engine.new(Source.new(path), options: options).run(text)
  end

  # Reads and parses the file at *path* (plain or gzip): Markdown when
  # `Markdown.file?` holds, roff otherwise.
  def self.load(path : String, options : Options = Options.new) : Document
    text = Source.read(path)
    Markdown.file?(path) ? Markdown.parse(text, options.highlight) : parse(text, path, options)
  end

  # The file of page *name* in *section* along *manpath*; `nil` when none.
  def self.find(name : String, section : String? = nil, manpath : Manpath = Manpath.default) : String?
    manpath.find(name, section)
  end

  # Finds and parses page *name*; `nil` when there is no such page.
  def self.open(name : String, section : String? = nil, manpath : Manpath = Manpath.default,
                options : Options = Options.new) : Document?
    find(name, section, manpath).try { |path| load(path, options) }
  end
end
