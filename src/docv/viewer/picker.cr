# src/docv/viewer/picker.cr
module Docv
  class Viewer
    # A fuzzy-filtered, ranked list with a selection: the page search, and
    # the ranking behind finding in the page.
    #
    # The query splits into space-separated terms, each a `Fuzzy` matcher.
    # Every term must match an item's label, or its detail when details are
    # searched. A term counts with the better of its label score plus
    # `LABEL_BONUS` and its detail score. Items of a lower group come first
    # (the project's pages and documents in the page search); within a
    # group the best score wins, and ties go to the shorter label, then to
    # the item order. An empty query lists every item in order.
    class Picker
      # What a label match is worth above an equal detail match.
      LABEL_BONUS = Fuzzy::SCORE_MATCH // 2
      # Widest label column in percent of the width; details follow in a
      # column.
      LABEL_PERCENT = 40

      # A candidate: the *label* shown and matched first, a secondary
      # *detail*, the caller's *target*, the *role* the label is drawn in and
      # the *group* it ranks in.
      record Item, label : String, detail : String = "", target : Int32 = 0, role : Theme::Role = Theme::Role::Text,
        group : Int32 = 0

      getter items : Array(Item)
      # Indices into `items` of the matching items, best first.
      getter results = [] of Int32
      # Index into `results` of the selected item.
      getter selected = 0
      # Index into `results` of the first visible row.
      getter top = 0
      getter query = ""

      @terms = [] of Fuzzy
      @marks = {} of Int32 => {Array(Int32), Array(Int32)}
      @label_width = 0

      def initialize(@items : Array(Item), @search_details : Bool = true)
        measure
        refilter
      end

      # Replaces the items, keeping the query, and the selected target when
      # the selection was moved.
      def items=(items : Array(Item)) : Array(Item)
        target = @selected > 0 ? current.try(&.target) : nil
        @items = items
        measure
        refilter
        @selected = 0
        @top = 0
        if target && (index = @results.index { |result| @items[result].target == target })
          @selected = index
        end
        items
      end

      # Sets the query and selects the best match.
      def query=(text : String) : String
        return text if text == @query
        @query = text
        @terms = text.split.map { |term| Fuzzy.new(term) }
        refilter
        @selected = 0
        @top = 0
        text
      end

      # The selected item.
      def current : Item?
        (result = @results[@selected]?) ? @items[result] : nil
      end

      # Moves the selection by *delta* and scrolls it into a view of *rows*.
      def move(delta : Int32, rows : Int32) : Nil
        return if @results.empty?
        @selected = (@selected + delta).clamp(0, @results.size - 1)
        @top = @selected if @selected < @top
        @top = @selected - rows + 1 if @selected >= @top + rows
        @top = @top.clamp(0, max_top(rows))
      end

      # Scrolls a view of *rows* to *top*, keeping the selection in view.
      def scroll_to(top : Int32, rows : Int32) : Nil
        @top = top.clamp(0, max_top(rows))
        return if @results.empty?
        @selected = @selected.clamp(@top, Math.min(@top + rows, @results.size) - 1)
      end

      # The largest `top` for a view of *rows*.
      def max_top(rows : Int32) : Int32
        Math.max(@results.size - rows, 0)
      end

      # Selects the item on visible *row*; `nil` when the row is empty.
      def select_row(row : Int32) : Item?
        index = @top + row
        return nil unless row >= 0 && index < @results.size
        @selected = index
        current
      end

      # Matched character positions in the label and the detail of item
      # *index*.
      def marks(index : Int32) : {Array(Int32), Array(Int32)}
        @marks[index] ||= begin
          item = @items[index]
          label = [] of Int32
          detail = [] of Int32
          @terms.each do |term|
            side, _ = best(term, item) || next
            if side.label?
              term.positions(item.label).try { |found| label.concat(found) }
            else
              term.positions(item.detail).try { |found| detail.concat(found) }
            end
          end
          {label, detail}
        end
      end

      # Draws *rows* results into *cols* columns of *screen* from (*row*,
      # *col*) with the role style ids *styles* (`Theme#styles`): labels in
      # their item's role, details in `Detail`, the selected row on
      # `Selection`, the visible row *hover* under the pointer on `Hover` and
      # matched characters in `Mark`.
      def draw(screen : Screen, row : Int32, col : Int32, rows : Int32, cols : Int32, styles : Array(UInt16),
               hover : Int32? = nil) : Nil
        detail = styles[Theme::Role::Detail.value]
        selection = styles[Theme::Role::Selection.value]
        hovered = styles[Theme::Role::Hover.value]
        mark = styles[Theme::Role::Mark.value]
        left = col + 1
        right = col + cols - 1
        label_width = Math.min(@label_width, cols * LABEL_PERCENT // 100)
        rows.times do |offset|
          index = @top + offset
          result = @results[index]? || break
          item = @items[result]
          row_style = index == @selected ? selection : (offset == hover ? hovered : 0_u16)
          label = Styles.merge(styles[item.role.value], row_style)
          plain = Styles.merge(detail, row_style)
          y = row + offset
          screen.fill(y, col, cols, Cell.blank(row_style))
          label_marks, detail_marks = marks(result)
          stop = Math.min(left + label_width, right)
          write(screen, y, left, stop, item.label, label_marks, label, mark)
          write(screen, y, stop + 2, right, item.detail, detail_marks, plain, mark)
        end
      end

      # Writes *text* in style *plain* from *col* up to *limit* (exclusive),
      # with the characters at *marks* in *plain* merged with *mark*, ending
      # in `…` when it does not fit.
      private def write(screen : Screen, row : Int32, col : Int32, limit : Int32, text : String,
                        marks : Array(Int32), plain : UInt16, mark : UInt16) : Nil
        return if col >= limit || text.empty?
        marked = Styles.merge(plain, mark)
        fits = Unicode.text_width(text) <= limit - col
        stop = fits ? limit : limit - 1
        index = 0
        text.each_grapheme do |grapheme|
          cluster = grapheme.to_s
          size = cluster.size
          width = Unicode.width(cluster)
          hit = marks.any? { |mark| index <= mark < index + size }
          index += size
          next if width == 0
          break if col + width > stop
          id = hit ? marked : plain
          screen[row, col] = Cell.from(cluster, id)
          screen[row, col + 1] = Cell.continuation(id) if width == 2
          col += width
        end
        screen[row, col] = Cell.new('…', plain) unless fits
      end

      private def measure : Nil
        @label_width = @items.max_of? { |item| Unicode.text_width(item.label) } || 0
      end

      private def refilter : Nil
        @marks.clear
        if @terms.empty?
          @results = Array(Int32).new(@items.size) { |index| index }
        else
          scored = [] of {Int32, Int32, Int32, Int32}
          @items.each_with_index do |item, index|
            total = score(item) || next
            scored << {item.group, -total, item.label.size, index}
          end
          scored.sort!
          @results = scored.map(&.[3])
        end
        @selected = @selected.clamp(0, Math.max(@results.size - 1, 0))
      end

      private def score(item : Item) : Int32?
        total = 0
        @terms.each do |term|
          _, value = best(term, item) || return nil
          total += value
        end
        total
      end

      # The part of an item a term counts on.
      private enum Side
        Label
        Detail
      end

      # The part of *item* that *term* counts on, with its score.
      private def best(term : Fuzzy, item : Item) : {Side, Int32}?
        label = term.score(item.label).try { |value| value + LABEL_BONUS }
        detail = @search_details ? term.score(item.detail) : nil
        if label && (detail.nil? || label >= detail)
          {Side::Label, label}
        elsif detail
          {Side::Detail, detail}
        end
      end
    end
  end
end
