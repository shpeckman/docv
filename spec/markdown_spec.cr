# spec/markdown_spec.cr
require "./spec_helper"
require "file_utils"

# Lays out Markdown *source* and returns the lines as text without trailing
# blanks.
private def md(source : String, width : Int32 = 60, wrap : Bool = true) : Array(String)
  Docv::Layout.new(Docv::Markdown.parse(source)).lines(width, wrap).map(&.text.rstrip)
end

private def markup(id : UInt16) : Docv::Markup
  Docv::Styles[id].markup
end

describe Docv::Markdown do
  it "recognizes Markdown files by extension" do
    Docv::Markdown.file?("README.md").should be_true
    Docv::Markdown.file?("docs/guide.markdown.gz").should be_true
    Docv::Markdown.file?("NOTES.MD").should be_true
    Docv::Markdown.file?("ls.1").should be_false
  end

  it "fills paragraphs and keeps hard line breaks" do
    md("one two\nthree\n\nnext  \nline\n", 60).should eq ["one two three", "", "next", "line"]
  end

  it "never breaks a code span" do
    md("aaaa `one two three` b\n", 14).should eq ["aaaa", "one two three", "b"]
  end

  it "keeps heading levels, the title and GitHub anchors" do
    doc = Docv::Markdown.parse("# Top Title\n\ntext\n\n## Sub, part!\n\n### Sub, part!\n\n###### Six\n")
    doc.format.markdown?.should be_true
    doc.title.should eq "Top Title"
    headings = doc.blocks.select(&.kind.heading?)
    headings.map(&.level).should eq [1, 2, 3, 6]
    doc.anchors.keys.should eq ["top-title", "sub-part", "sub-part-1", "six"]
    doc.blocks[doc.anchors["sub-part-1"]].level.should eq 3
    Docv::Layout.new(doc).header_line(60).should be_nil
  end

  it "styles emphasis, strikethrough and code" do
    spans = Docv::Markdown.parse("*a* **b** ~~c~~ `d`\n").blocks.first.spans
    Docv::Styles[spans.find!(&.text.==("a")).style].attr.italic?.should be_true
    Docv::Styles[spans.find!(&.text.==("b")).style].attr.bold?.should be_true
    Docv::Styles[spans.find!(&.text.==("c")).style].attr.strike?.should be_true
    markup(spans.find!(&.text.==("d")).style).should eq Docv::Markup::Code
  end

  it "hangs list items on their markers" do
    md("- one\n- two\n  - nested\n\n1. first\n2. second\n\n- [ ] todo\n- [x] done\n").should eq [
      "• one", "• two", "  ◦ nested", "", "1. first", "2. second", "", "☐ todo", "☑ done",
    ]
  end

  it "widens ordered markers to the largest number and spaces loose lists" do
    md("9. nine\n10. ten\n").should eq ["9.  nine", "10. ten"]
    md("- a\n\n- b\n").should eq ["• a", "", "• b"]
  end

  it "puts a bar on every line of a block quote" do
    md("> one\n>\n> > two\n").should eq ["│ one", "│", "│ │ two"]
    md("> [!NOTE]\n> Read this.\n").should eq ["│ Note", "│ Read this."]
    Docv::Markdown.parse("> q\n").blocks.first.bars.should eq [0]
  end

  it "keeps the lines of code blocks unwrapped and indented" do
    lines = md("```\nlong line of code that does not wrap at all\n  indented\n```\n", 20)
    lines.should eq ["    long line of code that does not wrap at all", "      indented"]
    block = Docv::Markdown.parse("```\nx\n```\n").blocks.first
    block.fill?.should be_false
    markup(block.spans.first.style).should eq Docv::Markup::CodeBlock
  end

  it "draws horizontal rules across the width" do
    md("a\n\n---\n\nb\n", 12).should eq ["a", "", "─" * 12, "", "b"]
  end

  it "boxes tables as wide as the page with the header ruled off" do
    md("| a | bb |\n|:-:|--:|\n| x | y |\n", 20).should eq [
      "┌──────┬───────────┐", "│  a   │        bb │", "├──────┼───────────┤", "│  x   │         y │", "└──────┴───────────┘",
    ]
    md("| a | b |\n|---|---|\n| x | y |\n", 33, wrap: false).map(&.size).uniq.should eq [33]
    table = Docv::Markdown.parse("| h |\n|---|\n| c |\n").blocks.first.table.not_nil!
    Docv::Styles[table.rows.first.cells.first.spans.first.style].attr.bold?.should be_true
  end

  it "drops raw HTML and keeps its text" do
    md("<!-- note -->\n<p align=\"center\"><img src=\"x.png\"></p>\n\n<details><summary>More &amp; less</summary>\n\nbody <b>bold</b>\n").should eq [
      "More & less", "", "body bold",
    ]
  end

  it "shows images as their description" do
    md("![the logo](logo.png) ![](img/pic.png)\n").should eq ["the logo pic.png"]
  end

  it "turns link destinations into targets" do
    doc = Docv::Markdown.parse("[u](https://e.org/x) [f](docs/a%20b.md#usage) [h](#intro) [u2](https://e.org/x)\n")
    doc.links.should eq [
      Docv::Target.new(Docv::TargetKind::Url, "https://e.org/x"),
      Docv::Target.new(Docv::TargetKind::File, "docs/a b.md", "usage"),
      Docv::Target.new(Docv::TargetKind::Anchor, "", "intro"),
    ]
    doc.blocks.first.spans.map(&.link).should eq [1, 0, 2, 0, 3, 0, 1]
  end

  it "lays out one link over linked words and keeps links in table cells" do
    doc = Docv::Markdown.parse("see [two words](#x) and `ls(1)`\n\n| [c](#y) |\n|---|\n| d |\n")
    lines = Docv::Layout.new(doc).lines(60)
    links = lines[0].links
    links.size.should eq 2
    links[0].should eq Docv::Layout::Link.new(4, 9, Docv::Target.new(Docv::TargetKind::Anchor, "", "x"))
    links[1].target.should eq Docv::Target.new(Docv::TargetKind::Page, "ls", "1")
    lines.find! { |line| line.text.includes?("c") && line.text.includes?("│") }.links.first.col.should eq 2
  end

  it "describes a document by its first heading and paragraph" do
    Docv::Markdown.description("<!-- x -->\n# Tool\n\nDoes things.\n\nMore.\n").should eq "Tool — Does things."
    Docv::Markdown.description("Just text.\n").should eq "Just text."
  end

  it "is loaded by Docv.load from a Markdown file" do
    path = File.tempname("docv-md", ".md")
    File.write(path, "# Hello\n")
    Docv.load(path).format.markdown?.should be_true
  ensure
    FileUtils.rm_rf(path) if path
  end
end
