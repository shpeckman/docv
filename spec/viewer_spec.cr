# spec/viewer_spec.cr
require "./spec_helper"

describe Docv::Viewer::Bindings do
  bindings = Docv::Viewer::Bindings.new

  it "binds no text keys, so typing finds in the page" do
    (' '.ord..'~'.ord).each do |code|
      bindings.lookup(Docv::Term::KeyEvent.new(code)).should be_nil
      bindings.lookup(Docv::Term::KeyEvent.new(code, Docv::Term::Mods::Shift)).should be_nil
    end
  end

  it "jumps to the top and bottom, leaving finer scrolling to the mouse" do
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::PAGE_UP)).should eq Docv::Viewer::Action::Top
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::PAGE_DOWN)).should eq Docv::Viewer::Action::Bottom
    {Docv::Term::Key::UP, Docv::Term::Key::DOWN, Docv::Term::Key::LEFT, Docv::Term::Key::RIGHT,
     Docv::Term::Key::HOME, Docv::Term::Key::END}.each do |key|
      bindings.lookup(Docv::Term::KeyEvent.new(key)).should be_nil
    end
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::LEFT, Docv::Term::Mods::Alt)).should eq Docv::Viewer::Action::Back
  end

  it "matches the physical key through the base layout" do
    event = Docv::Term::KeyEvent.new(0x438, Docv::Term::Mods::Ctrl, base: 'b'.ord)
    bindings.lookup(event).should eq Docv::Viewer::Action::ToggleDock
  end

  it "matches shifted symbols without their shift" do
    keymap = Docv::Viewer::Bindings.new([{Docv::Term::Mods::None, '$'.ord, Docv::Viewer::Action::Bottom}])
    event = Docv::Term::KeyEvent.new('4'.ord, Docv::Term::Mods::Shift, shifted: '$'.ord)
    keymap.lookup(event).should eq Docv::Viewer::Action::Bottom
  end

  it "ignores lock modifiers" do
    event = Docv::Term::KeyEvent.new('q'.ord, Docv::Term::Mods::Ctrl | Docv::Term::Mods::NumLock)
    bindings.lookup(event).should eq Docv::Viewer::Action::Quit
  end

  it "finds, searches pages and steps through matches on command keys" do
    bindings.lookup(Docv::Term::KeyEvent.new('f'.ord, Docv::Term::Mods::Ctrl)).should eq Docv::Viewer::Action::Find
    bindings.lookup(Docv::Term::KeyEvent.new('o'.ord, Docv::Term::Mods::Ctrl)).should eq Docv::Viewer::Action::OpenPage
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::F1 + 2)).should eq Docv::Viewer::Action::FindNext
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::F1 + 2, Docv::Term::Mods::Shift)).should eq Docv::Viewer::Action::FindPrevious
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::F1)).should eq Docv::Viewer::Action::Help
    bindings.lookup(Docv::Term::KeyEvent.new('z'.ord, Docv::Term::Mods::Alt)).should eq Docv::Viewer::Action::ToggleWrap
  end
end

describe Docv::Viewer::FieldBindings do
  bindings = Docv::Viewer::FieldBindings.new

  it "maps editing and list keys" do
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::ENTER)).should eq Docv::Viewer::FieldAction::Accept
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::DOWN)).should eq Docv::Viewer::FieldAction::Next
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::UP)).should eq Docv::Viewer::FieldAction::Previous
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::TAB)).should eq Docv::Viewer::FieldAction::Cancel
    bindings.lookup(Docv::Term::KeyEvent.new('j'.ord)).should be_nil
    bindings.lookup(Docv::Term::KeyEvent.new('n'.ord, Docv::Term::Mods::Ctrl)).should be_nil
  end
end

describe Docv::Viewer::Field do
  it "edits by grapheme" do
    field = Docv::Viewer::Field.new
    field.insert("ab")
    field.insert("é")
    field.delete_back.should be_true
    field.text.should eq "ab"
    field.clear
    field.delete_back.should be_false
  end
end

