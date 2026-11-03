# spec/manpath_spec.cr
require "./spec_helper"
require "compress/gzip"
require "file_utils"

private def with_tree(&)
  root = File.tempname("docv-spec")
  Dir.mkdir_p(File.join(root, "man1"))
  Dir.mkdir_p(File.join(root, "man3"))
  Dir.mkdir_p(File.join(root, "man3p"))
  File.write(File.join(root, "man1", "tool.1"), ".TH TOOL 1\n.SH NAME\ntool \\- plain\n")
  File.open(File.join(root, "man3", "func.3.gz"), "w") do |file|
    Compress::Gzip::Writer.open(file) { |gzip| gzip << ".so man3/real.3\n" }
  end
  File.write(File.join(root, "man3", "real.3"), ".TH REAL 3\n.SH NAME\nreal \\- included\n")
  File.write(File.join(root, "man3p", "func.3p"), ".TH FUNC 3P\n")
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

describe Docv::Manpath do
  it "finds pages by name and section" do
    with_tree do |root|
      path = Docv::Manpath.new([root], nil)
      path.find("tool").should eq File.join(root, "man1", "tool.1")
      path.find("func", "3").should eq File.join(root, "man3", "func.3.gz")
      path.find("func", "3p").should eq File.join(root, "man3p", "func.3p")
      path.find("missing").should be_nil
    end
  end

  it "reads gzip pages and resolves .so includes" do
    with_tree do |root|
      doc = Docv.load(File.join(root, "man3", "func.3.gz"))
      doc.title.should eq "REAL"
      doc.blocks.map(&.text).should contain("real - included")
    end
  end

  it "parses references" do
    Docv::Manpath.parse_reference("printf(3)").should eq({"printf", "3"})
    Docv::Manpath.parse_reference("ls").should eq({"ls", nil})
  end

  it "splits page file names" do
    Docv::Manpath.split("printf.3.gz", "3").should eq({"printf", "3"})
    Docv::Manpath.split("systemd.unit.5", "5").should eq({"systemd.unit", "5"})
    Docv::Manpath.split("foo.3p", "3").should eq({"foo", "3p"})
    Docv::Manpath.split("foo.1.xz", "1").should be_nil
    Docv::Manpath.split("README", "1").should be_nil
    Docv::Manpath.split("tool.8").should eq({"tool", "8"})
    Docv::Manpath.split("main.cr").should be_nil
  end

  it "finds pages in flat directories, before later roots" do
    with_project do |project|
      path = Docv::Manpath.new([File.join(project, "doc"), File.join(project, "man")], nil)
      path.roots.map(&.flat).should eq [true, false]
      path.find("flat").should eq File.join(project, "doc", "flat.7")
      path.find("tool", "1").should eq File.join(project, "man", "man1", "tool.1")
      path.find("notes").should be_nil
    end
  end

  it "builds the system path like man-db" do
    with_project do |project|
      bin = File.join(project, "bin")
      Dir.mkdir_p(bin)
      Dir.mkdir_p(File.join(project, "share", "man"))
      config = Docv::Manpath.parse_man_db("# comment\nMANDATORY_MANPATH /m1\nMANPATH_MAP /mapped /m2\nMANPATH_MAP /mapped /m3\n")
      config.mandatory.should eq ["/m1"]
      config.map["/mapped"].should eq ["/m2", "/m3"]
      path = "#{bin}:/mapped"
      neighbors = [File.join(project, "man"), File.join(project, "share", "man")]
      Docv::Manpath.system(nil, path, config).should eq neighbors + ["/m2", "/m3", "/m1"]
      Docv::Manpath.system("/x::/y", path, config).should eq ["/x"] + neighbors + ["/m2", "/m3", "/m1", "/y"]
      Docv::Manpath.system("/x", path, config).should eq ["/x"]
    end
  end

  it "finds the project root and its man page directories" do
    with_project do |project|
      deep = File.join(project, "src", "deep")
      Docv::Manpath.project_root(deep).should eq project
      found = Docv::Manpath.discover(deep)
      found.should eq [project, File.join(project, "doc"), File.join(project, "man")]
      Docv::Manpath.project_root(Path.home.to_s).should be_nil
    end
  end

  it "finds the Markdown documents of the project and marks its roots" do
    with_project do |project|
      File.write(File.join(project, "README.md"), "# Readme\n")
      File.write(File.join(project, "src", "deep", "notes.markdown"), "notes\n")
      File.write(File.join(project, "node_modules", "dep", "dep.md"), "dep\n")
      File.write(File.join(project, ".cache", "hidden.md"), "hidden\n")
      File.write(File.join(project, ".draft.md"), "draft\n")
      found = Docv::Manpath.project(File.join(project, "src")).not_nil!
      found.root.should eq project
      found.documents.should eq [File.join(project, "README.md"), File.join(project, "src", "deep", "notes.markdown")]
      manpath = Docv::Manpath.new(found.pages + ["/usr/share/man"], nil, found)
      manpath.project.should eq found
      manpath.roots.select(&.project).map(&.path).should eq found.pages
    end
  end

  it "adds and removes directories in the paths file" do
    with_project do |project|
      file = File.join(project, "config", "paths")
      Docv::Manpath.add_paths([File.join(project, "doc"), File.join(project, "man")], file).size.should eq 2
      Docv::Manpath.add_paths([File.join(project, "doc")], file).should be_empty
      Docv::Manpath.read_paths(file).should eq [File.join(project, "doc"), File.join(project, "man")]
      Docv::Manpath.remove_paths([File.join(project, "doc"), "/elsewhere"], file).should eq [File.join(project, "doc")]
      Docv::Manpath.read_paths(file).should eq [File.join(project, "man")]
    end
  end
end

private def with_project(&)
  root = File.tempname("docv-project")
  Dir.mkdir_p(File.join(root, ".git"))
  Dir.mkdir_p(File.join(root, "man", "man1"))
  Dir.mkdir_p(File.join(root, "doc"))
  Dir.mkdir_p(File.join(root, "src", "deep"))
  Dir.mkdir_p(File.join(root, "node_modules", "dep", "man", "man1"))
  Dir.mkdir_p(File.join(root, ".cache"))
  File.write(File.join(root, "man", "man1", "tool.1"), ".TH TOOL 1\n")
  File.write(File.join(root, "doc", "flat.7"), ".TH FLAT 7\n")
  File.write(File.join(root, "doc", "notes.1"), "plain text\n")
  File.write(File.join(root, "top.1"), "'\\\" comment\n.TH TOP 1\n")
  File.write(File.join(root, "node_modules", "dep", "man", "man1", "dep.1"), ".TH DEP 1\n")
  File.write(File.join(root, ".cache", "hidden.1"), ".TH HIDDEN 1\n")
  yield File.realpath(root)
ensure
  FileUtils.rm_rf(root) if root
end
