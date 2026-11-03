# spec/decoder_spec.cr
require "./spec_helper"

private def decode(input : String, flush : Bool = false) : Array(Docv::Term::Event)
  decoder = Docv::Term::Decoder.new
  events = [] of Docv::Term::Event
  decoder.feed(input.to_slice) { |event| events << event }
  decoder.flush { |event| events << event } if flush
  events
end

describe Docv::Term::Decoder do
  it "decodes OSC 21 color reports with either terminator" do
    report = decode("\e]21;foreground=rgb:ff/00/00;cursor=;3=#808000\e\\").first.as(Docv::Term::ColorsReport)
    report.colors.should eq({"foreground" => "rgb:ff/00/00", "cursor" => "", "3" => "#808000"})
    decode("\e]21;background=rgb:00/00/00\a").first.as(Docv::Term::ColorsReport).colors["background"].should eq "rgb:00/00/00"
  end

  it "ignores other OSC strings and waits for a split report" do
    decode("\e]11;rgb:0/0/0\e\\j").map(&.as(Docv::Term::KeyEvent).key).should eq ['j'.ord]
    decoder = Docv::Term::Decoder.new
    events = [] of Docv::Term::Event
    decoder.feed("\e]21;foreground=rgb:ff".to_slice) { |event| events << event }
    events.should be_empty
    decoder.feed("/00/00\e\\".to_slice) { |event| events << event }
    events.first.as(Docv::Term::ColorsReport).colors["foreground"].should eq "rgb:ff/00/00"
  end

  it "reads an unterminated ESC ] as Alt-]" do
    key = decode("\e]", flush: true).first.as(Docv::Term::KeyEvent)
    key.key.should eq ']'.ord
    key.mods.alt?.should be_true
  end

  it "decodes kitty key reports with alternates, modifiers, events and text" do
    event = decode("\e[97:65;2:1;65u").first.as(Docv::Term::KeyEvent)
    event.key.should eq 'a'.ord
    event.shifted.should eq 'A'.ord
    event.mods.shift?.should be_true
    event.action.press?.should be_true
    event.text.should eq "A"
  end

  it "decodes the base-layout key and release events" do
    event = decode("\e[1089::99;5:3u").first.as(Docv::Term::KeyEvent)
    event.key.should eq 1089
    event.base.should eq 'c'.ord
    event.mods.ctrl?.should be_true
    event.action.release?.should be_true
  end

  it "decodes legacy letter and tilde keys" do
    keys = decode("\e[A\e[1;5B\e[5~\e[3;2~\eOP").map(&.as(Docv::Term::KeyEvent))
    keys.map(&.key).should eq [Docv::Term::Key::UP, Docv::Term::Key::DOWN,
                               Docv::Term::Key::PAGE_UP, Docv::Term::Key::DELETE, Docv::Term::Key::F1]
    keys[1].mods.ctrl?.should be_true
    keys[3].mods.shift?.should be_true
  end

  it "decodes plain text, control bytes and alt prefixes" do
    keys = decode("jG\x03\r\ex").map(&.as(Docv::Term::KeyEvent))
    keys[0].text.should eq "j"
    keys[1].key.should eq 'g'.ord
    keys[1].shifted.should eq 'G'.ord
    keys[2].key.should eq 'c'.ord
    keys[2].mods.ctrl?.should be_true
    keys[3].key.should eq Docv::Term::Key::ENTER
    keys[4].mods.alt?.should be_true
  end

  it "waits for incomplete sequences and resolves a lone ESC on flush" do
    decoder = Docv::Term::Decoder.new
    events = [] of Docv::Term::Event
    decoder.feed("\e[1;5".to_slice) { |event| events << event }
    events.should be_empty
    decoder.pending?.should be_true
    decoder.feed("A".to_slice) { |event| events << event }
    events.size.should eq 1
    decode("\e", flush: true).first.as(Docv::Term::KeyEvent).key.should eq Docv::Term::Key::ESCAPE
  end

  it "decodes SGR mouse reports by priority" do
    events = decode("\e[<0;100;50M\e[<32;110;50M\e[<0;110;50m\e[<35;5;5M\e[<65;1;1M\e[<256;0;0M\e[<20;1;1M\e[<128;1;1M")
    mice = events.map(&.as(Docv::Term::MouseEvent))
    mice.map(&.action.to_s).should eq %w(Press Drag Release Hover Scroll Leave Press Press)
    mice[0].x.should eq 100
    mice[4].button.wheel_down?.should be_true
    mice[6].mods.ctrl?.should be_true
    mice[6].mods.shift?.should be_true
    mice[7].button.aux8?.should be_true
  end

  it "decodes terminal notifications" do
    events = decode("\e[48;30;100;600;1000t\e[I\e[O\e[?997;2n\e[?999;2n\e[?1016;1$y\e[6;20;10t\e[?31u")
    events[0].should eq Docv::Term::ResizeEvent.new(30, 100, 600, 1000)
    events[1].should eq Docv::Term::FocusEvent.new(true)
    events[2].should eq Docv::Term::FocusEvent.new(false)
    events[3].should eq Docv::Term::ColorSchemeEvent.new(false)
    events[4].should eq Docv::Term::VisibilityEvent.new(false)
    events[5].should eq Docv::Term::ModeReport.new(1016, 1)
    events[6].should eq Docv::Term::CellSizeReport.new(20, 10)
    events[7].should eq Docv::Term::KeyboardFlagsReport.new(31)
  end
end

describe Docv::Term::Tty do
  it "reads the color depth from the environment" do
    Docv::Term::Tty.color_depth("1", "truecolor", "xterm-kitty").should eq Docv::ColorDepth::None
    Docv::Term::Tty.color_depth("", "TrueColor", "xterm").should eq Docv::ColorDepth::TrueColor
    Docv::Term::Tty.color_depth(nil, "24bit", nil).should eq Docv::ColorDepth::TrueColor
    Docv::Term::Tty.color_depth(nil, nil, "xterm-256color").should eq Docv::ColorDepth::Palette
    Docv::Term::Tty.color_depth(nil, nil, "xterm-direct").should eq Docv::ColorDepth::TrueColor
    Docv::Term::Tty.color_depth(nil, nil, "vt100").should eq Docv::ColorDepth::Ansi
  end

  it "copies to the clipboard with OSC 52, clearing it first" do
    reader, writer = IO.pipe
    Docv::Term::Tty.new(reader, writer).copy("hé")
    writer.close
    reader.gets_to_end.should eq "\e]52;c;!\e\\\e]52;c;aMOp\e\\"
  end

  it "shapes the pointer with OSC 22" do
    reader, writer = IO.pipe
    tty = Docv::Term::Tty.new(reader, writer)
    tty.pointer("ew-resize")
    tty.pointer("")
    writer.close
    reader.gets_to_end.should eq "\e]22;ew-resize\e\\\e]22;\e\\"
  end

  it "queries the theme colors with OSC 21" do
    Docv::Term::Sequences::COLORS_QUERY.should start_with("\e]21;foreground=?;background=?;0=?;")
    Docv::Term::Sequences::COLORS_QUERY.should end_with(";15=?\e\\")
  end
end
