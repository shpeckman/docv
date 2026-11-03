# spec/screen_spec.cr
require "./spec_helper"

describe Docv::Screen do
  it "draws everything first, then only changed rows" do
    screen = Docv::Screen.new(3, 5)
    io = IO::Memory.new
    screen.write(0, 0, "hello")
    screen.render(io).should be_true
    io.to_s.should contain("\e[1;1H")
    io.to_s.should contain("\e[3;1H")

    io = IO::Memory.new
    screen.render(io).should be_false

    screen.write(1, 0, "x")
    screen.render(io).should be_true
    io.to_s.should contain("\e[2;1H")
    io.to_s.should_not contain("\e[1;1H")
  end

  it "emits SGR only on style changes" do
    screen = Docv::Screen.new(1, 4)
    bold = Docv::Styles.id(Docv::Style.new(Docv::Attr::Bold))
    screen.write(0, 0, "ab", bold)
    io = IO::Memory.new
    screen.render(io)
    io.to_s.scan("\e[0;1m").size.should eq 1
  end

  it "reduces colors to the depth" do
    orange = Docv::Styles.id(Docv::Style.new(fg: Docv::Color.rgb(255, 135, 0)))
    screen = Docv::Screen.new(1, 2)
    screen.write(0, 0, "x", orange)
    io = IO::Memory.new
    screen.render(io)
    io.to_s.should contain("\e[0;38;2;255;135;0m")
    screen.colors(Docv::Palette.new, Docv::ColorDepth::Palette)
    io = IO::Memory.new
    screen.render(io)
    io.to_s.should contain("\e[0;38;5;208m")
    screen.colors(Docv::Palette.new, Docv::ColorDepth::None)
    io = IO::Memory.new
    screen.render(io)
    io.to_s.should_not contain("38;")
  end

  it "blanks wide characters that do not fit" do
    screen = Docv::Screen.new(1, 3)
    cells = [Docv::Cell.new('a'), Docv::Cell.new('日', width: 2_u8), Docv::Cell.continuation(0_u16)]
    screen.blit(0, 0, cells, 1, 3)
    screen[0, 0].width.should eq 2
    screen[0, 2].should eq Docv::Cell::BLANK
  end

  it "writes hyperlinks as OSC 8 and redraws rows whose links change" do
    screen = Docv::Screen.new(1, 6)
    screen.write(0, 0, "a link")
    screen.link(0, 2, 4, "https://e.org/")
    io = IO::Memory.new
    screen.render(io)
    io.to_s.should contain("a \e]8;;https://e.org/\e\\link\e]8;;\e\\")
    screen.clear
    screen.write(0, 0, "a link")
    screen.render(io = IO::Memory.new).should be_true
    io.to_s.should_not contain("\e]8;;h")
    screen.link(0, 0, 1, "bad\e]uri")
    screen.render(io = IO::Memory.new).should be_false
  end
end
