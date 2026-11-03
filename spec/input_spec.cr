# spec/input_spec.cr
require "./spec_helper"

private def derive(input : Docv::Term::Input, bytes : String) : Array(Docv::Term::Derived)
  events = [] of Docv::Term::Derived
  input.feed(bytes.to_slice) { |event| events << event }
  events
end

private def pixel_input : Docv::Term::Input
  input = Docv::Term::Input.new
  input.pixels = true
  input.cell_width = 10
  input.cell_height = 20
  input
end

describe Docv::Term::Input do
  it "separates text input from key commands" do
    events = derive(Docv::Term::Input.new, "\e[106;1;106u\e[106;5u\e[13u")
    events[0].should be_a(Docv::Term::TextInput)
    events[1].should be_a(Docv::Term::KeyCommand)
    events[2].should be_a(Docv::Term::KeyCommand)
  end

  it "tracks the pressed-set and swallows releases and modifier keys" do
    input = Docv::Term::Input.new
    derive(input, "\e[57441u\e[97;2u").size.should eq 1
    input.held.keys.sort.should eq [97, 57441]
    derive(input, "\e[97;1:2u").size.should eq 1
    input.held[97].repeat_count.should eq 1
    derive(input, "\e[97;1:3u\e[57441;1:3u").should be_empty
    input.held.should be_empty
  end

  it "converts pixel coordinates to cells and detects clicks and double clicks" do
    input = pixel_input
    events = derive(input, "\e[<0;55;45M\e[<0;56;45m\e[<0;55;45M\e[<0;55;45m")
    clicks = events.select(Docv::Term::Click)
    clicks.map(&.count).should eq [1, 2]
    clicks.first.col.should eq 5
    clicks.first.row.should eq 2
  end

  it "brackets drags into start, move and end" do
    events = derive(pixel_input, "\e[<0;5;5M\e[<32;30;5M\e[<32;50;25M\e[<0;50;25m")
    drags = events.select(Docv::Term::Drag)
    drags.map(&.phase.to_s).should eq %w(Start Move End)
    drags.first.start_col.should eq 0
    drags.last.col.should eq 5
    drags.last.row.should eq 1
    events.select(Docv::Term::Click).should be_empty
  end

  it "accumulates scroll reports into one gesture" do
    events = derive(pixel_input, "\e[<65;5;5M\e[<65;5;5M\e[<65;5;5M\e[<66;5;5M")
    scrolls = events.select(Docv::Term::Scroll)
    scrolls.size.should eq 1
    scrolls.first.dy.should eq 3
    scrolls.first.dx.should eq -1
  end

  it "infers enter after leave and reports moves" do
    input = pixel_input
    events = derive(input, "\e[<35;5;5M\e[<256;0;0M\e[<35;5;5M")
    events.map(&.class.name.split("::").last).should eq %w(PointerEnter PointerMove PointerLeave PointerEnter PointerMove)
  end

  it "switches to pixel coordinates when mode 1016 is reported set" do
    input = Docv::Term::Input.new
    derive(input, "\e[?1016;1$y")
    input.pixels?.should be_true
  end
end
