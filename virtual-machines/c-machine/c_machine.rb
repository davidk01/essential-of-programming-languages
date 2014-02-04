require 'pegrb'
require File.expand_path(File.dirname(__FILE__) + '/c_machine_grammar')
require File.expand_path(File.dirname(__FILE__) + '/c_machine_stack')

# The actual virtual machine class.
class CMachine

  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+
  class Instruction < Struct.new(:instruction, :arguments); end

  # Set up the initial stack and registers.
  def initialize(c)
    @code, @stack, @pc, @ir = c, Stack.new, -1, nil
  end

  # Retrieve next instruction and execute it.
  def step
    @ir = @code[@pc += 1]
    execute
  end

  # Instruction dispatcher.
  def execute
    case (sym = @ir.instruction)
    when :pop
      @ir.arguments[0].times { @stack.pop }
    when :loadc
      @stack.push(@ir.arguments[0])
    when :load
      starting, count = @stack.pop, @ir.arguments[0]
      (0...count).each do |i|
        @stack.push @stack[starting + i]
      end
    when :store
      ending = @stack.pop + (count = @ir.arguments[0]) - 1
      address = @stack.sp
      (0...count).each do |i|
        @stack[ending - i] = @stack[address - i]
      end
    when :loada
      starting, count = *@ir.arguments
      (0...count).each do |i|
        @stack.push @stack[starting + i]
      end
    when :storea
      ending = @ir.arguments[0] + (count = @ir.arguments[1]) - 1
      address = @stack.sp
      (0...count).each do |i|
        @stack[ending - i] = @stack[address - i]
      end
    when :jump
      @pc = @ir.arguments[0]
    when :jumpz
      @pc = @ir.arguments[0] if @stack.pop == 0
    when :jumpi
      @pc = @ir.arguments[0] + @stack.pop
    when :dup
      @stack.push @stack.top_value
    when :*, :/, :+, :-, :%
      right = @stack.pop
      left = @stack.pop
      @stack.push left.send(sym, right)
    when :==, :!=, :<, :<=, :>, :>=
      right = @stack.pop
      left = @stack.pop
      @stack.push(left.send(sym, right) ? right : 0)
    when :-@
      @stack.push @stack.pop.send(sym)
    when :!
      @stack.push(@stack.pop != 0 ? 0 : 1)
    else
      raise StandardError, "Unrecognized operation: #{sym}."
    end
  end

  def run
    raise StandardError
  end

end
