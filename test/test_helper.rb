# frozen_string_literal: true

require "minitest/autorun"

# Shared harness for unit-testing the standalone scripts in this repo.
#
# Scripts in ./bin are extensionless executables, so a plain `require_relative`
# (which only finds `.rb` files) cannot pull them in. `load_script` loads one by
# path relative to this directory; the script's `__FILE__ == $PROGRAM_NAME`
# guard keeps its CLI body from running, exposing just its module/classes.
module ScriptTest
  def self.load_script(relative_path)
    load File.expand_path(relative_path, __dir__)
  end
end