describe Docv::Viewer::Frame do
  frame = Docv::Viewer::Frame.new(10, 20)
  wide = Docv::Viewer::Frame.new(10, 60)

  it "keeps the title row for the name, the page's heading and the close mark" do
    wide.region(0, 0).should eq Docv::Viewer::Frame::Region::Name
    wide.region(0, 14).should eq Docv::Viewer::Frame::Region::Name
    wide.region(0, 15).should eq Docv::Viewer::Frame::Region::Title
    wide.heading_bounds.should eq({17, 56})
    wide.heading_col(10).should eq 25
    wide.heading_col(50).should eq 17
    wide.region(0, 17).should eq Docv::Viewer::Frame::Region::Title
    wide.region(0, 30).should eq Docv::Viewer::Frame::Region::Title
    wide.region(0, 58).should eq Docv::Viewer::Frame::Region::Close
  end

  it "starts the content after the dock" do
    docked = Docv::Viewer::Frame.new(10, 60, 20)
    {docked.inner, docked.left}.should eq({20, 21})
    docked.inner_cols.should eq 39
    docked.region(3, 10).should eq Docv::Viewer::Frame::Region::Border
    docked.region(3, 20).should eq Docv::Viewer::Frame::Region::Content
    docked.region(8, 10).should eq Docv::Viewer::Frame::Region::Border
    docked.region(8, 20).should eq Docv::Viewer::Frame::Region::HorizontalBar
  end

  it "places content between the title line and the scrollbar, padded on both sides" do
    frame.content_rows.should eq 6
    frame.inner_cols.should eq 19
    frame.content_cols.should eq 17
    frame.right.should eq 19
    frame.status_row.should eq 9
    frame.region(0, 5).should eq Docv::Viewer::Frame::Region::Name
    frame.region(0, 18).should eq Docv::Viewer::Frame::Region::Close
    frame.region(1, 5).should eq Docv::Viewer::Frame::Region::Border
    frame.region(2, 0).should eq Docv::Viewer::Frame::Region::Content
    frame.region(2, 18).should eq Docv::Viewer::Frame::Region::Content
    frame.region(2, 19).should eq Docv::Viewer::Frame::Region::VerticalBar
    frame.region(8, 5).should eq Docv::Viewer::Frame::Region::HorizontalBar
    frame.region(8, 19).should eq Docv::Viewer::Frame::Region::Border
    frame.region(9, 5).should eq Docv::Viewer::Frame::Region::Status
  end

  it "sizes thumbs, filling the track when everything fits" do
    Docv::Viewer::Frame.thumb(10, 10, 5, 0, 0).should eq({0, 10})
    Docv::Viewer::Frame.thumb(10, 10, 100, 90, 90).should eq({9, 1})
    Docv::Viewer::Frame.thumb(10, 10, 40, 15, 30).should eq({4, 2})
  end

  it "draws the close mark, the title line and the scrollbars, the vertical one without its track" do
    screen = Docv::Screen.new(10, 20)
    frame.draw(screen, {0, 2}, {0, 18}, 1_u16, 2_u16, 3_u16)
    screen[0, 18].ch.should eq Docv::Viewer::Frame::CLOSE
    screen[0, 18].style.should eq 3_u16
    screen[1, 0].ch.should eq '─'
    screen[1, 19].ch.should eq '─'
    screen[2, 19].ch.should eq '┃'
    screen[2, 19].style.should eq 2_u16
    screen[4, 19].should eq Docv::Cell::BLANK
    screen[8, 0].ch.should eq '━'
    screen[8, 18].ch.should eq '─'
    screen[8, 19].ch.should eq '─'
    screen[2, 0].should eq Docv::Cell::BLANK
  end

  it "draws a rule across the content area" do
    screen = Docv::Screen.new(10, 20)
    frame.rule(screen, 3, 1_u16)
    screen[3, 0].ch.should eq '╶'
    screen[3, 1].ch.should eq '─'
    screen[3, 18].ch.should eq '╴'
    screen[3, 19].should eq Docv::Cell::BLANK
  end
end

