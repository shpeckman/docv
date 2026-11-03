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
    Docv::Config.parse("").viewer.should eq Docv::ViewerSettings.new
    Docv::Config.parse(Docv::Config::DEFAULT).viewer.should eq Docv::ViewerSettings.new
    settings = Docv::Config.parse("[viewer]\ndock = Overlay\ndock-width = 50\ndock-open = yes\nsearch-threads = 4\n").viewer
    settings.should eq Docv::ViewerSettings.new(Docv::DockStyle::Overlay, 50, true, 4)
    expect_raises(Docv::Config::Error, /dock must be regular or overlay/) { Docv::Config.parse("[viewer]\ndock = left\n") }
    expect_raises(Docv::Config::Error, /dock-width must be a number from 16/) { Docv::Config.parse("[viewer]\ndock-width = 3\n") }
    expect_raises(Docv::Config::Error, /search-threads must be a number/) { Docv::Config.parse("[viewer]\nsearch-threads = many\n") }
  end

  it "parses booleans" do
    Docv::Config.parse("[roff]\nunsafe = yes\n").unsafe?.should be_true
    Docv::Config.parse("[roff]\nunsafe = Off\n").unsafe?.should be_false
    Docv::Config.parse("").unsafe?.should be_false
  end

  it "rejects invalid values, unknown keys and sections" do
    expect_raises(Docv::Config::Error, /true or false/) { Docv::Config.parse("[roff]\nunsafe = maybe\n") }
    expect_raises(Docv::Config::Error, /unknown key/) { Docv::Config.parse("[roff]\nfoo = 1\n") }
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
