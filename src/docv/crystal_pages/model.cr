# src/docv/crystal_pages/model.cr
module Docv
  module CrystalPages
    # Source location of a documented type.
    struct Location
      include JSON::Serializable

      getter filename : String?
    end

    # Reference to another type.
    struct TypeRef
      include JSON::Serializable

      getter kind : String
      getter full_name : String
    end

    # Method or macro parameter; only its external name matters, to recognize
    # generated members.
    struct Arg
      include JSON::Serializable

      getter external_name : String?
    end

    # Definition node of a member: the declared return type and the body.
    struct Definition
      include JSON::Serializable

      getter return_type : String?
      getter body : String?
    end

    # Constant or enum member.
    struct Constant
      include JSON::Serializable

      # Openings of macro expressions, which `crystal docs` leaves unexpanded.
      MACRO_STARTS = {"{{", "{%"}

      getter name : String
      getter doc : String?
      @value : String?

      # Value as written in the source; `nil` when unknown or an unexpanded
      # macro expression.
      def value : String?
        value = @value
        value unless value && MACRO_STARTS.any? { |start| value.starts_with?(start) }
      end
    end

    # Constructor, method or macro.
    struct Member
      include JSON::Serializable

      # Members the compiler or `record` defines in every type; hidden unless
      # someone documented them.
      BOILERPLATE = {"clone", "copy_with", "finalize"}

      # Bodies of the `new` overloads `JSON::Serializable` and
      # `YAML::Serializable` define in every including type.
      SERIALIZER_BODIES = {"new_from_json_pull_parser(pull)", "new_from_yaml_node(ctx, node)"}

      ID_SUFFIX = /-(?:instance-method|class-method|macro|function)\z/

      getter html_id : String
      getter name : String
      getter doc : String?
      @[JSON::Field(key: "abstract")]
      getter? abstract_def : Bool = false
      getter args : Array(Arg) = [] of Arg
      getter args_string : String?
      @[JSON::Field(key: "def")]
      getter definition : Definition?

      # Whether the standard library or the compiler generated this member.
      def generated? : Bool
        (doc.nil? && BOILERPLATE.includes?(name)) ||
          args.any? { |arg| arg.external_name.try(&.starts_with?("__")) } ||
          SERIALIZER_BODIES.includes?(definition.try(&.body))
      end

      # Parameters and return type as declared, e.g. `(name : String) : Language`.
      def parameters : String
        CrystalPages.clean_type(args_string || return_type.try { |type| " : #{type}" } || "")
      end

      # `crystal docs` gives no parameter string for a member without
      # parameters, and macro-generated getters carry their return type only
      # in the id (`name:Type-instance-method`).
      private def return_type : String?
        definition.try(&.return_type) || begin
          rest = HTML.unescape(html_id).lchop(name)
          rest.sub(ID_SUFFIX, "")[1..].presence if args.empty? && rest.starts_with?(':')
        end
      end
    end

    # A documented type; the program, the top level namespace, is one too.
    class TypeDoc
      include JSON::Serializable

      getter kind : String
      getter full_name : String
      @[JSON::Field(key: "abstract")]
      getter? abstract_type : Bool = false
      getter superclass : TypeRef?
      getter ancestors : Array(TypeRef) = [] of TypeRef
      getter locations : Array(Location) = [] of Location
      getter? program : Bool = false
      @[JSON::Field(key: "enum")]
      getter? enum_type : Bool = false
      @[JSON::Field(key: "alias")]
      getter? alias_type : Bool = false
      getter aliased : String?
      getter constants : Array(Constant) = [] of Constant
      getter included_modules : Array(TypeRef) = [] of TypeRef
      getter extended_modules : Array(TypeRef) = [] of TypeRef
      getter subclasses : Array(TypeRef) = [] of TypeRef
      getter including_types : Array(TypeRef) = [] of TypeRef
      getter namespace : TypeRef?
      getter doc : String?
      getter constructors : Array(Member) = [] of Member
      getter class_methods : Array(Member) = [] of Member
      getter instance_methods : Array(Member) = [] of Member
      getter macros : Array(Member) = [] of Member
      getter types : Array(TypeDoc) = [] of TypeDoc

      # Drops generated members, and the `Kind#member?` predicates every enum
      # gets, right after parsing.
      protected def after_initialize : Nil
        {@constructors, @class_methods, @instance_methods, @macros}.each &.reject!(&.generated?)
        return unless enum_type?
        predicates = constants.map { |constant| "#{constant.name.underscore}?" }
        @instance_methods.reject! { |member| member.args.empty? && predicates.includes?(member.name) }
      end

      def base_name : String
        CrystalPages.base_name(full_name)
      end

      def lib? : Bool
        kind == "lib"
      end

      # Related type lists with their section titles, in page order.
      def relations : Array({String, Array(TypeRef)})
        [
          {"INCLUDED MODULES", included_modules},
          {"EXTENDED MODULES", extended_modules},
          {"DIRECT KNOWN SUBCLASSES", subclasses},
          {"DIRECT INCLUDING TYPES", including_types},
        ]
      end

      # The doc comments of the type and of everything it declares.
      def docs : Array(String)
        list = [doc].compact
        constants.each { |constant| constant.doc.try { |text| list << text } }
        {constructors, class_methods, instance_methods, macros}.each do |members|
          members.each { |member| member.doc.try { |text| list << text } }
        end
        list
      end

      # Whether the top level namespace declares anything worth a page.
      def toplevel_content? : Bool
        !(class_methods.empty? && macros.empty? && constants.empty?)
      end
    end

    # Root of the `crystal docs --format json` output.
    class Project
      include JSON::Serializable

      getter repository_name : String
      getter body : String
      getter program : TypeDoc
    end

    # Runs the compiler's doc tool.
    module DocTool
      COMMAND = "crystal"

      # The documentation index of the shard in *root*; compiler diagnostics
      # go to standard error.
      def self.load(root : String) : Project
        output = IO::Memory.new
        status = Process.run(COMMAND, {"docs", "--format", "json"}, chdir: root, output: output, error: Process::Redirect::Inherit)
        raise Error.new("`#{COMMAND} docs` failed with exit code #{status.exit_code}") unless status.success?
        Project.from_json(output.rewind)
      rescue ex : File::Error
        raise Error.new("cannot run `#{COMMAND}`: #{ex.message}")
      end
    end

    # The shard being documented: its root, name, version, and the `require`
    # that loads each source file.
    class Shard
      MANIFEST     = "shard.yml"
      REQUIRE      = /\A\s*require\s+"(\.\.?\/[^"]+)"/
      VERSION_LINE = /\Aversion:\s*["']?([^\s"']+)/

      getter root : String
      getter name : String
      getter version : String?

      # Source file → {entry order, require path}; the main entry
      # (`src/<name>.cr`) comes first.
      @entries = {} of String => {Int32, String}

      # The nearest directory from *dir* up that holds a `shard.yml`.
      def self.root(dir : String) : String?
        current = File.expand_path(dir)
        loop do
          return current if File.file?(File.join(current, MANIFEST))
          parent = File.dirname(current)
          return nil if parent == current
          current = parent
        end
      end

      def initialize(@root : String, @name : String)
        manifest = File.join(root, MANIFEST)
        @version = File.read_lines(manifest).compact_map(&.match(VERSION_LINE).try(&.[1])).first? if File.file?(manifest)
        main = File.join(root, "src", "#{name}.cr")
        entries = Dir.glob(File.join(root, "src", "*.cr")).sort_by { |path| {path == main ? 0 : 1, path} }
        entries.each_with_index do |entry, order|
          stem = File.basename(entry, ".cr")
          visit(entry, {order, stem == name ? name : "#{name}/#{stem}"})
        end
      end

      # The `require` that loads *type*, from the first entry file that
      # reaches one of its source files.
      def require_path(type : TypeDoc) : String?
        found = type.locations.compact_map { |location| location.filename.try { |file| @entries[File.expand_path(file, root)]? } }
        found.min_by?(&.[0]).try(&.[1])
      end

      # *text* with the shard's absolute path made relative, so pages built
      # on any machine are identical.
      def relative(text : String) : String
        text.gsub("#{root}/", "").gsub(root, ".")
      end

      private def visit(file : String, entry : {Int32, String}) : Nil
        return if @entries.has_key?(file)
        @entries[file] = entry
        File.each_line(file) do |line|
          next unless md = line.match(REQUIRE)
          targets(File.expand_path(md[1], File.dirname(file))).each { |target| visit(target, entry) }
        end
      end

      # Files a relative require loads, by the compiler's lookup rules.
      private def targets(path : String) : Array(String)
        return Dir.glob(File.join(path.rchop("/**"), "**", "*.cr")).sort if path.ends_with?("/**")
        return Dir.glob(File.join(path.rchop("/*"), "*.cr")).sort if path.ends_with?("/*")
        candidates = path.ends_with?(".cr") ? [path] : ["#{path}.cr", File.join(path, "#{File.basename(path)}.cr")]
        candidates.select { |candidate| File.file?(candidate) }.first(1)
      end
    end

    # Lookup tables over the documented types.
    class Types
      TYPE_PATH = /\A((?:::)?[A-Z]\w*(?:::[A-Z]\w*)*)(?:[#.(]|\z)/
      CODE_SPAN = /(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)/m

      getter project : Project
      # The types with a page of their own: the top level when it declares
      # anything, then every type in nesting order.
      getter types = [] of TypeDoc

      @by_name = {} of String => TypeDoc

      def initialize(@project : Project)
        program = project.program
        @types << program if program.toplevel_content?
        collect(program)
      end

      # The documented type named *full_name*, generic arguments ignored.
      def []?(full_name : String) : TypeDoc?
        @by_name[CrystalPages.base_name(full_name)]?
      end

      # Resolves *name* as Crystal does: relative to *context*, then to each
      # enclosing namespace.
      def lookup(context : TypeDoc, name : String) : TypeDoc?
        name = CrystalPages.base_name(name)
        return @by_name[name.lchop("::")]? if name.starts_with?("::")
        scope = context.program? ? nil : context.base_name
        loop do
          found = @by_name[scope ? "#{scope}::#{name}" : name]?
          return found if found
          return nil unless scope
          scope = scope.rpartition("::")[0].presence
        end
      end

      # Types the docs of *type* name in code spans: `Tree`, `Tree#edit`,
      # `Language.load`, `Language::MIN_ABI`.
      def referenced(type : TypeDoc) : Array(TypeDoc)
        found = [] of TypeDoc
        type.docs.each do |doc|
          doc.scan(CODE_SPAN) do |md|
            next unless path = md[2].strip.match(TYPE_PATH).try(&.[1])
            parent = path.rpartition("::")[0].presence
            target = lookup(type, path) || parent.try { |name| lookup(type, name) }
            found << target if target
          end
        end
        found
      end

      private def collect(type : TypeDoc) : Nil
        type.types.each do |nested|
          @by_name[nested.base_name] = nested
          @types << nested
          collect(nested)
        end
      end
    end
  end
end
