require File.expand_path(File.dirname(__FILE__) + '/cmachinestack')

##
# The actual virtual machine class.

class CMachine

  ##
  # It is important to distinguish between absolute loads and stores and relative loads and
  # stores.

  ##
  # Need a convenient way to see all the instructions. Simple comment for the time being
  # :label l (symbolic labels for jump instructions)
  # :pop (decrement the stack pointer)
  # :pushstack (add another stack on top of the current one for a function call)
  # :popstack (remove the context that was used for a function call)
  # :loadc c (push a constant on top of the stack)
  # :load c (take the top of the stack as a starting address and load c values from it)
  # :store c (take the top of the stack as a starting address and store c values to it)
  # :loada s c (load c elements starting at s)
  # :storea s c (store c elements starting at s)
  # :initvar s l (initialize l zeroes starting at s)
  # :jump a (jump to address a)
  # :jumpz a (jump to address a if top of stack is 0)
  # :jumpnz a (jump to address a if top of stack is not 0)
  # :jumpi a (indexed jump takes top of stack and adds a to it and jumps to that address)
  # :dup (duplicate top value on stack)
  # :*, :/, :+, :-, :% (arithmetic instructions)
  # :==, :!=, :<, :<=, :>, :>= (comparison instructions)
  # :-@, :! (unary instructions)
  # :&, :| (boolean/bitwise instructions)

  ##
  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+

  class Instruction < Struct.new(:instruction, :arguments)
    def self.[](instruction, *arguments); [new(instruction, arguments)]; end
  end

  ##
  # Readers for most of the internal state. Will help with debugging.

  attr_reader :code, :stack, :pc, :ir

  ##
  # Set up the initial stack and registers.
  
  def initialize(c)
    @code, @stack, @pc, @ir = c, Stack.new, -1, nil
  end

  ##
  # Retrieve next instruction and execute it.
  
  def step
    @ir = @code[@pc += 1]
    execute
  end

  ##
  # Instruction dispatcher.
  
  def execute
    case (sym = (@ir || Instruction.new(:noop, [])).instruction)
    when :label
    when :noop
    when :initvar
      len = @ir.arguments[0]
      @stack.push(*[0] * len)
    when :pop
      result = nil
      @ir.arguments[0].times { result = @stack.pop }
      result
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
      top_address = @stack.sp
      (0...count).each do |i|
        value = @stack[top_address - i]
        @stack[ending - i] = value
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

  ##
  # Execute all the instructions in sequence.

  def run
    step if @pc == -1
    step while @ir
  end

end
