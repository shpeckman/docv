# src/docv/layout.cr
module Docv
  # Turns a `Document` into lines of cells for a given width. Wrapped layout
  # fills paragraphs to the width; unwrapped layout puts each paragraph on a
  # single line. Unfilled text and tables never wrap.
  class Layout
    # A link on a line: a span link of the document (`Span#link`), or a
    # cross-reference (`name(section)`) found in the text.
    record Link, col : Int32, width : Int32, target : Target

    # One output line.
    class Line
      getter cells : Array(Cell)
      # Index of the block the line belongs to (`-1` for header and footer).
      getter block : Int32
      # Character offset of the line's first word within its block, used to
      # keep the reading position across layouts.
      getter offset : Int32
      getter links : Array(Link)

      def initialize(@cells = [] of Cell, @block = -1, @offset = 0, @links = [] of Link)
      end

      # Width in columns.
      def width : Int32
        @cells.size
      end

      # The line as text (trailing blanks kept).
      def text : String
        String.build do |io|
          @cells.each { |cell| cell.text(io) unless cell.continuation? }
        end
      end

      # The line as text plus the column of every character, for search.
      def text_columns : {String, Array(Int32)}
        columns = [] of Int32
        text = String.build do |io|
          @cells.each_with_index do |cell, col|
            next if cell.continuation?
            cell.text(io)
            count = cell.cluster == 0 ? 1 : Unicode.cluster(cell.cluster).size
            count.times { columns << col }
          end
        end
        {text, columns}
      end
    end

    # A word, a run of blanks or a tab, ready to be placed. A word with
    # linked text has the `Span#link` of each of its cells in *links*.
    struct Piece
      enum Kind : UInt8
        Word
        Space
        Tab
      end

      getter kind : Kind
      getter cells : Array(Cell)
      getter text : String
      getter offset : Int32
      getter count : Int32
      getter links : Array(Int32)?

      def initialize(@kind, @cells = [] of Cell, @text = "", @offset = 0, @count = 0, @links = nil)
      end
    end

    # A line under construction.
    class Row
      getter cells = [] of Cell
      getter links = [] of Link
      property offset : Int32 = -1

      def col : Int32
        @cells.size
      end

      def pad(col : Int32) : Nil
        while @cells.size < col
          @cells << Cell::BLANK
        end
      end

      def to_line(block : Int32) : Line
        Line.new(@cells, block, Math.max(@offset, 0), @links)
      end
    end

    LINK = /(?<![\w.\-])([A-Za-z_][\w.:+\-@]*)\(([0-9][a-zA-Z0-9]*|n|l)\)/

    # Drawn at each `Block#bars` column, and across a `BlockKind::Rule`.
    QUOTE_BAR = '│'
    RULE      = '─'

    getter document : Document

    @quote_style : UInt16 = Styles.id(Style.new(markup: Markup::Quote))
    @rule_style : UInt16 = Styles.id(Style.new(markup: Markup::Rule))

    def initialize(@document : Document)
    end

    # Lays out the document for *width* columns. With *header* the lines
    # start with the page header (`header_line`) and a blank line; with
    # *footer* they end with a blank line and the page footer
    # (`footer_line`).
    def lines(width : Int32, wrap : Bool = true, header : Bool = true, footer : Bool = true) : Array(Line)
      width = Math.max(width, 10)
      limit = wrap ? width : Int32::MAX
      lines = [] of Line
      if header && (line = header_line(width))
        lines << line << Line.new
      end
      @document.blocks.each_with_index do |block, index|
        rows = case block.kind
               in .blank? then Array.new(block.lines) { Row.new }
               in .text?  then text_block(block, limit, width)
               in .heading?
                 flow(tokenize(block.spans), block.indent, block.indent, limit, true, block.tabs)
               in .table?
                 block.table.try { |table| TableLayout.new(table, self).rows(block.indent, width, wrap) } || [] of Row
               in .rule? then [rule_row(block.indent, width)]
               end
        block.bars.try { |bars| rows.each { |row| bar(row, bars) } }
        rows.each { |row| lines << row.to_line(index) }
      end
      if footer && (line = footer_line(width))
        lines << Line.new << line
      end
      lines
    end

    # The page header for *width* columns: the reference, the manual title
    # centered and the reference again. `nil` when the document has no
    # title, and for Markdown.
    def header_line(width : Int32) : Line?
      doc = @document
      return nil if doc.title.empty? || doc.format.markdown?
      three_part(doc.reference, doc.manual, doc.reference, Math.max(width, 10))
    end

    # The page footer for *width* columns: the source, the date centered and
    # the reference. `nil` when the document has no title, and for Markdown.
    def footer_line(width : Int32) : Line?
      doc = @document
      return nil if doc.title.empty? || doc.format.markdown?
      three_part(doc.source, doc.date, doc.reference, Math.max(width, 10))
    end

    private def three_part(left : String, center : String, right : String, width : Int32) : Line
      left_width = Unicode.text_width(left)
      center_width = Unicode.text_width(center)
      right_width = Unicode.text_width(right)
      row = Row.new
      if left_width + center_width + right_width + 4 <= width
        place(row, left, 0)
        place(row, center, (width - center_width) // 2)
        place(row, right, width - right_width)
      else
        place(row, [left, center, right].reject(&.empty?).join("  "), 0)
      end
      row.to_line(-1)
    end

    private def place(row : Row, text : String, col : Int32) : Nil
      row.pad(col)
      text.each_grapheme do |grapheme|
        Layout.append(row.cells, grapheme.to_s, 0_u16)
      end
    end

    private def text_block(block : Block, limit : Int32, width : Int32) : Array(Row)
      pieces = tokenize(block.spans)
      first = Math.max(block.indent + block.offset, 0)
      start = nil
      rows = [] of Row
      if tag = block.tag
        tag_row = Row.new
        tag_row.pad(block.tag_indent)
        flow_into(tag_row, tokenize(tag), block.tag_indent, Int32::MAX, false, block.tabs, block.tag_indent, rows, false)
        if tag_row.col < block.indent || pieces.empty?
          start = tag_row
          first = block.indent
        else
          rows << tag_row
        end
      end
      rows.concat(flow(pieces, first, block.indent, limit, block.fill?, block.tabs, start))
      align(rows, block, width) unless block.align.left? || block.align.both?
      rows
    end

    private def align(rows : Array(Row), block : Block, width : Int32) : Nil
      rows.each do |row|
        lead = row.cells.index { |cell| cell != Cell::BLANK } || row.cells.size
        content = row.cells[lead..]
        room = width - block.indent - content.size
        next if room <= 0
        target = block.indent + (block.align.center? ? room // 2 : room)
        delta = target - lead
        row.cells.clear
        row.pad(target)
        row.cells.concat(content)
        row.links.map! { |link| link.copy_with(col: link.col + delta) }
      end
    end

    # A horizontal rule from *indent* to the end of *width*.
    private def rule_row(indent : Int32, width : Int32) : Row
      row = Row.new
      row.pad(indent)
      cell = Cell.new(RULE, @rule_style)
      (width - indent).times { row.cells << cell }
      row
    end

    # Puts a quote bar at each of the *bars* columns of *row*.
    private def bar(row : Row, bars : Array(Int32)) : Nil
      cell = Cell.new(QUOTE_BAR, @quote_style)
      bars.each do |col|
        row.pad(col + 1)
        row.cells[col] = cell if row.cells[col] == Cell::BLANK
      end
    end

    # Splits spans into words, blank runs and tabs.
    def tokenize(spans : Array(Span)) : Array(Piece)
      Tokenizer.new(spans.any? { |span| span.link != 0 }).run(spans)
    end

    # Builds pieces from spans; ASCII text skips grapheme segmentation. With
    # *linked* the link of every cell is kept.
    private class Tokenizer
      @pieces = [] of Piece
      @cells = [] of Cell
      @links = [] of Int32
      @offset = 0
      @word_offset = 0
      @paren = false

      def initialize(@linked : Bool)
      end

      def run(spans : Array(Span)) : Array(Piece)
        spans.each do |span|
          style = span.style
          if span.text.ascii_only?
            span.text.each_byte do |byte|
              case byte
              when 0x20 then space
              when 0x09 then tab
              when 0x0A, 0x0D
              else
                if 0x20 < byte < 0x7F
                  start_word
                  @paren = true if byte == 0x28
                  @cells << Cell.new(byte.unsafe_chr, style)
                  link(span.link)
                end
              end
              @offset += 1
            end
          else
            span.text.each_grapheme do |grapheme|
              cluster = grapheme.to_s
              case cluster
              when " "  then space
              when "\t" then tab
              when "\n", "\r"
              else
                start_word
                cluster = " " if cluster == " "
                @paren = true if cluster == "("
                Layout.append(@cells, cluster, style)
                link(span.link)
              end
              @offset += 1
            end
          end
        end
        flush
        @pieces
      end

      # Gives the cells added for the current grapheme the link *id*.
      private def link(id : Int32) : Nil
        return unless @linked
        while @links.size < @cells.size
          @links << id
        end
      end

      private def start_word : Nil
        @word_offset = @offset if @cells.empty?
      end

      private def space : Nil
        flush
        if (last = @pieces.last?) && last.kind.space?
          @pieces[-1] = Piece.new(Piece::Kind::Space, count: last.count + 1, offset: last.offset)
        else
          @pieces << Piece.new(Piece::Kind::Space, count: 1, offset: @offset)
        end
      end

      private def tab : Nil
        flush
        @pieces << Piece.new(Piece::Kind::Tab, offset: @offset)
      end

      private def flush : Nil
        return if @cells.empty?
        text = @paren ? String.build { |io| @cells.each { |cell| cell.text(io) unless cell.continuation? } } : ""
        links = @links.any? { |id| id != 0 } ? @links : nil
        @pieces << Piece.new(Piece::Kind::Word, @cells, text, @word_offset, links: links)
        @cells = [] of Cell
        @links = [] of Int32
        @paren = false
      end
    end

    # Appends the cell(s) of a grapheme cluster.
    def self.append(cells : Array(Cell), cluster : String, style : UInt16) : Nil
      return if cluster.empty?
      cell = Cell.from(cluster, style)
      if Unicode.width(cluster) == 0 && cluster.size == 1
        return
      end
      cells << cell
      cells << Cell.continuation(style) if cell.width == 2
    end

    # Places *pieces* into rows: the first row starts at *first* (or
    # continues *start*), wrapped rows at *rest*, filling up to *limit*.
    def flow(pieces : Array(Piece), first : Int32, rest : Int32, limit : Int32, fill : Bool, tabs : Tabs, start : Row? = nil) : Array(Row)
      rows = [] of Row
      row = start || Row.new
      row.pad(first)
      flow_into(row, pieces, rest, limit, fill, tabs, rest, rows, true)
      rows
    end

    private def flow_into(row : Row, pieces : Array(Piece), rest : Int32, limit : Int32, fill : Bool, tabs : Tabs, tab_base : Int32, rows : Array(Row), finish : Bool) : Nil
      pending = 0
      placed = false
      wrapped = false
      pieces.each do |piece|
        case piece.kind
        in .space?
          pending += piece.count unless wrapped && !placed
        in .tab?
          row.pad(row.col + pending)
          pending = 0
          relative = Math.max(row.col - tab_base, 0)
          row.pad(tab_base + tabs.next_stop(relative))
          placed = true
        in .word?
          size = piece.cells.size
          if fill && placed && row.col + pending + size > limit
            rows << row
            row = Row.new
            row.pad(rest)
            pending = 0
            wrapped = true
          end
          row.pad(row.col + pending)
          pending = 0
          row.offset = piece.offset if row.offset < 0
          links(row, piece)
          row.cells.concat(piece.cells)
          placed = true
        end
      end
      rows << row if finish
    end

    # Adds the links of *piece*, about to be placed at the end of *row*:
    # its span links (a link continues one of the same target that ends
    # before it on the row with only blanks between), or else the
    # cross-references in its text.
    private def links(row : Row, piece : Piece) : Nil
      if ids = piece.links
        start = 0
        while start < ids.size
          id = ids[start]
          finish = start + 1
          while finish < ids.size && ids[finish] == id
            finish += 1
          end
          if id > 0 && (target = @document.links[id - 1]?)
            span_link(row, row.col + start, finish - start, target)
          end
          start = finish
        end
        return
      end
      return if piece.text.empty?
      piece.text.scan(LINK) do |match|
        start = column_of(piece.text, match.begin(0))
        width = Unicode.text_width(match[0])
        row.links << Link.new(row.col + start, width, Target.new(TargetKind::Page, match[1], match[2]))
      end
    end

    private def span_link(row : Row, col : Int32, width : Int32, target : Target) : Nil
      if (last = row.links.last?) && last.target == target
        gap = last.col + last.width
        if gap <= col && (gap...Math.min(col, row.cells.size)).all? { |index| row.cells[index] == Cell::BLANK }
          row.links[-1] = last.copy_with(width: col + width - last.col)
          return
        end
      end
      row.links << Link.new(col, width, target)
    end

    private def column_of(text : String, char_index : Int32) : Int32
      return char_index if text.ascii_only?
      Unicode.text_width(text[0, char_index])
    end
  end
end

require "./layout/table"
