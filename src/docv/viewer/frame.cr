# src/docv/viewer/frame.cr
module Docv
  class Viewer
    # The screen layout: a title row with the search bar and a close mark, a
    # line under it, the content with one blank column of padding on either
    # side, and the vertical scrollbar in the last column (only its thumb is
    # drawn). Below the content the horizontal scrollbar runs as a line
    # (thumb `━`, track `─`), then the status row. A thumb that fills its
    # track means everything fits.
    #
    # ```text
    # ＤＯＣＶ v0.1.0   ◖ search bar                 ◗ 🞪
    # ────────────────────────────────────────────────────
    #  content                                          ┃
    #  content                                          ┃
    #  content
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━─
    # message                             status │ status
    # ```
    struct Frame
      # Where a screen cell lies.
      enum Region
        Title
        Bar
        Close
        Border
        Content
        VerticalBar
        HorizontalBar
        Status
      end

      # The close mark at the end of the title row.
      CLOSE = '🞪'
      # The title at the start of the title row: the name, then the version.
      NAME    = "ＤＯＣＶ"
      VERSION = " v#{Docv::VERSION}"
      # The ends of the search bar, drawn in the bar's background color.
      BAR_LEFT  = '◖'
      BAR_RIGHT = '◗'
      # Columns between the title and the search bar.
      BAR_GAP = 3

      # Screen row of the first content row.
      TOP = 2
      # Screen column of the first cell of the content area (padding
      # included).
      INNER = 0
      # Blank columns between the content and either edge of the content
      # area.
      PADDING = 1
      # Screen column of the first content column.
      LEFT = INNER + PADDING

      getter rows : Int32
      getter cols : Int32

      def initialize(@rows : Int32, @cols : Int32)
      end

      def content_rows : Int32
        Math.max(@rows - TOP - 2, 1)
      end

      # Columns of the content area: everything left of the vertical
      # scrollbar.
      def inner_cols : Int32
        Math.max(@cols - INNER - 1, 1)
      end

      def content_cols : Int32
        Math.max(inner_cols - 2 * PADDING, 1)
      end

      # Screen row of the horizontal scrollbar.
      def bottom : Int32
        TOP + content_rows
      end

      # Screen row of the status line.
      def status_row : Int32
        bottom + 1
      end

      # Screen column of the vertical scrollbar.
      def right : Int32
        INNER + inner_cols
      end

      # Screen column of the close mark, left of the scrollbar column.
      def close_col : Int32
        Math.max(right - 1, 0)
      end

      # Screen columns of the search bar ends (`BAR_LEFT`, `BAR_RIGHT`).
      def bar_start : Int32
        Unicode.text_width(NAME) + Unicode.text_width(VERSION) + BAR_GAP
      end

      def bar_end : Int32
        close_col - 2
      end

      # True when the title row has room for the search bar.
      def bar? : Bool
        bar_end - bar_start >= 4
      end

      # The region of screen cell (*row*, *col*); the padding is content.
      def region(row : Int32, col : Int32) : Region
        if row < TOP - 1
          return Region::Close if col == close_col
          return bar? && bar_start <= col <= bar_end ? Region::Bar : Region::Title
        end
        return Region::Status if row > bottom
        if row == bottom
          return INNER <= col < right ? Region::HorizontalBar : Region::Border
        end
        return Region::Border if row < TOP || col < INNER
        col >= right ? Region::VerticalBar : Region::Content
      end

      # Start and size of a thumb on a *track* of cells for a view of
      # *visible* of *total* positions, scrolled to *offset* of at most
      # *max_offset*.
      def self.thumb(track : Int32, visible : Int32, total : Int32, offset : Int32, max_offset : Int32) : {Int32, Int32}
        total = Math.max(total, 1)
        size = (track.to_i64 * visible // total).clamp(1_i64, track.to_i64).to_i
        start = max_offset <= 0 ? 0 : (offset.to_i64 * (track - size) // max_offset).to_i
        {start, size}
      end

      # Draws the close mark, the line under the title row and the
      # scrollbars (thumb start and size on their tracks), in the given
      # style ids.
      def draw(screen : Screen, vertical : {Int32, Int32}, horizontal : {Int32, Int32},
               line : UInt16, thumb : UInt16, close : UInt16) : Nil
        screen[0, close_col] = Cell.new(CLOSE, close)
        screen.fill(TOP - 1, 0, @cols, Cell.new('─', line))
        start, size = vertical
        size.times { |offset| screen[TOP + start + offset, right] = Cell.new('┃', thumb) }
        start, size = horizontal
        inner_cols.times do |col|
          screen[bottom, INNER + col] = start <= col < start + size ? Cell.new('━', thumb) : Cell.new('─', line)
        end
        screen[bottom, right] = Cell.new('─', line)
      end

      # Writes the title in styles *name* and *version*.
      def title(screen : Screen, name : UInt16, version : UInt16) : Nil
        screen.write(0, screen.write(0, 0, NAME, name), VERSION, version)
      end

      # Draws the search bar filled in style *field*, its ends in the bar's
      # background color. Returns the first and past-the-last columns for
      # its text.
      def bar(screen : Screen, field : UInt16) : {Int32, Int32}
        ends = Styles.id(Style.new(fg: Styles[field].bg))
        screen[0, bar_start] = Cell.new(BAR_LEFT, ends)
        screen.fill(0, bar_start + 1, bar_end - bar_start - 1, Cell.blank(field))
        screen[0, bar_end] = Cell.new(BAR_RIGHT, ends)
        {bar_start + 2, bar_end - 1}
      end

      # Draws a rule across the content area on screen row *row* in style
      # *line*.
      def rule(screen : Screen, row : Int32, line : UInt16) : Nil
        screen.fill(row, INNER, inner_cols, Cell.new('─', line))
        screen[row, INNER] = Cell.new('╶', line)
        screen[row, right - 1] = Cell.new('╴', line)
      end

      # Draws a rounded box of *height* × *width* cells from (*row*, *col*)
      # with *title* in its top edge (in *heading*): edges in *line*, inside
      # filled with *fill*.
      def box(screen : Screen, row : Int32, col : Int32, height : Int32, width : Int32, title : String,
              line : UInt16, fill : UInt16, heading : UInt16) : Nil
        last = col + width - 1
        screen[row, col] = Cell.new('╭', line)
        screen.fill(row, col + 1, width - 2, Cell.new('─', line))
        screen[row, last] = Cell.new('╮', line)
        screen.write(row, col + 2, " #{title} ", heading) if width > Unicode.text_width(title) + 4
        (1...height - 1).each do |offset|
          screen[row + offset, col] = Cell.new('│', line)
          screen.fill(row + offset, col + 1, width - 2, Cell.blank(fill))
          screen[row + offset, last] = Cell.new('│', line)
        end
        screen[row + height - 1, col] = Cell.new('╰', line)
        screen.fill(row + height - 1, col + 1, width - 2, Cell.new('─', line))
        screen[row + height - 1, last] = Cell.new('╯', line)
      end
    end
  end
end
