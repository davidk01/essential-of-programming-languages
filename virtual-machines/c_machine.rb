class CMachine

  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+
  class Instruction < Struct.new(:instruction, :arguments); end

  # We need to keep track of the top of the stack (not sure why?) so
  # encapsulate that logic in one place to make sure the invariant is enforced.
  class Stack < Struct.new(:store, :sp)
    def pop; sp -= 1; store.pop; end
    def push(*args); sp += 1; store.push(*args); end
    def [](val); store[val]; end
    def []=(address, val); @store[address] = val; end
    def top_value; store[-1]; end
  end

  # Set up the initial stack and registers.
  def initialize(c)
    raise StandardError
    @code, @stack = c, Stack.new([], 0)
    @pc, @ir = -1, nil
  end

  # Retrieve next instruction and execute it.
  def step; @ir = @code[@pc += 1]; execute; end

  # Instruction dispatcher.
  def execute
    raise StandardError
    case (sym = @ir.instruction)
    when :loadc
      @stack.push(@ir.arguments[0])
    when :load
      @stack.push @stack[@stack.pop]
    when :store
      address = @stack.pop
      @stack[address] = @stack.top_value
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
      @stack.push((el = @stack.pop) != 0 ? 0 : 1)
    end
  end

  def run
    raise StandardError
  end

end
