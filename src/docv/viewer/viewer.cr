# src/docv/viewer/viewer.cr
module Docv
  # A full-screen terminal viewer for a `Document`: a manual page or a
  # Markdown document. The title row holds an always-visible search bar and
  # a close mark; below it a framed page whose right and bottom borders are
  # draggable scrollbars, and a status row. The page header of a manual page
  # stays pinned at the top of the frame and the page footer at the bottom.
  # The page lays out wrapped or unwrapped and has links with back
  # navigation (cross-references, files, heading anchors; URLs go to the
  # terminal as OSC 8 hyperlinks) and mouse text selection copied to the
  # clipboard.
  #
  # The search bar fuzzy-finds in the lines of the displayed page,
  # highlighting the matches in place and scrolling to the best one; text
  # that starts with `/` lists the pages of the manual and the documents of
  # the project instead (`Index`), the project's first.
  #
  # ```
  # Docv::Viewer.new(Docv.open("ls", "1").not_nil!).run
  # ```
  #
  # Without a document the viewer starts on an empty page; performing
  # `Action::OpenPage` before `run` starts in the page search:
  #
  # ```
  # viewer = Docv::Viewer.new
  # viewer.perform(Docv::Viewer::Action::OpenPage)
  # viewer.run
  # ```
  class Viewer
    # Columns moved by one horizontal step and lines by one wheel notch.
    HORIZONTAL_STEP = 8
    WHEEL_LINES     = 3
    # Timeout that resolves a lone ESC byte.
    ESCAPE_TIMEOUT = 50.milliseconds
    # Index entries described between two yields to the input loop.
    INDEX_BATCH = 16
    # Shortest interval between page search refreshes while the index is
    # being described.
    INDEX_REFRESH = 250.milliseconds

    # Between the parts of the status row.
    STATUS_SEPARATOR = " │ "
    # Rows a pinned page header or footer takes: the line and a rule.
    PINNED_ROWS = 2

    # Typed first in the search bar, searches the manual instead of the page.
    MANUAL_PREFIX = '/'
    # Shown in the search bar while it is empty and not focused.
    PLACEHOLDER = "find in page, / for pages"

    # Page text attributes and the roles that restyle them, most specific
    # first; the roles replace `TEXT_ATTRS`. Text a page colors itself keeps
    # its colors.
    TEXT_ROLES = [
      {Attr::Bold | Attr::Italic, Theme::Role::BoldItalic},
      {Attr::Bold, Theme::Role::Bold},
      {Attr::Italic, Theme::Role::Italic},
      {Attr::Underline, Theme::Role::Underline},
    ]
    TEXT_ATTRS = Attr::Bold | Attr::Italic | Attr::Underline

    # Roles of marked page text (`Style#markup`), put on top of its text
    # role.
    MARKUP_ROLES = {
      Markup::Code => Theme::Role::Code, Markup::CodeBlock => Theme::Role::CodeBlock,
      Markup::Quote => Theme::Role::Quote, Markup::Rule => Theme::Role::Rule, Markup::Image => Theme::Role::Image,
      Markup::SyntaxKeyword => Theme::Role::SyntaxKeyword, Markup::SyntaxString => Theme::Role::SyntaxString,
      Markup::SyntaxComment => Theme::Role::SyntaxComment, Markup::SyntaxFunction => Theme::Role::SyntaxFunction,
      Markup::SyntaxType => Theme::Role::SyntaxType, Markup::SyntaxConstant => Theme::Role::SyntaxConstant,
      Markup::SyntaxOperator => Theme::Role::SyntaxOperator, Markup::SyntaxPunctuation => Theme::Role::SyntaxPunctuation,
      Markup::SyntaxProperty => Theme::Role::SyntaxProperty, Markup::SyntaxTag => Theme::Role::SyntaxTag,
    }

    # Roles of whole heading lines by `Block#level`, from level 1.
    HEADING_ROLES = [
      Theme::Role::Heading1, Theme::Role::Heading2, Theme::Role::Heading3,
      Theme::Role::Heading4, Theme::Role::Heading5, Theme::Role::Heading6,
    ]

    # Characters a double click selects along with letters and digits, so
    # it takes `--color` and `snake_case` whole.
    WORD_CHARS = Set{'_', '-'}

    # What a double click selects a run of: a word or punctuation.
    enum CharClass
      Blank
      Word
      Punctuation
    end

    # Groups of the page search: the project's pages and documents first.
    PROJECT_GROUP = 0
    OTHER_GROUP   = 1

    # A loaded page.
    record Page, document : Document, path : String?

    # Where the reader was on a page, for back navigation.
    record Position, page : Page, block : Int32, offset : Int32, left : Int32, wrap : Bool

    # What a left-button drag moves.
    enum DragTarget
      None
      Content
      VerticalThumb
      HorizontalThumb
    end

    # What has the keyboard.
    enum Mode
      # The page, through `Bindings`.
      View
      # The search bar, through `FieldBindings`.
      Search
    end

    # What the search bar searches.
    enum Scope
      # The lines of the displayed page; the page stays in the frame with the
      # matches highlighted.
      Page
      # The pages of the manual (text after `MANUAL_PREFIX`), listed in the
      # frame.
      Manual
    end

    getter page : Page
    getter? wrap : Bool
    getter mode : Mode = Mode::View
    property bindings : Bindings = Bindings.new
    property field_bindings : FieldBindings = FieldBindings.new

    @tty : Term::Tty
    @input = Term::Input.new
    @screen : Screen
    @frame = Frame.new(24, 80)
    @manpath : Manpath
    @options : Options
    @events = Channel(Bytes | Symbol).new(64)
    @layouts = Hash({Int32, Bool}, Array(Layout::Line)).new
    @header : Layout::Line? = nil
    @footer : Layout::Line? = nil
    @lines = [] of Layout::Line
    @max_width = 0
    @links = [] of {Int32, Layout::Link}
    @focus : Int32? = nil
    @top = 0
    @left = 0
    @history = [] of Position
    @field = Field.new
    @scope : Scope? = nil
    @picker : Picker? = nil
    @help : Help? = nil
    @found = Set(Int32).new
    @origin = {0, 0}
    @index : Index? = nil
    @index_progress : {Int32, Int32}? = nil
    @message : String? = nil
    @selection : {Int32, Int32, Int32, Int32}? = nil
    @pointer : {Int32, Int32}? = nil
    @dark = true
    @theme : Theme
    @depth : ColorDepth
    @palette : Palette
    @styles = [] of UInt16
    @page_styles = Hash(UInt16, UInt16).new
    @visible = true
    @running = false
    @closed = false
    @drag = DragTarget::None
    @drag_grab = 0
    @press_target = DragTarget::None

    # *options* (unsafe requests, syntax highlighting) applies to pages
    # opened through links and the page search; `.rd` never reads there,
    # since the terminal belongs to the viewer.
    # *theme* styles the viewer (`Config#theme`); its colors follow the
    # terminal theme once the terminal answers the OSC 21 query, and are
    # off with `NO_COLOR` (*depth*).
    def initialize(document : Document = Document.new, path : String? = nil, @wrap : Bool = true,
                   @manpath : Manpath = Manpath.default, @tty : Term::Tty = Term::Tty.new,
                   options : Options = Options.new, @theme : Theme = Theme.new,
                   @depth : ColorDepth = Term::Tty.color_depth)
      @options = options.copy_with(stdin: nil)
      @page = Page.new(document, path)
      @screen = Screen.new(@frame.rows, @frame.cols)
      @palette = Palette.new(@dark)
      apply_colors
    end

    # Runs the viewer until the user quits. Restores the terminal on exit and
    # saves the page search index.
    def run : Nil
      @tty.enter
      @running = true
      begin
        spawn read_input
        Signal::WINCH.trap { @events.send(:resize) }
        resize
        draw
        while @running
          message = if @input.pending?
                      select
                      when value = @events.receive
                        value
                      when timeout(ESCAPE_TIMEOUT)
                        :flush
                      end
                    else
                      @events.receive
                    end
          case message
          when Bytes
            @input.feed(message) { |event| handle(event) }
          when :flush
            @input.flush { |event| handle(event) }
          when :resize
            resize
          when :index
            index_updated
          when :eof
            @running = false
          end
          draw if @running
        end
      ensure
        @closed = true
        Signal::WINCH.reset
        @tty.leave
        @index.try &.save
      end
    end

    private def read_input : Nil
      buffer = Bytes.new(4096)
      loop do
        count = @tty.input.read(buffer)
        break if count == 0
        @events.send(buffer[0, count].dup)
      end
    rescue IO::Error
    ensure
      @events.send(:eof) unless @events.closed?
    end

    # --- geometry ----------------------------------------------------------

    private def content_rows : Int32
      @frame.content_rows
    end

    private def content_cols : Int32
      @frame.content_cols
    end

    # Rows above the page body: the pinned header and its rule.
    private def header_rows : Int32
      @header ? PINNED_ROWS : 0
    end

    # Rows below the page body: a rule and the pinned footer.
    private def footer_rows : Int32
      @footer ? PINNED_ROWS : 0
    end

    # Rows of the page body.
    private def page_rows : Int32
      Math.max(content_rows - header_rows - footer_rows, 1)
    end

    # Screen row of the first body row.
    private def page_top : Int32
      Frame::TOP + header_rows
    end

    private def max_top : Int32
      Math.max(@lines.size - page_rows, 0)
    end

    private def max_left : Int32
      Math.max(@max_width - content_cols, 0)
    end

    private def clamp : Nil
      @top = @top.clamp(0, max_top)
      @left = @left.clamp(0, max_left)
    end

    private def resize : Nil
      rows, cols, width, height = @tty.size
      @input.window(rows, cols, width, height)
      return if rows == @frame.rows && cols == @frame.cols && !@lines.empty?
      anchor = anchor_of(@top)
      @frame = Frame.new(rows, cols)
      @screen.resize(rows, cols)
      relayout(anchor)
      list.try &.move(0, content_rows)
    end

    # --- layout ------------------------------------------------------------

    private def anchor_of(index : Int32) : {Int32, Int32}
      line = @lines[index]? || return {-1, 0}
      if line.block < 0
        later = @lines[index..].find { |candidate| candidate.block >= 0 }
        return index == 0 || later.nil? ? {-1, 0} : {later.block, later.offset}
      end
      {line.block, line.offset}
    end

    # The page body for the content width, without the header and footer,
    # which are pinned instead.
    private def layout(wrap : Bool) : Array(Layout::Line)
      @layouts[{content_cols, wrap}] ||= Layout.new(@page.document).lines(content_cols, wrap, header: false, footer: false)
    end

    private def relayout(anchor : {Int32, Int32}) : Nil
      layout = Layout.new(@page.document)
      @header = layout.header_line(content_cols)
      @footer = layout.footer_line(content_cols)
      @lines = layout(@wrap)
      @max_width = @lines.max_of?(&.width) || 0
      @links = [] of {Int32, Layout::Link}
      @lines.each_with_index { |line, index| line.links.each { |link| @links << {index, link} } }
      @focus = nil
      @selection = nil
      @top = locate(anchor)
      clamp
      refind
    end

    private def locate(anchor : {Int32, Int32}) : Int32
      block, offset = anchor
      return 0 if block < 0
      found = 0
      @lines.each_with_index do |line, index|
        next if line.block < 0
        break if line.block > block || (line.block == block && line.offset > offset)
        found = index
      end
      found
    end

    # --- input ---------------------------------------------------------------

    private def handle(event : Term::Derived) : Nil
      case event
      when Term::TextInput
        if @help
          help_key(event.key)
        else
          @mode.view? ? key(event.key) : field_text(event.text)
        end
      when Term::KeyCommand
        if @help
          help_key(event.key)
        else
          @mode.view? ? key(event.key) : field_key(event.key)
        end
      when Term::MousePress  then press(event)
      when Term::Drag        then drag(event)
      when Term::Click       then click(event)
      when Term::Scroll      then scroll(event)
      when Term::PointerMove then @pointer = {event.row, event.col}
      when Term::PointerLeave
        @drag = DragTarget::None
        @pointer = nil
      when Term::ResizeEvent then resize
      when Term::VisibilityEvent
        @visible = event.visible
        @screen.invalidate if @visible
      when Term::ColorSchemeEvent
        changed = event.dark != @dark
        @dark = event.dark
        @palette = Palette.new(@dark) unless @palette.reported?
        apply_colors
        @tty.query_colors if changed
      when Term::ColorsReport
        event.colors.each { |key, value| @palette.set(key, value) }
        apply_colors
      end
    end

    private def key(event : Term::KeyEvent) : Nil
      @selection = nil
      action = @bindings.lookup(event) || return
      @message = nil unless action.escape?
      perform(action)
    end

    # Runs *action* as if its key was pressed in the page view.
    def perform(action : Action) : Nil
      half = Math.max(page_rows // 2, 1)
      case action
      in .line_down?   then @top += 1
      in .line_up?     then @top -= 1
      in .page_down?   then @top += Math.max(page_rows - 1, 1)
      in .page_up?     then @top -= Math.max(page_rows - 1, 1)
      in .half_down?   then @top += half
      in .half_up?     then @top -= half
      in .top?         then @top = 0
      in .bottom?      then @top = max_top
      in .left?        then @left -= HORIZONTAL_STEP
      in .right?       then @left += HORIZONTAL_STEP
      in .half_left?   then @left -= Math.max(content_cols // 2, 1)
      in .half_right?  then @left += Math.max(content_cols // 2, 1)
      in .line_start?  then @left = 0
      in .line_end?    then @left = max_left
      in .toggle_wrap? then toggle_wrap
      in .next_link?   then focus_link(true)
      in .prev_link?   then focus_link(false)
      in .follow_link? then follow_focus
      in .back?        then back
      in .open_page?   then focus_bar(MANUAL_PREFIX.to_s)
      in .find?        then focus_bar("")
      in .help?        then @help = Help.new(@bindings, @field_bindings)
      in .escape?
        @focus = nil
        @message = nil
        @selection = nil
      in .redraw?
        @screen.invalidate
      in .quit?
        @running = false
      end
      clamp
    end

    # Scrolls the help with the scrolling keys; any other key closes it.
    private def help_key(event : Term::KeyEvent) : Nil
      help = @help || return
      rows = help.rows(@frame)
      case @bindings.lookup(event)
      when .nil?                    then @help = nil
      when .line_down?              then help.scroll(1, @frame)
      when .line_up?                then help.scroll(-1, @frame)
      when .page_down?, .half_down? then help.scroll(rows, @frame)
      when .page_up?, .half_up?     then help.scroll(-rows, @frame)
      when .top?                    then help.scroll(-help.lines.size, @frame)
      when .bottom?                 then help.scroll(help.lines.size, @frame)
      else                               @help = nil
      end
    end

    private def toggle_wrap : Nil
      anchor = anchor_of(@top)
      @wrap = !@wrap
      @left = 0
      relayout(anchor)
    end

    # --- search bar ----------------------------------------------------------

    # Gives the search bar the keyboard with *text* typed in.
    private def focus_bar(text : String) : Nil
      @mode = Mode::Search
      @field.clear
      @field.insert(text)
      @message = nil
      @selection = nil
      @scope = nil
      @origin = {@top, @left}
      field_changed
    end

    # Gives the keyboard back to the page and empties the search bar.
    private def close_bar : Nil
      @mode = Mode::View
      @picker = nil
      @scope = nil
      @found.clear
      @field.clear
    end

    # The results the frame lists instead of the page: the page search's.
    private def list : Picker?
      @scope.try(&.manual?) ? @picker : nil
    end

    private def field_text(text : String) : Nil
      @field.insert(text)
      field_changed
    end

    # Filters the results by the search bar text, first building the items
    # of the scope the text selects when that changed. Finding in the page
    # then scrolls to the best match.
    private def field_changed : Nil
      text = @field.text
      scope = text.starts_with?(MANUAL_PREFIX) ? Scope::Manual : Scope::Page
      picker = @picker
      if picker.nil? || scope != @scope
        picker = scope.manual? ? Picker.new(page_items(load_index)) : Picker.new(line_items, search_details: false)
        @picker = picker
        @scope = scope
      end
      picker.query = scope.manual? ? text[1..] : text
      mark_matches if scope.page?
    end

    private def field_key(event : Term::KeyEvent) : Nil
      action = @field_bindings.lookup(event) || return
      rows = content_rows
      page = Math.max(rows - 1, 1)
      case action
      in .accept?      then accept
      in .cancel?      then cancel
      in .delete_back? then field_changed if @field.delete_back
      in .clear?
        @field.clear
        field_changed
      in .next?          then step(1, rows)
      in .previous?      then step(-1, rows)
      in .page_next?     then step(page, rows)
      in .page_previous? then step(-page, rows)
      end
    end

    # Moves the selection by *delta*: through the listed pages, or through
    # the matches in the page (scrolling to the new one).
    private def step(delta : Int32, rows : Int32) : Nil
      picker = @picker || return
      return picker.move(delta, rows) if @scope.try(&.manual?)
      return if @found.empty?
      picker.move(delta, rows)
      reveal_match
    end

    # Opens the selected page, or stays at the match in the page.
    private def accept : Nil
      if @scope.try(&.manual?)
        item = @picker.try(&.current) || return
        close_bar
        open_entry(item.target)
      else
        close_bar
      end
    end

    # Leaves the search bar; finding in the page goes back to where it
    # started.
    private def cancel : Nil
      @top, @left = @origin if @scope.try(&.page?)
      close_bar
      clamp
    end

    # Scrolls so that (*line*, *col*..*col + width*) is visible.
    private def reveal(line : Int32, col : Int32, width : Int32) : Nil
      if line < @top || line >= @top + page_rows
        @top = line - page_rows // 3
      end
      if col < @left || col + width > @left + content_cols
        @left = Math.max(col + width - content_cols // 2, 0)
        @left = col if col < @left
      end
      clamp
    end

    # --- finding in the page -------------------------------------------------

    # One item per line of the displayed layout; item index is line index.
    private def line_items : Array(Picker::Item)
      @lines.map_with_index { |line, index| Picker::Item.new(line.text, target: index) }
    end

    # Marks the lines matching the query and scrolls to the best match.
    private def mark_matches : Nil
      picker = @picker || return
      @found = picker.query.blank? ? Set(Int32).new : picker.results.to_set
      reveal_match
    end

    # Matches the query again in a new layout of the page.
    private def refind : Nil
      return unless @scope.try(&.page?) && (picker = @picker)
      query = picker.query
      picker = Picker.new(line_items, search_details: false)
      picker.query = query
      @picker = picker
      @found = query.blank? ? Set(Int32).new : picker.results.to_set
    end

    # The selected match: its line and the screen-independent columns of
    # its matched characters.
    private def current_match : {Int32, Array(Int32)}?
      return nil if @found.empty?
      picker = @picker || return nil
      index = picker.results[picker.selected]? || return nil
      {index, match_columns(index)}
    end

    # Columns of the characters of line *index* the query matched.
    private def match_columns(index : Int32) : Array(Int32)
      picker = @picker || return [] of Int32
      _, columns = @lines[index].text_columns
      picker.marks(index)[0].compact_map { |position| columns[position]? }
    end

    private def reveal_match : Nil
      index, columns = current_match || return
      first = columns.min? || 0
      last = columns.max? || first
      reveal(index, first, last - first + 1)
    end

    # --- page search ---------------------------------------------------------

    private def load_index : Index
      @index ||= begin
        index = Index.new(@manpath)
        spawn describe(index) unless index.complete?
        index
      end
    end

    private def page_items(index : Index) : Array(Picker::Item)
      index.entries.map_with_index do |entry, number|
        Picker::Item.new(entry.reference, entry.description, number, Theme::Role::Name,
          entry.project? ? PROJECT_GROUP : OTHER_GROUP)
      end
    end

    # Describes the index in the background, yielding to the input loop
    # every `INDEX_BATCH` pages and refreshing the page search at most every
    # `INDEX_REFRESH`.
    private def describe(index : Index) : Nil
      last = Time.instant
      index.describe do |done, total|
        break if @closed
        @index_progress = {done, total}
        Fiber.yield if done % INDEX_BATCH == 0
        now = Time.instant
        if done == total || now - last >= INDEX_REFRESH
          last = now
          @events.send(:index)
        end
      end
    end

    private def index_updated : Nil
      return unless @scope.try(&.manual?)
      if (picker = @picker) && (index = @index)
        picker.items = page_items(index)
        picker.move(0, content_rows)
      end
    end

    private def open_entry(target : Int32) : Nil
      entry = @index.try(&.entries[target]?) || return
      open_path(entry.path)
    end

    # --- links and history ---------------------------------------------------

    private def focus_link(forward : Bool) : Nil
      return @message = "No links" if @links.empty?
      index = if focus = @focus
                (focus + (forward ? 1 : -1)) % @links.size
              elsif forward
                @links.index { |line, _| line >= @top } || 0
              else
                @links.rindex { |line, _| line < @top + page_rows } || @links.size - 1
              end
      @focus = index
      line, link = @links[index]
      reveal(line, link.col, link.width)
      @message = link.target.label
    end

    private def follow_focus : Nil
      focus = @focus || return
      _, link = @links[focus]
      open_link(link)
    end

    # Follows *link*: a manual page along the manual path, a file relative
    # to the current one (at its anchor, if any) or an anchor of the current
    # page. A URL is the terminal's to open (OSC 8); it is shown instead.
    private def open_link(link : Layout::Link) : Nil
      target = link.target
      case target.kind
      in .page?
        path = @manpath.find(target.location, target.part) || @manpath.find(target.location)
        return @message = "No manual entry for #{target.label}" unless path
        open_path(path)
      in .url?
        @message = target.location
      in .file?
        base = @page.path.try { |current| File.dirname(current) } || Dir.current
        path = File.expand_path(target.location, base)
        return @message = "No such file: #{target.location}" unless File.file?(path)
        open_path(path, target.part)
      in .anchor?
        block = anchor_block(target.part) || return @message = "No heading #{target.label}"
        remember
        show(@page, {block, 0}, 0)
      end
    end

    # Opens the page at *path*, at the heading of *anchor* when it has one,
    # remembering the current position unless the current page is the empty
    # start page.
    private def open_path(path : String, anchor : String = "") : Nil
      document = begin
        Docv.load(path, @options)
      rescue ex : IO::Error | Compress::Gzip::Error
        @message = "Cannot read #{path}: #{ex.message}"
        return
      end
      remember unless blank_page?
      page = Page.new(document, path)
      block = anchor.empty? ? nil : anchor_block(anchor, document)
      show(page, {block || -1, 0}, 0)
    end

    # Puts the reading position on the history.
    private def remember : Nil
      block, offset = anchor_of(@top)
      @history << Position.new(@page, block, offset, @left, @wrap)
    end

    # The block of the heading with *anchor* in *document*, matched as
    # written or as a heading anchor of the text.
    private def anchor_block(anchor : String, document : Document = @page.document) : Int32?
      document.anchors[anchor]? || document.anchors[Markdown.slug(anchor)]?
    end

    private def blank_page? : Bool
      @page.path.nil? && @page.document.blocks.empty?
    end

    private def back : Nil
      position = @history.pop? || return @message = "No previous page"
      @wrap = position.wrap
      show(position.page, {position.block, position.offset}, position.left)
    end

    private def show(page : Page, anchor : {Int32, Int32}, left : Int32) : Nil
      @page = page
      @layouts.clear
      @left = left
      relayout(anchor)
      @left = left
      clamp
    end

    # --- text selection ------------------------------------------------------

    # The page line and column under screen cell (*row*, *col*), kept on the
    # visible body rows.
    private def page_point(row : Int32, col : Int32) : {Int32, Int32}?
      return nil if @lines.empty?
      last = Math.min(@top + page_rows, @lines.size) - 1
      {(@top + row - page_top).clamp(@top, last), Math.max(@left + col - Frame::LEFT, 0)}
    end

    # The selection in page order: first line and column, last line and
    # column (inclusive).
    private def selection_range : {Int32, Int32, Int32, Int32}?
      anchor_line, anchor_col, head_line, head_col = @selection || return nil
      if anchor_line < head_line || (anchor_line == head_line && anchor_col <= head_col)
        {anchor_line, anchor_col, head_line, head_col}
      else
        {head_line, head_col, anchor_line, anchor_col}
      end
    end

    # The selected columns of line *index*: start and past-the-end, within
    # the line's text (its indentation and trailing blanks are not
    # selected); `nil` when none.
    private def selected_cols(index : Int32, range : {Int32, Int32, Int32, Int32}) : {Int32, Int32}?
      first_line, first_col, last_line, last_col = range
      return nil unless first_line <= index <= last_line
      cells = @lines[index].cells
      text_start = cells.index { |cell| !blank?(cell) } || return nil
      text_end = (cells.rindex { |cell| !blank?(cell) } || text_start) + 1
      start = index == first_line ? first_col : 0
      start -= 1 if start > 0 && cells[start]?.try(&.continuation?)
      start = Math.max(start, text_start)
      finish = index == last_line ? Math.min(last_col + 1, cells.size) : cells.size
      finish += 1 if finish < cells.size && cells[finish].continuation?
      finish = Math.min(finish, text_end)
      start < finish ? {start, finish} : nil
    end

    # The selected text, lines joined by newlines. Lines lose the
    # indentation they share, so text is copied flush left while code keeps
    # its relative indentation; lines between selected ones that have no
    # text stay as empty lines.
    private def selected_text : String?
      range = selection_range || return nil
      first_line, _, last_line, _ = range
      selected = (first_line..last_line).map { |index| selected_cols(index, range) }
      base = selected.compact_map(&.try(&.[0])).min? || return nil
      String.build do |io|
        selected.each_with_index do |cols, offset|
          io << '\n' if offset > 0
          start, finish = cols || next
          start = base if offset > 0
          cells = @lines[first_line + offset].cells
          (start...finish).each { |col| cells[col].text(io) unless cells[col].continuation? }
        end
      end
    end

    # True for a cell without a character: padding and spaces between words.
    private def blank?(cell : Cell) : Bool
      cell.ch == ' ' && cell.cluster == 0 && !cell.continuation?
    end

    # Selects what a double click (*count* 2: the word or the run of
    # punctuation) or a triple click (*count* 3: the paragraph) at screen
    # cell (*row*, *col*) of the page body points at, and copies it.
    private def select_at(row : Int32, col : Int32, count : Int32) : Nil
      return unless 0 <= row - page_top < page_rows
      index, page_col = page_point(row, col) || return
      @selection = count == 2 ? word_at(index, page_col) : paragraph_at(index)
      copy_selection
    end

    # The run of cells of one `CharClass` around column *col* of line
    # *index*, as a selection; `nil` on a blank.
    private def word_at(index : Int32, col : Int32) : {Int32, Int32, Int32, Int32}?
      cells = @lines[index].cells
      return nil unless col < cells.size
      kind = char_class(cells, col)
      return nil if kind.blank?
      start = col
      while start > 0 && char_class(cells, start - 1) == kind
        start -= 1
      end
      finish = col
      while finish + 1 < cells.size && char_class(cells, finish + 1) == kind
        finish += 1
      end
      {index, start, index, finish}
    end

    # The class of the character at *col*; a continuation cell takes the
    # class of the wide character it continues.
    private def char_class(cells : Array(Cell), col : Int32) : CharClass
      while col > 0 && cells[col].continuation?
        col -= 1
      end
      cell = cells[col]
      return CharClass::Blank if blank?(cell)
      cell.ch.alphanumeric? || WORD_CHARS.includes?(cell.ch) ? CharClass::Word : CharClass::Punctuation
    end

    # The lines of the paragraph around line *index*: the lines with text
    # next to it in blocks of the same kind; a heading stands alone.
    private def paragraph_at(index : Int32) : {Int32, Int32, Int32, Int32}?
      kind = paragraph_kind(index) || return nil
      first = index
      last = index
      unless kind.heading?
        while first > 0 && paragraph_kind(first - 1) == kind
          first -= 1
        end
        while last + 1 < @lines.size && paragraph_kind(last + 1) == kind
          last += 1
        end
      end
      {first, 0, last, Math.max(@lines[last].cells.size - 1, 0)}
    end

    # The kind of the block of line *index*; `nil` for a line without text.
    private def paragraph_kind(index : Int32) : BlockKind?
      line = @lines[index]
      return nil if line.block < 0 || line.cells.all? { |cell| blank?(cell) }
      @page.document.blocks[line.block].kind
    end

    # Puts the selected text on the clipboard.
    private def copy_selection : Nil
      text = selected_text || return
      return if text.strip.empty?
      @tty.copy(text)
      @message = "Copied #{text.size} characters"
    end

    # --- mouse ---------------------------------------------------------------

    # Rows of what the frame shows: listed pages or page lines.
    private def view_rows : Int32
      (picker = list) ? picker.results.size : @lines.size
    end

    # Rows of the frame that scroll: all of them for a list, the body for a
    # page.
    private def view_visible : Int32
      list ? content_rows : page_rows
    end

    private def view_top : Int32
      (picker = list) ? picker.top : @top
    end

    private def view_max_top : Int32
      Math.max(view_rows - view_visible, 0)
    end

    private def scroll_to(top : Int32) : Nil
      if picker = list
        picker.scroll_to(top, content_rows)
      else
        @top = top
        clamp
      end
    end

    private def vertical_thumb : {Int32, Int32}
      Frame.thumb(content_rows, view_visible, view_rows, view_top, view_max_top)
    end

    private def horizontal_thumb : {Int32, Int32}
      return {0, @frame.inner_cols} if list
      Frame.thumb(@frame.inner_cols, content_cols, @max_width, @left, max_left)
    end

    private def press(event : Term::MousePress) : Nil
      @press_target = DragTarget::None
      return if @help
      case event.button
      when .aux8?
        back unless list
        return
      when .left?
      else
        return
      end
      case @frame.region(event.row, event.col)
      when .vertical_bar?
        track = event.row - Frame::TOP
        start, size = vertical_thumb
        if start <= track < start + size
          @press_target = DragTarget::VerticalThumb
          @drag_grab = track - start
        else
          page = Math.max(view_visible - 1, 1)
          scroll_to(view_top + (track < start ? -page : page))
        end
      when .horizontal_bar?
        return if list
        track = event.col - Frame::INNER
        start, size = horizontal_thumb
        if start <= track < start + size
          @press_target = DragTarget::HorizontalThumb
          @drag_grab = track - start
        else
          @left += track < start ? -content_cols : content_cols
          clamp
        end
      when .content?
        @press_target = DragTarget::Content
      end
    end

    private def drag(event : Term::Drag) : Nil
      return unless event.button.left?
      case event.phase
      in .start?
        @drag = @press_target
        if @drag.content? && list.nil?
          anchor = page_point(event.start_row, event.start_col)
          head = page_point(event.row, event.col)
          @selection = anchor && head ? {anchor[0], anchor[1], head[0], head[1]} : nil
        end
        drag_move(event)
      in .move?
        drag_move(event)
      in .end?
        drag_move(event)
        copy_selection if @drag.content? && list.nil?
        @drag = DragTarget::None
      end
    end

    private def drag_move(event : Term::Drag) : Nil
      case @drag
      in .content?
        return if list
        selection = @selection || return
        head = page_point(event.row, event.col) || return
        @selection = {selection[0], selection[1], head[0], head[1]}
      in .vertical_thumb?
        _, size = vertical_thumb
        travel = Math.max(content_rows - size, 1)
        scroll_to(((event.row - Frame::TOP - @drag_grab).to_i64 * view_max_top // travel).to_i)
      in .horizontal_thumb?
        return if list
        _, size = horizontal_thumb
        travel = Math.max(@frame.inner_cols - size, 1)
        @left = ((event.col - Frame::INNER - @drag_grab).to_i64 * max_left // travel).to_i
        clamp
      in .none?
      end
    end

    private def click(event : Term::Click) : Nil
      return unless event.button.left?
      if event.count > 1
        select_at(event.row, event.col, event.count) unless @help || list || !@frame.region(event.row, event.col).content?
        return
      end
      return @help = nil if @help
      region = @frame.region(event.row, event.col)
      return @running = false if region.close?
      @selection = nil
      if region.bar?
        focus_bar("") unless @mode.search?
        return
      end
      return unless region.content?
      if picker = list
        accept if picker.select_row(event.row - Frame::TOP)
        return
      end
      row = event.row - page_top
      return unless 0 <= row < page_rows
      index = @top + row
      line = @lines[index]? || return
      col = @left + event.col - Frame::LEFT
      line.links.each do |link|
        if link.col <= col < link.col + link.width
          @focus = @links.index { |entry| entry[0] == index && entry[1] == link }
          open_link(link)
          return
        end
      end
    end

    private def scroll(event : Term::Scroll) : Nil
      if help = @help
        help.scroll(event.dy * WHEEL_LINES, @frame)
        return
      end
      if picker = list
        picker.scroll_to(picker.top + event.dy * WHEEL_LINES, content_rows)
        return
      end
      if event.mods.shift?
        @left += (event.dy + event.dx) * HORIZONTAL_STEP
      else
        @top += event.dy * WHEEL_LINES
        @left += event.dx * HORIZONTAL_STEP
      end
      clamp
    end

    # --- drawing -------------------------------------------------------------

    # Resolves the theme for the palette at the color depth: 24-bit once the
    # terminal reported its colors, otherwise what the environment says.
    private def apply_colors : Nil
      depth = @depth.none? || !@palette.reported? ? @depth : ColorDepth::TrueColor
      @styles = @theme.styles(@palette, depth)
      @page_styles.clear
      @screen.colors(@palette, depth)
    end

    # The style id of *role*.
    private def role(role : Theme::Role) : UInt16
      @styles[role.value]
    end

    # The themed style of page style *id*: bold, italic and underlined text
    # in their roles, other text as it is; then marked text with the role of
    # its markup on top.
    private def page_style(id : UInt16) : UInt16
      @page_styles[id] ||= begin
        style = Styles[id]
        found = TEXT_ROLES.find { |attrs, _| style.attr & attrs == attrs }
        themed = if found && style.fg.default? && style.bg.default?
                   Styles.merge(Styles.id(Style.new(style.attr & ~TEXT_ATTRS)), role(found[1]))
                 else
                   id
                 end
        (markup = MARKUP_ROLES[style.markup]?) ? Styles.merge(themed, role(markup)) : themed
      end
    end

    private def draw : Nil
      return unless @visible
      @screen.clear
      if picker = list
        picker.draw(@screen, Frame::TOP, Frame::INNER, content_rows, @frame.inner_cols, @styles, hover_row)
      else
        draw_page
      end
      @frame.draw(@screen, vertical_thumb, horizontal_thumb, role(Theme::Role::Border),
        role(Theme::Role::Thumb), role(Theme::Role::Close))
      draw_title
      draw_status
      @help.try &.draw(@screen, @frame, @styles)
      @screen.render(@tty.output)
    end

    # The visible picker row under the pointer, if any.
    private def hover_row : Int32?
      row, col = @pointer || return nil
      return nil unless list
      @frame.region(row, col).content? ? row - Frame::TOP : nil
    end

    # The body, then the pinned header with its rule above it and the
    # pinned footer with its rule below it. Text takes its role (headings
    # whole), then links, the matches of finding in the page (the selected
    # one's line on `Selection`), the selection and the focused link go on
    # top.
    private def draw_page : Nil
      blocks = @page.document.blocks
      range = selection_range
      current = current_match.try(&.[0])
      page_rows.times do |row|
        index = @top + row
        line = @lines[index]? || next
        y = page_top + row
        @screen.blit(y, Frame::LEFT, line.cells, @left, content_cols)
        block = line.block >= 0 ? blocks[line.block] : nil
        if block && block.kind.heading? && (line_role = HEADING_ROLES[block.level - 1]?)
          heading = role(line_role)
          @screen.restyle(y, Frame::LEFT, content_cols) { heading }
        else
          @screen.restyle(y, Frame::LEFT, content_cols) { |id| page_style(id) }
        end
        line.links.each do |link|
          overlay(y, link.col, link.width) { |id| Styles.merge(id, role(Theme::Role::Link)) }
          if link.target.kind.url? && (cols = visible(link.col, link.width))
            @screen.link(y, cols[0], cols[1], link.target.location)
          end
        end
        if index == current
          @screen.restyle(y, Frame::LEFT, content_cols) { |id| Styles.merge(id, role(Theme::Role::Selection)) }
        end
        if @found.includes?(index)
          cells = line.cells
          match_columns(index).each do |col|
            overlay(y, col, cells[col]?.try(&.width.to_i) || 1) { |id| Styles.merge(id, role(Theme::Role::Mark)) }
          end
        end
        if range && (cols = selected_cols(index, range))
          overlay(y, cols[0], cols[1] - cols[0]) { |id| Styles.merge(id, role(Theme::Role::TextSelection)) }
        end
        if (focus = @focus) && (entry = @links[focus]?) && entry[0] == index
          link = entry[1]
          overlay(y, link.col, link.width) { |id| Styles.merge(id, role(Theme::Role::LinkFocus)) }
        end
      end
      if header = @header
        pinned(Frame::TOP, header)
        @frame.rule(@screen, Frame::TOP + 1, role(Theme::Role::Rule))
      end
      if footer = @footer
        last = @frame.bottom - 1
        @frame.rule(@screen, last - 1, role(Theme::Role::Rule))
        pinned(last, footer)
      end
    end

    # Draws a pinned *line* on screen row *row*, unscrolled, in `PageHeader`.
    private def pinned(row : Int32, line : Layout::Line) : Nil
      @screen.blit(row, Frame::LEFT, line.cells, 0, content_cols)
      over = role(Theme::Role::PageHeader)
      @screen.restyle(row, Frame::LEFT, content_cols) { |id| Styles.merge(page_style(id), over) }
    end

    # Restyles page columns *col*...*col + width* on screen row *row*.
    private def overlay(row : Int32, col : Int32, width : Int32, & : UInt16 -> UInt16) : Nil
      start, count = visible(col, width) || return
      @screen.restyle(row, start, count) { |id| yield id }
    end

    # The screen column and count of the visible part of page columns
    # *col*...*col + width*; `nil` when none is visible.
    private def visible(col : Int32, width : Int32) : {Int32, Int32}?
      start = Frame::LEFT + col - @left
      finish = Math.min(start + width, Frame::LEFT + content_cols)
      start = Math.max(start, Frame::LEFT)
      finish > start ? {start, finish - start} : nil
    end

    # The title row: the title, then the search bar: its text with a
    # cursor while focused (a leading `/` in `Prompt`), else the placeholder.
    private def draw_title : Nil
      @frame.title(@screen, role(Theme::Role::Title), role(Theme::Role::Version))
      return unless @frame.bar?
      field = role(Theme::Role::Field)
      start, limit = @frame.bar(@screen, field)
      unless @mode.search?
        @screen.write(0, start, Unicode.truncate(PLACEHOLDER, limit - start), Styles.merge(field, role(Theme::Role::Placeholder)))
        return
      end
      text = @field.text
      visible = tail(text, limit - start - 1)
      col = start
      if visible == text && text.starts_with?(MANUAL_PREFIX)
        col = @screen.write(0, col, MANUAL_PREFIX.to_s, Styles.merge(field, role(Theme::Role::Prompt)))
        visible = text[1..]
      end
      col = @screen.write(0, col, visible, field)
      @screen[0, col] = Cell.blank(Styles.merge(field, role(Theme::Role::Cursor))) if col < limit
    end

    # The status row: the message on the left; on the right the result
    # count (and indexing progress) of the page search, or the layout,
    # visible lines and column of the page, after the selected match and
    # the match count while finding in it.
    private def draw_status : Nil
      parts = [] of String
      if picker = list
        parts << "#{picker.results.size}/#{picker.items.size}"
        if (progress = @index_progress) && progress[0] < progress[1]
          parts << "indexing #{progress[0] * 100 // progress[1]}%"
        end
      else
        if (picker = @picker) && !picker.query.blank?
          parts << (@found.empty? ? "no matches" : "match #{picker.selected + 1}/#{@found.size}")
        end
        parts << (@wrap ? "[wrap]" : "[nowrap]")
        unless @lines.empty?
          parts << "#{@top + 1}-#{Math.min(@top + page_rows, @lines.size)}/#{@lines.size}"
          parts << "col #{@left + 1}"
        end
      end
      row = @frame.status_row
      text = parts.join(STATUS_SEPARATOR)
      width = Unicode.text_width(text)
      if width > @frame.cols
        @screen.write(row, 0, Unicode.truncate(text, @frame.cols), role(Theme::Role::Status))
        return
      end
      col = @frame.cols - width
      if message = @message
        @screen.write(row, 0, Unicode.truncate(message, col - 2), role(Theme::Role::Message))
      end
      parts.each_with_index do |part, index|
        col = @screen.write(row, col, STATUS_SEPARATOR, role(Theme::Role::StatusSeparator)) if index > 0
        col = @screen.write(row, col, part, role(Theme::Role::Status))
      end
    end

    # The end of *text* that fits in *width* columns, after a `…` when cut.
    private def tail(text : String, width : Int32) : String
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
