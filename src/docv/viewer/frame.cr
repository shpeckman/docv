# src/docv/viewer/frame.cr
module Docv
  class Viewer
    # The screen layout: a title row with the name, the page's heading
    # centered and a close mark, a line under it, the
    # content with one blank column of padding on either side, and the
    # vertical scrollbar in the last column (only its thumb is drawn). Below
    # the content the horizontal scrollbar runs as a line (thumb `━`, track
    # `─`), then the status row. A thumb that fills its track means
    # everything fits. A regular dock (`Dock`) takes the first *dock*
    # columns of the content rows; the content area starts after it.
    #
    # ```text
    # ＤＯＣＶ v0.1.0          Manual - LS(1)            🞪
    # ──────────┬─────────────────────────────────────────
    # dock      │ content                               ┃
    # dock      │ content                               ┃
    # dock      │ content
    # ──────────┴━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━─
    # message                             status │ status
    # ```
    struct Frame
      # Where a screen cell lies.
      enum Region
        Name
        Title
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

      # Screen row of the first content row.
      TOP = 2
      # Blank columns between the content and either edge of the content
      # area.
      PADDING = 1

      getter rows : Int32
      getter cols : Int32
      # Columns a regular dock takes left of the content area.
      getter dock : Int32

      def initialize(@rows : Int32, @cols : Int32, dock : Int32 = 0)
        @dock = dock.clamp(0, Math.max(@cols - 2, 0))
      end

      # Screen column of the first cell of the content area (padding
      # included).
      def inner : Int32
        @dock
      end

      # Screen column of the first content column.
      def left : Int32
        inner + PADDING
      end

      def content_rows : Int32
        Math.max(@rows - TOP - 2, 1)
      end

      # Columns of the content area: everything left of the vertical
      # scrollbar.
      def inner_cols : Int32
        Math.max(@cols - inner - 1, 1)
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
        inner + inner_cols
      end

      # Screen column of the close mark, left of the scrollbar column.
      def close_col : Int32
        Math.max(right - 1, 0)
      end

      # Columns the name and the version take at the start of the title row.
      def name_width : Int32
        Unicode.text_width(NAME) + Unicode.text_width(VERSION)
      end

      # The first column and the limit (exclusive) of the page's heading on
      # the title row: between the name and the close mark.
      def heading_bounds : {Int32, Int32}
        {name_width + 2, Math.max(close_col - 2, name_width + 2)}
      end

      # The first column of a heading *width* columns wide: centered on the
      # screen, kept within `heading_bounds`.
      def heading_col(width : Int32) : Int32
        first, limit = heading_bounds
        ((@cols - width) // 2).clamp(first, Math.max(first, limit - width))
      end

      # The region of screen cell (*row*, *col*); the padding is content,
      # the columns of a regular dock are border.
      def region(row : Int32, col : Int32) : Region
        if row < TOP - 1
          return Region::Close if col == close_col
          return col < name_width ? Region::Name : Region::Title
        end
        return Region::Status if row > bottom
        if row == bottom
          return inner <= col < right ? Region::HorizontalBar : Region::Border
        end
        return Region::Border if row < TOP || col < inner
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
        screen.fill(bottom, 0, inner, Cell.new('─', line))
        inner_cols.times do |col|
          screen[bottom, inner + col] = start <= col < start + size ? Cell.new('━', thumb) : Cell.new('─', line)
        end
        screen[bottom, right] = Cell.new('─', line)
      end

      # Writes the title in styles *name* and *version*.
      def title(screen : Screen, name : UInt16, version : UInt16) : Nil
        screen.write(0, screen.write(0, 0, NAME, name), VERSION, version)
      end

      # Draws a rule across the content area on screen row *row* in style
      # *line*.
      def rule(screen : Screen, row : Int32, line : UInt16) : Nil
        screen.fill(row, inner, inner_cols, Cell.new('─', line))
        screen[row, inner] = Cell.new('╶', line)
        screen[row, right - 1] = Cell.new('╴', line)
      end
    end
  end
end