describe Docv::Viewer::Help do
  help = Docv::Viewer::Help.new(Docv::Viewer::Bindings.new, Docv::Viewer::FieldBindings.new)
  line = ->(keys : String, text : String, depth : Int32) { Docv::Viewer::Help::Line.new(keys, text, depth) }

  it "groups keys, mouse and configuration under indented headings" do
    help.entries.select(&.heading).map { |entry| {entry.keys, entry.depth} }.should eq [
      {"KEYS", 0}, {"General", 1}, {"Viewer", 1}, {"Search field", 1}, {"Picker", 1}, {"MOUSE", 0}, {"CONFIG", 0},
    ]
    help.entries.find!(&.text.==("top")).should eq line.call("PgUp", "top", 2)
    help.entries.find!(&.text.==("help")).should eq line.call("F1", "help", 2)
    help.entries.find!(&.text.==("previous match or page")).keys.should eq "↑"
    help.entries.find!(&.text.==("to the viewer")).keys.should eq "Esc"
    help.entries.find!(&.keys.==("wheel")).depth.should eq 1
    help.entries.find!(&.keys.==("[picker]")).text.should eq "dock-width, dock-open, min-group, search-threads"
    help.entries.find!(&.keys.==("[colors]")).text.should eq "a style per role"
    Docv::Viewer::ACTION_HELP.values.flat_map(&.keys).sort_by(&.value).should eq Docv::Viewer::Action.values
    Docv::Viewer::FIELD_HELP.keys.should eq Docv::Viewer::FieldAction.values
    Docv::Viewer::TREE_HELP.keys.should eq Docv::Viewer::TreeAction.values
  end

  it "names keys with their modifiers" do
    Docv::Viewer::Help.key_name(Docv::Term::Mods::Shift, ' '.ord).should eq "Shift-Space"
    Docv::Viewer::Help.key_name(Docv::Term::Mods::Ctrl | Docv::Term::Mods::Alt, 'x'.ord).should eq "Ctrl-Alt-x"
    Docv::Viewer::Help.key_name(Docv::Term::Mods::None, Docv::Term::Key::F1 + 4).should eq "F5"
  end

  it "wraps descriptions at the description column" do
    Docv::Viewer::Help.wrap("one two three", 7).should eq ["one two", "three"]
    Docv::Viewer::Help.wrap("unbreakable", 4).should eq ["unbreakable"]
    frame = Docv::Viewer::Frame.new(30, 60)
    lines = help.lines(frame)
    lines.size.should be > help.entries.size
    index = lines.index!(&.text.starts_with?("open the page, or"))
    lines[index].keys.should eq "Enter"
    lines[index + 1].keys.should eq ""
    lines.each do |wrapped|
      next if wrapped.heading || wrapped.keys == "file"
      (help.column + Docv::Unicode.text_width(wrapped.text)).should be <= frame.content_cols
    end
  end

  it "scrolls within the page area" do
    small = Docv::Viewer::Frame.new(12, 80)
    scroller = Docv::Viewer::Help.new(Docv::Viewer::Bindings.new, Docv::Viewer::FieldBindings.new)
    scroller.rows(small).should eq 8
    scroller.scroll(1000, small)
    scroller.top.should eq scroller.lines(small).size - 8
    scroller.max_top(small).should eq scroller.top
    scroller.scroll(-1000, small)
    scroller.top.should eq 0
  end

  it "scrolls sideways when the screen is narrower than its narrowest description" do
    narrow = Docv::Viewer::Frame.new(30, 30)
    scroller = Docv::Viewer::Help.new(Docv::Viewer::Bindings.new, Docv::Viewer::FieldBindings.new)
    scroller.width(narrow).should be > narrow.content_cols
    scroller.scroll_x(1000, narrow)
    scroller.left.should eq scroller.width(narrow) - narrow.content_cols
    screen = Docv::Screen.new(30, 30)
    styles = Docv::Theme.new.styles(Docv::Palette.new(true), Docv::ColorDepth::TrueColor)
    scroller.scroll_x(-1000, narrow)
    scroller.scroll_x(2, narrow)
    scroller.draw(screen, narrow, styles)
    screen[Docv::Viewer::Frame::TOP, 1].ch.should eq 'Y'
    screen[Docv::Viewer::Frame::TOP + 1, 1].ch.should eq 'G'
  end

  it "draws in the page area, after the dock, indented by depth" do
    docked = Docv::Viewer::Frame.new(30, 100, 20)
    screen = Docv::Screen.new(30, 100)
    styles = Docv::Theme.new.styles(Docv::Palette.new(true), Docv::ColorDepth::TrueColor)
    help.draw(screen, docked, styles)
    screen[Docv::Viewer::Frame::TOP, 21].ch.should eq 'K'
    screen[Docv::Viewer::Frame::TOP + 1, 23].ch.should eq 'G'
    screen[Docv::Viewer::Frame::TOP + 2, 25].ch.should eq 'F'
    screen[Docv::Viewer::Frame::TOP + 2, 21 + help.column].ch.should eq 'h'
    screen[Docv::Viewer::Frame::TOP, 20].ch.should eq ' '
  end
