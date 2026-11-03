# spec/fuzzy_spec.cr
require "./spec_helper"

describe Docv::Fuzzy do
  it "matches subsequences only" do
    fuzzy = Docv::Fuzzy.new("prf")
    fuzzy.score("printf").should_not be_nil
    fuzzy.score("fpr").should be_nil
    fuzzy.positions("open").should be_nil
  end

  it "finds the best alignment" do
    Docv::Fuzzy.new("prf").positions("printf").should eq [0, 1, 5]
    Docv::Fuzzy.new("ls").positions("false").should eq [2, 3]
    Docv::Fuzzy.new("éc").positions("café éclair").should eq [5, 6]
  end

  it "prefers word starts and consecutive characters" do
    fuzzy = Docv::Fuzzy.new("ls")
    fuzzy.score("ls(1)").not_nil!.should be > fuzzy.score("false(1)").not_nil!
    fuzzy.score("lsblk").not_nil!.should be > fuzzy.score("l_s").not_nil!
    Docv::Fuzzy.new("fb").score("foo-bar").not_nil!.should be > Docv::Fuzzy.new("fb").score("foobar").not_nil!
  end

  it "ignores case for lower-case queries only" do
    Docv::Fuzzy.new("ls").score("LS").should_not be_nil
    Docv::Fuzzy.new("LS").score("ls").should be_nil
    Docv::Fuzzy.new("LS").score("LS").should_not be_nil
  end

  it "matches everything with an empty query" do
    Docv::Fuzzy.new("").score("anything").should eq 0
    Docv::Fuzzy.new("").positions("anything").should eq [] of Int32
  end
end
