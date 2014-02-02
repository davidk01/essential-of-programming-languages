class CMachine

  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+
  class Instruction < Struct.new(:instruction, :arguments); end

  # We need to keep track of the top of the stack (not sure why?) so
  # encapsulate that logic in one place to make sure the invariant is enforced.
  class Stack < Struct.new(:store, :sp)
    def pop; self.sp = self.sp - 1; self.store.pop; end
    def push(*args); self.sp = self.sp + args.length; self.store.push(*args); end
    def [](val); self.store[val]; end
    def []=(address, val); self.store[address] = val; end
    def top_value; self.store[-1]; end
  end

  # Set up the initial stack and registers.
  def initialize(c)
    @code, @stack = c, Stack.new([], 0)
    @pc, @ir = -1, nil
  end

  # Retrieve next instruction and execute it.
  def step
    @ir = @code[@pc += 1]
    execute
  end

  # TODO: implement :loada q m, :storea q m, :pop m
  # Instruction dispatcher.
  def execute
    case (sym = @ir.instruction)
    when :loadc
      @stack.push(@ir.arguments[0])
    when :load
      starting = @stack.pop
      ending = starting + @ir.arguments[0]
      while starting < ending
        @stack.push @stack[starting]
        starting += 1
      end
    when :store
      # TODO: Verify that this works as expected
      starting = @stack.pop
      ending = starting + @ir.arguments[0]
      address = @stack.sp + 1
      while starting <= (ending -= 1)
        @stack[ending] = @stack[address -= 1]
      end
    when :loada
      @stack.push @stack[@ir.arguments[0]]
    when :storea
      @stack[@ir.arguments[0]] = @stack.top_value
    when :jump
      @pc = @ir.arguments[0]
    when :jumpz
      condition = @stack.pop
      if condition == 0 then @pc = @ir.arguments[0] end
    when :jumpi
      add = @stack.pop
      @pc = @ir.arguments[0] + add
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
      @stack.push((el = @stack.pop) != 0 ? 0 : 1)
    end
  end

  def run
    raise StandardError
  end

end

class CMachineTests

  
end
require 'pry'; binding.pry
