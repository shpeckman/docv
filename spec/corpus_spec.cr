# spec/corpus_spec.cr
require "./spec_helper"
require "../src/docv/corpus"

describe Docv::Corpus do
  root = File.tempname("docv-corpus")
  Dir.mkdir_p(root)
  sort = File.join(root, "sort.1")
  File.write(sort, ".TH SORT 1\n.SH NAME\nsort \\- sort lines of text\n.SH DESCRIPTION\nSort the lines.\n.PP\nReverse the result.\n")
  guide = File.join(root, "guide.md")
  File.write(guide, "# Guide\n\nSorting by time.\n\nNothing else.\n")
  cache = File.join(root, "cache", "text.bin")
  sources = -> { [sort, guide].map { |path| Docv::Corpus::Source.new(path, File.info(path).modification_time.to_unix_ns.to_i64) } }

  it "extracts the stripped lines of a page" do
    text = Docv::Corpus.extract(sort)
    text.lines.should contain "Sort the lines."
    text.lines.none?(&.blank?).should be_true
    Docv::Corpus.extract(File.join(root, "missing.1")).should eq ""
  end

  it "parses pages once, then reads them from its cache" do
    corpus = Docv::Corpus.new(cache, 2)
    parsed = [] of Int32
    corpus.build(sources.call) { |done, _| parsed << done }
    parsed.should eq [1, 2]
    corpus.ready?.should be_true
    String.new(corpus.text(1)).should contain "Sorting by time."
    corpus.close

    again = Docv::Corpus.new(cache, 2)
    parsed.clear
    again.build(sources.call) { |done, _| parsed << done }
    parsed.should be_empty
    String.new(again.text(0)).should contain "Reverse the result."
    again.close
  end

  it "parses a page again when it changed" do
    File.touch(guide, Time.utc + 1.minute)
    corpus = Docv::Corpus.new(cache, 2)
    parsed = [] of Int32
    corpus.build(sources.call) { |done, total| parsed << total }
    parsed.should eq [1]
    corpus.close
  end

  it "counts the lines every term matches, per page" do
    corpus = Docv::Corpus.new(cache, 2)
    corpus.build(sources.call)
    corpus.count("sort").should eq [2, 1]
    corpus.count("sort time").should eq [0, 1]
    corpus.count("").should be_nil
    corpus.count("sort", -> { true }).should be_nil
    corpus.close
  end

  it "parses in worker processes that serve page paths" do
    input = IO::Memory.new("#{sort}\n")
    output = IO::Memory.new
    Docv::Corpus.serve(input, output)
    size, text = output.to_s.split('\n', 2)
    text.bytesize.should eq size.to_i
    text.should contain "Sort the lines."
  end
end
