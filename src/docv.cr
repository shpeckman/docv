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

# Parses manual pages written in roff with the man(7) or mdoc(7) macro
# packages and tbl(1) tables, and Markdown documents (`Markdown`), and lays
# them out for a terminal.
#
# ```
# doc = Docv.open("ls", "1") || abort "no page"
# doc = Docv.load("README.md")
# lines = Docv::Layout.new(doc).lines(80, wrap: true)
# lines.each { |line| puts line.text }
# ```
module Docv
  VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}

  # Parses roff source *text*. *path* is the file it came from, used to
  # resolve `.so` includes; *options* enables unsafe requests.
  def self.parse(text : String, path : String? = nil, options : Options = Options.new) : Document
    Roff::Engine.new(Source.new(path), options: options).run(text)
  end

  # Reads and parses the file at *path* (plain or gzip): Markdown when it is
  # named like a Markdown document (`Markdown.file?`), roff otherwise.
  def self.load(path : String, options : Options = Options.new) : Document
    text = Source.read(path)
    Markdown.file?(path) ? Markdown.parse(text, options.highlight) : parse(text, path, options)
  end

  # Finds the file of page *name* in *section* along *manpath*
  # (`Manpath.default`: the added directories and the system path).
  def self.find(name : String, section : String? = nil, manpath : Manpath = Manpath.default) : String?
    manpath.find(name, section)
  end

  # Finds and parses page *name*; `nil` when there is no such page.
  def self.open(name : String, section : String? = nil, manpath : Manpath = Manpath.default,
                options : Options = Options.new) : Document?
    find(name, section, manpath).try { |path| load(path, options) }
  end
end
