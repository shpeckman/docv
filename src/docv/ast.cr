# src/docv/ast.cr

module Docv
  # A run of text in one style (a `Styles` id). Spaces break, U+00A0 does
  # not; *link* is a 1-based index into `Document#links`, `0` for none.
  record Span, text : String, style : UInt16 = 0_u16, link : Int32 = 0

  # The source format of a `Document`.
  enum Format : UInt8
    Roff
    Man
    Mdoc
    Markdown
  end

  # What a block holds.
  enum BlockKind : UInt8
    # Inline text, filled or unfilled.
    Text
    # A heading of `Block#level` (1 for `.SH` and `#`, 2 for `.SS` and `##`...).
    Heading
    # `Block#lines` empty lines.
    Blank
    # A table in `Block#table`.
    Table
    # A horizontal rule.
    Rule
  end

  # What a link leads to.
  enum TargetKind : UInt8
    # A manual page: name in `Target#location`, section in `Target#part`.
    Page
    # An absolute URL in `Target#location`.
    Url
    # A file relative to the document, with an optional anchor in `Target#part`.
    File
    # A heading anchor of the same document, in `Target#part`.
    Anchor
  end

  # Where a link leads.
  record Target, kind : TargetKind, location : String, part : String = "" do
    # The target as text: `ls(1)`, the URL, or the path with its `#anchor`.
    def label : String
      case kind
      in .page?   then "#{location}(#{part})"
      in .url?    then location
      in .file?   then part.empty? ? location : "#{location}##{part}"
      in .anchor? then "##{part}"
      end
    end
  end

  # Horizontal alignment of a block's lines.
  enum Align : UInt8
    Left
    Center
    Right
    Both
  end

  # Tab stops in columns from the block's indent; past `stops` they repeat
  # every `repeat` columns.
  class Tabs
    getter stops : Array(Int32)
    getter repeat : Int32

    def initialize(@stops = [] of Int32, @repeat = 5)
    end

    # Stops every 5 columns.
    DEFAULT = new

    # The first stop after column *col*.
    def next_stop(col : Int32) : Int32
      @stops.each { |stop| return stop if stop > col }
      last = @stops.last? || 0
      step = @repeat > 0 ? @repeat : 5
      last + ((col - last) // step + 1) * step
    end
  end

  # A layout unit; each block starts on a new line.
  class Block
    property kind : BlockKind
    # Heading level (1-6) of a `BlockKind::Heading`.
    property level : Int32 = 1
    # Left margin of the body text in columns.
    property indent : Int32 = 0
    # First-line offset from `indent` (negative for hanging paragraphs).
    property offset : Int32 = 0
    # Tag drawn at `tag_indent` before the body (`.TP`, `.IP`, list markers).
    property tag : Array(Span)? = nil
    property tag_indent : Int32 = 0
    property? fill : Bool = true
    property align : Align = Align::Left
    property tabs : Tabs = Tabs::DEFAULT
    property spans : Array(Span) = [] of Span
    # Empty lines of a `BlockKind::Blank`.
    property lines : Int32 = 0
    # Whether a blank merges with adjacent ones (paragraph spacing).
    property? soft : Bool = true
    property table : Table? = nil
    # Columns of the block quote bars drawn on every line.
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
    # Diagnostics from parsing (`.tm`, unknown requests).
    property messages : Array(String) = [] of String
    # Link targets; `Span#link` is a 1-based index into it.
    property links : Array(Target) = [] of Target
    # Heading anchors (GitHub-style slugs) to block indices.
    property anchors : Hash(String, Int32) = {} of String => Int32

    # The page reference, e.g. `ls(1)`.
    def reference : String
      @section.empty? ? @title : "#{@title}(#{@section})"
    end

    # Plain text of all blocks, one per line.
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

    # A table cell.
    class Cell
      property kind : CellKind
      property align : CellAlign
      property spans : Array(Span)
      # A `T{ ... T}` text block, filled to the column width.
      property? block : Bool

      def initialize(@kind, @align, @spans = [] of Span, @block = false)
      end
    end

    # A table row.
    class Row
      property kind : RowKind
      property cells : Array(Cell)

      def initialize(@kind, @cells = [] of Cell)
      end
    end

    property rows : Array(Row) = [] of Row
    property columns : Int32 = 0
    # Minimum column widths (`w(n)`).
    property min_widths : Array(Int32) = [] of Int32
    # Vertical rules before each column and after the last (0, 1 or 2).
    property vrules : Array(Int32) = [] of Int32
    # Gap after each column, in columns (format digits).
    property gaps : Array(Int32) = [] of Int32
    property frame : Frame = Frame::None
    property? allbox : Bool = false
    property? center : Bool = false
    property? expand : Bool = false
  end
end
