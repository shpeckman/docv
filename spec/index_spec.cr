# spec/index_spec.cr
require "./spec_helper"
require "compress/gzip"
require "file_utils"

private def with_pages(&)
  root = File.tempname("docv-index")
  Dir.mkdir_p(File.join(root, "man1"))
  Dir.mkdir_p(File.join(root, "man3"))
  File.write(File.join(root, "man1", "tool.1"), ".TH TOOL 1\n.SH NAME\ntool, tl \\- plain tool\n.SH SYNOPSIS\ntool\n")
  File.write(File.join(root, "man1", "doc.1"), ".Dd x\n.Dt DOC 1\n.Os\n.Sh NAME\n.Nm doc\n.Nd mdoc page\n.Sh DESCRIPTION\n")
  File.write(File.join(root, "man1", "macros.1"),
    ".de XX\n.SH \"NOT A HEADING\"\n..\n.TH MACROS 1\n.SH VERSION\n1.0\n.SH NAME\nmacros \\- after others\n.SH SYNOPSIS\n")
  File.open(File.join(root, "man3", "alias.3.gz"), "w") do |file|
    Compress::Gzip::Writer.open(file) { |gzip| gzip << ".so man3/real.3\n" }
  end
  File.write(File.join(root, "man3", "real.3"), ".TH REAL 3\n.SH NAME\nreal \\- included\n")
  File.write(File.join(root, "man3", "notes.txt"), "not a page\n")
  yield root, File.join(root, "cache", "index.tsv")
ensure
  FileUtils.rm_rf(root) if root
end

describe Docv::Index do
  it "lists pages in section order and describes them" do
    with_pages do |root, cache|
      index = Docv::Index.new(Docv::Manpath.new([root], nil), cache)
      index.entries.map(&.reference).should eq ["doc(1)", "macros(1)", "tool(1)", "alias(3)", "real(3)"]
      index.complete?.should be_false
      index.describe
      index.complete?.should be_true
      descriptions = index.entries.to_h { |entry| {entry.reference, entry.description} }
      descriptions["tool(1)"].should eq "plain tool"
      descriptions["doc(1)"].should eq "mdoc page"
      descriptions["macros(1)"].should eq "after others"
      descriptions["alias(3)"].should eq "included"
    end
  end

  it "reuses the cache and describes only new files" do
    with_pages do |root, cache|
      manpath = Docv::Manpath.new([root], nil)
      Docv::Index.new(manpath, cache).describe
      File.exists?(cache).should be_true
      again = Docv::Index.new(manpath, cache)
      again.complete?.should be_true
      again.entries.find! { |entry| entry.name == "tool" }.description.should eq "plain tool"
      File.write(File.join(root, "man1", "new.1"), ".TH NEW 1\n.SH NAME\nnew \\- added\n")
      changed = Docv::Index.new(manpath, cache)
      changed.pending.should eq 1
      changed.describe
      changed.entries.find! { |entry| entry.name == "new" }.description.should eq "added"
    end
  end

  it "keeps partial progress in the cache" do
    with_pages do |root, cache|
      manpath = Docv::Manpath.new([root], nil)
      index = Docv::Index.new(manpath, cache)
      index.describe { |done, _| break if done == 2 }
      index.save
      Docv::Index.new(manpath, cache).pending.should eq 3
    end
  end

  it "lists the pages of flat directories" do
    with_pages do |root, cache|
      flat = File.join(root, "doc")
      Dir.mkdir_p(flat)
      File.write(File.join(flat, "flat.7"), ".TH FLAT 7\n.SH NAME\nflat \\- loose page\n")
      File.write(File.join(flat, "notes.1"), "not roff\n")
      index = Docv::Index.new(Docv::Manpath.new([flat, root], nil), cache)
      index.describe
      flat_entry = index.entries.find! { |entry| entry.name == "flat" }
      flat_entry.section.should eq "7"
      flat_entry.description.should eq "loose page"
      index.entries.any? { |entry| entry.name == "notes" }.should be_false
    end
  end

  it "lists the project's pages and documents first" do
    with_pages do |root, cache|
      project = File.join(root, "project")
      Dir.mkdir_p(File.join(project, "docs"))
      Dir.mkdir_p(File.join(project, ".git"))
      File.write(File.join(project, "README.md"), "# Proj\n\nThe project.\n")
      File.write(File.join(project, "docs", "guide.md"), "Guide text.\n")
      File.write(File.join(project, "proj.1"), ".TH PROJ 1\n.SH NAME\nproj \\- own page\n")
      found = Docv::Manpath.project(project).not_nil!
      manpath = Docv::Manpath.new(found.pages + [root], nil, found)
      index = Docv::Index.new(manpath, cache)
      index.entries.map(&.reference).first(3).should eq ["proj(1)", "README.md", "docs/guide.md"]
      index.entries.first(3).all?(&.project?).should be_true
      index.entries[3].project?.should be_false
      index.describe
      index.entries[1].description.should eq "Proj — The project."
      index.entries[2].description.should eq "Guide text."
      Docv::Index.new(manpath, cache).pending.should eq 2
    end
  end
end
