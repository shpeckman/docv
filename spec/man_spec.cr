# spec/man_spec.cr
require "./spec_helper"

PAGE = <<-ROFF
  .TH LS 1 2024-01-01 "GNU coreutils" "User Commands"
  .SH NAME
  ls \\- list directory contents
  .SH OPTIONS
  .TP
  .BR \\-a ", " \\-\\-all
  do not ignore entries
  .IP \\(bu 4
  bullet item
  .RS
  nested
  .RE
  .SH "SEE ALSO"
  .BR dircolors (1)
  ROFF

describe Docv::Macros::Man do
  it "reads the title header" do
    doc = parse(PAGE)
    doc.format.man?.should be_true
    doc.title.should eq "LS"
    doc.section.should eq "1"
    doc.manual.should eq "User Commands"
    doc.reference.should eq "LS(1)"
  end

  it "lays out headings, tags and indents like groff" do
    lines = render(PAGE, 60)
    lines[0].should start_with("LS(1)")
    lines.should contain("NAME")
    lines.should contain("       ls - list directory contents")
    lines.should contain("       -a, --all")
    lines.should contain("              do not ignore entries")
    lines.should contain("       •   bullet item")
    lines.should contain("           nested")
  end

  it "detects cross references" do
    lines = Docv::Layout.new(parse(PAGE)).lines(60)
    link = lines.flat_map(&.links).first
    link.target.should eq Docv::Target.new(Docv::TargetKind::Page, "dircolors", "1")
  end

  it "puts a short tag on the body line" do
    render(".TH X 1\n.SH A\n.TP 8\n.B \\-x\nexplain\n", 60).should contain("       -x      explain")
  end

  it "fills the default manual name from the section" do
    parse(".TH X 7\n").manual.should eq "Miscellaneous Information Manual"
  end

  it "keeps example blocks unfilled" do
    blocks(".TH X 1\n.EX\na   b\nc\n.EE\n").should eq ["a   b", "c"]
  end

  it "renders URLs after their text" do
    blocks(".TH X 1\n.UR https://x.org\nsite\n.UE .\n").first.should eq "site ⟨https://x.org⟩."
  end
end
