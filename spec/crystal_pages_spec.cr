# spec/crystal_pages_spec.cr
require "./spec_helper"
require "file_utils"
require "../src/docv/crystal_pages"

private def roff(markdown : String, sections : Bool = false) : String
  io = IO::Memory.new
  Docv::CrystalPages::Renderer.new(io, sections).render(Docv::CrystalPages.blocks(markdown))
  io.to_s
end

private PROJECT = <<-JSON
  {"repository_name": "demo", "body": "<!-- README.md -->\\n# demo\\n\\nA demo shard. It does things.\\n\\n## Usage\\n\\nRun it.\\n",
   "program": {"kind": "module", "full_name": "Top Level Namespace", "program": true, "types": [
     {"kind": "class", "full_name": "Demo::Thing", "doc": "A thing.\\n\\nNOTE: careful.",
      "locations": [{"filename": "src/demo.cr"}], "superclass": {"kind": "class", "full_name": "Reference"},
      "constants": [{"name": "MAX", "value": "3", "doc": "Most."}],
      "instance_methods": [
        {"html_id": "run-instance-method", "name": "run", "doc": "Runs `Demo::Thing`.", "args_string": "(x : Int32) : Nil"},
        {"html_id": "clone-instance-method", "name": "clone"}],
      "types": [
        {"kind": "enum", "full_name": "Demo::Thing::Mode", "enum": true, "doc": "How it runs.",
         "locations": [{"filename": "src/demo.cr"}],
         "constants": [{"name": "Fast", "value": "0"}, {"name": "Slow", "value": "1"}],
         "instance_methods": [{"html_id": "fast?-instance-method", "name": "fast?"}]}]},
     {"kind": "class", "full_name": "Demo::Tool", "locations": [{"filename": "src/demo/tool.cr"}],
      "instance_methods": [{"html_id": "use-instance-method", "name": "use", "args_string": " : Nil"}]},
     {"kind": "alias", "full_name": "Demo::Id", "alias": true, "aliased": "Int32", "doc": "An id."}]}}
  JSON

private def with_shard(&)
  root = File.tempname("docv-shard")
  Dir.mkdir_p(File.join(root, "src"))
  File.write(File.join(root, "shard.yml"), "name: demo\nversion: 1.2.3\ntargets:\n  demo:\n    main: src/cli.cr\n")
  File.write(File.join(root, "src", "demo.cr"), "class Demo::Thing\nend\n")
  File.write(File.join(root, "src", "cli.cr"), "require \"./demo\"\nrequire \"./demo/tool\"\n")
  Dir.mkdir_p(File.join(root, "src", "demo"))
  File.write(File.join(root, "src", "demo", "tool.cr"), "require \"../demo\"\nclass Demo::Tool\nend\n")
  yield File.realpath(root)
ensure
  FileUtils.rm_rf(root) if root
end

private def pages(root : String) : Array(Docv::CrystalPages::Page)
  project = Docv::CrystalPages::Project.from_json(PROJECT)
  shard = Docv::CrystalPages::Shard.new(root, project.repository_name)
  Docv::CrystalPages::Pages.new(shard, Docv::CrystalPages::Types.new(project), "man").all
end

