# spec/color_spec.cr
require "./spec_helper"

private def sgr(style : Docv::Style) : String
  String.build { |io| style.to_sgr(io) }
end

describe Docv::Color do
  it "writes ANSI, bright, palette and RGB colors" do
    sgr(Docv::Style.new(fg: Docv::Color.palette(1))).should eq "\e[0;31m"
    sgr(Docv::Style.new(fg: Docv::Color.palette(12), bg: Docv::Color.palette(3))).should eq "\e[0;94;43m"
    sgr(Docv::Style.new(fg: Docv::Color.palette(208))).should eq "\e[0;38;5;208m"
    sgr(Docv::Style.new(Docv::Attr::Bold, bg: Docv::Color.rgb(1, 2, 3))).should eq "\e[0;1;48;2;1;2;3m"
    sgr(Docv::Style.new).should eq "\e[0m"
  end

  it "merges styles: attributes combined, colors replaced where given" do
    base = Docv::Style.new(Docv::Attr::Bold, Docv::Color.palette(6))
    over = Docv::Style.new(Docv::Attr::Underline, bg: Docv::Color.palette(3))
    base.merge(over).should eq Docv::Style.new(Docv::Attr::Bold | Docv::Attr::Underline, Docv::Color.palette(6), Docv::Color.palette(3))
  end

  it "keeps roff colors defined as RGB" do
    Docv::Colors.define("orange", "rgb", "#ff8800")
    Docv::Colors["orange"]?.should eq Docv::Color.rgb(255, 136, 0)
    Docv::Colors["red"]?.should eq Docv::Color.palette(1)
  end
end

describe Docv::Palette do
  it "parses OSC 21 color values" do
    Docv::Palette.parse("rgb:ff/80/00").should eq Docv::Palette::RGB.new(255, 128, 0)
    Docv::Palette.parse("rgb:ffff/0000/8080").should eq Docv::Palette::RGB.new(255, 0, 128)
    Docv::Palette.parse("rgb:f/0/8").should eq Docv::Palette::RGB.new(255, 0, 136)
    Docv::Palette.parse("#3a7").should eq Docv::Palette::RGB.new(0x30, 0xa0, 0x70)
    Docv::Palette.parse("#ff8800@0.5").should eq Docv::Palette::RGB.new(255, 136, 0)
    Docv::Palette.parse("rgbi:1/0.5/0").should eq Docv::Palette::RGB.new(255, 128, 0)
    Docv::Palette.parse("").should be_nil
    Docv::Palette.parse("rgb:zz/00/00").should be_nil
  end

  it "takes reported colors and tells dark from light" do
    palette = Docv::Palette.new(dark: true)
    palette.dark?.should be_true
    palette.reported?.should be_false
    palette.set("background", "rgb:ff/ff/ff").should be_true
    palette.set("4", "rgb:00/00/80").should be_true
    palette.set("cursor", "").should be_false
    palette.reported?.should be_true
    palette.dark?.should be_false
    palette.rgb(Docv::Color.palette(4), true).should eq Docv::Palette::RGB.new(0, 0, 128)
  end

  it "ramps toward the foreground or the background" do
    palette = Docv::Palette.new(dark: true)
    palette.set("foreground", "rgb:c8/c8/c8")
    palette.set("background", "rgb:00/00/00")
    palette.ramp(palette.background, 10).should eq Docv::Palette::RGB.new(20, 20, 20)
    palette.ramp(palette.foreground, -50).should eq Docv::Palette::RGB.new(100, 100, 100)
  end

  it "reduces colors to the depth" do
    palette = Docv::Palette.new
    orange = Docv::Color.rgb(255, 135, 0)
    palette.reduce(orange, Docv::ColorDepth::TrueColor).should eq orange
    palette.reduce(orange, Docv::ColorDepth::Palette).should eq Docv::Color.palette(208)
    palette.reduce(Docv::Color.palette(196), Docv::ColorDepth::Ansi).should eq Docv::Color.palette(9)
    palette.reduce(Docv::Color.palette(3), Docv::ColorDepth::Ansi).should eq Docv::Color.palette(3)
    palette.reduce(orange, Docv::ColorDepth::None).should eq Docv::Color::DEFAULT
  end
end

describe Docv::Theme do
  it "parses specs" do
    spec = Docv::Theme.parse("bold underline black on yellow")
    spec.attr.should eq Docv::Attr::Bold | Docv::Attr::Underline
    spec.fg.color.should eq Docv::Color.palette(0)
    spec.bg.color.should eq Docv::Color.palette(3)
    Docv::Theme.parse("bright-blue").fg.color.should eq Docv::Color.palette(12)
    Docv::Theme.parse("208").fg.color.should eq Docv::Color.palette(208)
    Docv::Theme.parse("#ff8800").fg.color.should eq Docv::Color.rgb(255, 136, 0)
    ramped = Docv::Theme.parse("on background+12").bg
    ramped.base.background?.should be_true
    ramped.ramp.should eq 12
    Docv::Theme.parse("foreground-40").fg.ramp.should eq -40
    Docv::Theme.parse("").should eq Docv::Theme::Spec.new
  end

  it "rejects unknown words and misplaced colors" do
    expect_raises(Docv::Theme::Error, /unknown/) { Docv::Theme.parse("blinking") }
    expect_raises(Docv::Theme::Error, /two foreground/) { Docv::Theme.parse("red blue") }
    expect_raises(Docv::Theme::Error, /without a color/) { Docv::Theme.parse("red on") }
    expect_raises(Docv::Theme::Error, /unknown/) { Docv::Theme.parse("red+101") }
    expect_raises(Docv::Theme::Error, /unknown/) { Docv::Theme.parse("256") }
  end

  it "resolves roles against the palette, ramping in RGB" do
    palette = Docv::Palette.new(dark: true)
    palette.set("foreground", "rgb:c8/c8/c8")
    palette.set("background", "rgb:00/00/00")
    theme = Docv::Theme.new({Docv::Theme::Role::Field => Docv::Theme.parse("on background+10")})
    styles = theme.styles(palette, Docv::ColorDepth::TrueColor)
    Docv::Styles[styles[Docv::Theme::Role::Field.value]].bg.should eq Docv::Color.rgb(20, 20, 20)
    heading = Docv::Styles[styles[Docv::Theme::Role::Heading1.value]]
    heading.attr.bold?.should be_true
    heading.fg.should eq Docv::Color.palette(12)
  end

  it "drops colors for NO_COLOR" do
    styles = Docv::Theme.new.styles(Docv::Palette.new, Docv::ColorDepth::None)
    styles.map { |id| Docv::Styles[id] }.all? { |style| style.fg.default? && style.bg.default? }.should be_true
    Docv::Styles[styles[Docv::Theme::Role::Selection.value]].attr.reverse?.should be_true
  end

  it "names every role as a config key" do
    Docv::Theme::KEYS["text-selection"].should eq Docv::Theme::Role::TextSelection
    Docv::Theme::KEYS.size.should eq Docv::Theme::Role.values.size
    Docv::Theme::DEFAULT.keys.should eq Docv::Theme::Role.values
    Docv::Theme::MONOCHROME.keys.should eq Docv::Theme::Role.values
  end
end
