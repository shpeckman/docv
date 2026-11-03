# src/docv/viewer/dock.cr
module Docv
  class Viewer
    # The dock left of the page: the search field on its first row, then a
    # tree of pages (nested `Picker`s the viewer sets: the current page's
    # group, or every page during a manual search), with a divider on its
    # right edge that resizes it and joins the lines above and below the
    # content. A `Regular` dock narrows the page (`Frame#dock`); an
    # `Overlay` dock covers its left part, on `Popup`.
    #
    # ```text
    # ────────────────────┬
    #  ◖ /abrt          ◗ │
    #  ▾ abrt             │
    #      abrt(1)        │
    #    ▸ action         │
    # ────────────────────┴
    # ```
    class Dock
      # Narrowest dock, and the columns it leaves the page at least.
      MIN_WIDTH = 16
      MIN_PAGE  = 20
      # Rows above the tree: the field.
      HEAD_ROWS = 1
      # Blank columns on either side of the field.
      FIELD_MARGIN = 1
      # The ends of the search field, drawn in the field's background color.
      FIELD_LEFT  = '◖'
      FIELD_RIGHT = '◗'
      # Shown in the field while it is empty and not focused.
      PLACEHOLDER = "find"
      # Typed first, searches the manual instead of the page.
      MANUAL_PREFIX = '/'

      # What a screen cell of the dock is.
      enum Part
        Field
        Tree
        Divider
      end

      getter field = Field.new
      getter style : DockStyle
      # Width in columns, divider included, before it is fitted to a screen
      # (`span`).
      getter width : Int32
      property? open : Bool
      # The tree of the current page's group (or of the folder's pages).
      property group : Picker? = nil
      # The tree of every page, for manual searches.
      property pages : Picker? = nil

      def initialize(@width : Int32 = ViewerSettings.new.dock_width, @style : DockStyle = DockStyle::Regular,
                     @open : Bool = false)
        @width = Math.max(@width, MIN_WIDTH)
      end

      # Sets the width, at least `MIN_WIDTH`.
      def width=(width : Int32) : Int32
        @width = Math.max(width, MIN_WIDTH)
      end

      # Columns the dock takes on a screen of *cols* columns, leaving the
      # page `MIN_PAGE` columns when there is room.
      def span(cols : Int32) : Int32
        Math.min(@width, Math.max(cols - MIN_PAGE, MIN_WIDTH)).clamp(1, Math.max(cols - 2, 1))
      end

      # Columns the page moves right on a screen of *cols* columns: the span
      # of an open regular dock.
      def offset(cols : Int32) : Int32
        @open && @style.regular? ? span(cols) : 0
      end

      # The tree shown: every page during a manual search, otherwise the
      # current page's group.
      def tree : Picker?
        manual? ? @pages : @group
      end

      # True when the field holds a manual search (a leading `/`).
      def manual? : Bool
        @field.text.starts_with?(MANUAL_PREFIX)
      end

      # The query of the field: after the prefix of a manual search.
      def query : String
        manual? ? @field.text[1..] : @field.text
      end

      # Rows of the tree on *frame*.
      def tree_rows(frame : Frame) : Int32
        Math.max(frame.content_rows - HEAD_ROWS, 1)
      end

      # Columns of the tree on *frame* (the divider excluded).
      def tree_cols(frame : Frame) : Int32
        Math.max(span(frame.cols) - 1, 1)
      end

      # The part of the open dock at screen cell (*row*, *col*), if any.
      def part(frame : Frame, row : Int32, col : Int32) : Part?
        return nil unless @open && Frame::TOP <= row < frame.bottom && 0 <= col < span(frame.cols)
        return Part::Divider if col == span(frame.cols) - 1
        row - Frame::TOP < HEAD_ROWS ? Part::Field : Part::Tree
      end

      # The visible tree row at screen *row*, if the row is in the tree.
      def tree_row(frame : Frame, row : Int32) : Int32?
        offset = row - Frame::TOP - HEAD_ROWS
        0 <= offset < tree_rows(frame) ? offset : nil
      end

      # Draws the open dock on *frame* with the role style ids *styles*: the
      # field (its text with a cursor when *focused*, a leading `/` in
      # `Prompt`, otherwise the placeholder), the divider in `Border`
      # (`Thumb` while *dragging*) joining the lines above and below with
      # `┬` and `┴`, and the tree with the visible row *hover* (with details
      # in a manual search). An overlay dock is drawn on `Popup`.
      def draw(screen : Screen, frame : Frame, styles : Array(UInt16), focused : Bool, hover : Int32?,
               dragging : Bool) : Nil
        return unless @open
        width = span(frame.cols)
        fill = @style.overlay? ? styles[Theme::Role::Popup.value] : 0_u16
        line = Styles.merge(fill, styles[Theme::Role::Border.value])
        frame.content_rows.times { |offset| screen.fill(Frame::TOP + offset, 0, width - 1, Cell.blank(fill)) }
        divider = dragging ? Styles.merge(fill, styles[Theme::Role::Thumb.value]) : line
        frame.content_rows.times { |offset| screen[Frame::TOP + offset, width - 1] = Cell.new('│', divider) }
        border = styles[Theme::Role::Border.value]
        screen[Frame::TOP - 1, width - 1] = Cell.new('┬', border)
        screen.fill(frame.bottom, 0, width - 1, Cell.new('─', border))
        screen[frame.bottom, width - 1] = Cell.new('┴', border)
        draw_field(screen, width - 1, styles, focused)
        tree = self.tree || return
        tree.draw(screen, Frame::TOP + HEAD_ROWS, 0, tree_rows(frame), width - 1, styles, hover, fill, manual?)
      end

      # Draws the field in the first *cols* columns, inside `FIELD_MARGIN`.
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
