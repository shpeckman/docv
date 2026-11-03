# spec/unsafe_spec.cr
require "./spec_helper"
require "file_utils"

UNSAFE = Docv::Options.new(unsafe: true)

private def unsafe_blocks(source : String, options = UNSAFE) : Array(String)
  Docv.parse(source, nil, options).blocks.select(&.kind.text?).map(&.text)
end

private def with_dir(&)
  dir = File.tempname("docv-unsafe")
  Dir.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "unsafe requests" do
  it "ignores them by default" do
    with_dir do |dir|
      marker = File.join(dir, "ran")
      blocks(".sy touch #{marker}\n.pso echo injected\n.open s #{marker}2\n.write s x\n\\V[HOME]text\n").should eq ["text"]
      File.exists?(marker).should be_false
      File.exists?("#{marker}2").should be_false
    end
  end

  it "runs .sy and stores the wait status in systat" do
    with_dir do |dir|
      marker = File.join(dir, "ran")
      unsafe_blocks(".sy touch #{marker}\n\\n[systat]\n.sy exit 3\n\\n[systat]\n").should eq ["0 768"]
      File.exists?(marker).should be_true
    end
  end

  it "reads .pso output as input" do
    unsafe_blocks(".pso printf '.ds x piped\\\\n'\n\\*x\n").should eq ["piped"]
  end

  it "writes streams with .open, .write, .writec, .writem and .close" do
    with_dir do |dir|
      path = File.join(dir, "out")
      source = ".de M\nbody\n..\n.open s #{path}\n.write s \"  one\n.writec s two\n.write s \\n(.$\n.writem s M\n.close s\n.opena s #{path}\n.write s three\n.close s\n"
      Docv.parse(source, nil, UNSAFE)
      File.read(path).should eq "  one\ntwo0\nbody\nthree\n"
    end
  end

  it "copies files unprocessed with .cf and .trf" do
    with_dir do |dir|
      path = File.join(dir, "raw")
      File.write(path, ".B not a macro\n\\fBraw\\fR\n")
      unsafe_blocks("before\n.cf #{path}\n.trf #{path}\n").should eq ["before", ".B not a macro", "\\fBraw\\fR", ".B not a macro", "\\fBraw\\fR"]
    end
  end

  it "pipes the formatted page to .pi commands" do
    with_dir do |dir|
      path = File.join(dir, "piped")
      Docv.parse(".pi cat > #{path}\nhello world\n", nil, UNSAFE)
      File.read(path).should contain("hello world")
    end
  end

  it "reads .rd input up to an empty line" do
    options = Docv::Options.new(unsafe: true, stdin: IO::Memory.new(".ds x read\nvalue\n\nignored\n"))
    unsafe_blocks(".rd\n\\*x\n", options).should eq ["value read"]
  end

  it "interpolates environment variables with \\V" do
    ENV["DOCV_SPEC_VAR"] = "env"
    unsafe_blocks("\\V[DOCV_SPEC_VAR]\n").should eq ["env"]
  ensure
    ENV.delete("DOCV_SPEC_VAR")
  end
end
