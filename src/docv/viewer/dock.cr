# src/docv/viewer/dock.cr

module Docv
  class Viewer
    # :nodoc:
    # The search field and page tree left of the page.
    class Dock
      # Narrowest dock; columns kept for the page when possible.
      MIN_WIDTH = 16
      MIN_PAGE  = 20
      # Rows above the tree (the field).
      HEAD_ROWS = 1
      # Blank columns on either side of the field.
      FIELD_MARGIN = 1
      # Field ends, drawn in the field's background color.
      FIELD_LEFT  = '◖'
      FIELD_RIGHT = '◗'
      PLACEHOLDER = "find"
      # Leading character of a search of every page.
      MANUAL_PREFIX = '/'

      enum Part
        Field
        Tree
        Divider
      end

      getter field = Field.new
      # Requested width, divider included; `span` fits it to a screen.
      getter width : Int32
      property? open : Bool
      # Tree of the current page's group.
      property group : Picker? = nil
      # Tree of every page, for manual searches.
      property pages : Picker? = nil

      def initialize(@width : Int32 = PickerSettings.new.dock_width, @open : Bool = false)
        @width = Math.max(@width, MIN_WIDTH)
      end

      def width=(width : Int32) : Int32
        @width = Math.max(width, MIN_WIDTH)
      end

      # Columns taken on a screen *cols* wide, leaving the page `MIN_PAGE`.
      def span(cols : Int32) : Int32
        Math.min(@width, Math.max(cols - MIN_PAGE, MIN_WIDTH)).clamp(1, Math.max(cols - 2, 1))
      end

      # Columns the page moves right: the span of an open dock.
      def offset(cols : Int32) : Int32
        @open ? span(cols) : 0
      end

      def tree : Picker?
        manual? ? @pages : @group
      end

      def manual? : Bool
        @field.text.starts_with?(MANUAL_PREFIX)
      end

      def query : String
        manual? ? @field.text[1..] : @field.text
      end

      def tree_rows(frame : Frame) : Int32
        Math.max(frame.content_rows - HEAD_ROWS, 1)
      end

      def tree_cols(frame : Frame) : Int32
        Math.max(span(frame.cols) - 1, 1)
      end

      def part(frame : Frame, row : Int32, col : Int32) : Part?
        return nil unless @open && Frame::TOP <= row < frame.bottom && 0 <= col < span(frame.cols)
        return Part::Divider if col == span(frame.cols) - 1
        row - Frame::TOP < HEAD_ROWS ? Part::Field : Part::Tree
      end

      def tree_row(frame : Frame, row : Int32) : Int32?
        offset = row - Frame::TOP - HEAD_ROWS
        0 <= offset < tree_rows(frame) ? offset : nil
      end

      # *hover* is the visible tree row under the pointer.
      def draw(screen : Screen, frame : Frame, styles : Array(UInt16), focused : Bool, hover : Int32?,
               dragging : Bool) : Nil
        return unless @open
        width = span(frame.cols)
        border = styles[Theme::Role::Border.value]
        frame.content_rows.times { |offset| screen.fill(Frame::TOP + offset, 0, width - 1, Cell.blank(0_u16)) }
        divider = dragging ? styles[Theme::Role::Thumb.value] : border
        frame.content_rows.times { |offset| screen[Frame::TOP + offset, width - 1] = Cell.new('│', divider) }
        screen[Frame::TOP - 1, width - 1] = Cell.new('┬', border)
        screen.fill(frame.bottom, 0, width - 1, Cell.new('─', border))
        screen[frame.bottom, width - 1] = Cell.new('┴', border)
        draw_field(screen, width - 1, styles, focused)
        tree = self.tree || return
        tree.draw(screen, Frame::TOP + HEAD_ROWS, 0, tree_rows(frame), width - 1, styles, hover, manual?)
      end

      private def draw_field(screen : Screen, cols : Int32, styles : Array(UInt16), focused : Bool) : Nil
        first = FIELD_MARGIN
        last = cols - 1 - FIELD_MARGIN
        return if last - first < 3
        row = Frame::TOP
        field = styles[Theme::Role::Field.value]
        ends = Styles.id(Style.new(fg: Styles[field].bg))
        screen[row, first] = Cell.new(FIELD_LEFT, ends)
        screen.fill(row, first + 1, last - first - 1, Cell.blank(field))
        screen[row, last] = Cell.new(FIELD_RIGHT, ends)
        start = first + 2
        limit = last
        text = @field.text
        if !focused && text.empty?
          placeholder = Styles.merge(field, styles[Theme::Role::Placeholder.value])
          screen.write(row, start, Unicode.truncate(PLACEHOLDER, limit - start), placeholder)
          return
        end
        visible = Dock.tail(text, limit - start - (focused ? 1 : 0))
        col = start
        if visible == text && text.starts_with?(MANUAL_PREFIX)
          col = screen.write(row, col, MANUAL_PREFIX.to_s, Styles.merge(field, styles[Theme::Role::Prompt.value]))
          visible = text[1..]
        end
        col = screen.write(row, col, visible, field)
        screen[row, col] = Cell.blank(Styles.merge(field, styles[Theme::Role::Cursor.value])) if focused && col < limit
      end

      # The end of *text* that fits in *width* columns, after a `…` when cut.
      def self.tail(text : String, width : Int32) : String
        return text if Unicode.text_width(text) <= width
        return "" if width < 2
        graphemes = text.graphemes
        used = 1
        start = graphemes.size
        while start > 0 && used + Unicode.width(graphemes[start - 1].to_s) <= width
          start -= 1
          used += Unicode.width(graphemes[start].to_s)
        end
        "…" + graphemes[start..].join(&.to_s)
      end
    end
  end
end
