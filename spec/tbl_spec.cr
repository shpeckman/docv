# spec/tbl_spec.cr
require "./spec_helper"

TABLE = <<-ROFF
  .TH X 1
  .SH T
  .TS
  box;
  l r
  l n.
  Name\tSize
  _
  a\t1.5
  bb\t10
  .TE
  ROFF

describe Docv::Roff::Tbl do
  it "parses rows, rules and cells" do
    table = parse(TABLE).blocks.find(&.kind.table?).try(&.table).not_nil!
    table.columns.should eq 2
    table.frame.box?.should be_true
    table.rows.map(&.kind.to_s).should eq ["Data", "Rule", "Data", "Data"]
    table.rows[2].cells[1].align.numeric?.should be_true
  end

  it "draws frames and aligns numbers on the decimal point" do
    lines = render(TABLE, 60)
    top = lines.index(&.includes?("┌")).not_nil!
    lines[top + 1].should contain("│ Name   Size │")
    lines[top + 2].should contain("├")
    lines[top + 3].should contain("│ a       1.5 │")
    lines[top + 4].should contain("│ bb     10   │")
    lines[top + 5].should contain("└")
  end

  it "fills text blocks to the available width" do
    source = ".TS\nl l.\nkey\tT{\n#{"word " * 30}\nT}\n.TE\n"
    lines = render(source, 40)
    lines.size.should be > 3
    lines.all? { |line| line.size <= 40 }.should be_true
  end

  it "treats a rule-only format row as a rule" do
    table = parse(".TS\nl l\n__\nl l.\nA\tB\nc\td\n.TE\n").blocks.first.table.not_nil!
    table.rows.map(&.kind.to_s).should eq ["Data", "Rule", "Data"]
  end

  it "widens an expand table to the line" do
    lines = render(".TH X 1\n.SH T\n.TS\nexpand box;\nl l.\na\tbb\n.TE\n", 40)
    table = lines.select(&.includes?('│'))
    table.should_not be_empty
    table.map(&.size).uniq.should eq [40]
  end
end
