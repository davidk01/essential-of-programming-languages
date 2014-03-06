require File.expand_path(File.dirname(__FILE__) + '/cmachinestack')

# The actual virtual machine class.
class CMachine

  # Need a convenient way to see all the instructions. Simple comment for the time being
  # :label l
  # :pop
  # :loadc c
  # :load c
  # :store c
  # :loada s c
  # :storea s c
  # :jump a
  # :jumpz a
  # :jumpnz a
  # :jumpi a
  # :dup
  # :*, :/, :+, :-, :%
  # :==, :!=, :<, :<=, :>, :>=
  # :-@, :!
  # :&, :|

  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+
  class Instruction < Struct.new(:instruction, :arguments)
    def self.[](instruction, *arguments); [new(instruction, arguments)]; end
  end

  ##
  # Readers for most of the internal state. Will help with debugging.

  attr_reader :code, :stack, :pc, :ir

  # Set up the initial stack and registers.
  def initialize(c)
    @code, @stack, @pc, @ir = c, Stack.new, -1, nil
  end

  # Retrieve next instruction and execute it.
  def step
    @ir = @code[@pc += 1]; execute
  end

  # Instruction dispatcher.
  def execute
    case (sym = @ir.instruction)
    when :label
    when :pop
      @ir.arguments[0].times { return @stack.pop }
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
    when :jumpnz
      @pc = @ir.arguments[0] if @stack.pop != 0
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
      @stack.push(left.send(sym, right) ? 1 : 0)
    when :&, :|
      right = stack.pop
      left = stack.pop
      @stack.push(left.send(sym, right))
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
