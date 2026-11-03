# spec/config_spec.cr
require "./spec_helper"
require "file_utils"

private def with_env(name : String, value : String?, &)
  saved = ENV[name]?
  value ? (ENV[name] = value) : ENV.delete(name)
  yield
ensure
  saved ? (ENV[name] = saved) : ENV.delete(name)
end

describe Docv::Config do
  it "lives under XDG_CONFIG_HOME, falling back to ~/.config" do
    with_env("XDG_CONFIG_HOME", "/tmp/xdg") do
      Docv::Config.path.should eq "/tmp/xdg/docv/config.ini"
    end
    with_env("XDG_CONFIG_HOME", "relative") do
      Docv::Config.path.should eq Path.home.join(".config", "docv", "config.ini").to_s
    end
    with_env("XDG_CONFIG_HOME", nil) do
      Docv::Config.path.should eq Path.home.join(".config", "docv", "config.ini").to_s
    end
  end

  it "creates the default file on first load" do
    root = File.tempname("docv-config")
    begin
      with_env("XDG_CONFIG_HOME", root) do
        config = Docv::Config.load
        File.read(Docv::Config.path).should eq Docv::Config::DEFAULT
        config.unsafe?.should be_false
        Docv::Config.load.unsafe?.should be_false
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "reads where the viewer starts" do
    Docv::Config.parse("").start_wrapped?.should be_true
    Docv::Config.parse("[viewer]\nstart-wrapped = no\n").start_wrapped?.should be_false
    Docv::Config::DEFAULT.should contain("[viewer]\n")
    Docv::Config.parse(Docv::Config::DEFAULT).start_wrapped?.should be_true
    expect_raises(Docv::Config::Error, /start-wrapped must be true or false/) { Docv::Config.parse("[viewer]\nstart-wrapped = maybe\n") }
  end

  it "reads the dock and search settings" do
    Docv::Config.parse("").picker.should eq Docv::PickerSettings.new
    Docv::Config.parse(Docv::Config::DEFAULT).picker.should eq Docv::PickerSettings.new
    text = "[picker]\ndock-width = 50\ndock-open = yes\nmin-group = 5\nsearch-threads = 4\n"
    Docv::Config.parse(text).picker.should eq Docv::PickerSettings.new(50, true, 5, 4)
    expect_raises(Docv::Config::Error, /unknown key dock in \[picker\]/) { Docv::Config.parse("[picker]\ndock = overlay\n") }
    expect_raises(Docv::Config::Error, /dock-width must be a number from 16/) { Docv::Config.parse("[picker]\ndock-width = 3\n") }
    expect_raises(Docv::Config::Error, /min-group must be a number from 2/) { Docv::Config.parse("[picker]\nmin-group = 1\n") }
    expect_raises(Docv::Config::Error, /unknown key dock-width in \[viewer\]/) { Docv::Config.parse("[viewer]\ndock-width = 40\n") }
  end

  it "reads the Crystal page settings" do
    Docv::Config.parse("").crystal.should eq Docv::CrystalSettings.new
    Docv::Config.parse(Docv::Config::DEFAULT).crystal.should eq Docv::CrystalSettings.new(true, Docv::PageStore::Memory)
    config = Docv::Config.parse("[crystal]\ngenerate = no\nstore = Disk\n")
    config.crystal.should eq Docv::CrystalSettings.new(false, Docv::PageStore::Disk)
    expect_raises(Docv::Config::Error, /store must be memory or disk, not tape/) { Docv::Config.parse("[crystal]\nstore = tape\n") }
  end

  it "reads the man page settings" do
    Docv::Config.parse("").indent.should eq 2
    Docv::Config.parse(Docv::Config::DEFAULT).indent.should eq 2
    config = Docv::Config.parse("[man]\nroff-unsafe = yes\nindent = 4\n")
    {config.unsafe?, config.indent}.should eq({true, 4})
    config.options.indent.should eq 4
    expect_raises(Docv::Config::Error, /unknown section \[roff\]/) { Docv::Config.parse("[roff]\nunsafe = yes\n") }
  end

  it "parses booleans" do
    Docv::Config.parse("[man]\nroff-unsafe = yes\n").unsafe?.should be_true
    Docv::Config.parse("[man]\nroff-unsafe = Off\n").unsafe?.should be_false
    Docv::Config.parse("").unsafe?.should be_false
  end

  it "rejects invalid values, unknown keys and sections" do
    expect_raises(Docv::Config::Error, /true or false/) { Docv::Config.parse("[man]\nroff-unsafe = maybe\n") }
    expect_raises(Docv::Config::Error, /unknown key/) { Docv::Config.parse("[man]\nfoo = 1\n") }
    expect_raises(Docv::Config::Error, /unknown section/) { Docv::Config.parse("[other]\n") }
  end

  it "reads role styles from [colors]" do
    config = Docv::Config.parse("[colors]\nheading1 = bold #ff8800\nfield = on background+5\n")
    config.colors[Docv::Theme::Role::Heading1].fg.color.should eq Docv::Color.rgb(255, 136, 0)
    config.theme.specs[Docv::Theme::Role::Field].bg.ramp.should eq 5
    config.theme.specs[Docv::Theme::Role::Link].should eq Docv::Theme.default_specs[Docv::Theme::Role::Link]
    expect_raises(Docv::Config::Error, /heading1: unknown color/) { Docv::Config.parse("[colors]\nheading1 = shiny\n") }
    expect_raises(Docv::Config::Error, /unknown key/) { Docv::Config.parse("[colors]\nsparkle = red\n") }
  end

  it "lists every role in the default file" do
    Docv::Theme::KEYS.each_key { |key| Docv::Config::DEFAULT.should contain("; #{key} = ") }
    Docv::Config.parse(Docv::Config::DEFAULT).colors.should be_empty
  end

  it "turns into parsing options" do
    options = Docv::Config.new(unsafe: true).options(STDIN)
    options.unsafe.should be_true
    options.stdin.should be(STDIN)
  end
end
