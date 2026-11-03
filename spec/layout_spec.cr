# spec/layout_spec.cr
require "./spec_helper"

describe Docv::Layout do
  long = ".TH X 1\n.SH D\n#{(1..40).map { |n| "word#{n}" }.join(' ')}\n"

  it "wraps filled text to the width" do
    lines = render(long, 40)
    body = lines.select(&.starts_with?("       word"))
    body.size.should be > 1
    body.all? { |line| line.size <= 40 }.should be_true
  end

  it "lays out the page header and footer on their own or leaves them out" do
    layout = Docv::Layout.new(parse(long))
    header = layout.header_line(40).not_nil!.text
    header.size.should eq 40
    header.should start_with("X(1) ")
    header.should end_with(" X(1)")
    layout.lines(40).first.text.should eq layout.header_line(40).not_nil!.text
    layout.lines(40, header: false).first.text.should eq "D"
    footer = layout.footer_line(40).not_nil!.text
    footer.size.should eq 40
    footer.should end_with(" X(1)")
    layout.lines(40).last.text.should eq footer
    layout.lines(40, footer: false).last.text.should contain("word40")
    Docv::Layout.new(parse("text\n")).header_line(40).should be_nil
    Docv::Layout.new(parse("text\n")).footer_line(40).should be_nil
  end

  it "puts each paragraph on one line when unwrapped" do
    lines = render(long, 40, wrap: false)
    lines.count(&.includes?("word1 ")).should eq 1
    lines.find(&.includes?("word40")).not_nil!.should contain("word1 ")
  end

  it "never wraps unfilled text" do
    lines = render(".nf\n#{"x" * 100}\n", 40)
    lines.should contain("x" * 100)
  end

  it "expands tabs to stops" do
    render(".nf\na\tb\n.ta 10\nc\td\n", 40).should eq ["a    b", "c         d"]
  end

  it "records block and offset of every line for anchoring" do
    lines = Docv::Layout.new(parse(long)).lines(30)
    body = lines.select { |line| line.block >= 0 && line.width > 0 && !line.text.strip.empty? }
    body.map(&.offset).should eq body.map(&.offset).sort
  end

  it "measures wide characters as two columns" do
    line = Docv::Layout.new(parse("日本\n")).lines(20).first
    line.width.should eq 4
    line.cells[1].continuation?.should be_true
  end
end
