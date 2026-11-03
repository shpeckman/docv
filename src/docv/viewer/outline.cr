# src/docv/viewer/outline.cr

module Docv
  class Viewer
    class Picker
      # Items folded into nested groups by shared prefixes of whole `Item#key`
      # tokens (split at `SEPARATORS`). A prefix shared by *min_group* items is
      # a group; a group with one subgroup and no items takes its prefix. Items
      # of different `Item#group`s never share a group. Items with an
      # `Item#folder` go into a group of that name after the others of their
      # `Item#group`, outlined the same way inside it. Inside a group, items
      # come before subgroups.
      class Outline
        # Characters that end a name token.
        SEPARATORS = {'-', '_', '.', ':', '/'}
        # Default fewest items that make a group.
        MIN_GROUP = 2
        # Columns each nesting level indents.
        INDENT = 2

        # A group (*item* -1) of *size* items sharing *prefix*, or item *item*;
        # *parent* is -1 at the top. *text* is the name relative to the group:
        # the prefix or label without its first *skip* characters.
        record Node, prefix : String, item : Int32, parent : Int32, depth : Int32, size : Int32,
          children : Array(Int32), text : String, skip : Int32 do
          def group? : Bool
            item < 0
          end
        end

        private class Trie
          getter prefix : String
          getter children = {} of String => Trie
          getter items = [] of Int32
          property size = 0

          def initialize(@prefix)
          end
        end

        # Every node; a group comes before its children.
        getter nodes = [] of Node
        # Top-level node ids, by item group, then outline order.
        getter roots = [] of Int32

        @leaves : Array(Int32)

        def initialize(items : Array(Item), @min_group : Int32 = MIN_GROUP)
          @leaves = Array(Int32).new(items.size, -1)
          # Item group → folder ("" for none) → trie.
          tries = {} of Int32 => Hash(String, Trie)
          items.each_with_index do |item, index|
            folders = tries[item.group] ||= {} of String => Trie
            insert(folders[item.folder] ||= Trie.new(item.folder), item.key, index)
          end
          tries.keys.sort!.each do |group|
            folders = tries[group]
            folders[""]?.try do |trie|
              count(trie)
              emit(trie, items, -1, 0, "", "", @roots)
            end
            folders.keys.reject(&.empty?).sort!.each { |name| folder(folders[name], items) }
          end
        end

        # The node id of item *index*.
        def leaf(index : Int32) : Int32
          @leaves[index]
        end

        # The items under node *id*, in outline order.
        def items(id : Int32) : Array(Int32)
          collect(id, [] of Int32)
        end

        # Yields the end of each token of *key* and the start of the next.
        def self.each_token(key : String, & : Int32, Int32 ->) : Nil
          bytes = key.to_slice
          index = skip(bytes, 0, true)
          while index < bytes.size
            stop = skip(bytes, index, false)
            index = skip(bytes, stop, true)
            yield stop, index
          end
        end

        # *text* without group prefix *outer* and the separators after it, and
        # the characters dropped. Text that does not continue *outer* with a
        # separator and a name (`abrt-dump(1)`) is relative to *above* instead.
        def self.relative(text : String, outer : String, above : String = "") : {String, Int32}
          return {text, 0} if outer.empty? || !text.starts_with?(outer)
          start = skip(text.to_slice, outer.bytesize, true)
          if start == outer.bytesize || start >= text.bytesize || text.byte_at(start) == '('.ord
            return relative(text, above)
          end
          {text.byte_slice(start), text.byte_slice(0, start).size}
        end

        # Skips separators (*separators* true) or non-separators from *index*.
        private def self.skip(bytes : Bytes, index : Int32, separators : Bool) : Int32
          while index < bytes.size && SEPARATORS.includes?(bytes[index].unsafe_chr) == separators
            index += 1
          end
          index
        end

        private def collect(id : Int32, into : Array(Int32)) : Array(Int32)
          node = @nodes[id]
          if node.group?
            node.children.each { |child| collect(child, into) }
          else
            into << node.item
          end
          into
        end

        private def insert(root : Trie, key : String, index : Int32) : Nil
          node = root
          start = 0
          Outline.each_token(key) do |stop, next_start|
            token = key.byte_slice(start, stop - start)
            node = node.children[token] ||= Trie.new(key.byte_slice(0, stop))
            start = next_start
          end
          node.items << index
        end

        # A top-level group named after a folder, holding its outlined items.
        private def folder(trie : Trie, items : Array(Item)) : Nil
          id = @nodes.size
          @roots << id
          children = [] of Int32
          @nodes << Node.new(trie.prefix, -1, -1, 0, count(trie), children, trie.prefix, 0)
          emit(trie, items, id, 1, "", "", children)
        end

        private def count(trie : Trie) : Int32
          trie.size = trie.items.size + trie.children.each_value.sum { |child| count(child) }
        end

        # Adds *trie*'s members as nodes under *parent* (prefix *outer*, inside
        # *above*) and their ids to *into*.
        private def emit(trie : Trie, items : Array(Item), parent : Int32, depth : Int32, outer : String,
                         above : String, into : Array(Int32)) : Nil
          members = [] of {String, Int32, Trie?}
          trie.items.each { |index| members << {items[index].key, index, nil} }
          trie.children.each_value do |child|
            while child.items.empty? && child.children.size == 1
              child = child.children.first_value
            end
            if child.size >= @min_group
              members << {child.prefix, -1, child}
            else
              gather(child, indices = [] of Int32)
              indices.each { |index| members << {items[index].key, index, nil} }
            end
          end
          # Inside a group its items come before its subgroups; the top
          # level mixes them by name.
          members.sort! do |left, right|
            order = depth > 0 ? (left[2] ? 1 : 0) <=> (right[2] ? 1 : 0) : 0
            order = left[0].compare(right[0], case_insensitive: true) if order == 0
            order = left[0] <=> right[0] if order == 0
            order == 0 ? left[1] <=> right[1] : order
          end
          members.each do |name, index, group|
            id = @nodes.size
            into << id
            if group
              children = [] of Int32
              text, skip = Outline.relative(name, outer)
              @nodes << Node.new(name, -1, parent, depth, group.size, children, text, skip)
              emit(group, items, id, depth + 1, name, outer, children)
            else
              text, skip = Outline.relative(items[index].label, outer, above)
              @nodes << Node.new("", index, parent, depth, 1, [] of Int32, text, skip)
              @leaves[index] = id
            end
          end
        end

        private def gather(trie : Trie, into : Array(Int32)) : Nil
          into.concat(trie.items)
          trie.children.each_value { |child| gather(child, into) }
        end
      end
    end
  end
end
