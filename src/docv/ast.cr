# src/docv/ast.cr
module Docv
  # A run of text in one rendition. The text may hold spaces (breakable),
  # U+00A0 (unbreakable space) and tabs. *link* is the number of the
  # span's link in `Document#links`, counted from 1; `0` for none.
  record Span, text : String, style : UInt16 = 0_u16, link : Int32 = 0

  # What a document was written in: roff with its macro package, or
  # Markdown.
  enum Format : UInt8
    Roff
    Man
    Mdoc
    Markdown
  end

  # What a block holds.
  enum BlockKind : UInt8
    # Inline text: filled (wrapped) or unfilled (one line).
    Text
    # A heading of `Block#level`: 1 for a section (`.SH`, `.Sh`, `#`), 2
    # for a subsection (`.SS`, `.Ss`, `##`), down to 6.
    Heading
    # Vertical space of `Block#lines` empty lines.
    Blank
    # A table, in `Block#table`.
    Table
    # A horizontal rule across the width.
    Rule
  end

  # What a link leads to.
  enum TargetKind : UInt8
    # A manual page: `Target#location` is its name, `Target#part` its
    # section.
    Page
    # An absolute URL (`https:`, `mailto:`...) in `Target#location`, left
    # to the terminal (OSC 8).
    Url
    # A file relative to the document in `Target#location`, with a heading
    # anchor in `Target#part` (may be empty).
    File
    # A heading of the same document: the anchor in `Target#part`.
    Anchor
  end

  # Where a link leads.
  record Target, kind : TargetKind, location : String, part : String = "" do
    # The target as text: `ls(1)`, the URL, the path with its `#anchor`.
    def label : String
      case kind
      in .page?   then "#{location}(#{part})"
      in .url?    then location
      in .file?   then part.empty? ? location : "#{location}##{part}"
      in .anchor? then "##{part}"
      end
    end
  end

  # Horizontal placement of a block's lines.
  enum Align : UInt8
    Left
    Center
    Right
    Both
  end

  # Tab stops in columns, relative to the block's indent. Stops beyond the
  # explicit list repeat every `repeat` columns.
  class Tabs
    getter stops : Array(Int32)
    getter repeat : Int32

    def initialize(@stops = [] of Int32, @repeat = 5)
    end

    # Default stops: every 5 columns (groff's `0.5i` on a terminal).
    DEFAULT = new

    # Returns the first stop after column *col*.
    def next_stop(col : Int32) : Int32
      @stops.each { |stop| return stop if stop > col }
      last = @stops.last? || 0
      step = @repeat > 0 ? @repeat : 5
      last + ((col - last) // step + 1) * step
    end
  end

  # A layout unit. Every block starts on a new line; blocks with the same
  # indent following each other read as one paragraph with line breaks.
  class Block
    property kind : BlockKind
    # Heading level (1-6) of a `BlockKind::Heading`.
    property level : Int32 = 1
    # Left margin of the body text in columns.
    property indent : Int32 = 0
    # First-line offset from `indent` (negative for hanging paragraphs).
    property offset : Int32 = 0
    # Tag placed at `tag_indent` before the body (`.TP`, `.IP`, `.It`).
    property tag : Array(Span)? = nil
    property tag_indent : Int32 = 0
    property? fill : Bool = true
    property align : Align = Align::Left
    property tabs : Tabs = Tabs::DEFAULT
    property spans : Array(Span) = [] of Span
    # Number of empty lines of a `BlockKind::Blank` block.
    property lines : Int32 = 0
    # Whether a blank merges with an adjacent blank (paragraph spacing) or
    # stands as written (`.sp` in no-fill text, empty input lines).
    property? soft : Bool = true
    property table : Table? = nil
    # Columns of block quote bars drawn on every line of the block, left of
    # its text.
    property bars : Array(Int32)? = nil

    def initialize(@kind : BlockKind)
    end

    # The block's text without styles.
    def text : String
      String.build { |io| @spans.each { |span| io << span.text } }
    end
  end

  # A parsed manual page or Markdown document.
  class Document
    property format : Format = Format::Roff
    property title : String = ""
    property section : String = ""
    property date : String = ""
    property source : String = ""
    property manual : String = ""
    property arch : String = ""
    property blocks : Array(Block) = [] of Block
    # Diagnostics collected while parsing (`.tm`, unknown requests).
    property messages : Array(String) = [] of String
    # Targets of the links of the spans (`Span#link` counts from 1).
    property links : Array(Target) = [] of Target
    # Heading anchors (GitHub-style slugs) and the index of their block.
    property anchors : Hash(String, Int32) = {} of String => Int32

    # The page reference, e.g. `ls(1)`.
    def reference : String
      @section.empty? ? @title : "#{@title}(#{@section})"
    end

    # Plain text of all blocks, one block per line (for inspection and tests).
    def text : String
      String.build do |io|
        @blocks.each do |block|
          case block.kind
          when .blank? then block.lines.times { io << '\n' }
          when .rule?  then io << '\n'
          when .table?
            block.table.try &.rows.each do |row|
              io << row.cells.map { |cell| cell.spans.join(&.text) }.join('\t') << '\n'
            end
          else
            block.tag.try { |tag| io << tag.join(&.text) << '\t' }
            io << block.text << '\n'
          end
        end
      end
    end
  end

  # A tbl(1) table.
  class Table
    # Cell alignment from the tbl format keys.
    enum CellAlign : UInt8
      Left
      Right
      Center
      Numeric
      Alpha
    end

    # What a cell holds.
    enum CellKind : UInt8
      Text
      # `s`: continuation of the cell to the left.
      HSpan
      # `^`: continuation of the cell above.
      VSpan
      # `_` / `\_`: a single rule across the cell.
      Rule
      # `=`: a double rule across the cell.
      DoubleRule
    end

    # What a row holds.
    enum RowKind : UInt8
      Data
      Rule
      DoubleRule
    end

    # The outer frame.
    enum Frame : UInt8
      None
      Box
      DoubleBox
    end

    class Cell
      property kind : CellKind
      property align : CellAlign
      property spans : Array(Span)
      # A `T{ ... T}` text block: filled to the column width.
      property? block : Bool

      def initialize(@kind, @align, @spans = [] of Span, @block = false)
      end
    end

    class Row
      property kind : RowKind
      property cells : Array(Cell)

      def initialize(@kind, @cells = [] of Cell)
      end
    end

    property rows : Array(Row) = [] of Row
    property columns : Int32 = 0
    # Minimum column widths (`w(n)`), in columns.
    property min_widths : Array(Int32) = [] of Int32
    # Vertical rules before each column and after the last (0, 1 or 2).
    property vrules : Array(Int32) = [] of Int32
    # Extra gap after each column (`n` digits in the format), in columns.
    property gaps : Array(Int32) = [] of Int32
    property frame : Frame = Frame::None
    property? allbox : Bool = false
    property? center : Bool = false
    property? expand : Bool = false
  end
end
