# spec/syntax_spec.cr
require "./spec_helper"
require "file_utils"
require "treesitter/fixture"

# Points `Syntax` at the JSON fixture grammar and at a query directory with
# the *queries* (`{language, text}`), restoring the defaults afterwards.
private def with_queries(queries : Hash(String, String), first_wins : Bool = false, &)
  root = File.tempname("docv-queries")
  queries.each do |language, text|
    Dir.mkdir_p(File.join(root, language))
    File.write(File.join(root, language, Docv::Syntax::QUERY_FILE), text)
  end
  grammars = Docv::Syntax.grammar_directories
  directories = Docv::Syntax.query_directories
  Docv::Syntax.grammar_directories = [File.dirname(TreeSitter::Fixture.library("json"))]
  Docv::Syntax.query_directories = [Docv::Syntax::QueryDirectory.new(root, first_wins)]
  Docv::Syntax.clear
  yield
ensure
  Docv::Syntax.grammar_directories = grammars if grammars
  Docv::Syntax.query_directories = directories if directories
  Docv::Syntax.clear
  FileUtils.rm_rf(root) if root
end

private JSON_QUERY = <<-SCM
  (pair key: (string) @property)
  (string) @string
  (number) @number
  [(true) (false) (null)] @constant.builtin
  ["{" "}" "[" "]"] @punctuation.bracket
  SCM

private def marks(runs : Array(Array({String, Docv::Markup}))) : Array(Array({String, String}))
  runs.map(&.map { |text, markup| {text, markup.to_s} })
end

describe Docv::Syntax do
  it "maps labels and page sections to languages" do
    Docv::Syntax.language("CR title=x").should eq "crystal"
    Docv::Syntax.language("json").should eq "json"
    Docv::Syntax.language("").should be_nil
    Docv::Syntax.page_language("man/man3/Foo::Bar.3cr").should eq "crystal"
    Docv::Syntax.page_language("/usr/share/man/man1/ls.1.gz").should be_nil
  end

  it "maps capture names by their longest known prefix" do
    Docv::Syntax.markup("keyword.function.builtin").should eq Docv::Markup::SyntaxKeyword
    Docv::Syntax.markup("variable.member").should eq Docv::Markup::SyntaxProperty
    Docv::Syntax.markup("variable.parameter").should be_nil
    Docv::Syntax.markup("_private").should be_nil
    Docv::Syntax.markup("unknown").should be_nil
  end

  it "splits code into lines of marked runs, later patterns of a node winning" do
    with_queries({"json" => JSON_QUERY}) do
      runs = Docv::Syntax.highlight(%({"a": 1,\n "b": [true]}), "json").not_nil!
      marks(runs).should eq [
        [{"{", "SyntaxPunctuation"}, {"\"a\"", "SyntaxString"}, {": ", "None"}, {"1", "SyntaxConstant"}, {",", "None"}],
        [{" ", "None"}, {"\"b\"", "SyntaxString"}, {": ", "None"}, {"[", "SyntaxPunctuation"}, {"true", "SyntaxConstant"},
         {"]}", "SyntaxPunctuation"}],
      ]
    end
  end

  it "gives the earlier pattern of a node priority for first-wins directories" do
    with_queries({"json" => JSON_QUERY}, first_wins: true) do
      runs = Docv::Syntax.highlight(%({"a": 1}), "json").not_nil!
      runs[0][1].should eq({"\"a\"", Docv::Markup::SyntaxProperty})
    end
  end

  it "prepends inherited queries" do
    with_queries({"base" => "(number) @number\n", "json" => "; inherits: base,(missing)\n(string) @string\n"}) do
      marks(Docv::Syntax.highlight(%(["x", 2]), "json").not_nil!)[0].should contain({"2", "SyntaxConstant"})
    end
  end

  it "leaves languages without a grammar, query or valid query plain" do
    with_queries({"json" => "(no_such_node) @keyword\n", "nogrammar" => "(x) @keyword\n"}) do
      Docv::Syntax.highlight("[1]", "json").should be_nil
      Docv::Syntax.highlight("x", "nogrammar").should be_nil
      Docv::Syntax.highlight("x", "noquery").should be_nil
    end
  end

  it "highlights labeled Markdown code blocks only when asked" do
    with_queries({"json" => JSON_QUERY}) do
      source = "```json\n[1,\n\n2]\n```\n\n```\n[3]\n```\n"
      blocks = Docv::Markdown.parse(source, highlight: true).blocks.select { |block| block.kind.text? && !block.fill? }
      blocks.size.should eq 4
      blocks[0].spans.map { |span| Docv::Styles[span.style].markup }.should eq [
        Docv::Markup::SyntaxPunctuation, Docv::Markup::SyntaxConstant, Docv::Markup::CodeBlock,
      ]
      blocks[1].spans.should be_empty
      blocks[3].spans.map { |span| Docv::Styles[span.style].markup }.should eq [Docv::Markup::CodeBlock]
      plain = Docv::Markdown.parse(source).blocks.reject(&.spans.empty?)
      plain.flat_map(&.spans).map { |span| Docv::Styles[span.style].markup }.uniq.should eq [Docv::Markup::CodeBlock]
    end
  end

  it "applies to the blocks of an example, blank blocks as empty lines" do
    with_queries({"json" => JSON_QUERY}) do
      first = Docv::Block.new(Docv::BlockKind::Text)
      first.spans = [Docv::Span.new("[1,")]
      blank = Docv::Block.new(Docv::BlockKind::Blank)
      blank.lines = 2
      last = Docv::Block.new(Docv::BlockKind::Text)
      last.spans = [Docv::Span.new("true]")]
      Docv::Syntax.apply([first, blank, last], "json")
      first.spans.map(&.text).should eq ["[", "1", ","]
      last.spans.map { |span| Docv::Styles[span.style].markup }.should eq [Docv::Markup::SyntaxConstant, Docv::Markup::SyntaxPunctuation]
    end
  end
end
