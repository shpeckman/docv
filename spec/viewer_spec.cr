# spec/viewer_spec.cr
require "./spec_helper"

describe Docv::Viewer::Bindings do
  bindings = Docv::Viewer::Bindings.new

  it "matches plain keys" do
    bindings.lookup(Docv::Term::KeyEvent.new('j'.ord)).should eq Docv::Viewer::Action::LineDown
  end

  it "matches the physical key through the base layout" do
    event = Docv::Term::KeyEvent.new(0x43E, base: 'j'.ord)
    bindings.lookup(event).should eq Docv::Viewer::Action::LineDown
  end

  it "matches shifted symbols without their shift" do
    event = Docv::Term::KeyEvent.new('4'.ord, Docv::Term::Mods::Shift, shifted: '$'.ord)
    bindings.lookup(event).should eq Docv::Viewer::Action::LineEnd
    event = Docv::Term::KeyEvent.new('g'.ord, Docv::Term::Mods::Shift, shifted: 'G'.ord)
    bindings.lookup(event).should eq Docv::Viewer::Action::Bottom
  end

  it "ignores lock modifiers" do
    event = Docv::Term::KeyEvent.new('q'.ord, Docv::Term::Mods::NumLock)
    bindings.lookup(event).should eq Docv::Viewer::Action::Quit
  end

  it "focuses the search bar on f and t, with / typed on / and o" do
    bindings.lookup(Docv::Term::KeyEvent.new('f'.ord)).should eq Docv::Viewer::Action::Find
    bindings.lookup(Docv::Term::KeyEvent.new('t'.ord)).should eq Docv::Viewer::Action::Find
    bindings.lookup(Docv::Term::KeyEvent.new('/'.ord)).should eq Docv::Viewer::Action::OpenPage
    bindings.lookup(Docv::Term::KeyEvent.new('o'.ord)).should eq Docv::Viewer::Action::OpenPage
  end
end

describe Docv::Viewer::FieldBindings do
  bindings = Docv::Viewer::FieldBindings.new

  it "maps editing and list keys" do
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::ENTER)).should eq Docv::Viewer::FieldAction::Accept
    bindings.lookup(Docv::Term::KeyEvent.new('n'.ord, Docv::Term::Mods::Ctrl)).should eq Docv::Viewer::FieldAction::Next
    bindings.lookup(Docv::Term::KeyEvent.new(Docv::Term::Key::UP)).should eq Docv::Viewer::FieldAction::Previous
    bindings.lookup(Docv::Term::KeyEvent.new('j'.ord)).should be_nil
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

  it "places the search bar between the title and the close mark" do
    wide.bar_start.should eq 18
    wide.bar_end.should eq 56
    wide.bar?.should be_true
    wide.region(0, 17).should eq Docv::Viewer::Frame::Region::Title
    wide.region(0, 18).should eq Docv::Viewer::Frame::Region::Bar
    wide.region(0, 56).should eq Docv::Viewer::Frame::Region::Bar
    wide.region(0, 58).should eq Docv::Viewer::Frame::Region::Close
    frame.bar?.should be_false
    screen = Docv::Screen.new(10, 60)
    field = Docv::Styles.id(Docv::Style.new(bg: Docv::Color.palette(4)))
    wide.bar(screen, field).should eq({20, 55})
    screen[0, 18].ch.should eq Docv::Viewer::Frame::BAR_LEFT
    Docv::Styles[screen[0, 18].style].fg.should eq Docv::Color.palette(4)
    screen[0, 56].ch.should eq Docv::Viewer::Frame::BAR_RIGHT
    screen[0, 30].style.should eq field
  end

  it "places content between the title line and the scrollbar, padded on both sides" do
    frame.content_rows.should eq 6
    frame.inner_cols.should eq 19
    frame.content_cols.should eq 17
    frame.right.should eq 19
    frame.status_row.should eq 9
    frame.region(0, 5).should eq Docv::Viewer::Frame::Region::Title
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

  it "draws a titled box" do
    screen = Docv::Screen.new(10, 20)
    frame.box(screen, 2, 2, 4, 12, "Help", 1_u16, 2_u16, 3_u16)
    screen[2, 2].ch.should eq '╭'
    screen[2, 5].ch.should eq 'H'
    screen[2, 5].style.should eq 3_u16
    screen[3, 4].style.should eq 2_u16
    screen[5, 13].ch.should eq '╯'
  end
end

describe Docv::Viewer::Help do
  help = Docv::Viewer::Help.new(Docv::Viewer::Bindings.new, Docv::Viewer::FieldBindings.new)

  it "lists every bound action with its keys, the search bar keys and the mouse" do
    help.lines.find! { |line| line.text == "line down" }.keys.should eq "j ↓ Ctrl-n Ctrl-e"
    help.lines.find! { |line| line.text == "this help" }.keys.should eq "h"
    help.lines.find! { |line| line.text == "previous match or page" }.keys.should eq "↑ Ctrl-p Shift-Tab"
    help.lines.select(&.heading).map(&.keys).should eq ["Keys", "Search bar", "Mouse"]
    Docv::Viewer::ACTION_HELP.keys.should eq Docv::Viewer::Action.values
    Docv::Viewer::FIELD_HELP.keys.should eq Docv::Viewer::FieldAction.values
  end

  it "names keys with their modifiers" do
    Docv::Viewer::Help.key_name(Docv::Term::Mods::Shift, ' '.ord).should eq "Shift-Space"
    Docv::Viewer::Help.key_name(Docv::Term::Mods::Ctrl | Docv::Term::Mods::Alt, 'x'.ord).should eq "Ctrl-Alt-x"
    Docv::Viewer::Help.key_name(Docv::Term::Mods::None, Docv::Term::Key::F1 + 4).should eq "F5"
  end

  it "scrolls within the box" do
    small = Docv::Viewer::Frame.new(12, 80)
    scroller = Docv::Viewer::Help.new(Docv::Viewer::Bindings.new, Docv::Viewer::FieldBindings.new)
    scroller.rows(small).should eq 6
    scroller.scroll(1000, small)
    scroller.top.should eq scroller.lines.size - 6
    scroller.scroll(-1000, small)
    scroller.top.should eq 0
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
    picker.select_row(0).should eq items[0]
    picker.select_row(5).should be_nil
  end

  it "keeps a moved selection when the items change" do
    picker = Docv::Viewer::Picker.new(items)
    picker.move(2, 4)
    picker.items = items.reverse
    picker.current.should eq items[2]
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
