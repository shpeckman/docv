# spec/spec_helper.cr
require "spec"
require "../src/docv/viewer"

# Parses *source* and returns the document.
def parse(source : String) : Docv::Document
  Docv.parse(source)
end

# Lays out *source* and returns the lines as text without trailing blanks.
def render(source : String, width : Int32 = 60, wrap : Bool = true) : Array(String)
  Docv::Layout.new(parse(source)).lines(width, wrap).map(&.text.rstrip)
end

# The text blocks of *source*, one string per block.
def blocks(source : String) : Array(String)
  parse(source).blocks.select(&.kind.text?).map(&.text)
end
