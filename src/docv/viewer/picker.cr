# src/docv/viewer/picker.cr

module Docv
  class Viewer
    # :nodoc:
    # Fuzzy-ranked list with a selection, shown as an `Outline` when nested.
    class Picker
      # What a label match is worth above an equal detail match.
      LABEL_BONUS = Fuzzy::SCORE_MATCH // 2
      # Widest label column, in percent of the width.
      LABEL_PERCENT = 40
      # Group marks and the columns they take.
      FOLDED       = '●'
      OPEN         = '○'
      MARKER_WIDTH = 2
      # Tree lines before a nested row, per enclosing level: `STEM` while that
      # level continues below, else `GUIDE` while an outer one does (in
      # `GUIDE_ROLE`); then the branch to a row with a later sibling, or the
      # last branch. Stems and branches are in `LINE_ROLE`.
      STEM        = "│"
      GUIDE       = "╎"
      BRANCH      = "├╴"
      LAST_BRANCH = "╰╴"
      GUIDE_ROLE  = Theme::Role::TreeGuide
      LINE_ROLE   = Theme::Role::Border
      # Roles of group labels and of their marks; word after a group's item
      # count.
      GROUP_ROLE   = Theme::Role::Button
      MARK_ROLE    = Theme::Role::ButtonDim
      GROUP_DETAIL = "pages"
      # The section of a page reference (`(1)` in `ls(1)`), drawn in `SUFFIX_ROLE`.
      SUFFIX      = /\([^()]*\)\z/
      SUFFIX_ROLE = Theme::Role::Detail

      # *target* is the caller's id; lower *group*s rank first; *key* places
      # the item in an outline, inside a group named *folder* unless empty.
      record Item, label : String, detail : String = "", target : Int32 = 0, role : Theme::Role = Theme::Role::Text,
        group : Int32 = 0, key : String = "", folder : String = ""

      getter items : Array(Item)
      # Indices into `items` of the matching items, best first.
      getter results = [] of Int32
      # Outline node ids when nested, otherwise `results`.
      getter rows = [] of Int32
      # Index into `rows` of the selected row.
      getter selected = 0
      # Index into `rows` of the first visible row.
      getter top = 0
      getter query = ""
      getter outline : Outline?
      # Columns the widest label takes, with its indentation and mark.
      getter label_width = 0
      # Columns the rows are scrolled sideways.
      getter left = 0
      getter hits : Array(Int32)? = nil

      @terms = [] of Fuzzy
      @marks = {} of Int32 => {Array(Int32), Array(Int32)}
      # Best result position under each outline node while there is a query.
      @rank = [] of Int32
      # Groups opened without a query, and groups folded while querying.
      @opened = Set(Int32).new
      @folded = Set(Int32).new
      @detail_width = 0
      # Per row id: an item's hit count, a group's number of items with hits.
      @row_hits : Array(Int32) = [] of Int32
      # Per row: bit *n* is set when a later row at depth *n* follows before a
      # shallower one (the levels that continue below it).
      @stems = [] of Int32

      def initialize(@items : Array(Item), @search_details : Bool = true, nested : Bool = false,
                     @min_group : Int32 = Outline::MIN_GROUP)
        @outline = Outline.new(@items, @min_group) if nested
        measure
        refilter
      end

      # Keeps the query, a moved selection, and open groups while the keys
      # stay the same.
      def items=(items : Array(Item)) : Array(Item)
        node = @selected > 0 ? @rows[@selected]? : nil
        target = node.try { |id| item_of(id) }.try { |index| @items[index].target }
        same = same_keys?(items)
        @items = items
        unless same || @outline.nil?
          @outline = Outline.new(items, @min_group)
          @opened.clear
          @folded.clear
          node = nil
        end
        self.hits = nil unless same
        measure
        refilter
        @selected = 0
        @top = 0
        index = if node && @outline
                  @rows.index(node)
                elsif target
                  @rows.index { |id| item_of(id).try { |item| @items[item].target == target } }
                end
        @selected = index if index
        items
      end

      # Sets the query and selects the best match.
      def query=(text : String) : String
        return text if text == @query
        @query = text
        @terms = text.split.map { |term| Fuzzy.new(term) }
        @folded.clear
        refilter
        @selected = 0
        @top = 0
        text
      end

      # The selected item; `nil` on a group.
      def current : Item?
        (id = @rows[@selected]?) && (index = item_of(id)) ? @items[index] : nil
      end

      # True when the selected row is a group.
      def group? : Bool
        (id = @rows[@selected]?) ? item_of(id).nil? : false
      end

      # Opens or folds the selected group in a view of *rows*.
      def toggle(rows : Int32) : Nil
        id = @rows[@selected]? || return
        return if item_of(id)
        set = @terms.empty? ? @opened : @folded
        set.add(id) unless set.delete(id)
        list_rows
        move(0, rows)
      end

      # Opens the selected group, or moves into it when it is open.
      def expand(rows : Int32) : Nil
        id = @rows[@selected]? || return
        return if item_of(id)
        open?(id) ? move(1, rows) : toggle(rows)
      end

      # Folds the selected group, or moves to its parent group.
      def collapse(rows : Int32) : Nil
        id = @rows[@selected]? || return
        return toggle(rows) if item_of(id).nil? && open?(id)
        parent = @outline.try(&.nodes[id].parent) || return
        index = @rows.index(parent) || return
        move(index - @selected, rows)
      end

      # Selects the item with *target*, unfolding its groups, in a view of
      # *rows*; false when no item has it.
      def reveal(target : Int32, rows : Int32) : Bool
        index = @items.index { |item| item.target == target } || return false
        if (outline = @outline) && @terms.empty?
          parent = outline.nodes[outline.leaf(index)].parent
          while parent >= 0
            @opened.add(parent)
            parent = outline.nodes[parent].parent
          end
          list_rows
        end
        row = @rows.index { |id| item_of(id) == index } || return false
        @top = Math.max(row - rows // 3, 0)
        @selected = row
        move(0, rows)
        true
      end

      # Opens groups level by level while the rows fit in *rows*; only
      # without a query.
      def unfold(rows : Int32) : Nil
        outline = @outline || return
        return unless @terms.empty?
        count = @rows.size
        level = outline.roots.select { |id| outline.nodes[id].group? }
        until level.empty?
          deeper = [] of Int32
          level.each do |id|
            node = outline.nodes[id]
            unless @opened.includes?(id)
              next if count + node.children.size > rows
              @opened.add(id)
              count += node.children.size
            end
            node.children.each { |child| deeper << child if outline.nodes[child].group? }
          end
          level = deeper
        end
        list_rows
        @selected = @selected.clamp(0, Math.max(@rows.size - 1, 0))
      end

      # Moves the selection by *delta* and scrolls it into a view of *rows*.
      def move(delta : Int32, rows : Int32) : Nil
        return if @rows.empty?
        @selected = (@selected + delta).clamp(0, @rows.size - 1)
        @top = @selected if @selected < @top
        @top = @selected - rows + 1 if @selected >= @top + rows
        @top = @top.clamp(0, max_top(rows))
      end

      # Scrolls a view of *rows* to *top*, keeping the selection in view.
      def scroll_to(top : Int32, rows : Int32) : Nil
        @top = top.clamp(0, max_top(rows))
        return if @rows.empty?
        @selected = @selected.clamp(@top, Math.min(@top + rows, @rows.size) - 1)
      end

      # Columns of the widest row, with or without *details*.
      def width(details : Bool) : Int32
        details ? @label_width + 2 + @detail_width : @label_width
      end

      # Scrolls sideways by *delta* columns in a view *cols* wide.
      def scroll_x(delta : Int32, cols : Int32, details : Bool) : Nil
        @left = (@left + delta).clamp(0, Math.max(width(details) - (cols - 2), 0))
      end

      # Sets hit counts per item; groups count their items with hits. `nil`
      # removes them.
      def hits=(counts : Array(Int32)?) : Array(Int32)?
        @hits = counts
        @row_hits = if counts
                      (outline = @outline) ? outline_hits(outline, counts) : counts
                    else
                      [] of Int32
                    end
        counts
      end

      def max_top(rows : Int32) : Int32
        Math.max(@rows.size - rows, 0)
      end

      # Selects visible *row*; false when the row is empty.
      def select_row(row : Int32) : Bool
        index = @top + row
        return false unless row >= 0 && index < @rows.size
        @selected = index
        true
      end

      # Matched character positions in the label and detail of item *index*.
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

      # *hover* is the visible row under the pointer; rows are drawn over *fill*.
      def draw(screen : Screen, row : Int32, col : Int32, rows : Int32, cols : Int32, styles : Array(UInt16),
               hover : Int32? = nil, fill : UInt16 = 0_u16, details : Bool = true) : Nil
        detail = styles[Theme::Role::Detail.value]
        selection = styles[Theme::Role::Selection.value]
        hovered = styles[Theme::Role::Hover.value]
        mark = styles[Theme::Role::Mark.value]
        hit = styles[Theme::Role::Hit.value]
        left = col + 1
        right = col + cols - 1
        column = Math.min(@label_width, (right - left) * LABEL_PERCENT // 100)
        rows.times do |offset|
          index = @top + offset
          id = @rows[index]? || break
          row_style = Styles.merge(fill, index == @selected ? selection : (offset == hover ? hovered : 0_u16))
          plain = Styles.merge(detail, row_style)
          y = row + offset
          screen.fill(y, col, cols, Cell.blank(row_style))
          count = @row_hits[id]? || 0
          badge = count > 0 ? count.to_s : ""
          limit = badge.empty? ? right : right - badge.size - 1
          screen.write(y, right - badge.size, badge, Styles.merge(hit, row_style)) unless badge.empty?
          x = 0
          if node = @outline.try(&.nodes[id])
            line = Styles.merge(styles[LINE_ROLE.value], row_style)
            guide = Styles.merge(styles[GUIDE_ROLE.value], row_style)
            x = branches(screen, y, left, limit, left - @left, node.depth, @stems[index]? || 0, line, guide)
            if node.group?
              label = Styles.merge(Styles.merge(styles[GROUP_ROLE.value], row_style), count > 0 ? hit : 0_u16)
              marker = Styles.merge(styles[MARK_ROLE.value], row_style)
              origin = left - @left
              write(screen, y, left, limit, origin + x, (open?(id) ? OPEN : FOLDED).to_s, [] of Int32, marker, mark)
              x += MARKER_WIDTH
              write(screen, y, left, limit, origin + x, node.text, shift(prefix_marks(node.prefix), node.skip),
                label, mark)
              if details
                after = Math.max(column, x + Unicode.text_width(node.text)) + 2
                write(screen, y, left, limit, origin + after, "#{node.size} #{GROUP_DETAIL}", [] of Int32, plain, mark)
              end
              next
            end
            x += MARKER_WIDTH if node.depth == 0
            id = node.item
          end
          item = @items[id]
          label = Styles.merge(Styles.merge(styles[item.role.value], row_style), count > 0 ? hit : 0_u16)
          label_marks, detail_marks = marks(id)
          text = node ? node.text : item.label
          label_marks = shift(label_marks, node.skip) if node
          name = text.match(SUFFIX).try { |md| text[0, md.begin(0)] } || text
          start = left - @left + x
          write(screen, y, left, limit, start, name, label_marks, label, mark)
          if name.size < text.size
            suffix = Styles.merge(styles[SUFFIX_ROLE.value], row_style)
            write(screen, y, left, limit, start + Unicode.text_width(name), text[name.size..],
              shift(label_marks, name.size), suffix, mark)
          end
          if details
            after = Math.max(column, x + Unicode.text_width(text)) + 2
            write(screen, y, left, limit, left - @left + after, item.detail, detail_marks, plain, mark)
          end
        end
      end

      # Draws the tree lines of a row at *depth* from screen column *start*
      # (*stems* as in `@stems`): stems and the branch in *style*, guides in
      # *guide*; returns the columns they take.
      private def branches(screen : Screen, row : Int32, origin : Int32, limit : Int32, start : Int32, depth : Int32,
                           stems : Int32, style : UInt16, guide : UInt16) : Int32
        return 0 if depth == 0
        (1...depth).each do |level|
          col = start + (level - 1) * Outline::INDENT
          if stems.bit(level) == 1
            write(screen, row, origin, limit, col, STEM, [] of Int32, style, 0_u16)
          elsif stems & ((1 << level) - 2) != 0
            write(screen, row, origin, limit, col, GUIDE, [] of Int32, guide, 0_u16)
          end
        end
        branch = stems.bit(depth) == 1 ? BRANCH : LAST_BRANCH
        write(screen, row, origin, limit, start + (depth - 1) * Outline::INDENT, branch, [] of Int32, style, 0_u16)
        depth * Outline::INDENT
      end

      # Writes the part of *text* from *col* within *origin*...*limit*, *marks*
      # merged with *mark*, ending in `…` when cut.
      private def write(screen : Screen, row : Int32, origin : Int32, limit : Int32, col : Int32, text : String,
                        marks : Array(Int32), plain : UInt16, mark : UInt16) : Nil
        return if col >= limit || text.empty?
        marked = Styles.merge(plain, mark)
        fits = col + Unicode.text_width(text) <= limit
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
          if col >= origin
            id = hit ? marked : plain
            screen[row, col] = Cell.from(cluster, id)
            screen[row, col + 1] = Cell.continuation(id) if width == 2
          end
          col += width
        end
        screen[row, col] = Cell.new('…', plain) unless fits || col < origin
      end

      # Per node: an item's count, a group's number of items with hits.
      # Children follow their group, so a reverse walk sums them up.
      private def outline_hits(outline : Outline, counts : Array(Int32)) : Array(Int32)
        nodes = outline.nodes
        shown = Array(Int32).new(nodes.size, 0)
        pages = Array(Int32).new(nodes.size, 0)
        (nodes.size - 1).downto(0) do |id|
          node = nodes[id]
          if node.group?
            shown[id] = pages[id]
          else
            shown[id] = counts[node.item]? || 0
            pages[id] = shown[id] > 0 ? 1 : 0
          end
          pages[node.parent] += pages[id] if node.parent >= 0
        end
        shown
      end

      # Characters of a group *prefix* the terms match.
      private def prefix_marks(prefix : String) : Array(Int32)
        @terms.each_with_object([] of Int32) do |term, found|
          term.positions(prefix).try { |positions| found.concat(positions) }
        end
      end

      # *marks* in a text without its first *skip* characters.
      private def shift(marks : Array(Int32), skip : Int32) : Array(Int32)
        skip == 0 ? marks : marks.compact_map { |mark| mark >= skip ? mark - skip : nil }
      end

      # The item of row *id*; `nil` for a group.
      private def item_of(id : Int32) : Int32?
        return id unless outline = @outline
        node = outline.nodes[id]
        node.group? ? nil : node.item
      end

      private def open?(id : Int32) : Bool
        @terms.empty? ? @opened.includes?(id) : !@folded.includes?(id)
      end

      private def same_keys?(items : Array(Item)) : Bool
        return false unless items.size == @items.size
        items.each_with_index do |item, index|
          old = @items[index]
          return false unless item.key == old.key && item.group == old.group && item.folder == old.folder
        end
        true
      end

      private def measure : Nil
        @label_width = if outline = @outline
                         outline.nodes.max_of? do |node|
                           mark = node.group? || node.depth == 0 ? MARKER_WIDTH : 0
                           node.depth * Outline::INDENT + mark + Unicode.text_width(node.text)
                         end || 0
                       else
                         @items.max_of? { |item| Unicode.text_width(item.label) } || 0
                       end
        @detail_width = @items.max_of? { |item| Unicode.text_width(item.detail) } || 0
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
        rank
        list_rows
        @selected = @selected.clamp(0, Math.max(@rows.size - 1, 0))
      end

      # Best result position under each outline node.
      private def rank : Nil
        outline = @outline || return
        return @rank.clear if @terms.empty?
        @rank = Array(Int32).new(outline.nodes.size, Int32::MAX)
        @results.each_with_index { |index, position| @rank[outline.leaf(index)] = position }
        (outline.nodes.size - 1).downto(0) do |id|
          parent = outline.nodes[id].parent
          @rank[parent] = Math.min(@rank[parent], @rank[id]) if parent >= 0
        end
      end

      private def list_rows : Nil
        unless outline = @outline
          @rows = @results
          return
        end
        @rows = [] of Int32
        if @terms.empty?
          outline.roots.each { |id| list_outline(outline, id) }
        else
          list_ranked(outline, outline.roots)
        end
        stem_rows(outline)
      end

      # Fills `@stems`, walking the rows backward: a row ends the levels
      # deeper than its own and continues its own.
      private def stem_rows(outline : Outline) : Nil
        @stems = Array(Int32).new(@rows.size, 0)
        later = 0
        (@rows.size - 1).downto(0) do |index|
          depth = outline.nodes[@rows[index]].depth
          @stems[index] = later & ((1 << (depth + 1)) - 1)
          later = (later & ((1 << depth) - 1)) | (1 << depth)
        end
      end

      private def list_outline(outline : Outline, id : Int32) : Nil
        @rows << id
        return unless @opened.includes?(id)
        outline.nodes[id].children.each { |child| list_outline(outline, child) }
      end

      private def list_ranked(outline : Outline, ids : Array(Int32)) : Nil
        ranked = ids.select { |id| @rank[id] < Int32::MAX }
        ranked.sort_by! { |id| @rank[id] }
        ranked.each do |id|
          @rows << id
          node = outline.nodes[id]
          list_ranked(outline, node.children) if node.group? && !@folded.includes?(id)
        end
      end

      private def score(item : Item) : Int32?
        total = 0
        @terms.each do |term|
          _, value = best(term, item) || return nil
          total += value
        end
        total
      end

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
