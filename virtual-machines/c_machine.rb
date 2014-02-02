class CMachine

  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+
  class Instruction < Struct.new(:instruction, :arguments); end

  # We need to keep track of the top of the stack (not sure why?) so
  # encapsulate that logic in one place to make sure the invariant is enforced.
  class Stack < Struct.new(:store, :sp)
    def initialize; super([], -1); end
    def pop; self.sp = self.sp - 1; self.store.pop; end
    def push(*args); self.sp = self.sp + args.length; self.store.push(*args); end
    def [](val); self.store[val]; end
    def []=(address, val); self.store[address] = val; end
    def top_value; self.store[-1]; end
  end

  # Set up the initial stack and registers.
  def initialize(c)
    @code, @stack = c, Stack.new
    @pc, @ir = -1, nil
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
