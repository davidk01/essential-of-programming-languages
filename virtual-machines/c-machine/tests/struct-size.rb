require 'minitest/autorun'
require_relative '../cmachinegrammar'

class TestStructSize < MiniTest::Unit::TestCase

  def setup
    @code = File.read(File.expand_path(File.dirname(__FILE__) + '/../examples/struct'))
    @context = CMachineGrammar::CompileData.new
    @ast = CMachineGrammar.parse(@code)
    @ast.compile(@context)
  end

  def test_basic_struct_size
    struct_size = @context.structs['BasicStruct'].size(@context)
    assert_equal(3, struct_size, "Struct with 3 basic members is of size 3.")
  end

  def test_another_basic_struct_size
    struct_size = @context.structs['AnotherBasicStruct'].size(@context)
    assert_equal(3, struct_size, "Struct with 3 basic members if of size 3.")
  end

  def test_non_basic_struct_size
    struct_size = @context.structs['NonBasicStruct'].size(@context)
    assert_equal(14, struct_size, "Struct with more complicated members should have correct size.")
  end

  def test_basic_struct_member_offsets
  end

  def test_another_basic_struct_member_offsets
  end

  def test_non_basic_struct_member_offsets
  end

end
