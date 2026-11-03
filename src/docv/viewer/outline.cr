# src/docv/viewer/outline.cr
module Docv
  class Viewer
    class Picker
      # Items folded into groups by the name prefixes they share, for the
      # page search: `abrt-cli` and `abrt-dump-oops` under `abrt`, and
      # `abrt-dump-oops` and `abrt-dump-xorg` under `abrt-dump` within it.
      #
      # An item's `Item#key` splits into tokens at runs of `SEPARATORS`
      # (`::` counts once). A prefix of whole tokens shared by at least
      # `MIN_GROUP` items becomes a group; a group with a single subgroup and
      # no items of its own takes that subgroup's prefix instead. Items with
      # different `Item#group`s never share a group, and an item whose key
      # is the prefix itself (`git` in `git`) is a member like the others.
      # Groups and items are sorted by prefix or key ignoring case, items of
      # one key in item order.
      #
      # Rows are named relative to their group: in `abrt-action`, the group
      # `abrt-action-analyze` is `analyze` and the item `abrt-action-notify(1)`
      # is `notify(1)`. An item named like its group is named relative to
      # the group above (`abrt(1)` in `abrt`, `dump(1)` in `abrt-dump`), and
      # one whose label does not start with the group prefix keeps its whole
      # label.
      class Outline
        # Characters that end a name token.
        SEPARATORS = {'-', '_', '.', ':', '/'}
        # Fewest items that make a group.
        MIN_GROUP = 3
        # Columns each nesting level indents.
        INDENT = 2

        # A row of the outline: a group (*item* is -1) of *size* items
        # sharing *prefix*, or the item *item*. *parent* is the group it is
        # in (-1 at the top) and *depth* its nesting level; a group's
        # *children* are node ids in outline order. *text* is the row's name
        # relative to its group: the prefix or the item label without its
        # first *skip* characters.
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
        # Top-level node ids, in item group order, then outline order.
        getter roots = [] of Int32

        @leaves : Array(Int32)

        def initialize(items : Array(Item))
          @leaves = Array(Int32).new(items.size, -1)
          tries = {} of Int32 => Trie
          items.each_with_index do |item, index|
            insert(tries[item.group] ||= Trie.new(""), item.key, index)
          end
          tries.keys.sort!.each do |group|
            trie = tries[group]
            count(trie)
            emit(trie, items, -1, 0, "", "", @roots)
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

        # Calls the block with the token boundaries of *key*: the end of the
        # token (the end of its prefix) and the start of the next token.
        def self.each_token(key : String, & : Int32, Int32 ->) : Nil
          bytes = key.to_slice
          index = skip(bytes, 0, true)
          while index < bytes.size
            stop = skip(bytes, index, false)
            index = skip(bytes, stop, true)
            yield stop, index
          end
        end

        # *text* (a prefix or a label) relative to the group prefix *outer*:
        # without *outer* and the separators after it, and the characters
        # dropped. Text that does not continue *outer* with a separator and
        # more name (`abrt-dump(1)` in `abrt-dump`) is relative to *above*,
        # the prefix of the group around that one; text that does not start
        # with *outer* is whole.
        def self.relative(text : String, outer : String, above : String = "") : {String, Int32}
          return {text, 0} if outer.empty? || !text.starts_with?(outer)
          start = skip(text.to_slice, outer.bytesize, true)
          if start == outer.bytesize || start >= text.bytesize || text.byte_at(start) == '('.ord
            return relative(text, above)
          end
          {text.byte_slice(start), text.byte_slice(0, start).size}
        end

        # The first index from *index* in *bytes* that is not a separator
        # (*separators*) or is one (not *separators*).
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

        private def count(trie : Trie) : Int32
          trie.size = trie.items.size + trie.children.each_value.sum { |child| count(child) }
        end

        # Adds the members of *trie* as nodes under *parent* (whose prefix is
        # *outer*, inside the group of prefix *above*), their ids to *into*.
        private def emit(trie : Trie, items : Array(Item), parent : Int32, depth : Int32, outer : String,
                         above : String, into : Array(Int32)) : Nil
          members = [] of {String, Int32, Trie?}
          trie.items.each { |index| members << {items[index].key, index, nil} }
          trie.children.each_value do |child|
            while child.items.empty? && child.children.size == 1
              child = child.children.first_value
            end
            if child.size >= MIN_GROUP
              members << {child.prefix, -1, child}
            else
              gather(child, indices = [] of Int32)
              indices.each { |index| members << {items[index].key, index, nil} }
            end
          end
          members.sort! do |left, right|
            order = left[0].compare(right[0], case_insensitive: true)
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
