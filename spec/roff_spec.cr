# spec/roff_spec.cr
require "./spec_helper"

describe Docv::Roff::Engine do
  it "fills text lines into one block" do
    blocks("hello\nworld\n").should eq ["hello world"]
  end

  it "breaks on .br and keeps unfilled lines apart" do
    blocks("a\n.br\nb\n.nf\nc  d\ne\n").should eq ["a", "b", "c  d", "e"]
  end

  it "interpolates strings and registers" do
    blocks(".ds x World\n.nr n 41\n.nr n +1\nHello \\*x \\nn.\n").should eq ["Hello World 42."]
  end

  it "formats registers per .af" do
    blocks(".nr p 4\n.af p I\n\\np\n").should eq ["IV"]
  end

  it "defines and calls macros with arguments" do
    blocks(".de GREET\nHi \\\\$1 and \\\\$2\n..\n.GREET Ann \"B C\"\n").should eq ["Hi Ann and B C"]
  end

  it "evaluates conditionals and else branches" do
    source = ".if n nroff\n.if t troff\n.ie '\\*(.T'utf8' utf\n.el other\n.ie 0 no\n.el \\{\\\nyes\n.\\}\n"
    blocks(source).should eq ["nroff utf yes"]
  end

  it "skips false brace blocks across lines" do
    blocks(".if 0 \\{\\\nhidden\n.  if 1 more\n.\\}\nshown\n").should eq ["shown"]
  end

  it "runs while loops with break" do
    source = ".nr i 0 1\n.while \\n+i<10 \\{\\\n.if \\ni=4 .break\n\\ni\n.\\}\n"
    blocks(source).should eq ["1 2 3"]
  end

  it "ignores .ig blocks and comments" do
    blocks(".\\\" comment\n.ig\nhidden\n..\nvisible\\\" trailing\n").should eq ["visible"]
  end

  it "maps fonts to styles" do
    doc = parse("\\fBbold\\fR \\fIitalic\\fP\n")
    spans = doc.blocks.first.spans
    Docv::Styles[spans.first.style].attr.bold?.should be_true
    spans.find(&.text.==("italic")).try { |span| Docv::Styles[span.style].attr.italic?.should be_true }
  end

  it "renders special characters and escapes" do
    blocks("\\(em \\[u00E9] \\e \\- \\(lq\\(rq \\N'65'\n").should eq ["— é \\ - “” A"]
  end

  it "joins lines with \\c" do
    blocks("foo\\c\nbar\n").should eq ["foobar"]
  end

  it "applies .tr translations" do
    blocks(".tr ab\naaa\n").should eq ["bbb"]
  end

  it "centers lines with .ce" do
    parse(".ce\ntitle\n").blocks.first.align.center?.should be_true
  end

  it "diverts input into a macro" do
    blocks(".di D\nsaved\n.di\nfirst\n.D\n").should eq ["first saved"]
  end

  it "measures text with \\w" do
    blocks("\\w'abc'\n").should eq ["72"]
  end

  it "records .tm messages" do
    parse(".tm hello\n").messages.should eq ["hello"]
  end

  it "stops at .ex" do
    blocks("a\n.ex\nb\n").should eq ["a"]
  end
end
