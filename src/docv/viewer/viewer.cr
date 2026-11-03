# src/docv/viewer/viewer.cr
module Docv
  # A full-screen terminal viewer for a `Document`: a manual page or a
  # Markdown document. The title row holds the title (a click opens the
  # help), the page's heading centered (the manual and the page reference,
  # or the file name and first heading of a document; the page footer's
  # source and date beside it under the pointer) and a close mark; below it
  # a framed page whose right and bottom borders are draggable scrollbars,
  # and a status row. The page lays out wrapped or unwrapped and has links with back navigation
  # (cross-references, files, heading anchors; URLs go to the terminal as
  # OSC 8 hyperlinks) and mouse text selection copied to the clipboard.
  #
  # A dock (`Dock`) left of the page holds the search field and the tree of
  # the current page's group, or of the project's pages and documents
  # (`Index`), names sharing a prefix folded into nested groups
  # (`Picker::Outline`), the current page selected. Text in the field
  # fuzzy-finds in the lines of the displayed page, highlighting the matches
  # in place and scrolling to the best one, while the tree shows how many
  # lines of its pages match (`Corpus`); text that starts with `/` ranks
  # every page of the manual instead. The mouse pointer takes the shape of
  # what it is over (OSC 22).
  #
  # ```
  # Docv::Viewer.new(Docv.open("ls", "1").not_nil!).run
  # ```
  #
  # Without a document the viewer starts on an empty page, the dock closed;
  # performing `Action::OpenPage` before `run` starts in a search of every
  # page:
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
    # Shortest interval between refreshes while the index is described or
    # the text of the pages is read.
    INDEX_REFRESH = 250.milliseconds

    # Between the parts of the status row.
    STATUS_SEPARATOR = " │ "
    # Between the parts of the page's heading in the title row.
    HEADING_SEPARATOR = " - "

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
    # Key of the dock's tree while it shows the project's pages; a page in
    # no group has a key below it.
    PROJECT_KEY = -1

    # Shown on the empty start page.
    START_HINT = "p: this folder's pages │ /: search every page │ h: help"

    # What lies under the mouse pointer, for its shape.
    enum Hover
      Plain
      Text
      Link
      Resize
      Thumb
      Grabbed
    end

    # The CSS cursor names of the pointer shapes (OSC 22).
    POINTER_SHAPES = {
      Hover::Plain => "default", Hover::Text => "text", Hover::Link => "pointer",
      Hover::Resize => "ew-resize", Hover::Thumb => "grab", Hover::Grabbed => "grabbing",
    }

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
      Divider
    end

    # What has the keyboard.
    enum Focus
      # The page, through `Bindings`.
      Page
      # The dock's tree, through `TreeBindings`, then `Bindings`.
      Tree
      # The dock's search field, through `FieldBindings`.
      Field
    end

    getter page : Page
    getter? wrap : Bool
    getter focus : Focus = Focus::Page
    property bindings : Bindings = Bindings.new
    property field_bindings : FieldBindings = FieldBindings.new
    property tree_bindings : TreeBindings = TreeBindings.new

    @tty : Term::Tty
    @input = Term::Input.new
    @screen : Screen
    @frame = Frame.new(24, 80)
    @manpath : Manpath
    @options : Options
    @events = Channel(Bytes | Symbol).new(64)
    @layouts = Hash({Int32, Bool}, Array(Layout::Line)).new
    @lines = [] of Layout::Line
    @max_width = 0
    @links = [] of {Int32, Layout::Link}
    @link : Int32? = nil
    @top = 0
    @left = 0
    @history = [] of Position
    @dock : Dock
    # Finding in the page: one item per line of the layout.
    @finder : Picker? = nil
    @help : Help? = nil
    @found = Set(Int32).new
    @index : Index? = nil
    @index_progress : {Int32, Int32}? = nil
    @corpus : Corpus? = nil
    @search_threads : Int32
    @text_progress : {Int32, Int32}? = nil
    # Bumped by every search across pages; a search whose number is no
    # longer current stops and is dropped.
    @hit_generation = Atomic(Int32).new(0)
    # The latest hit counts, per index entry.
    @hit_counts : Array(Int32)? = nil
    # Key of the pages in the group's tree (`group_of`).
    @group_key : Int32? = nil
    # The outline of every page, to find the group of a page.
    @outline : Picker::Outline? = nil
    # True while the field held a manual search.
    @manual_view = false
    # The pointer shape last set.
    @hover = Hover::Plain
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
    # off with `NO_COLOR` (*depth*). *settings* places the dock and sets
    # the threads that search the text of all pages (`Config#viewer`).
    def initialize(document : Document = Document.new, path : String? = nil, @wrap : Bool = true,
                   @manpath : Manpath = Manpath.default, @tty : Term::Tty = Term::Tty.new,
                   options : Options = Options.new, @theme : Theme = Theme.new,
                   @depth : ColorDepth = Term::Tty.color_depth, settings : ViewerSettings = ViewerSettings.new)
      @options = options.copy_with(stdin: nil)
      @page = Page.new(document, path)
      @screen = Screen.new(@frame.rows, @frame.cols)
      @palette = Palette.new(@dark)
      @dock = Dock.new(settings.dock_width, settings.dock, false)
      @search_threads = settings.search_threads
      @message = START_HINT if blank_page?
      apply_colors
      open_dock if settings.dock_open
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
          when :corpus
            search_hits
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

    # Rows of the page body.
    private def page_rows : Int32
      content_rows
    end

    # Screen row of the first body row.
    private def page_top : Int32
      Frame::TOP
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
      @screen.resize(rows, cols)
      refit(rows, cols)
    end

    # Lays the frame out for *rows* × *cols* with the dock as it is, and the
    # page for the content width.
    private def refit(rows : Int32 = @frame.rows, cols : Int32 = @frame.cols) : Nil
      anchor = anchor_of(@top)
      @frame = Frame.new(rows, cols, @dock.offset(cols))
      relayout(anchor)
      @dock.tree.try &.move(0, @dock.tree_rows(@frame))
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
    # whose text the title row shows instead.
    private def layout(wrap : Bool) : Array(Layout::Line)
      @layouts[{content_cols, wrap}] ||= Layout.new(@page.document).lines(content_cols, wrap, header: false, footer: false)
    end

    private def relayout(anchor : {Int32, Int32}) : Nil
      @lines = layout(@wrap)
      @max_width = @lines.max_of?(&.width) || 0
      @links = [] of {Int32, Layout::Link}
      @lines.each_with_index { |line, index| line.links.each { |link| @links << {index, link} } }
      @link = nil
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
        return help_key(event.key) if @help
        case @focus
        in .field? then field_text(event.text)
        in .tree?  then tree_key(event.key) || key(event.key)
        in .page?  then key(event.key)
        end
      when Term::KeyCommand
        return help_key(event.key) if @help
        case @focus
        in .field? then field_key(event.key)
        in .tree?  then tree_key(event.key) || key(event.key)
        in .page?  then key(event.key)
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
      in .open_page?   then focus_field(Dock::MANUAL_PREFIX.to_s)
      in .find?        then focus_field("")
      in .toggle_dock? then toggle_dock
      in .help?        then @help = Help.new(@bindings, @field_bindings, @tree_bindings)
      in .escape?
        @link = nil
        @message = nil
        @selection = nil
      in .redraw?
        @screen.invalidate
      in .quit?
        @running = false
      end
      clamp
    end

    # Scrolls the help with the scrolling keys, both ways; any other key
    # closes it.
    private def help_key(event : Term::KeyEvent) : Nil
      help = @help || return
      rows = help.rows(@frame)
      half = Math.max(content_cols // 2, 1)
      case @bindings.lookup(event)
      when .nil?                    then @help = nil
      when .line_down?              then help.scroll(1, @frame)
      when .line_up?                then help.scroll(-1, @frame)
      when .page_down?, .half_down? then help.scroll(rows, @frame)
      when .page_up?, .half_up?     then help.scroll(-rows, @frame)
      when .top?                    then help.scroll(-help.lines.size, @frame)
      when .bottom?                 then help.scroll(help.lines.size, @frame)
      when .left?                   then help.scroll_x(-HORIZONTAL_STEP, @frame)
      when .right?                  then help.scroll_x(HORIZONTAL_STEP, @frame)
      when .half_left?              then help.scroll_x(-half, @frame)
      when .half_right?             then help.scroll_x(half, @frame)
      when .line_start?             then help.scroll_x(-help.width, @frame)
      when .line_end?               then help.scroll_x(help.width, @frame)
      else                               @help = nil
      end
    end

    private def toggle_wrap : Nil
      anchor = anchor_of(@top)
      @wrap = !@wrap
      @left = 0
      relayout(anchor)
    end

    # --- dock ----------------------------------------------------------------

    private def toggle_dock : Nil
      if @dock.open?
        close_dock
      else
        open_dock
        @focus = Focus::Tree
      end
    end

    # Opens the dock with the tree on the current page.
    private def open_dock : Nil
      return if @dock.open?
      @dock.open = true
      refit
      reveal_current
    end

    private def close_dock : Nil
      @dock.open = false
      @focus = Focus::Page
      refit
    end

    # The tree the dock shows: every page during a manual search, otherwise
    # the current page's group.
    private def tree : Picker
      @dock.manual? ? all_pages : group_tree
    end

    # The tree of every page, built on first use.
    private def all_pages : Picker
      @dock.pages ||= Picker.new(page_items(load_index), nested: true)
    end

    # The tree of the current page's group (`group_of`), built again when
    # the page is in another one, with as many groups unfolded as fit.
    private def group_tree : Picker
      index = load_index
      current = entry_number(index)
      key, members = group_of(index, current)
      picker = @dock.group
      if picker.nil? || key != @group_key
        picker = Picker.new(members.map { |number| page_item(index.entries[number], number) }, nested: true)
        rows = @dock.tree_rows(@frame)
        picker.reveal(current, rows) if current
        picker.unfold(rows)
        @dock.group = picker
        @group_key = key
        apply_hits
      end
      picker
    end

    # The pages the tree shows around page *number*, with a key that names
    # them: the project's pages and documents for one of them, or without a
    # page (`PROJECT_KEY`); the outermost group of a page in one (its node
    # id); the page alone otherwise.
    private def group_of(index : Index, number : Int32?) : {Int32, Array(Int32)}
      entries = index.entries
      if number.nil? || entries[number].project?
        return {PROJECT_KEY, (0...entries.size).select { |entry| entries[entry].project? }}
      end
      outline = @outline ||= Picker::Outline.new(page_items(index))
      root = -1
      parent = outline.nodes[outline.leaf(number)].parent
      while parent >= 0
        root = parent
        parent = outline.nodes[parent].parent
      end
      root < 0 ? {PROJECT_KEY - 1 - number, [number]} : {root, outline.items(root)}
    end

    # Selects the current page in the group's tree.
    private def reveal_current : Nil
      tree = group_tree
      number = entry_number(load_index) || return
      tree.reveal(number, @dock.tree_rows(@frame))
    end

    # Gives the search field the keyboard with *text* typed in.
    private def focus_field(text : String) : Nil
      open_dock
      @focus = Focus::Field
      @dock.field.clear
      @dock.field.insert(text)
      @message = nil
      @selection = nil
      field_changed
    end

    private def field_text(text : String) : Nil
      @dock.field.insert(text)
      field_changed
    end

    # Applies the field: a manual search ranks the tree; other text finds
    # in the page (scrolling to the best match) and counts the matching
    # lines of every page for the tree.
    private def field_changed : Nil
      if @dock.manual?
        @finder = nil
        @found.clear
        all_pages.query = @dock.query
        @manual_view = true
        clear_hits
        return
      end
      if @manual_view
        @manual_view = false
        reveal_current
      end
      find(@dock.field.text)
      search_hits
    end

    private def field_key(event : Term::KeyEvent) : Nil
      action = @field_bindings.lookup(event) || return
      rows = @dock.tree_rows(@frame)
      page = Math.max(rows - 1, 1)
      case action
      in .accept?      then accept
      in .cancel?      then @focus = Focus::Tree
      in .delete_back? then field_changed if @dock.field.delete_back
      in .clear?
        @dock.field.clear
        field_changed
      in .next?          then step(1)
      in .previous?      then step(-1)
      in .page_next?     then step(page)
      in .page_previous? then step(-page)
      in .expand?        then tree.expand(rows)
      in .collapse?      then tree.collapse(rows)
      in .scroll_left?   then tree.scroll_x(-HORIZONTAL_STEP, @dock.tree_cols(@frame), @dock.manual?)
      in .scroll_right?  then tree.scroll_x(HORIZONTAL_STEP, @dock.tree_cols(@frame), @dock.manual?)
      in .switch?        then @focus = Focus::Tree
      end
    end

    # Moves by *delta* through the tree, or through the matches in the page
    # while finding in it (scrolling to the new one).
    private def step(delta : Int32) : Nil
      finder = @finder
      if finder.nil? || @dock.manual? || @dock.field.empty?
        tree.move(delta, @dock.tree_rows(@frame))
        return
      end
      return if @found.empty?
      finder.move(delta, page_rows)
      reveal_match
    end

    # Opens the selected page of a manual search (or folds and unfolds the
    # selected group); finding in the page gives the page the keyboard at
    # the match.
    private def accept : Nil
      if @dock.manual?
        tree_open(tree)
      else
        @focus = Focus::Page
      end
    end

    # Runs the tree binding of *event*; false when there is none, so the
    # page view takes the key.
    private def tree_key(event : Term::KeyEvent) : Bool
      action = @tree_bindings.lookup(event) || return false
      tree = self.tree
      rows = @dock.tree_rows(@frame)
      page = Math.max(rows - 1, 1)
      case action
      in .next?          then tree.move(1, rows)
      in .previous?      then tree.move(-1, rows)
      in .page_next?     then tree.move(page, rows)
      in .page_previous? then tree.move(-page, rows)
      in .first?         then tree.move(-tree.rows.size, rows)
      in .last?          then tree.move(tree.rows.size, rows)
      in .open?          then tree_open(tree)
      in .expand?        then tree.expand(rows)
      in .collapse?      then tree.collapse(rows)
      in .scroll_left?   then tree.scroll_x(-HORIZONTAL_STEP, @dock.tree_cols(@frame), @dock.manual?)
      in .scroll_right?  then tree.scroll_x(HORIZONTAL_STEP, @dock.tree_cols(@frame), @dock.manual?)
      in .field?         then @focus = Focus::Field
      in .leave?         then @focus = Focus::Page
      end
      @message = nil
      true
    end

    # Opens the selected page of *tree* unless it is the current one, or
    # folds or unfolds the selected group. A page picked in a manual search
    # ends the search: the field is emptied, the tree goes back to the
    # page's group, and the page gets the keyboard.
    private def tree_open(tree : Picker) : Nil
      return tree.toggle(@dock.tree_rows(@frame)) if tree.group?
      item = tree.current || return
      if @dock.manual?
        @dock.field.clear
        @focus = Focus::Page
        open_entry(item.target)
        field_changed
        return
      end
      return if @index.try(&.entries[item.target]?).try(&.path) == @page.path
      open_entry(item.target)
    end

    # The visible tree row under the pointer, if any.
    private def tree_hover : Int32?
      row, col = @pointer || return nil
      return nil unless @dock.part(@frame, row, col).try(&.tree?)
      @dock.tree_row(@frame, row)
    end

    # --- finding in the page -------------------------------------------------

    # One item per line of the displayed layout; item index is line index.
    private def line_items : Array(Picker::Item)
      @lines.map_with_index { |line, index| Picker::Item.new(line.text, target: index) }
    end

    # Finds *text* in the lines of the page and scrolls to the best match.
    private def find(text : String) : Nil
      finder = @finder ||= Picker.new(line_items, search_details: false)
      finder.query = text
      @found = text.blank? ? Set(Int32).new : finder.results.to_set
      reveal_match
    end

    # Matches the query again in a new layout of the page.
    private def refind : Nil
      return unless finder = @finder
      query = finder.query
      finder = Picker.new(line_items, search_details: false)
      finder.query = query
      @finder = finder
      @found = query.blank? ? Set(Int32).new : finder.results.to_set
    end

    # The selected match: its line and the screen-independent columns of
    # its matched characters.
    private def current_match : {Int32, Array(Int32)}?
      return nil if @found.empty?
      finder = @finder || return nil
      index = finder.results[finder.selected]? || return nil
      {index, match_columns(index)}
    end

    # Columns of the characters of line *index* the query matched.
    private def match_columns(index : Int32) : Array(Int32)
      finder = @finder || return [] of Int32
      _, columns = @lines[index].text_columns
      finder.marks(index)[0].compact_map { |position| columns[position]? }
    end

    private def reveal_match : Nil
      index, columns = current_match || return
      first = columns.min? || 0
      last = columns.max? || first
      reveal(index, first, last - first + 1)
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

    # --- finding across pages ------------------------------------------------

    # Counts the lines of every page that the field's text matches and
    # hands the counts to the tree; the text of the pages is read first
    # (once, in the background) when it is not yet.
    private def search_hits : Nil
      generation = @hit_generation.add(1) + 1
      query = @dock.field.text
      return clear_hits if @dock.manual? || query.blank?
      corpus = self.corpus
      return unless corpus.ready?
      spawn do
        counts = corpus.count(query, -> { @hit_generation.get != generation })
        if counts && @hit_generation.get == generation
          @hit_counts = counts
          apply_hits
          @events.send(:hits)
        end
      end
    end

    private def clear_hits : Nil
      @hit_generation.add(1)
      @hit_counts = nil
      apply_hits
    end

    # Hands the hit counts (per index entry) to the group's tree.
    private def apply_hits : Nil
      tree = @dock.group || return
      counts = @hit_counts
      tree.hits = counts ? tree.items.map { |item| counts[item.target]? || 0 } : nil
    end

    # The text of every page, read in the background on first use.
    private def corpus : Corpus
      @corpus ||= begin
        corpus = Corpus.new(threads: @search_threads)
        sources = load_index.entries.map { |entry| Corpus::Source.new(entry.path, entry.mtime) }
        spawn read_pages(corpus, sources)
        corpus
      end
    end

    # Builds *corpus*, refreshing the progress in the status row at most
    # every `INDEX_REFRESH`, then searches the field's text.
    private def read_pages(corpus : Corpus, sources : Array(Corpus::Source)) : Nil
      last = Time.instant
      corpus.build(sources) do |done, total|
        @text_progress = {done, total}
        now = Time.instant
        if now - last >= INDEX_REFRESH
          last = now
          @events.send(:text)
        end
      end
      @text_progress = nil
      @events.send(:corpus)
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
      index.entries.map_with_index { |entry, number| page_item(entry, number) }
    end

    private def page_item(entry : Index::Entry, number : Int32) : Picker::Item
      Picker::Item.new(entry.reference, entry.description, number, Theme::Role::Name,
        entry.project? ? PROJECT_GROUP : OTHER_GROUP, entry.name)
    end

    # Describes the index in the background, yielding to the input loop
    # every `INDEX_BATCH` pages and refreshing the tree at most every
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
      tree = @dock.pages || return
      index = @index || return
      tree.items = page_items(index)
      tree.move(0, @dock.tree_rows(@frame))
    end

    private def open_entry(target : Int32) : Nil
      entry = @index.try(&.entries[target]?) || return
      open_path(entry.path)
    end

    # The index entry of the current page: by path, then by name and
    # section.
    private def entry_number(index : Index) : Int32?
      path = File.expand_path(@page.path || return nil)
      entries = index.entries
      entries.index { |entry| entry.path == path } || begin
        name, section = Manpath.split(File.basename(path)) || return nil
        entries.index { |entry| entry.name == name && entry.section == section }
      end
    end

    # --- links and history ---------------------------------------------------

    private def focus_link(forward : Bool) : Nil
      return @message = "No links" if @links.empty?
      index = if link = @link
                (link + (forward ? 1 : -1)) % @links.size
              elsif forward
                @links.index { |line, _| line >= @top } || 0
              else
                @links.rindex { |line, _| line < @top + page_rows } || @links.size - 1
              end
      @link = index
      line, link = @links[index]
      reveal(line, link.col, link.width)
      @message = link.target.label
    end

    private def follow_focus : Nil
      focus = @link || return
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

    # Shows *page*: finds the field's text in it and selects it in the tree.
    private def show(page : Page, anchor : {Int32, Int32}, left : Int32) : Nil
      @page = page
      @layouts.clear
      @left = left
      relayout(anchor)
      @left = left
      clamp
      reveal_current if @dock.open?
    end

    # --- text selection ------------------------------------------------------

    # The page line and column under screen cell (*row*, *col*), kept on the
    # visible body rows.
    private def page_point(row : Int32, col : Int32) : {Int32, Int32}?
      return nil if @lines.empty?
      last = Math.min(@top + page_rows, @lines.size) - 1
      {(@top + row - page_top).clamp(@top, last), Math.max(@left + col - @frame.left, 0)}
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

    private def scroll_to(top : Int32) : Nil
      @top = top
      clamp
    end

    private def vertical_thumb : {Int32, Int32}
      if help = @help
        return Frame.thumb(content_rows, help.rows(@frame), help.lines.size, help.top, help.max_top(@frame))
      end
      Frame.thumb(content_rows, page_rows, @lines.size, @top, max_top)
    end

    private def horizontal_thumb : {Int32, Int32}
      if help = @help
        return Frame.thumb(@frame.inner_cols, content_cols, help.width, help.left, help.max_left(@frame))
      end
      Frame.thumb(@frame.inner_cols, content_cols, @max_width, @left, max_left)
    end

    private def press(event : Term::MousePress) : Nil
      @press_target = DragTarget::None
      return if @help
      if part = @dock.part(@frame, event.row, event.col)
        @press_target = DragTarget::Divider if part.divider? && event.button.left?
        return
      end
      case event.button
      when .aux8?
        back
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
          page = Math.max(page_rows - 1, 1)
          scroll_to(@top + (track < start ? -page : page))
        end
      when .horizontal_bar?
        track = event.col - @frame.inner
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
        if @drag.content?
          anchor = page_point(event.start_row, event.start_col)
          head = page_point(event.row, event.col)
          @selection = anchor && head ? {anchor[0], anchor[1], head[0], head[1]} : nil
        end
        drag_move(event)
      in .move?
        drag_move(event)
      in .end?
        drag_move(event)
        copy_selection if @drag.content?
        refit if @drag.divider?
        @drag = DragTarget::None
      end
    end

    private def drag_move(event : Term::Drag) : Nil
      case @drag
      in .content?
        selection = @selection || return
        head = page_point(event.row, event.col) || return
        @selection = {selection[0], selection[1], head[0], head[1]}
      in .vertical_thumb?
        _, size = vertical_thumb
        travel = Math.max(content_rows - size, 1)
        scroll_to(((event.row - Frame::TOP - @drag_grab).to_i64 * max_top // travel).to_i)
      in .horizontal_thumb?
        _, size = horizontal_thumb
        travel = Math.max(@frame.inner_cols - size, 1)
        @left = ((event.col - @frame.inner - @drag_grab).to_i64 * max_left // travel).to_i
        clamp
      in .divider?
        # The page lays out for the new width when the drag ends (`refit`).
        @dock.width = event.col + 1
        @frame = Frame.new(@frame.rows, @frame.cols, @dock.offset(@frame.cols))
        clamp
      in .none?
      end
    end

    private def click(event : Term::Click) : Nil
      return unless event.button.left?
      part = @dock.part(@frame, event.row, event.col)
      if event.count > 1
        select_at(event.row, event.col, event.count) unless @help || part ||
                                                            !@frame.region(event.row, event.col).content?
        return
      end
      return @help = nil if @help
      if part
        dock_click(part, event.row)
        return
      end
      region = @frame.region(event.row, event.col)
      return @running = false if region.close?
      return perform(Action::Help) if region.name?
      @selection = nil
      return unless region.content?
      @focus = Focus::Page
      row = event.row - page_top
      return unless 0 <= row < page_rows
      index = @top + row
      line = @lines[index]? || return
      col = @left + event.col - @frame.left
      line.links.each do |link|
        if link.col <= col < link.col + link.width
          @link = @links.index { |entry| entry[0] == index && entry[1] == link }
          open_link(link)
          return
        end
      end
    end

    # A click on *part* of the dock at screen *row*: the field takes the
    # keyboard; a tree row opens its page or folds and unfolds its group.
    private def dock_click(part : Dock::Part, row : Int32) : Nil
      case part
      when .field?
        @focus = Focus::Field
      when .tree?
        offset = @dock.tree_row(@frame, row) || return
        tree = self.tree
        return unless tree.select_row(offset)
        @focus = Focus::Tree
        tree_open(tree)
      end
    end

    private def scroll(event : Term::Scroll) : Nil
      if (help = @help) && @dock.part(@frame, event.row, event.col).nil?
        if event.mods.shift?
          help.scroll_x((event.dy + event.dx) * HORIZONTAL_STEP, @frame)
        else
          help.scroll(event.dy * WHEEL_LINES, @frame)
          help.scroll_x(event.dx * HORIZONTAL_STEP, @frame)
        end
        return
      end
      if @dock.part(@frame, event.row, event.col)
        tree = @dock.tree || return
        if event.mods.shift? || event.dx != 0
          tree.scroll_x((event.dy + event.dx) * HORIZONTAL_STEP, @dock.tree_cols(@frame), @dock.manual?)
        else
          tree.scroll_to(tree.top + event.dy * WHEEL_LINES, @dock.tree_rows(@frame))
        end
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
      if help = @help
        help.draw(@screen, @frame, @styles)
      else
        draw_page
      end
      @frame.draw(@screen, vertical_thumb, horizontal_thumb, role(Theme::Role::Border),
        role(Theme::Role::Thumb), role(Theme::Role::Close))
      draw_title
      draw_status
      @dock.draw(@screen, @frame, @styles, @focus.field?, tree_hover, @drag.divider?)
      @screen.render(@tty.output)
      shape_pointer
    end

    # Sets the pointer shape for what lies under the pointer, when it
    # changed.
    private def shape_pointer : Nil
      hover = hover_kind
      return if hover == @hover
      @hover = hover
      @tty.pointer(POINTER_SHAPES[hover])
    end

    # What lies under the pointer: text to select, a link, page or group to
    # open, a field to type in, the dock's edge or a scrollbar thumb.
    private def hover_kind : Hover
      case @drag
      when .divider?                            then return Hover::Resize
      when .vertical_thumb?, .horizontal_thumb? then return Hover::Grabbed
      when .content?                            then return Hover::Text
      end
      row, col = @pointer || return Hover::Plain
      return Hover::Plain if @help
      if part = @dock.part(@frame, row, col)
        return case part
        in .field?   then Hover::Text
        in .divider? then Hover::Resize
        in .tree?
          offset = @dock.tree_row(@frame, row)
          tree = @dock.tree
          offset && tree && tree.top + offset < tree.rows.size ? Hover::Link : Hover::Plain
        end
      end
      case @frame.region(row, col)
      when .close?, .name?  then Hover::Link
      when .vertical_bar?   then on_thumb?(row - Frame::TOP, vertical_thumb) ? Hover::Thumb : Hover::Plain
      when .horizontal_bar? then on_thumb?(col - @frame.inner, horizontal_thumb) ? Hover::Thumb : Hover::Plain
      when .content?        then page_hover(row, col)
      else                       Hover::Plain
      end
    end

    private def on_thumb?(track : Int32, thumb : {Int32, Int32}) : Bool
      thumb[0] <= track < thumb[0] + thumb[1]
    end

    # A link, text or nothing at screen cell (*row*, *col*) of the page body.
    private def page_hover(row : Int32, col : Int32) : Hover
      offset = row - page_top
      return Hover::Plain unless 0 <= offset < page_rows
      line = @lines[@top + offset]? || return Hover::Plain
      at = @left + col - @frame.left
      return Hover::Link if line.links.any? { |link| link.col <= at < link.col + link.width }
      cell = line.cells[at]?
      cell && !blank?(cell) ? Hover::Text : Hover::Plain
    end

    # The body. Text takes its role (headings whole), then links, the matches of finding in the page (the selected
    # one's line on `Selection`), the selection and the focused link go on
    # top.
    private def draw_page : Nil
      blocks = @page.document.blocks
      range = selection_range
      current = current_match.try(&.[0])
      left = @frame.left
      page_rows.times do |row|
        index = @top + row
        line = @lines[index]? || next
        y = page_top + row
        @screen.blit(y, left, line.cells, @left, content_cols)
        block = line.block >= 0 ? blocks[line.block] : nil
        if block && block.kind.heading? && (line_role = HEADING_ROLES[block.level - 1]?)
          heading = role(line_role)
          @screen.restyle(y, left, content_cols) { heading }
        else
          @screen.restyle(y, left, content_cols) { |id| page_style(id) }
        end
        line.links.each do |link|
          overlay(y, link.col, link.width) { |id| Styles.merge(id, role(Theme::Role::Link)) }
          if link.target.kind.url? && (cols = visible(link.col, link.width))
            @screen.link(y, cols[0], cols[1], link.target.location)
          end
        end
        if index == current
          @screen.restyle(y, left, content_cols) { |id| Styles.merge(id, role(Theme::Role::Selection)) }
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
        if (focus = @link) && (entry = @links[focus]?) && entry[0] == index
          link = entry[1]
          overlay(y, link.col, link.width) { |id| Styles.merge(id, role(Theme::Role::LinkFocus)) }
        end
      end
    end

    # The title row: the title, then the page's heading centered in
    # `PageHeader` (`Help::TITLE` while the help is shown), with the page
    # footer's source and date after it in `Detail` while the pointer is on
    # it.
    private def draw_title : Nil
      @frame.title(@screen, role(Theme::Role::Title), role(Theme::Role::Version))
      heading = @help ? Help::TITLE : page_heading
      return if heading.empty?
      first, limit = @frame.heading_bounds
      text = Unicode.truncate(heading, limit - first)
      col = @frame.heading_col(Unicode.text_width(text))
      stop = @screen.write(0, col, text, role(Theme::Role::PageHeader))
      detail = @help ? "" : page_detail
      return if detail.empty? || limit - stop - 2 < 1
      row, at = @pointer || return
      return unless row == 0 && col <= at < stop + 2 + Unicode.text_width(detail)
      @screen.write(0, stop + 2, Unicode.truncate(detail, limit - stop - 2), role(Theme::Role::Detail))
    end

    # The page's heading: the manual and the reference of a manual page
    # (`ABRT Manual - ABRT(1)`), the file name and first heading of a
    # document (`README.md - docv`); empty for the start page.
    private def page_heading : String
      document = @page.document
      unless document.title.empty? || document.format.markdown?
        return document.manual.empty? ? document.reference : "#{document.manual}#{HEADING_SEPARATOR}#{document.reference}"
      end
      name = @page.path.try { |path| File.basename(path) } || return ""
      heading = document.blocks.find(&.kind.heading?).try(&.text.strip) || ""
      heading.empty? ? name : "#{name}#{HEADING_SEPARATOR}#{heading}"
    end

    # The page footer's source and date.
    private def page_detail : String
      document = @page.document
      [document.source, document.date].reject(&.empty?).join("  ")
    end

    # Restyles page columns *col*...*col + width* on screen row *row*.
    private def overlay(row : Int32, col : Int32, width : Int32, & : UInt16 -> UInt16) : Nil
      start, count = visible(col, width) || return
      @screen.restyle(row, start, count) { |id| yield id }
    end

    # The screen column and count of the visible part of page columns
    # *col*...*col + width*; `nil` when none is visible.
    private def visible(col : Int32, width : Int32) : {Int32, Int32}?
      start = @frame.left + col - @left
      finish = Math.min(start + width, @frame.left + content_cols)
      start = Math.max(start, @frame.left)
      finish > start ? {start, finish - start} : nil
    end

    # The status row: the message on the left; on the right the result
    # count of a manual search, or the selected match and the match count
    # while finding in the page, the progress of indexing and of reading
    # the pages, then the layout, visible lines and column of the page (the
    # visible lines of the help while it is shown).
    private def draw_status : Nil
      parts = [] of String
      if @dock.open? && @dock.manual?
        tree = @dock.pages
        parts << "#{tree.results.size}/#{tree.items.size}" if tree
      elsif (finder = @finder) && !finder.query.blank?
        parts << (@found.empty? ? "no matches" : "match #{finder.selected + 1}/#{@found.size}")
      end
      if @dock.open? && (progress = @index_progress) && progress[0] < progress[1]
        parts << "indexing #{progress[0] * 100 // progress[1]}%"
      end
      if (progress = @text_progress) && progress[1] > 0
        parts << "reading pages #{progress[0] * 100 // progress[1]}%"
      end
      if help = @help
        rows = help.rows(@frame)
        parts << "#{help.top + 1}-#{Math.min(help.top + rows, help.lines.size)}/#{help.lines.size}"
        parts << "col #{help.left + 1}"
      else
        parts << (@wrap ? "[wrap]" : "[nowrap]")
      end
      if @help.nil? && !@lines.empty?
        parts << "#{@top + 1}-#{Math.min(@top + page_rows, @lines.size)}/#{@lines.size}"
        parts << "col #{@left + 1}"
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
  end
end
