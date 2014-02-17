# We need to keep track of the top of the stack so
# encapsulate that logic in one place to make sure the invariant is enforced.
class Stack < Struct.new(:store, :sp)
  def initialize
    super([], -1)
  end

  def pop
    self.sp = self.sp - 1
    self.store.pop
  end

  def push(*args)
    self.sp = self.sp + args.length
    self.store.push(*args);
  end

  def [](val)
    self.store[val]
  end

  def []=(address, val)
    self.store[address] = val
  end

  def top_value
    self.store[-1]
  end
end