end

describe Docv::Viewer::Picker do
  items = [
    Docv::Viewer::Picker::Item.new("printf(1)", "format and print data", 0),
    Docv::Viewer::Picker::Item.new("printf(3)", "formatted output conversion", 1),
    Docv::Viewer::Picker::Item.new("lp(1)", "print files", 2),
    Docv::Viewer::Picker::Item.new("ls(1)", "list directory contents", 3),
  ]

  it "lists every item for an empty query" do
    Docv::Viewer::Picker.new(items).results.should eq [0, 1, 2, 3]
  end

  it "prefers label matches over equal detail matches" do
    picker = Docv::Viewer::Picker.new(items)
    picker.query = "print"
    picker.results.should eq [0, 1, 2]
    picker.marks(0)[0].should eq [0, 1, 2, 3, 4]
    picker.marks(2)[1].should eq [0, 1, 2, 3, 4]
  end

  it "ranks lower groups first" do
    grouped = [
      Docv::Viewer::Picker::Item.new("printf(1)", "", 0, group: 1),
      Docv::Viewer::Picker::Item.new("prf.md", "", 1, group: 0),
    ]
    picker = Docv::Viewer::Picker.new(grouped)
    picker.query = "printf"
    picker.results.should eq [0]
    picker.query = "prf"
    picker.results.should eq [1, 0]
  end

  it "requires every term" do
    picker = Docv::Viewer::Picker.new(items)
    picker.query = "printf 3"
    picker.results.should eq [1]
  end

  it "ignores details unless they are searched" do
    picker = Docv::Viewer::Picker.new(items, search_details: false)
    picker.query = "print"
    picker.results.should eq [0, 1]
  end

  it "moves and scrolls the selection" do
    picker = Docv::Viewer::Picker.new(items)
    picker.move(3, 2)
    picker.selected.should eq 3
    picker.top.should eq 2
    picker.scroll_to(0, 2)
    picker.selected.should eq 1
    picker.select_row(0).should be_true
    picker.current.should eq items[0]
    picker.select_row(5).should be_false
  end

  it "scrolls sideways within the widest row" do
    picker = Docv::Viewer::Picker.new(items)
    picker.width(false).should eq 9
    picker.width(true).should eq 9 + 2 + "formatted output conversion".size
    picker.scroll_x(100, 6, false)
    picker.left.should eq 5
    picker.scroll_x(-100, 12, false)
    picker.left.should eq 0
  end

  it "draws hit counts at the right edge" do
    picker = Docv::Viewer::Picker.new(items)
    picker.hits = [0, 7, 0, 12]
    screen = Docv::Screen.new(4, 30)
    styles = Docv::Theme.new.styles(Docv::Palette.new(true), Docv::ColorDepth::TrueColor)
    picker.draw(screen, 0, 0, 4, 30, styles, details: false)
    screen[1, 28].ch.should eq '7'
    screen[3, 27].ch.should eq '1'
    screen[0, 28].ch.should eq ' '
    picker.hits = nil
    picker.hits.should be_nil
  end

  it "keeps a moved selection when the items change" do
    picker = Docv::Viewer::Picker.new(items)
    picker.move(2, 4)
    picker.items = items.reverse
    picker.current.should eq items[2]
  end