describe Docv::CrystalPages do
  it "names and summarizes like the doc generator" do
    Docv::CrystalPages.base_name("Foo(K, V)::Bar(T)").should eq "Foo::Bar"
    Docv::CrystalPages.clean_type("(a : ::Foo) : ::Bar | ::Baz").should eq "(a : Foo) : Bar | Baz"
    Docv::CrystalPages.summary("First one. Second.\n\nOther.").should eq "First one."
  end

  it "renders Markdown as roff" do
    roff("Some *it* **bold** `co de` and [site](https://e.org).\n").should eq \
      ".PP\nSome \\fIit\\fR \\fBbold\\fR \\fB\\%co \\%de\\fR and site <https://e.org>.\n"
    roff("NOTE(x): careful\n").should eq ".PP\n\\fBNOTE (x):\\fR careful\n"
    roff("```\n.dot\n```\n").should eq ".PP\n.RS 4\n.EX\n\\&.dot\n.EE\n.RE\n"
    roff("- a\n- b\n").should eq ".IP \\(bu 2\na\n.IP \\(bu 2\nb\n"
    roff("# Title\n## Sub\n### Third\n", sections: true).should eq ".SH\nTITLE\n.SH\nSUB\n.SS\nThird\n"
    roff("# Title\n").should eq ".PP\n\\fBTitle\\fR\n"
    roff("<!-- gone -->\n\nkept\n").should eq ".PP\nkept\n"
    roff("| a | b |\n|---|---|\n| x | y |\n").should eq \
      ".PP\n.TS\ntab(\t);\nl lx.\nT{\n\\fBa\\fR\nT}\tT{\n\\fBb\\fR\nT}\n_\nT{\nx\nT}\tT{\ny\nT}\n.TE\n"
  end

  it "builds the overview and one API page with a section per type" do
    with_shard do |root|
      all = pages(root)
      all.map(&.path).should eq ["man7/demo.7cr.gz", "man3/demo.3cr.gz"]
      overview, api = all
      overview.body.should contain("demo \\- A demo shard.\n")
      overview.body.should contain(".SH\nUSAGE\n")
      overview.body.should contain(".TP\n\\fBDemo::Thing\\fR\nA thing.\n")
      overview.body.should end_with(".SH \"SEE ALSO\"\n.BR \"demo\" (3cr)\n")
      api.body.should start_with(".SH \"NAME\"\ndemo \\- demo API reference\n")
      api.body.should contain(".SH \"Demo::Thing\"\n.nf\n\\fBrequire \"demo\"\\fR\n.sp\n\\fBclass Demo::Thing\\fR\n.fi\n")
      api.body.should contain(".SS \"Constants\"\n")
      api.body.should contain("\\fBMAX = 3\\fR")
      api.body.should contain(".SS \"Instance methods\"\n")
      api.body.should contain("\\fBdef run(x : Int32) : Nil\\fR")
      api.body.should_not contain("clone")
      api.body.should contain(".SH \"Demo::Thing::Mode\"\n")
      api.body.should contain(".SS \"Enum members\"\n")
      api.body.should contain("\\fBFast = 0\\fR")
      api.body.should contain(%(\\fBrequire "demo/tool"\\fR))
      api.body.should contain("\\fBalias Demo::Id = Int32\\fR")
      api.body.should end_with(".SH \"SEE ALSO\"\n.BR \"demo\" (7cr)\n")
      api.render("2026-01-01").should contain(%(.TH "demo" "3cr" "2026-01-01" "demo 1.2.3" "demo API Reference"))
    end
  end

  it "writes gzipped pages, keeps unchanged ones and never touches other files" do
    with_shard do |root|
      output = File.join(root, "man")
      generator = Docv::CrystalPages::Generator.new(output, "2026-01-01")
      generator.run(pages(root)).should eq({2, 0, 0})
      Docv::CrystalPages::Generator.new(output, "2026-02-02").run(pages(root)).should eq({0, 2, 0})
      overview = File.join(output, "man7", "demo.7cr.gz")
      Compress::Gzip::Reader.open(overview, &.gets_to_end).should contain("2026-01-01")
      Docv.load(overview).title.should eq "demo"
      File.write(File.join(output, "man3", "old.3cr"), ".\\\" Generated by docv gen-cr from README.md and the doc comments; regenerate instead of editing.\n")
      generator.run(pages(root)).should eq({0, 2, 1})
      File.write(overview, ".TH DEMO 7\n")
      expect_raises(Docv::CrystalPages::Error, /not generated/) { generator.run(pages(root)) }
    end
  end

  it "generates pages into memory, saves them into the shard and removes them on close" do
    with_shard do |root|
      memory = File.tempname("docv-memory")
      session = Docv::CrystalPages::Session.new(root, Docv::PageStore::Memory, memory)
      session.directory.should start_with memory
      expect_raises(Docv::CrystalPages::Error, /no pages generated/) { session.save }
      session.generate.should eq ["demo(7cr)", "demo(3cr)"]
      File.file?(File.join(session.directory, "man3", "demo.3cr.gz")).should be_true
      Dir.exists?(File.join(root, "man")).should be_false
      session.save.should eq "man: 2 written, 0 unchanged, 0 removed"
      File.file?(File.join(root, "man", "man7", "demo.7cr.gz")).should be_true
      session.close
      Dir.exists?(session.directory).should be_false
      File.file?(File.join(root, "man", "man7", "demo.7cr.gz")).should be_true
    ensure
      FileUtils.rm_rf(memory) if memory
    end
  end

  it "generates pages on disk, and reports the compiler's error" do
    with_shard do |root|
      session = Docv::CrystalPages::Session.new(root, Docv::PageStore::Disk)
      session.directory.should eq File.join(root, "man")
      session.generate
      File.file?(File.join(root, "man", "man3", "demo.3cr.gz")).should be_true
      session.close
      File.file?(File.join(root, "man", "man3", "demo.3cr.gz")).should be_true
      File.write(File.join(root, "src", "demo.cr"), "class Demo::Thing\n  def broken(\nend\n")
      expect_raises(Docv::CrystalPages::Error, /crystal docs` failed: /) { session.generate }
    end
  end

  it "finds the shard root" do
    with_shard do |root|
      Docv::CrystalPages::Shard.root(File.join(root, "src")).should eq root
    end
  end
end
