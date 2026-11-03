# src/docv/screen.cr
module Docv
  # A cell grid with a front buffer (what the terminal shows) and a back
  # buffer (the next frame). `render` compares the buffers row by row and
  # rewrites only the rows that changed. Colors are written at `depth`:
  # colors the terminal cannot show are reduced through `palette`. Cells can
  # carry a hyperlink (`link`), written as OSC 8.
  class Screen
    getter rows : Int32 = 0
    getter cols : Int32 = 0
    getter depth : ColorDepth = ColorDepth::TrueColor
    getter palette : Palette = Palette.new

    @front = Pointer(Cell).null
    @back = Pointer(Cell).null
    # Hyperlink of each cell: an index into `@uris`, `0` for none.
    @front_links = Pointer(Int32).null
    @back_links = Pointer(Int32).null
    @uris = [""]
    @uri_ids = {"" => 0}
    @front_valid = false
    @out = IO::Memory.new
    @sgr = Hash(UInt16, String).new

    def initialize(rows : Int32, cols : Int32)
      resize(rows, cols)
    end

    # Reallocates both buffers; the next render redraws every row.
    def resize(rows : Int32, cols : Int32) : Nil
      @rows = Math.max(rows, 1)
      @cols = Math.max(cols, 1)
      @front = Pointer(Cell).malloc(@rows * @cols, Cell::BLANK)
      @back = Pointer(Cell).malloc(@rows * @cols, Cell::BLANK)
      @front_links = Pointer(Int32).malloc(@rows * @cols, 0)
      @back_links = Pointer(Int32).malloc(@rows * @cols, 0)
      @front_valid = false
    end

    # Forces a full redraw on the next render.
    def invalidate : Nil
      @front_valid = false
    end

    # Sets the terminal's colors and color depth; the next render redraws
    # every row.
    def colors(@palette : Palette, @depth : ColorDepth) : Nil
      @sgr.clear
      invalidate
    end

    # Fills the back buffer with *cell*, without hyperlinks.
    def clear(cell : Cell = Cell::BLANK) : Nil
      (@rows * @cols).times { |index| @back[index] = cell }
      @back_links.clear(@rows * @cols)
    end

    # Makes *count* cells from (*row*, *col*) a hyperlink to *uri*. A URI
    # with characters outside printable ASCII is ignored.
    def link(row : Int32, col : Int32, count : Int32, uri : String) : Nil
      return unless uri.each_byte.all? { |byte| 0x20 < byte < 0x7F }
      id = @uri_ids[uri] ||= begin
        @uris << uri
        @uris.size - 1
      end
      count.times do |offset|
        @back_links[row * @cols + col + offset] = id if inside?(row, col + offset)
      end
    end

    # Sets one cell of the back buffer (ignored outside the grid).
    def []=(row : Int32, col : Int32, cell : Cell) : Cell
      @back[row * @cols + col] = cell if inside?(row, col)
      cell
    end

    # A cell of the back buffer.
    def [](row : Int32, col : Int32) : Cell
      @back[row * @cols + col]
    end

    # Copies *count* cells of *source* starting at *from* to (*row*, *col*);
    # positions past the end of *source* become blanks.
    def blit(row : Int32, col : Int32, source : Array(Cell), from : Int32, count : Int32) : Nil
      return unless 0 <= row < @rows
      count = Math.min(count, @cols - col)
      return if count <= 0
      base = @back + row * @cols + col
      available = Math.max(source.size - from, 0)
      copied = Math.min(available, count)
      if copied > 0 && from >= 0
        base.copy_from(source.to_unsafe + from, copied)
      end
      (copied...count).each { |index| base[index] = Cell::BLANK }
    end

    # Writes *text* in *style* from (*row*, *col*); returns the column after.
    def write(row : Int32, col : Int32, text : String, style : UInt16 = 0_u16) : Int32
      text.each_grapheme do |grapheme|
        cluster = grapheme.to_s
        width = Unicode.width(cluster)
        next if width == 0
        break if col + width > @cols
        self[row, col] = Cell.from(cluster, style)
        self[row, col + 1] = Cell.continuation(style) if width == 2
        col += width
      end
      col
    end

    # Fills *count* cells from (*row*, *col*) with *cell*.
    def fill(row : Int32, col : Int32, count : Int32, cell : Cell) : Nil
      count.times { |offset| self[row, col + offset] = cell }
    end

    # Replaces the style of *count* cells from (*row*, *col*).
    def restyle(row : Int32, col : Int32, count : Int32, & : UInt16 -> UInt16) : Nil
      count.times do |offset|
        next unless inside?(row, col + offset)
        index = row * @cols + col + offset
        cell = @back[index]
        @back[index] = cell.with_style(yield cell.style)
      end
    end

    # Writes the changed rows to *io* inside a synchronized update; returns
    # true when anything was written.
    def render(io : IO) : Bool
      @out.clear
      size = @cols * sizeof(Cell)
      @rows.times do |row|
        offset = row * @cols
        next if @front_valid && (@front + offset).as(UInt8*).memcmp((@back + offset).as(UInt8*), size) == 0 &&
                (@front_links + offset).memcmp(@back_links + offset, @cols) == 0
        render_row(row)
        (@front + offset).copy_from(@back + offset, @cols)
        (@front_links + offset).copy_from(@back_links + offset, @cols)
      end
      @front_valid = true
      return false if @out.size == 0
      io << Term::Sequences::SYNC_BEGIN
      io.write(@out.to_slice)
      io << Term::Sequences::RESET << Term::Sequences::SYNC_END
      io.flush
      true
    end

    private def render_row(row : Int32) : Nil
      @out << "\e[" << row + 1 << ";1H"
      style = UInt16::MAX
      link = 0
      offset = row * @cols
      previous_wide = false
      @cols.times do |col|
        cell = @back[offset + col]
        if (id = @back_links[offset + col]) != link
          link = id
          @out << Term::Sequences::HYPERLINK << @uris[link] << Term::Sequences::TERMINATOR
        end
        if cell.continuation?
          if previous_wide
            previous_wide = false
            next
          end
          cell = Cell.blank(cell.style)
        elsif cell.width == 2 && col == @cols - 1
          cell = Cell.blank(cell.style)
        end
        if cell.style != style
          style = cell.style
          @out << sgr(style)
        end
        cell.text(@out)
        previous_wide = cell.width == 2
      end
      @out << Term::Sequences::HYPERLINK << Term::Sequences::TERMINATOR if link != 0
      @out << Term::Sequences::RESET
    end

    # The SGR sequence of style *id* at the current depth.
    private def sgr(id : UInt16) : String
      @sgr[id] ||= begin
        style = Styles[id]
        unless @depth.true_color?
          style = style.colors(@palette.reduce(style.fg, @depth), @palette.reduce(style.bg, @depth))
        end
        String.build { |io| style.to_sgr(io) }
      end
    end

    private def inside?(row : Int32, col : Int32) : Bool
      0 <= row < @rows && 0 <= col < @cols
    end
  end
end