end

describe Docv::Viewer::Dock do
  frame = Docv::Viewer::Frame.new(24, 100)

  it "fits its width to the screen and moves the page only when open" do
    dock = Docv::Viewer::Dock.new(30)
    dock.offset(100).should eq 0
    dock.open = true
    dock.offset(100).should eq 30
    dock.span(40).should eq 20
    dock.span(30).should eq Docv::Viewer::Dock::MIN_WIDTH
    dock.width = 3
    dock.width.should eq Docv::Viewer::Dock::MIN_WIDTH
  end

  it "tells the field, the tree and the divider apart" do
    dock = Docv::Viewer::Dock.new(30, open: true)
    top = Docv::Viewer::Frame::TOP
    dock.part(frame, top, 5).should eq Docv::Viewer::Dock::Part::Field
    dock.part(frame, top + 1, 5).should eq Docv::Viewer::Dock::Part::Tree
    dock.part(frame, top + 1, 29).should eq Docv::Viewer::Dock::Part::Divider
    dock.part(frame, top + 1, 30).should be_nil
    dock.part(frame, 0, 5).should be_nil
    dock.tree_row(frame, top + 1).should eq 0
    dock.tree_row(frame, top).should be_nil
    dock.tree_cols(frame).should eq 29
  end

  it "shows the group's tree, or every page during a manual search" do
    dock = Docv::Viewer::Dock.new
    group = Docv::Viewer::Picker.new([Docv::Viewer::Picker::Item.new("ls(1)", key: "ls")])
    pages = Docv::Viewer::Picker.new([Docv::Viewer::Picker::Item.new("cat(1)", key: "cat")])
    dock.group = group
    dock.pages = pages
    dock.tree.should be group
    dock.field.insert("/c")
    dock.tree.should be pages
  end

  it "reads a manual search from a leading slash" do
    dock = Docv::Viewer::Dock.new
    dock.field.insert("/printf")
    dock.manual?.should be_true
    dock.query.should eq "printf"
    dock.field.clear
    dock.field.insert("sort")
    dock.manual?.should be_false
    dock.query.should eq "sort"
  end

  it "draws the field, the divider with its junctions and the tree" do
    dock = Docv::Viewer::Dock.new(30, open: true)
    dock.group = Docv::Viewer::Picker.new([Docv::Viewer::Picker::Item.new("ls(1)", key: "ls")], nested: true)
    screen = Docv::Screen.new(24, 100)
    styles = Docv::Theme.new.styles(Docv::Palette.new(true), Docv::ColorDepth::TrueColor)
    dock.draw(screen, frame, styles, false, nil, false)
    top = Docv::Viewer::Frame::TOP
    screen[top, 0].ch.should eq ' '
    screen[top, 1].ch.should eq Docv::Viewer::Dock::FIELD_LEFT
    screen[top, 3].ch.should eq 'f'
    screen[top, 27].ch.should eq Docv::Viewer::Dock::FIELD_RIGHT
    screen[top - 1, 29].ch.should eq '┬'
    screen[frame.bottom, 29].ch.should eq '┴'
    screen[top + 1, 29].ch.should eq '│'
    screen[top + 1, 3].ch.should eq 'l'
  end
end

