# spec/manual_spec.cr
require "./spec_helper"

# The shard's own manual pages, in man/.
MANUAL = Dir.glob(File.join(__DIR__, "..", "man", "man*", "*")).sort

describe "docv's manual" do
  it "has its pages" do
    MANUAL.map { |path| File.basename(path) }.should eq ["docv.1", "docv-config.5"]
  end

  MANUAL.each do |path|
    it "parses #{File.basename(path)} without unknown requests or macros" do
      doc = Docv.load(path)
      doc.messages.should be_empty
      name, section = Docv::Manpath.split(File.basename(path)).not_nil!
      doc.reference.should eq "#{name.upcase}(#{section})"
      Docv::Layout.new(doc).lines(80).none? { |line| line.width > 80 }.should be_true
    end
  end

  it "is found as a project tree" do
    root = File.expand_path(File.join(__DIR__, ".."))
    Docv::Manpath.discover(root).should contain(File.join(root, "man"))
  end
end