describe Docv::Viewer::Picker::Outline do
  names = %w(abrt abrt-cli abrt-dump-oops abrt-dump-xorg abrt-dump-journal-core git git-add git-commit
    systemd.unit systemd.service sd_bus_open ls lsblk)

  pages = names.map_with_index do |name, index|
    Docv::Viewer::Picker::Item.new("#{name}(1)", "", index, key: name)
  end

  labels = ->(picker : Docv::Viewer::Picker) do
    outline = picker.outline.not_nil!
    picker.rows.map do |id|
      node = outline.nodes[id]
      text = node.group? ? "#{node.prefix}/" : picker.items[node.item].label
      "#{"  " * node.depth}#{text}"
    end
  end

  it "splits keys into tokens at separator runs" do
    tokens = [] of String
    Docv::Viewer::Picker::Outline.each_token("File::Spec-x") { |stop, _| tokens << "File::Spec-x"[0, stop] }
    tokens.should eq ["File", "File::Spec", "File::Spec-x"]
  end

  it "folds names sharing a prefix of at least MIN_GROUP items" do
    picker = Docv::Viewer::Picker.new(pages, nested: true)
    labels.call(picker).should eq ["abrt/", "git/", "ls(1)", "lsblk(1)", "sd_bus_open(1)", "systemd/"]
  end

  it "unfolds and folds a group, and steps into and out of it" do
    picker = Docv::Viewer::Picker.new(pages, nested: true, min_group: 3)
    picker.group?.should be_true
    picker.expand(20)
    labels.call(picker).first(4).should eq ["abrt/", "  abrt(1)", "  abrt-cli(1)", "  abrt-dump/"]
    picker.expand(20)
    picker.current.should eq pages[0]
    picker.move(2, 20)
    picker.expand(20)
    labels.call(picker)[4..6].should eq ["    abrt-dump-journal-core(1)", "    abrt-dump-oops(1)",
                                         "    abrt-dump-xorg(1)"]
    picker.move(1, 20)
    picker.collapse(20)
    picker.selected.should eq 3
    picker.collapse(20)
    picker.collapse(20)
    picker.collapse(20)
    picker.selected.should eq 0
    picker.rows.size.should eq 7
    picker.toggle(20)
    picker.rows.size.should eq 10
  end

  it "ranks groups by their best match and opens them while querying" do
    picker = Docv::Viewer::Picker.new(pages, nested: true)
    picker.query = "oops"
    labels.call(picker).should eq ["abrt/", "  abrt-dump/", "    abrt-dump-oops(1)"]
    picker.results.size.should eq 1
    picker.toggle(20)
    labels.call(picker).should eq ["abrt/"]
    picker.query = "git"
    labels.call(picker).first.should eq "git/"
  end

  it "puts items before subgroups inside a group, and mixes them at the top" do
    names = %w(abrt-action-x abrt-action-y abrt-action-z abrt-zz abrt-b zoo)
    items = names.map_with_index { |name, index| Docv::Viewer::Picker::Item.new(name, "", index, key: name) }
    outline = Docv::Viewer::Picker::Outline.new(items)
    outline.roots.map { |id| outline.nodes[id].text }.should eq ["abrt", "zoo"]
    abrt = outline.nodes[outline.roots[0]]
    abrt.children.map { |id| outline.nodes[id].text }.should eq ["b", "zz", "action"]
  end

  it "keeps groups apart by item group" do
    grouped = %w(a-x a-y a-z a-w).map_with_index do |name, index|
      Docv::Viewer::Picker::Item.new(name, "", index, group: index % 2, key: name)
    end
    picker = Docv::Viewer::Picker.new(grouped, nested: true, min_group: 3)
    labels.call(picker).should eq ["a-x", "a-z", "a-w", "a-y"]
  end

  it "names rows relative to their group" do
    outline = Docv::Viewer::Picker::Outline.new(pages)
    abrt = outline.nodes[outline.roots[0]]
    abrt.children.map { |id| outline.nodes[id].text }.should eq ["abrt(1)", "cli(1)", "dump"]
    dump = outline.nodes[abrt.children[2]]
    {dump.prefix, dump.skip}.should eq({"abrt-dump", 5})
    dump.children.map { |id| outline.nodes[id].text }.should eq ["journal-core(1)", "oops(1)", "xorg(1)"]
    Docv::Viewer::Picker::Outline.relative("File::Spec::Unix(3pm)", "File::Spec").should eq({"Unix(3pm)", 12})
    Docv::Viewer::Picker::Outline.relative("ls(1)", "lsblk").should eq({"ls(1)", 0})
    Docv::Viewer::Picker::Outline.relative("abrt-dump(1)", "abrt-dump", "abrt").should eq({"dump(1)", 5})
    Docv::Viewer::Picker::Outline.relative("abrt(1)", "abrt", "").should eq({"abrt(1)", 0})
  end

  it "lists the items under a group" do
    outline = Docv::Viewer::Picker::Outline.new(pages)
    outline.items(outline.roots[0]).should eq [0, 1, 4, 2, 3]
  end

  it "reveals an item by target, unfolding the groups around it" do
    picker = Docv::Viewer::Picker.new(pages, nested: true)
    picker.reveal(3, 20).should be_true
    picker.current.should eq pages[3]
    labels.call(picker)[picker.selected].should eq "    abrt-dump-xorg(1)"
    picker.reveal(99, 20).should be_false
  end

  it "unfolds groups level by level while they fit" do
    picker = Docv::Viewer::Picker.new(pages, nested: true, min_group: 3)
    picker.unfold(9)
    picker.rows.size.should eq 7
    picker.unfold(10)
    labels.call(picker).first(4).should eq ["abrt/", "  abrt(1)", "  abrt-cli(1)", "  abrt-dump/"]
    picker.rows.size.should eq 10
    roomy = Docv::Viewer::Picker.new(pages, nested: true, min_group: 3)
    roomy.unfold(100)
    roomy.rows.size.should eq 16
    picker.query = "oops"
    picker.unfold(100)
    picker.rows.size.should eq 3
  end

  it "draws tree lines and group marks" do
    picker = Docv::Viewer::Picker.new(pages, nested: true)
    picker.unfold(100)
    screen = Docv::Screen.new(20, 40)
    styles = Docv::Theme.new.styles(Docv::Palette.new(true), Docv::ColorDepth::TrueColor)
    picker.draw(screen, 0, 0, 20, 40, styles, details: false)
    text = (0...7).map { |row| (1...20).join { |col| screen[row, col].ch }.rstrip }
    text.should eq ["○ abrt", "├╴abrt(1)", "├╴cli(1)", "╰╴○ dump", "  ├╴journal-core(1)", "  ├╴oops(1)", "  ╰╴xorg(1)"]
    names = %w(a-b-1 a-b-q-x a-b-q-y a-b-q-z a-c-1 a-c-2 a-c-3)
    items = names.map_with_index { |name, index| Docv::Viewer::Picker::Item.new(name, "", index, key: name) }
    nested = Docv::Viewer::Picker.new(items, nested: true)
    nested.unfold(100)
    screen = Docv::Screen.new(20, 40)
    nested.draw(screen, 0, 0, 20, 40, styles, details: false)
    text = (0...11).map { |row| (1...20).join { |col| screen[row, col].ch }.rstrip }
    text.should eq ["○ a", "├╴○ b", "│ ├╴1", "│ ╰╴○ q", "│ ╎ ├╴x", "│ ╎ ├╴y", "│ ╎ ╰╴z", "╰╴○ c", "  ├╴1", "  ├╴2", "  ╰╴3"]
  end

  it "counts the items with hits in each group" do
    picker = Docv::Viewer::Picker.new(pages, nested: true)
    counts = Array(Int32).new(pages.size, 0)
    counts[2] = 4
    counts[3] = 1
    picker.hits = counts
    screen = Docv::Screen.new(10, 40)
    styles = Docv::Theme.new.styles(Docv::Palette.new(true), Docv::ColorDepth::TrueColor)
    picker.draw(screen, 0, 0, 10, 40, styles, details: false)
    screen[0, 38].ch.should eq '2'
    screen[1, 38].ch.should eq ' '
  end

  it "keeps open groups and the selection when the items are redescribed" do
    picker = Docv::Viewer::Picker.new(pages, nested: true)
    picker.move(1, 20)
    picker.toggle(20)
    picker.items = pages.map(&.copy_with(detail: "described"))
    picker.selected.should eq 1
    labels.call(picker)[2].should eq "  git(1)"
  end
end

describe Docv::Term::Input do
  it "reports pointer motion without a button" do
    input = Docv::Term::Input.new
    events = [] of Docv::Term::Derived
    input.feed("\e[<35;12;4M".to_slice) { |event| events << event }
    move = events.compact_map(&.as?(Docv::Term::PointerMove)).first
    {move.col, move.row}.should eq({11, 3})
  end
end
